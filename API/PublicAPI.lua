------------------------------------------------------------
-- API/PublicAPI.lua - GlassGear.API v1 (docs/API.md).
--
-- M0 implements discovery, readiness, characters/specs/profiles and Evaluate
-- for the current character (local baselines, pending item data, one load
-- queue with retries). Alts, the "tracked" scope and AssessProtection report
-- "unsupported" until GG-201/GG-301. The frame budget and result cache are
-- GG-114. Everything returned is a deep copy.
------------------------------------------------------------

local GG = GlassGear
local U = GG.Util
local API = { API_VERSION = 1 }
GG.API = API

API.LIMITS = { targets = 32, batch = 64, perFrame = 200, jobs = 512, requests = 64, itemQueue = 256,
    loadTimeout = 5, loadAttempts = 3 }

-- requests[id] = { request, specs, itemIDs = {[id]=true} }
-- waiting[itemID] = { attempts, since }   (the one owner of load attempts)
local state = { ready = false, nextId = 0, requests = {}, requestCount = 0, waiting = {}, waitingCount = 0 }
API._state = state   -- test seam

local function features()
    return {
        evaluate = true, evaluateBatch = true, cancelRequest = true,
        scopes = { current = true, own = true, tracked = false, targets = true },
        alts = false, sync = false, assessProtection = false, frameBudget = false, resultCache = false,
    }
end

function API.GetCapabilities()
    local alt = GG.Integrations.RosterProvider.DetectAltStable()
    return U.deepCopy({
        apiVersion = API.API_VERSION, build = GG.MEASURED_ON_BUILD, features = features(),
        unavailable = {
            alts = alt.reason or "GG-201 not implemented",
            sync = alt.reason or "GG-202 not implemented",
            assessProtection = "GG-301 not implemented",
            ["scope:tracked"] = "needs alts (GG-201)",
            frameBudget = "GG-114", resultCache = "GG-114",
        },
    })
end

function API.IsReady() return state.ready end

function API.GetCharacters()
    if not GG.player then return {} end
    return U.deepCopy(GG.Integrations.RosterProvider.Characters(GG.player))
end

function API.GetSpecs(charKey)
    local p = GG.player
    if not p or charKey ~= p.key then return {} end
    local out = {}
    for _, s in ipairs(GG.Data.Classes.Specs(p.class)) do
        out[#out + 1] = { key = s.key, name = s.name, current = s.key == GG.currentSpec,
            hasProfile = GG.Profiles.Active(GG.store, p.key, s.key) ~= nil }
    end
    return out
end

function API.GetProfile(charKey, specKey)
    if not GG.store then return nil, "not-ready" end
    local p = GG.Profiles.Active(GG.store, charKey, specKey)
    if not p then return nil, "NO_WEIGHTS" end
    return U.deepCopy(p)
end

------------------------------------------------------------
-- Evaluation
------------------------------------------------------------

-- The request's (character, spec) targets, in API order. M0: current character.
local function targetsFor(request)
    local p = GG.player
    local scope = request.scope or "current"
    local specs = {}
    if scope == "current" then
        specs[1] = GG.currentSpec or "UNKNOWN"
    elseif scope == "own" then
        if GG.currentSpec then specs[1] = GG.currentSpec end
        for _, s in ipairs(GG.Data.Classes.Specs(p.class)) do
            if s.key ~= GG.currentSpec then specs[#specs + 1] = s.key end
        end
    elseif scope == "targets" then
        if #(request.targets or {}) > API.LIMITS.targets then return nil, "TOO_MANY_TARGETS" end
        for _, t in ipairs(request.targets or {}) do
            if t.char ~= p.key then return nil, "ALT_TARGETS_UNSUPPORTED" end
            specs[#specs + 1] = t.spec
        end
    else
        return nil, "SCOPE_UNSUPPORTED"
    end
    return specs
end

-- One row per target with the same status and reason (placeholders, overload, timeout).
local function rowsFor(specs, status, reason)
    local rows = {}
    for _, spec in ipairs(specs) do
        rows[#rows + 1] = { status = status, spec = spec, current = spec == GG.currentSpec,
            character = GG.player and { key = GG.player.key, name = GG.player.name, realm = GG.player.realm,
                provenance = GG.player.provenance } or nil,
            reasons = { reason }, limitations = {} }
    end
    return rows
end

local function settingsFor()
    local s = GG.db and GG.db.settings or GG.DB.DEFAULTS.settings
    return { threshold = s.markers.threshold, levelWindow = s.levelWindow, specArmor = s.specArmor }
end

-- Returns response, waitIDs (item IDs still missing data), specs. A pending
-- request is re-evaluated against the targets captured when it was made.
local function evaluateOne(request, requestId, fixedSpecs)
    local response = { requestId = requestId, results = {} }
    local specs, why = fixedSpecs, nil
    if not specs then specs, why = targetsFor(request) end
    if not specs then
        response.results = { { status = "unsupported", reasons = { why }, limitations = {} } }
        response.status = "unsupported"
        return response, {}, {}
    end
    local link, instance = GG.Compat.ResolveItemRef(request.item)
    local facts = link and GG.Compat.ItemFacts(link)
    if not facts then
        response.results = rowsFor(specs, "unknown", "NO_ITEM")
        response.status = "unknown"
        return response, {}, specs
    end
    local waitIDs = {}
    if not facts.ready then waitIDs[#waitIDs + 1] = facts.itemID end
    local equipped, missing = GG.Compat.EquippedBaseline(time())
    for _, id in ipairs(missing) do waitIDs[#waitIDs + 1] = id end
    if #missing > 0 then
        -- Baseline items still loading: pending, not an "unknown slot" verdict.
        response.results = rowsFor(specs, "pending", "BASELINE_ITEM_DATA_PENDING")
        response.status = "pending"
        return response, waitIDs, specs
    end
    local baseline = GG.Baselines.Choose({ current = equipped })
    for _, spec in ipairs(specs) do
        local r = GG.Engine.Evaluate.One({
            item = facts, recipient = GG.player, spec = spec, current = spec == GG.currentSpec,
            profile = GG.Profiles.Active(GG.store, GG.player.key, spec),
            baseline = baseline, settings = settingsFor(), instance = instance,
            transfer = { state = "eligible", reasons = { "SAME_CHARACTER" } },
        })
        if spec == "UNKNOWN" then r.status = "unknown"; r.reasons = { "UNKNOWN_SPEC" } end
        response.results[#response.results + 1] = r
    end
    response.status = GG.Engine.Evaluate.Aggregate(response.results)
    return response, waitIDs, specs
end

local function wait(itemID)
    if state.waiting[itemID] then return true end
    if state.waitingCount >= API.LIMITS.itemQueue then return false end
    state.waiting[itemID] = { attempts = 1, since = GetTime() }
    state.waitingCount = state.waitingCount + 1
    GG.Compat.RequestItem(itemID)
    if GG.StartTick then GG.StartTick() end
    return true
end

local function unwait(itemID)
    if state.waiting[itemID] then
        state.waiting[itemID] = nil
        state.waitingCount = state.waitingCount - 1
    end
end

function API.Evaluate(request)
    if type(request) ~= "table" then error("GlassGear.API.Evaluate: request table required", 2) end
    state.nextId = state.nextId + 1
    local id = state.nextId
    if not state.ready then
        return { requestId = id, status = "unknown", results = { { status = "unknown", reasons = { "NOT_READY" } } } }
    end
    local response, waitIDs, specs = evaluateOne(request, id)
    if #waitIDs > 0 then
        if state.requestCount >= API.LIMITS.requests then
            return U.deepCopy({ requestId = id, status = "unknown", results = rowsFor(specs, "unknown", "OVERLOADED") })
        end
        local ids = {}
        for _, itemID in ipairs(waitIDs) do
            if not wait(itemID) then
                return U.deepCopy({ requestId = id, status = "unknown", results = rowsFor(specs, "unknown", "ITEM_QUEUE_FULL") })
            end
            ids[itemID] = true
        end
        state.requests[id] = { request = request, specs = specs, itemIDs = ids }
        state.requestCount = state.requestCount + 1
    end
    return U.deepCopy(response)
end

function API.EvaluateBatch(requests)
    if type(requests) ~= "table" then error("GlassGear.API.EvaluateBatch: list required", 2) end
    if #requests > API.LIMITS.batch then
        state.nextId = state.nextId + 1
        return { { requestId = state.nextId, status = "unknown",
            results = { { status = "unknown", reasons = { "BATCH_TOO_LARGE" } } } } }
    end
    local out = {}
    for i, r in ipairs(requests) do out[i] = API.Evaluate(r) end
    return out
end

function API.CancelRequest(requestId)
    local entry = state.requests[requestId]
    if not entry then return false end
    state.requests[requestId] = nil
    state.requestCount = state.requestCount - 1
    -- Stop loading items no other request is waiting for.
    for itemID in pairs(entry.itemIDs) do
        local needed = false
        for _, other in pairs(state.requests) do if other.itemIDs[itemID] then needed = true end end
        if not needed then unwait(itemID) end
    end
    return true
end

local function finish(id, response)
    state.requests[id] = nil
    state.requestCount = state.requestCount - 1
    GG.Callbacks.Fire("EvaluationReady", { requestId = id, response = response })
end

-- GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT. A failed load leaves the
-- item waiting: the tick retries it until attempts run out.
function API._ItemDataArrived(itemID, success)
    if success == false or not state.waiting[itemID] then return end
    -- Re-evaluate first: the waiting record (and its attempt budget) goes only
    -- once the data is really usable.
    local stillMissing = false
    for id, entry in pairs(state.requests) do
        if entry.itemIDs[itemID] then
            local response, waitIDs = evaluateOne(entry.request, id, entry.specs)
            entry.itemIDs = {}
            for _, w in ipairs(waitIDs) do
                entry.itemIDs[w] = true
                if w == itemID then stillMissing = true else wait(w) end
            end
            if #waitIDs == 0 then finish(id, response) end
        end
    end
    if not stillMissing then
        unwait(itemID)
        GG.Callbacks.Fire("ItemDataReady", { itemIDs = { itemID } })
    end
end

-- About once a second while items wait: retry timed-out loads; after the last
-- attempt, resolve their requests with every target row kept (status unknown).
function API._Tick(now)
    for itemID, w in pairs(state.waiting) do
        if now - w.since >= API.LIMITS.loadTimeout then
            if w.attempts < API.LIMITS.loadAttempts then
                w.attempts, w.since = w.attempts + 1, now
                GG.Compat.RequestItem(itemID)
            else
                unwait(itemID)
                for id, entry in pairs(state.requests) do
                    if entry.itemIDs[itemID] then
                        local response = evaluateOne(entry.request, id, entry.specs)
                        for _, r in ipairs(response.results) do
                            if r.status == "pending" then r.status = "unknown"; r.reasons = { "ITEM_DATA_UNAVAILABLE" } end
                        end
                        response.status = GG.Engine.Evaluate.Aggregate(response.results)
                        finish(id, response)
                    end
                end
            end
        end
    end
    return state.waitingCount > 0
end

-- Protection: unsupported until GG-301 (consumers fail closed).
function API.AssessProtection(itemRef, opts)
    return { verdict = "unsupported", token = nil, expiresAt = nil, recipients = {}, unchecked = {},
        reasons = { "NOT_IMPLEMENTED:GG-301" } }
end

function API.RegisterCallback(event, fn, owner) GG.Callbacks.Register(event, fn, owner) end
function API.UnregisterCallback(event, owner) GG.Callbacks.Unregister(event, owner) end

function API._SetReady()
    state.ready = true
    GG.Callbacks.Fire("Ready")
end

-- Anything that changes evaluation inputs (spec mapping, profiles, level, skills).
function API._Invalidate(reason, charKeys)
    GG.Callbacks.Fire("EvaluationInvalidated", { reason = reason, charKeys = charKeys })
end

return API
