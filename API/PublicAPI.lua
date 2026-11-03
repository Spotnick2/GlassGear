------------------------------------------------------------
-- API/PublicAPI.lua - GlassGear.API v1 (docs/API.md).
--
-- Discovery, readiness, characters/specs/profiles and Evaluate for the
-- current character. Alts, the "tracked" scope and AssessProtection report
-- "unsupported" until GG-201/GG-301. Everything returned is a deep copy.
--
-- The runtime (GG-114):
--   * A request subscribes to a job. Requests for the same item instance (or
--     link), targets and context share one job (deduplicated computation).
--     A job waits for item data and/or for the frame budget; when its rows
--     resolve, every subscriber gets EvaluationReady once, with its own id.
--   * At most LIMITS.perFrame evaluations (one per (character, spec) row) run
--     per frame. Rows over the budget are placeholders (pending,
--     FRAME_BUDGET) computed on a later frame.
--   * Bounds: LIMITS.requests outstanding subscriptions, LIMITS.jobs
--     outstanding pending rows (deduplicated across requests). Beyond them a
--     call returns OVERLOADED rows at once: terminal, no callback.
--   * Complete answers go into an LRU cache (LIMITS.cache) keyed like jobs and
--     stamped with the generation: any EvaluationInvalidated reason advances
--     it, so an old answer is never served. An answer whose stored baseline
--     goes stale (expiresAt) is dropped on the next look: the freshness
--     generation advances before that call returns, then EvaluationInvalidated
--     ("freshness") follows.
------------------------------------------------------------

local GG = GlassGear
local U = GG.Util
local API = { API_VERSION = 1 }
GG.API = API

API.LIMITS = { targets = 32, batch = 64, perFrame = 200, jobs = 512, requests = 64, itemQueue = 256,
    loadTimeout = 5, loadAttempts = 3, cache = 2000 }

-- requests[requestId] = jobKey (a subscription)
-- jobs[jobKey] = { request, specs, itemIDs = {[id]=true}, deferred, subs = {[requestId]=true}, rows, seq }
-- waiting[itemID] = { attempts, since }   (the one owner of load attempts)
local state = { ready = false, nextId = 0, requests = {}, requestCount = 0, jobs = {}, jobRows = 0, jobSeq = 0,
    waiting = {}, waitingCount = 0, generation = 0, gens = {}, frameTime = nil, frameUsed = 0,
    deferredScheduled = false,
    stats = { evaluations = 0, hits = 0, misses = 0, deferredRows = 0 } }
API._state = state   -- test seam

------------------------------------------------------------
-- The result cache (LRU)
------------------------------------------------------------
local cache = { map = {}, size = 0 }
cache.head = {}               -- most recent after head
cache.tail = {}
cache.head.next, cache.tail.prev = cache.tail, cache.head

local function unlink(n) n.prev.next, n.next.prev = n.next, n.prev end
local function pushFront(n)
    n.next, n.prev = cache.head.next, cache.head
    cache.head.next.prev = n
    cache.head.next = n
end

function cache.get(key)
    local n = cache.map[key]
    if not n then return nil end
    unlink(n)
    pushFront(n)
    return n
end

function cache.drop(key)
    local n = cache.map[key]
    if not n then return end
    unlink(n)
    cache.map[key] = nil
    cache.size = cache.size - 1
end

function cache.put(key, response, expiresAt)
    cache.drop(key)
    local n = { key = key, response = response, generation = state.generation, expiresAt = expiresAt }
    cache.map[key] = n
    cache.size = cache.size + 1
    pushFront(n)
    while cache.size > API.LIMITS.cache do cache.drop(cache.tail.prev.key) end
end

function cache.clear()
    cache.map, cache.size = {}, 0
    cache.head.next, cache.tail.prev = cache.tail, cache.head
end
API._cache = cache   -- test seam

local function features()
    return {
        evaluate = true, evaluateBatch = true, cancelRequest = true,
        scopes = { current = true, own = true, tracked = false, targets = true },
        alts = false, roster = GG.Integrations.RosterProvider.DetectAltStable().usable, sync = false,
        assessProtection = false, frameBudget = true, resultCache = true,
    }
end

function API.GetCapabilities()
    local alt = GG.Integrations.RosterProvider.DetectAltStable()
    return U.deepCopy({
        apiVersion = API.API_VERSION, build = GG.MEASURED_ON_BUILD, features = features(),
        limits = API.LIMITS,
        unavailable = {
            alts = alt.reason or "alt rows are GG-203 (the entry-sync library ES-001 and the transfer-rule probe GG-116)",
            sync = "needs the entry-sync library (ES-001, GG-202)",
            assessProtection = "GG-301 not implemented",
            ["scope:tracked"] = "needs alt rows (GG-203)",
        },
    })
end

function API.IsReady() return state.ready end

function API.GetCharacters()
    if not GG.player then return {} end
    return U.deepCopy(GG.Integrations.RosterProvider.Characters(GG.player))
end

-- The specs of the current character or one of the player's own others
-- (GG-201: the class's specs; which one an alt is in isn't known).
function API.GetSpecs(charKey)
    local p = GG.player
    if not p then return {} end
    local c = GG.Integrations.RosterProvider.Find(charKey)
    if not (c and c.class) then return {} end
    local me = c.key == p.key
    local out = {}
    for _, s in ipairs(GG.Data.Classes.Specs(c.class)) do
        out[#out + 1] = { key = s.key, name = s.name, current = me and s.key == GG.currentSpec or false,
            hasProfile = GG.Profiles.Active(GG.store, c.key, s.key) ~= nil }
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

-- The request's (character, spec) targets, in API order. M1: current character.
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

-- The per-frame budget. GetTime() is the frame's time; the deferred runner
-- always starts a new window (it runs on a later frame).
local function budgetLeft()
    local now = GetTime()
    if state.frameTime ~= now then state.frameTime, state.frameUsed = now, 0 end
    return API.LIMITS.perFrame - state.frameUsed
end

local function spend()
    state.frameUsed = state.frameUsed + 1
    state.stats.evaluations = state.stats.evaluations + 1
end

-- A finished row still holds while its stored baseline hasn't passed expiresAt.
local function rowFresh(r, now)
    local b = r.baseline
    return not (b and type(b.expiresAt) == "number" and not b.stale and now >= b.expiresAt)
end

-- Returns response, rowDeps ([i] = { [itemID] = true }: what a pending row
-- waits for). A pending request is re-evaluated against the targets captured
-- when it was made. `prior` (the job's last response, same generation) lends
-- its finished, still fresh rows: they aren't computed again, so a job always
-- progresses, whatever the budget. A row put off by the budget keeps what it
-- waited for before (`priorDeps`): the job keeps those item loads, with their
-- attempts, until the row is computed again.
local function evaluateOne(request, requestId, specs, prior, priorDeps)
    local response = { requestId = requestId, results = {} }
    local rowDeps = {}
    local link, instance = GG.Compat.ResolveItemRef(request.item)
    local facts = link and GG.Compat.ItemFacts(link)
    if not facts then
        response.results = rowsFor(specs, "unknown", "NO_ITEM")
        response.status = "unknown"
        return response, rowDeps
    end
    local now = time()
    local equipped, missing = GG.Compat.EquippedBaseline(now)
    -- Worn items still loading hold up only the specs that need them (GG-108):
    -- those compared with the current gear, and a candidate that pairs with a
    -- worn hand whose data hasn't arrived. Pending, not an "unknown slot" verdict.
    local handLoading = #missing > 0
        and (equipped.slots[16].state == "unknown" or equipped.slots[17].state == "unknown")
    -- What is worn now pairs with a candidate that needs a companion (a 1H
    -- against a spec's 2H): the off-hand or main hand from the current gear.
    local companion = { [16] = equipped.slots[16], [17] = equipped.slots[17] }
    for i, spec in ipairs(specs) do
        local r
        local deps = {}
        local done = prior and prior.results[i]
        if done and done.status ~= "pending" and done.spec == spec and rowFresh(done, now) then
            r = done
        elseif budgetLeft() <= 0 then
            -- Over this frame's budget: a placeholder, computed on a later frame.
            state.stats.deferredRows = state.stats.deferredRows + 1
            r = rowsFor({ spec }, "pending", "FRAME_BUDGET")[1]
            for id in pairs(priorDeps and priorDeps[i] or {}) do deps[id] = true end
        else
            spend()
            if not facts.ready then deps[facts.itemID] = true end
            -- Each spec's own gear (GG-108): a set, what it wore, or the current gear.
            local baseline, specMissing, fromLive = GG.Capture.BaselineFor(spec, equipped, now)
            if baseline and not (fromLive and #missing > 0) then
                r = GG.Engine.Evaluate.One({
                    item = facts, recipient = GG.player, spec = spec, current = spec == GG.currentSpec,
                    profile = GG.Profiles.Active(GG.store, GG.player.key, spec),
                    baseline = baseline, settings = settingsFor(), instance = instance, companion = companion,
                    transfer = { state = "eligible", reasons = { "SAME_CHARACTER" } },
                })
                if handLoading and r.status == "unknown"
                    and (U.contains(r.reasons, "NEEDS_COMPANION") or U.contains(r.reasons, "COMPANION_DATA_MISSING")) then
                    r, fromLive = nil, true      -- the worn hand it would pair with is still loading
                end
            end
            if r then
                if spec == "UNKNOWN" then r.status = "unknown"; r.reasons = { "UNKNOWN_SPEC" } end
            else
                if fromLive then for _, id in ipairs(missing) do deps[id] = true end end
                for _, id in ipairs(specMissing or {}) do deps[id] = true end
                r = rowsFor({ spec }, "pending", "BASELINE_ITEM_DATA_PENDING")[1]
            end
        end
        if r.status == "pending" then rowDeps[i] = deps end
        response.results[#response.results + 1] = r
    end
    response.status = GG.Engine.Evaluate.Aggregate(response.results)
    return response, rowDeps
end

-- What a response still needs: the item IDs its pending rows wait for, and
-- whether any row waits for the frame budget. A row waiting for an item that
-- gave up (`gaveUp`) becomes unknown, ITEM_DATA_UNAVAILABLE; the other rows
-- are untouched (a budget placeholder still finishes later).
local function needs(response, rowDeps, gaveUp)
    local waits, seen, deferred, changed = {}, {}, false, false
    for i, r in ipairs(response.results) do
        if r.status == "pending" then
            local deps = rowDeps[i] or {}
            local dead = false
            for id in pairs(deps) do if gaveUp and gaveUp[id] then dead = true end end
            if dead then
                r.status, r.reasons, changed = "unknown", { "ITEM_DATA_UNAVAILABLE" }, true
            else
                if r.reasons[1] == "FRAME_BUDGET" then deferred = true end
                for id in pairs(deps) do
                    if not seen[id] then seen[id] = true; waits[#waits + 1] = id end
                end
            end
        end
    end
    if changed then response.status = GG.Engine.Evaluate.Aggregate(response.results) end
    table.sort(waits)
    return waits, deferred
end

local function pendingRows(response)
    local n = 0
    for _, r in ipairs(response.results) do if r.status == "pending" then n = n + 1 end end
    return n
end

-- Answers worth asking again on the next look are never cached.
local RETRY = { NOT_READY = true, OVERLOADED = true, ITEM_QUEUE_FULL = true, ITEM_DATA_UNAVAILABLE = true,
    FRAME_BUDGET = true, NO_ITEM = true }
local function cacheable(response)
    for _, r in ipairs(response.results) do
        if r.status == "pending" then return false end
        for _, reason in ipairs(r.reasons or {}) do if RETRY[reason] then return false end end
    end
    return true
end

-- The earliest time a stored baseline in the answer goes stale.
local function expiryOf(response)
    local at
    for _, r in ipairs(response.results) do
        local e = r.baseline and r.baseline.expiresAt
        if type(e) == "number" and not r.baseline.stale and (not at or e < at) then at = e end
    end
    return at
end

-- The contextual key: item instance (or link), targets, context.
local function keyFor(link, instance, specs, context)
    local inst = ""
    if instance then
        inst = table.concat({ tostring(instance.guid or ""), tostring(instance.bag or ""), tostring(instance.slot or ""),
            tostring(instance.equipSlot or ""), instance.bound and "b" or "u" }, ",")
    end
    return table.concat({ link, inst, table.concat(specs, ","), tostring(context or "") }, "\31")
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

-- Release items no pending job depends on any more.
local function releaseUnneeded(candidates)
    for itemID in pairs(candidates) do
        local needed = false
        for _, job in pairs(state.jobs) do if job.itemIDs[itemID] then needed = true end end
        if not needed then unwait(itemID) end
    end
end

local function withId(response, id)
    local c = U.deepCopy(response)
    c.requestId = id
    return c
end

-- A job's rows resolved: every subscriber is told once, with its own id.
local function finishJob(key, response)
    local job = state.jobs[key]
    if not job then return end
    state.jobs[key] = nil
    state.jobRows = state.jobRows - job.rows
    local ids = {}
    for id in pairs(job.subs) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        state.requests[id] = nil
        state.requestCount = state.requestCount - 1
        GG.Callbacks.Fire("EvaluationReady", { requestId = id, response = withId(response, id) })
    end
    if cacheable(response) and job.generation == state.generation then
        cache.put(key, U.deepCopy(response), expiryOf(response))
    end
    releaseUnneeded(job.itemIDs)
end

local runDeferred
local function scheduleDeferred()
    if state.deferredScheduled then return end
    state.deferredScheduled = true
    C_Timer.After(0, function()
        state.deferredScheduled = false
        local ok, err = pcall(runDeferred)
        if not ok then geterrorhandler()("GlassGear API deferred: " .. tostring(err)) end
    end)
end

-- After a re-evaluation: finish the job, or keep it waiting for items and/or
-- the budget. A dependency that can't enter the item queue ends it (every row kept).
local function settle(key, response, rowDeps)
    local job = state.jobs[key]
    if not job then return end
    job.rowDeps = rowDeps
    local waitIDs, deferred = needs(response, rowDeps, job.gaveUp)
    -- An item taken for loaded that a computed row still can't use: its
    -- retries resume (never a load that waits forever).
    for i, deps in pairs(rowDeps) do
        local r = response.results[i]
        if r.status == "pending" and r.reasons[1] ~= "FRAME_BUDGET" then
            for id in pairs(deps) do
                local w = state.waiting[id]
                if w and w.ready then w.ready, w.since = nil, GetTime() end
            end
        end
    end
    local released = {}
    for old in pairs(job.itemIDs) do released[old] = true end
    local deps, full = {}, false
    for _, w in ipairs(waitIDs) do
        if wait(w) then deps[w] = true else full = true end
    end
    if full then
        for w in pairs(deps) do released[w] = true end   -- don't keep what was just queued
        job.itemIDs = {}
        finishJob(key, { status = "unknown", results = rowsFor(job.specs, "unknown", "ITEM_QUEUE_FULL") })
    elseif #waitIDs == 0 and not deferred then
        job.itemIDs = {}
        finishJob(key, response)
    else
        job.itemIDs = deps
        job.deferred = deferred
        local rows = pendingRows(response)
        state.jobRows = state.jobRows - job.rows + rows
        job.rows, job.response = rows, response
        if deferred then scheduleDeferred() end
    end
    releaseUnneeded(released)
end

-- A job's last response, when its finished rows still hold (same generation).
-- Otherwise everything is computed again, now for this generation.
local function priorOf(job)
    if job.generation == state.generation then return job.response, job.rowDeps end
    job.generation = state.generation
    return nil, job.rowDeps          -- rows recomputed; budget rows still keep their loads
end

-- Re-evaluate a job now (its finished, fresh rows kept) and settle it.
local function refresh(key)
    local job = state.jobs[key]
    if not job then return end
    local response, rowDeps = evaluateOne(job.request, nil, job.specs, priorOf(job))
    settle(key, response, rowDeps)
end

-- Is anything in the job's last response from before now: an older
-- generation, or a finished row whose baseline has since gone stale?
local function outdated(job)
    if job.generation ~= state.generation then return "generation" end
    local now = time()
    for _, r in ipairs(job.response.results) do
        if r.status ~= "pending" and not rowFresh(r, now) then return "freshness" end
    end
    return nil
end

-- A later frame: compute the jobs that were over the budget, oldest first.
runDeferred = function()
    state.frameTime, state.frameUsed = GetTime(), 0
    local list = {}
    for key, job in pairs(state.jobs) do if job.deferred then list[#list + 1] = { key = key, seq = job.seq } end end
    table.sort(list, function(a, b) return a.seq < b.seq end)
    for _, item in ipairs(list) do
        if budgetLeft() <= 0 then scheduleDeferred() return end
        refresh(item.key)
    end
end

local function overloaded(id, specs)
    return U.deepCopy({ requestId = id, status = "unknown", results = rowsFor(specs, "unknown", "OVERLOADED") })
end

function API.Evaluate(request)
    if type(request) ~= "table" then error("GlassGear.API.Evaluate: request table required", 2) end
    state.nextId = state.nextId + 1
    local id = state.nextId
    if not state.ready then
        return { requestId = id, status = "unknown", results = { { status = "unknown", reasons = { "NOT_READY" } } } }
    end
    local specs, why = targetsFor(request)
    if not specs then
        return { requestId = id, status = "unsupported", results = { { status = "unsupported", reasons = { why }, limitations = {} } } }
    end
    local link, instance = GG.Compat.ResolveItemRef(request.item)
    if not link then
        return U.deepCopy({ requestId = id, status = "unknown", results = rowsFor(specs, "unknown", "NO_ITEM") })
    end
    local key = keyFor(link, instance, specs, request.context)

    -- A cached answer of this generation, still fresh.
    local function fromCache()
        local hit = cache.get(key)
        if not hit then return nil end
        if hit.generation ~= state.generation then
            cache.drop(key)
        elseif hit.expiresAt and time() >= hit.expiresAt then
            cache.drop(key)
            API._Invalidate("freshness", { GG.player.key })   -- advances the generation now
        else
            state.stats.hits = state.stats.hits + 1
            return withId(hit.response, id)
        end
    end
    local cached = fromCache()
    if cached then return cached end
    state.stats.misses = state.stats.misses + 1

    -- The same computation already pending: subscribe to it. Its rows are
    -- brought up to date first: a new subscriber never gets an answer from
    -- before an invalidation, or one whose baseline has gone stale.
    local job = state.jobs[key]
    local why = job and outdated(job)
    if why then
        -- A finished row's baseline went stale: as for a cache hit, the
        -- freshness generation advances before this call returns.
        if why == "freshness" then API._Invalidate("freshness", { GG.player.key }) end
        refresh(key)
        job = state.jobs[key]
        if not job then
            cached = fromCache()                     -- it just finished
            if cached then return cached end
        end
    end
    if job then
        if state.requestCount >= API.LIMITS.requests then return overloaded(id, specs) end
        job.subs[id] = true
        state.requests[id] = key
        state.requestCount = state.requestCount + 1
        return withId(job.response, id)
    end

    local response, rowDeps = evaluateOne(request, id, specs)
    local waitIDs, deferred = needs(response, rowDeps)
    if #waitIDs == 0 and not deferred then
        if cacheable(response) then cache.put(key, U.deepCopy(response), expiryOf(response)) end
        return U.deepCopy(response)
    end
    local rows = pendingRows(response)
    if state.requestCount >= API.LIMITS.requests or state.jobRows + rows > API.LIMITS.jobs then
        return overloaded(id, specs)
    end
    local ids = {}
    for _, itemID in ipairs(waitIDs) do
        if not wait(itemID) then
            releaseUnneeded(ids)
            return U.deepCopy({ requestId = id, status = "unknown", results = rowsFor(specs, "unknown", "ITEM_QUEUE_FULL") })
        end
        ids[itemID] = true
    end
    state.jobSeq = state.jobSeq + 1
    state.jobs[key] = { request = request, specs = specs, itemIDs = ids, deferred = deferred, subs = { [id] = true },
        rows = rows, response = response, rowDeps = rowDeps, seq = state.jobSeq, generation = state.generation,
        gaveUp = {} }
    state.jobRows = state.jobRows + rows
    state.requests[id] = key
    state.requestCount = state.requestCount + 1
    if deferred then scheduleDeferred() end
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

local function jobsWaitingFor(itemID)
    local keys = {}
    for key, job in pairs(state.jobs) do if job.itemIDs[itemID] then keys[#keys + 1] = { key = key, seq = job.seq } end end
    table.sort(keys, function(a, b) return a.seq < b.seq end)
    return keys
end

-- GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT. A failed load leaves the
-- item waiting: the tick retries it until attempts run out.
function API._ItemDataArrived(itemID, success)
    if success == false or not state.waiting[itemID] then return end
    -- Pass 1: re-evaluate every job that waited on this item. The waiting
    -- record (and its attempt budget) goes only once the data is really usable.
    -- Whether the item is usable is read from the item itself, not from rows
    -- that happened to fit this frame's budget.
    local affected, computedMissing = {}, false
    for _, k in ipairs(jobsWaitingFor(itemID)) do
        local job = state.jobs[k.key]
        local response, rowDeps = evaluateOne(job.request, nil, job.specs, priorOf(job))
        affected[#affected + 1] = { key = k.key, response = response, rowDeps = rowDeps }
        for i, deps in pairs(rowDeps) do
            if deps[itemID] and response.results[i].reasons[1] ~= "FRAME_BUDGET" then computedMissing = true end
        end
    end
    local w = state.waiting[itemID]
    if GG.Compat.ItemLoaded(itemID) and not computedMissing and not w.ready then
        w.ready = true               -- no more retries; released once no row waits for it
        GG.Callbacks.Fire("ItemDataReady", { itemIDs = { itemID } })
    end
    -- Pass 2: reconcile each job's dependencies. An item no job needs any
    -- more is released there; one still unusable keeps its attempt count.
    for _, a in ipairs(affected) do settle(a.key, a.response, a.rowDeps) end
end

function API.CancelRequest(requestId)
    local key = state.requests[requestId]
    if not key then return false end
    state.requests[requestId] = nil
    state.requestCount = state.requestCount - 1
    local job = state.jobs[key]
    if job then
        job.subs[requestId] = nil
        if next(job.subs) == nil then
            -- Nobody waits for this computation any more: drop it and its loads.
            state.jobs[key] = nil
            state.jobRows = state.jobRows - job.rows
            releaseUnneeded(job.itemIDs)
        end
    end
    return true
end

-- About once a second while items wait: retry timed-out loads. After the
-- last attempt the item gave up: only the rows that waited for it become
-- unknown (ITEM_DATA_UNAVAILABLE); finished rows stay, and a row waiting for
-- the frame budget or another item still completes.
function API._Tick(now)
    local gaveUp = {}
    for itemID, w in pairs(state.waiting) do
        if not w.ready and now - w.since >= API.LIMITS.loadTimeout then
            if w.attempts < API.LIMITS.loadAttempts then
                w.attempts, w.since = w.attempts + 1, now
                GG.Compat.RequestItem(itemID)
            else
                gaveUp[#gaveUp + 1] = itemID
            end
        end
    end
    -- After the loop: settling a job may queue other items (never add keys
    -- to a table while pairs() walks it).
    table.sort(gaveUp)
    for _, itemID in ipairs(gaveUp) do
        local keys = jobsWaitingFor(itemID)
        unwait(itemID)
        for _, k in ipairs(keys) do
            local job = state.jobs[k.key]
            if job then
                job.gaveUp[itemID] = true
                job.itemIDs[itemID] = nil
                refresh(k.key)
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

-- Anything that changes evaluation inputs (spec mapping, profiles, baselines,
-- equipment, level, skills, settings, freshness). The generation advances at
-- once, so no cached answer from before is served again; consumers are told
-- on the next frame.
function API._Invalidate(reason, charKeys)
    state.generation = state.generation + 1
    state.gens[reason] = (state.gens[reason] or 0) + 1
    GG.Callbacks.Fire("EvaluationInvalidated", { reason = reason, charKeys = charKeys })
end

-- Test seam: drop every pending job, subscription and item load.
function API._ResetQueues()
    state.jobs, state.requests, state.waiting = {}, {}, {}
    state.jobRows, state.requestCount, state.waitingCount = 0, 0, 0
end

return API
