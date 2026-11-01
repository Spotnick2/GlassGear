------------------------------------------------------------
-- API/PublicAPI.lua - GlassGear.API v1 (docs/API.md).
--
-- M0 implements discovery, readiness, characters/specs/profiles and Evaluate
-- for the current character (local baselines, pending item data). Alts and
-- AssessProtection report "unsupported" with a reason until GG-201/GG-301.
-- Everything returned is a deep copy.
------------------------------------------------------------

local GG = GlassGear
local U = GG.Util
local API = { API_VERSION = 1 }
GG.API = API

API.LIMITS = { targets = 32, batch = 64, perFrame = 200, jobs = 512, requests = 64, itemQueue = 256,
    loadTimeout = 5, loadAttempts = 3 }

local state = { ready = false, nextId = 0, requests = {}, requestCount = 0, waitingItems = {}, waitingCount = 0 }
API._state = state   -- test seam

local function features()
    return {
        evaluate = true, evaluateBatch = true, cancelRequest = true,
        scopes = { current = true, own = true, tracked = false, targets = true },
        alts = false, sync = false, assessProtection = false,
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

-- Resolve the request's item to { facts, instance } (Compat does the game calls).
local function resolveItem(item)
    if type(item) == "string" then return GG.Compat.ItemFacts(item), nil end
    if type(item) == "table" and item.bag and item.slot then
        local b = GG.Compat.BagItem(item.bag, item.slot)
        if not b then return nil end
        return GG.Compat.ItemFacts(b.link), { bag = b.bag, slot = b.slot, guid = b.guid, bound = b.isBound }
    end
    return nil
end

local function targetsFor(request)
    local p = GG.player
    local scope = request.scope or "current"
    local specs = {}
    if scope == "current" then
        if GG.currentSpec then specs[1] = GG.currentSpec end
    elseif scope == "own" then
        if GG.currentSpec then specs[1] = GG.currentSpec end
        for _, s in ipairs(GG.Data.Classes.Specs(p.class)) do
            if s.key ~= GG.currentSpec then specs[#specs + 1] = s.key end
        end
    elseif scope == "targets" then
        for _, t in ipairs(request.targets or {}) do
            if t.char ~= p.key then return nil, "ALT_TARGETS_UNSUPPORTED" end
            specs[#specs + 1] = t.spec
        end
    else
        return nil, "SCOPE_UNSUPPORTED"
    end
    return specs
end

local function settingsFor()
    local s = GG.db and GG.db.settings or GG.DB.DEFAULTS.settings
    return { threshold = s.markers.threshold, levelWindow = s.levelWindow, specArmor = s.specArmor }
end

local function evaluateOne(request, requestId)
    local response = { requestId = requestId, results = {} }
    local specs, why = targetsFor(request)
    if not specs then
        response.results[1] = { status = "unsupported", reasons = { why } }
        response.status = "unsupported"
        return response
    end
    if #specs > API.LIMITS.targets then
        response.results[1] = { status = "unsupported", reasons = { "TOO_MANY_TARGETS" } }
        response.status = "unsupported"
        return response
    end
    local facts, instance = resolveItem(request.item)
    if not facts then
        response.results[1] = { status = "unknown", reasons = { "NO_ITEM" } }
        response.status = "unknown"
        return response
    end
    local baseline = GG.Baselines.Choose({ current = GG.Compat.EquippedBaseline(time()) })
    for _, spec in ipairs(specs) do
        response.results[#response.results + 1] = GG.Engine.Evaluate.One({
            item = facts, recipient = GG.player, spec = spec, current = spec == GG.currentSpec,
            profile = GG.Profiles.Active(GG.store, GG.player.key, spec),
            baseline = baseline, settings = settingsFor(), instance = instance,
            transfer = { state = "eligible", reasons = { "SAME_CHARACTER" } },
        })
    end
    response.status = GG.Engine.Evaluate.Aggregate(response.results)
    return response, facts
end

local function track(request, response, facts)
    local pending = false
    for _, r in ipairs(response.results) do if r.status == "pending" then pending = true end end
    if not pending then return true end
    if state.requestCount >= API.LIMITS.requests then return false end
    local itemID = facts and facts.itemID
    if itemID and not state.waitingItems[itemID] then
        if state.waitingCount >= API.LIMITS.itemQueue then return false, "ITEM_QUEUE_FULL" end
        state.waitingItems[itemID] = { attempts = 1, since = GetTime() }
        state.waitingCount = state.waitingCount + 1
        if GG.StartTick then GG.StartTick() end
    end
    state.requests[response.requestId] = { request = request, itemID = itemID }
    state.requestCount = state.requestCount + 1
    return true
end

local function overloaded(requestId, reason)
    return { requestId = requestId, status = "unknown", results = { { status = "unknown", reasons = { reason } } } }
end

function API.Evaluate(request)
    if type(request) ~= "table" then error("GlassGear.API.Evaluate: request table required", 2) end
    state.nextId = state.nextId + 1
    local id = state.nextId
    if not state.ready then return overloaded(id, "NOT_READY") end
    local response, facts = evaluateOne(request, id)
    local ok, why = track(request, response, facts)
    if not ok then return overloaded(id, why or "OVERLOADED") end
    return U.deepCopy(response)
end

function API.EvaluateBatch(requests)
    if type(requests) ~= "table" then error("GlassGear.API.EvaluateBatch: list required", 2) end
    if #requests > API.LIMITS.batch then
        state.nextId = state.nextId + 1
        return { overloaded(state.nextId, "BATCH_TOO_LARGE") }
    end
    local out = {}
    for i, r in ipairs(requests) do out[i] = API.Evaluate(r) end
    return out
end

function API.CancelRequest(requestId)
    if state.requests[requestId] then
        state.requests[requestId] = nil
        state.requestCount = state.requestCount - 1
        return true
    end
    return false
end

-- Called by Core/Main on GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT.
function API._ItemDataArrived(itemID)
    if state.waitingItems[itemID] then
        state.waitingItems[itemID] = nil
        state.waitingCount = state.waitingCount - 1
    end
    GG.Callbacks.Fire("ItemDataReady", { itemIDs = { itemID } })
    for id, entry in pairs(state.requests) do
        if entry.itemID == itemID then
            local response = evaluateOne(entry.request, id)
            local still = false
            for _, r in ipairs(response.results) do if r.status == "pending" then still = true end end
            if not still then
                state.requests[id] = nil
                state.requestCount = state.requestCount - 1
                GG.Callbacks.Fire("EvaluationReady", { requestId = id, response = response })
            end
        end
    end
end

-- Called about once a second while items are waiting: retry loads that timed
-- out; after the last attempt resolve their requests as unknown.
function API._Tick(now)
    for itemID, w in pairs(state.waitingItems) do
        if now - w.since >= API.LIMITS.loadTimeout then
            if w.attempts < API.LIMITS.loadAttempts then
                w.attempts, w.since = w.attempts + 1, now
                C_Item.RequestLoadItemDataByID(itemID)
            else
                state.waitingItems[itemID] = nil
                state.waitingCount = state.waitingCount - 1
                for id, entry in pairs(state.requests) do
                    if entry.itemID == itemID then
                        state.requests[id] = nil
                        state.requestCount = state.requestCount - 1
                        local response = { requestId = id, status = "unknown",
                            results = { { status = "unknown", reasons = { "ITEM_DATA_UNAVAILABLE" } } } }
                        GG.Callbacks.Fire("EvaluationReady", { requestId = id, response = response })
                    end
                end
            end
        end
    end
    return state.waitingCount > 0
end

-- Protection: unsupported until GG-301 (fail-closed for consumers).
function API.AssessProtection(itemRef, opts)
    return { verdict = "unsupported", token = nil, expiresAt = nil, recipients = {},
        reasons = { "NOT_IMPLEMENTED:GG-301" } }
end

function API.RegisterCallback(event, fn, owner) GG.Callbacks.Register(event, fn, owner) end
function API.UnregisterCallback(event, owner) GG.Callbacks.Unregister(event, owner) end

function API._SetReady()
    state.ready = true
    GG.Callbacks.Fire("Ready")
end

return API
