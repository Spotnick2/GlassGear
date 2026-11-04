------------------------------------------------------------
-- API/PublicAPI.lua - GlassGear.API v1 (docs/API.md).
--
-- Discovery, readiness, characters/specs/profiles, Evaluate and
-- AssessProtection (GG-301). A target is a (character, spec): the current
-- character's specs, and with AltStable (GG-201) the tracked alts' specs
-- (GG-203, Character/Alts.lua). Everything returned is a deep copy.
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
-- jobs[jobKey] = { request, targets, itemIDs = {[id]=true}, deferred, subs = {[requestId]=true}, rows, seq }
-- waiting[itemID] = { attempts, since }   (the one owner of load attempts)
local state = { ready = false, nextId = 0, requests = {}, requestCount = 0, jobs = {}, jobRows = 0, jobSeq = 0,
    waiting = {}, waitingCount = 0, generation = 0, gens = {}, frameTime = nil, frameUsed = 0,
    deferredScheduled = false,
    protectionWaits = {},     -- [itemID] = true: an AssessProtection waits for this item's data
    protectionGaveUp = {},    -- [itemID] = GetTime() its load gave up: unknown until PROTECTION_RETRY passes
    itemDataSignal = nil,     -- item IDs for the next coalesced EvaluationInvalidated(itemData)
    equippedMemo = nil,       -- { frame, generation, equipped, missing } (one build per frame)
    nextExpiry = nil,         -- earliest baseline expiresAt a protection answer depended on
    stats = { evaluations = 0, hits = 0, misses = 0, deferredRows = 0, protections = 0 } }
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
    local roster = GG.Integrations.RosterProvider.DetectAltStable().usable   -- GG-201
    return {
        roster = roster,
        evaluate = true, evaluateBatch = true, cancelRequest = true,
        scopes = { current = true, own = true, tracked = true, ["own+tracked"] = true, targets = true },
        alts = roster, sync = false, assessProtection = true, frameBudget = true, resultCache = true,
        defaultWeights = GG.Data.Defaults.Any(),      -- GG-120: specs without an import score with a default
    }
end

function API.GetCapabilities()
    local alt = GG.Integrations.RosterProvider.DetectAltStable()
    return U.deepCopy({
        apiVersion = API.API_VERSION, build = GG.MEASURED_ON_BUILD, features = features(),
        limits = API.LIMITS,
        unavailable = {
            -- English: other addons read these (the player's text is RosterProvider.Status).
            alts = not alt.usable and alt.reason or nil,
            sync = "needs the entry-sync library (ES-001, GG-202); until then the other account's alts have no weights here",
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
    -- What the spec scores with: the player's import, or a default (source "default", GG-120).
    local p = GG.Profiles.Effective(GG.store, charKey, specKey)
    if not p then return nil, "NO_WEIGHTS" end
    return U.deepCopy(p)
end

------------------------------------------------------------
-- Evaluation
------------------------------------------------------------

-- The current character's specs in API order: the current spec, then the
-- others in tree order; `only(spec)` filters them.
local function ownTargets(only)
    local p, out = GG.player, {}
    if GG.currentSpec and (not only or only(GG.currentSpec)) then out[1] = { char = p, spec = GG.currentSpec } end
    for _, s in ipairs(GG.Data.Classes.Specs(p.class)) do
        if s.key ~= GG.currentSpec and (not only or only(s.key)) then out[#out + 1] = { char = p, spec = s.key } end
    end
    return out
end

local function withTrackedAlts(list)
    for _, t in ipairs(GG.Alts.Tracked()) do list[#list + 1] = t end
    return list
end

local function tracked(spec) return GG.Prefs.IsTracked(GG.player.key, spec) end

-- Is `spec` (a string) one of that class's specs?
local function classHas(class, spec)
    if type(spec) ~= "string" then return false end
    for _, s in ipairs(GG.Data.Classes.Specs(class)) do if s.key == spec then return true end end
    return false
end

-- The request's (character, spec) targets, in API order: the current
-- character's, then the tracked alts' (the roster's order, tree order).
--   current       the current spec
--   own           every spec of the current character
--   tracked       the protection scope: its tracked specs and the tracked alts'
--   own+tracked   every own spec and the tracked alts' (the bag and tooltip surfaces)
--   targets       request.targets: the current character or own alts
-- A derived scope over LIMITS.targets is refused (TOO_MANY_TARGETS), never cut.
local function targetsFor(request)
    local p = GG.player
    local scope = request.scope or "current"
    local list
    if scope == "current" then
        list = { { char = p, spec = GG.currentSpec or "UNKNOWN" } }
    elseif scope == "own" then
        list = ownTargets()
    elseif scope == "tracked" then
        list = withTrackedAlts(ownTargets(tracked))
    elseif scope == "own+tracked" then
        list = withTrackedAlts(ownTargets())
    elseif scope == "targets" then
        if #(request.targets or {}) > API.LIMITS.targets then return nil, "TOO_MANY_TARGETS" end
        list = {}
        for _, t in ipairs(request.targets or {}) do
            local c = type(t) == "table" and GG.Integrations.RosterProvider.Find(t.char)
            if not c then return nil, "UNKNOWN_CHARACTER" end
            -- Every target, the current character's too: a spec of that character's class.
            if not classHas(c.class, t.spec) then return nil, "UNKNOWN_SPEC" end
            list[#list + 1] = { char = c, spec = t.spec }
        end
    else
        return nil, "SCOPE_UNSUPPORTED"
    end
    if #list > API.LIMITS.targets then return nil, "TOO_MANY_TARGETS" end
    return list
end

-- By key: GG.player is rebuilt on a level-up, and a pending job keeps the
-- targets it was made with.
local function isMe(t) return GG.player ~= nil and t.char ~= nil and t.char.key == GG.player.key end

local function charOf(t)
    local c = t.char
    return c and { key = c.key, name = c.name, realm = c.realm, provenance = c.provenance, current = isMe(t) } or nil
end

-- One row per target with the same status and reason (placeholders, overload, timeout).
local function rowsFor(targets, status, reason)
    local rows = {}
    for _, t in ipairs(targets) do
        rows[#rows + 1] = { status = status, spec = t.spec, current = isMe(t) and t.spec == GG.currentSpec,
            character = charOf(t), reasons = { reason }, limitations = {} }
    end
    return rows
end

-- Evaluation settings. Protection uses its own threshold (adr/0006: the
-- three scopes are independent; Prefs keeps the two values equal today).
local function settingsFor(forProtection)
    local s = GG.db and GG.db.settings or GG.DB.DEFAULTS.settings
    local threshold = forProtection and s.protection.threshold or s.markers.threshold
    return { threshold = threshold, levelWindow = s.levelWindow, specArmor = s.specArmor }
end

-- The per-frame budget. GetTime() is the frame's time; the deferred runner
-- always starts a new window (it runs on a later frame).
-- The frame window: everything counted per frame starts again together
-- (rows spent, time spent). `force`: the deferred runner, on a later frame.
local function frameWindow(force)
    local now = GetTime()
    if force or state.frameTime ~= now then state.frameTime, state.frameUsed, state.frameMs = now, 0, 0 end
end

local function budgetLeft()
    frameWindow()
    return API.LIMITS.perFrame - state.frameUsed
end

-- GG-402: the time the budgeted work takes in one frame (evaluating, and
-- settling what it computed), the worst frame kept (/gg stats), so the
-- budget can be judged in the real client.
local function noteTime(ms)
    frameWindow()
    state.frameMs = (state.frameMs or 0) + ms
    if state.frameMs > (state.stats.maxFrameMs or 0) then state.stats.maxFrameMs = state.frameMs end
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

-- "Better gear already owned" (GG-122): the owned items that compete for the
-- candidate's slots, each evaluated for the same spec and baseline (at most
-- OWNED_CHECKS of them), then Evaluate.ApplyOwned.
API.OWNED_CHECKS = 8
-- An owned item's evaluation depends on the spec, the generation (profiles,
-- baselines, equipment, bags...) and whether it is for protection: kept
-- for that generation, so a bag scan evaluates each owned item once per
-- spec, not once per candidate. Fresh ones are charged to the budget.
local function ownedMemoMap()
    local memo = state.ownedMemo
    if not memo or memo.generation ~= state.generation then
        memo = { generation = state.generation, map = {} }
        state.ownedMemo = memo
    end
    return memo.map
end

local function ownedKey(spec, itemString, protection)
    return spec .. "\31" .. itemString .. (protection and "\31p" or "")
end

-- The owned items a candidate competes with (at most OWNED_CHECKS).
local function competing(owned, item)
    local list = {}
    for _, o in ipairs(owned) do
        if #list >= API.OWNED_CHECKS then break end
        if o.facts.itemString ~= item.itemString and GG.Owned.SameSlots(o.facts.equipLoc, item.equipLoc) then
            list[#list + 1] = o
        end
    end
    return list
end

-- What a display row's owned checks could still cost this generation: the
-- competing items not evaluated yet for that spec (an upper bound: they
-- run only when the row is an upgrade).
local function ownedCost(owned, item, spec)
    local map, n = ownedMemoMap(), 0
    for _, o in ipairs(competing(owned, item)) do
        if not map[ownedKey(spec, o.facts.itemString, false)] then n = n + 1 end
    end
    return n
end

local function ownedResult(o, input, spec, protection, companionsWithout, charge)
    local map = ownedMemoMap()
    local key = ownedKey(spec, o.facts.itemString, protection)
    local hit = map[key]
    if hit then return hit end
    charge()
    local oi = {}
    for k, v in pairs(input) do oi[k] = v end
    oi.item, oi.instance, oi.current = o.facts, nil, false
    -- Every copy but this one (two identical copies: same answer either way).
    oi.companions = companionsWithout({ itemString = o.facts.itemString, bag = o.bag, slot = o.slot })
    local res = GG.Engine.Evaluate.One(oi)
    map[key] = res
    return res
end

local function ownedCheck(r, input, owned, companionsWithout, protection, charge)
    local item = input.item
    local results = {}
    for _, o in ipairs(competing(owned, item)) do
        results[#results + 1] = { item = o.facts, link = o.link,
            result = ownedResult(o, input, input.spec, protection, companionsWithout, charge) }
    end
    local positions = GG.Owned.Positions(item.equipLoc, input.recipient and input.recipient.canDualWield)
    -- Worn items in the other positions that already beat the candidate take
    -- those positions (rings, trinkets, dual-wield weapons).
    local wornBetter = 0
    if positions > 1 and input.profile then
        local mine = GG.Engine.Score.Compute(item.tokens or {}, input.profile).score
        for _, s in ipairs(GG.Data.Slots.FOR_EQUIP_LOC[item.equipLoc] or {}) do
            local b = input.baseline and input.baseline.slots and input.baseline.slots[s]
            if b and b.state == "occupied" and b.tokens
                and GG.Engine.Score.Compute(b.tokens, input.profile).score > mine then
                wornBetter = wornBetter + 1
            end
        end
    end
    return GG.Engine.Evaluate.ApplyOwned(r, results, positions, { candidate = item.itemString, wornBetter = wornBetter })
end

-- Returns response, rowDeps ([i] = { [itemID] = true }: what a pending row
-- waits for). A pending request is re-evaluated against the targets captured
-- when it was made. `prior` (the job's last response, same generation) lends
-- its finished, still fresh rows: they aren't computed again, so a job always
-- progresses, whatever the budget. A row put off by the budget keeps what it
-- waited for before (`priorDeps`): the job keeps those item loads, with their
-- attempts, until the row is computed again.
-- `opts.protection`: a protection assessment, synchronous and bounded: every
-- row is computed now (never put off by the frame budget), with the
-- protection threshold. The wrapper times the work (GG-402).
local evaluateOneTimed
local function evaluateOne(...)
    local t0 = GG.Compat.Clock()
    local response, rowDeps = evaluateOneTimed(...)
    noteTime(GG.Compat.Clock() - t0)
    return response, rowDeps
end

evaluateOneTimed = function(request, requestId, targets, prior, priorDeps, opts)
    opts = opts or {}
    local response = { requestId = requestId, results = {} }
    local rowDeps = {}
    local link, instance
    if opts.link then link, instance = opts.link, opts.instance
    else link, instance = GG.Compat.ResolveItemRef(request.item) end
    local facts = link and GG.Compat.ItemFacts(link)
    if not facts then
        response.results = rowsFor(targets, "unknown", "NO_ITEM")
        response.status = "unknown"
        return response, rowDeps
    end
    local now = time()
    -- The worn gear, built once per frame and generation (a bag scan by a
    -- consumer evaluates many items in one frame; equipment changes invalidate).
    local memo = state.equippedMemo
    local frame = GetTime()
    if not (memo and memo.frame == frame and memo.generation == state.generation and #memo.missing == 0) then
        local e, m = GG.Compat.EquippedBaseline(now)
        memo = { frame = frame, generation = state.generation, equipped = e, missing = m }
        state.equippedMemo = memo
    end
    local equipped, missing = memo.equipped, memo.missing
    -- Worn items still loading hold up only the specs that need them (GG-108):
    -- those compared with the current gear, and a candidate that pairs with a
    -- worn hand whose data hasn't arrived. Pending, not an "unknown slot" verdict.
    local handLoading = #missing > 0
        and (equipped.slots[16].state == "unknown" or equipped.slots[17].state == "unknown")
    -- A candidate that needs a companion (a 1H against a spec's 2H) pairs
    -- with the best usable hand: the one worn now, or one from the bags
    -- (GG-122). Never with itself, but another copy of the same item is a
    -- different item (two identical one-handers: one is the other's
    -- partner). `self` = { itemString, bag, slot, equipSlot }: the copy
    -- that is the item, by its bag or worn slot; a bare link (no instance)
    -- leaves out the first copy found, since it may be the one shown.
    local owned = GG.Owned and GG.Owned.Items() or {}
    local function companionsWithout(self)
        local lists = { [16] = {}, [17] = {} }
        local skipped = false
        local function isSelf(itemString, bag, slot, equipSlot)
            if skipped or itemString ~= self.itemString then return false end
            if self.bag then return bag == self.bag and slot == self.slot end
            if self.equipSlot then return equipSlot == self.equipSlot end
            return true
        end
        for _, s in ipairs({ 16, 17 }) do
            local worn = equipped.slots[s]
            if worn and worn.state == "occupied" then
                if isSelf(worn.itemString, nil, nil, s) then
                    skipped = true
                else
                    local c = {}
                    for k, v in pairs(worn) do c[k] = v end
                    c.worn = true
                    lists[s][1] = c
                end
            end
        end
        for _, o in ipairs(owned) do
            if isSelf(o.facts.itemString, o.bag, o.slot, nil) then
                skipped = true
            else
                for _, s in ipairs(GG.Data.Slots.FOR_EQUIP_LOC[o.facts.equipLoc] or {}) do
                    if s == 16 or s == 17 then lists[s][#lists[s] + 1] = o.slotItem end
                end
            end
        end
        return lists
    end
    local companions = companionsWithout({ itemString = facts.itemString,
        bag = instance and instance.bag, slot = instance and instance.slot,
        equipSlot = instance and instance.equipSlot })
    -- The owned checks' cost (GG-122): display rows charge the frame budget,
    -- protection only counts (it never spends the display budget).
    local function charge()
        state.stats.ownedEvaluations = (state.stats.ownedEvaluations or 0) + 1
        if not opts.protection then state.frameUsed = state.frameUsed + 1 end
    end
    local settings = settingsFor(opts.protection)
    for i, t in ipairs(targets) do
        local spec, me = t.spec, isMe(t)
        -- An alt as the roster has it now (a pending job keeps its targets).
        local alt = not me and t.char and GG.Integrations.RosterProvider.Find(t.char.key)
        -- Can the item reach that alt at all (GG-203)? Decided before any
        -- work: a bound item costs its alts nothing.
        local transfer = alt and facts.ready and GG.Alts.Transfer(facts, instance, alt)
        local r, putOff
        local deps = {}
        local done = prior and prior.results[i]
        if done and done.status ~= "pending" and done.spec == spec and rowFresh(done, now)
            and done.character and t.char and done.character.key == t.char.key then
            r = done
        elseif not me and not alt then
            r = rowsFor({ t }, "unknown", "UNKNOWN_CHARACTER")[1]      -- forgotten meanwhile
        elseif transfer and transfer.state == "ineligible" then
            r = rowsFor({ t }, "ineligible", "NOT_TRANSFERABLE")[1]
            r.transfer = transfer
        elseif not opts.protection and budgetLeft() <= 0 then
            -- Over this frame's budget: a placeholder, computed on a later frame.
            state.stats.deferredRows = state.stats.deferredRows + 1
            r = rowsFor({ t }, "pending", "FRAME_BUDGET")[1]
            for id in pairs(priorDeps and priorDeps[i] or {}) do deps[id] = true end
        elseif alt then
            if opts.protection then state.stats.evaluations = state.stats.evaluations + 1 else spend() end
            if not facts.ready then deps[facts.itemID] = true end
            -- The alt's own gear for that spec; its own bags are unknown, so no
            -- "better gear already owned" check (GG-122 is this character's).
            local baseline, altMissing, why = GG.Alts.BaselineFor(alt, spec, now)
            if baseline then
                r = GG.Engine.Evaluate.One({
                    item = facts, recipient = GG.Alts.Recipient(alt, baseline), spec = spec, current = false,
                    profile = GG.Profiles.Effective(GG.store, alt.key, spec),
                    baseline = baseline, settings = settings, instance = instance,
                    companions = GG.Alts.Companions(baseline), transfer = transfer or nil,
                })
            elseif why then
                r = rowsFor({ t }, "unknown", why)[1]
            else
                for _, id in ipairs(altMissing or {}) do deps[id] = true end
                r = rowsFor({ t }, "pending", "BASELINE_ITEM_DATA_PENDING")[1]
            end
        else
            local firstOfFrame = state.frameUsed == 0
            if opts.protection then
                -- Protection never spends the display budget (adr/0006).
                state.stats.evaluations = state.stats.evaluations + 1
            else
                spend()
            end
            if not facts.ready then deps[facts.itemID] = true end
            -- Each spec's own gear (GG-108): a set, what it wore, or the current gear.
            local baseline, specMissing, fromLive = GG.Capture.BaselineFor(spec, equipped, now)
            if baseline and not (fromLive and #missing > 0) then
                local input = {
                    item = facts, recipient = GG.player, spec = spec, current = spec == GG.currentSpec,
                    profile = GG.Profiles.Effective(GG.store, GG.player.key, spec),
                    baseline = baseline, settings = settings, instance = instance,
                    companions = companions,
                    transfer = { state = "eligible", reasons = { "SAME_CHARACTER" } },
                }
                r = GG.Engine.Evaluate.One(input)
                if r.status == "upgrade" then
                    -- The owned checks are paid from the same budget: when what
                    -- they could still cost doesn't fit, the row waits whole for
                    -- a later frame (never over the budget), and the frame closes,
                    -- so at most one row a frame is computed twice. The first row
                    -- of a frame always finishes, so a tiny budget still progresses.
                    if not opts.protection and not firstOfFrame
                        and budgetLeft() < ownedCost(owned, facts, spec) then
                        r, putOff = nil, true
                        state.frameUsed = API.LIMITS.perFrame
                    else
                        r = ownedCheck(r, input, owned, companionsWithout, opts.protection, charge)
                    end
                end
                if r and handLoading and r.status == "unknown"
                    and (U.contains(r.reasons, "NEEDS_COMPANION") or U.contains(r.reasons, "COMPANION_DATA_MISSING")) then
                    r, fromLive = nil, true      -- the worn hand it would pair with is still loading
                end
            end
            if putOff then
                state.stats.deferredRows = state.stats.deferredRows + 1
                r = rowsFor({ t }, "pending", "FRAME_BUDGET")[1]
                for id in pairs(priorDeps and priorDeps[i] or {}) do deps[id] = true end
            elseif r then
                if spec == "UNKNOWN" then r.status = "unknown"; r.reasons = { "UNKNOWN_SPEC" } end
            else
                if fromLive then for _, id in ipairs(missing) do deps[id] = true end end
                for _, id in ipairs(specMissing or {}) do deps[id] = true end
                r = rowsFor({ t }, "pending", "BASELINE_ITEM_DATA_PENDING")[1]
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
local function keyFor(link, instance, targets, context)
    local inst = ""
    if instance then
        inst = table.concat({ tostring(instance.guid or ""), tostring(instance.bag or ""), tostring(instance.slot or ""),
            tostring(instance.equipSlot or ""), instance.bound and "b" or "u" }, ",")
    end
    local who = {}
    for i, t in ipairs(targets) do who[i] = t.char.key .. "/" .. t.spec end
    return table.concat({ link, inst, table.concat(who, ","), tostring(context or "") }, "\31")
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
        local needed = state.protectionWaits[itemID] == true
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
local settleTimed
local function settle(...)
    local t0 = GG.Compat.Clock()
    settleTimed(...)
    noteTime(GG.Compat.Clock() - t0)
end

settleTimed = function(key, response, rowDeps)
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
        finishJob(key, { status = "unknown", results = rowsFor(job.targets, "unknown", "ITEM_QUEUE_FULL") })
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
    local response, rowDeps = evaluateOne(job.request, nil, job.targets, priorOf(job))
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
    frameWindow(true)
    local list = {}
    for key, job in pairs(state.jobs) do if job.deferred then list[#list + 1] = { key = key, seq = job.seq } end end
    table.sort(list, function(a, b) return a.seq < b.seq end)
    for _, item in ipairs(list) do
        if budgetLeft() <= 0 then scheduleDeferred() return end
        refresh(item.key)
    end
end

local function overloaded(id, targets)
    return U.deepCopy({ requestId = id, status = "unknown", results = rowsFor(targets, "unknown", "OVERLOADED") })
end

function API.Evaluate(request)
    if type(request) ~= "table" then error("GlassGear.API.Evaluate: request table required", 2) end
    state.nextId = state.nextId + 1
    local id = state.nextId
    if not state.ready then
        return { requestId = id, status = "unknown", results = { { status = "unknown", reasons = { "NOT_READY" } } } }
    end
    local targets, why = targetsFor(request)
    if not targets then
        return { requestId = id, status = "unsupported", results = { { status = "unsupported", reasons = { why }, limitations = {} } } }
    end
    local link, instance = GG.Compat.ResolveItemRef(request.item)
    if not link then
        return U.deepCopy({ requestId = id, status = "unknown", results = rowsFor(targets, "unknown", "NO_ITEM") })
    end
    local key = keyFor(link, instance, targets, request.context)

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
        if state.requestCount >= API.LIMITS.requests then return overloaded(id, targets) end
        job.subs[id] = true
        state.requests[id] = key
        state.requestCount = state.requestCount + 1
        return withId(job.response, id)
    end

    local response, rowDeps = evaluateOne(request, id, targets)
    local waitIDs, deferred = needs(response, rowDeps)
    if #waitIDs == 0 and not deferred then
        if cacheable(response) then cache.put(key, U.deepCopy(response), expiryOf(response)) end
        return U.deepCopy(response)
    end
    local rows = pendingRows(response)
    if state.requestCount >= API.LIMITS.requests or state.jobRows + rows > API.LIMITS.jobs then
        return overloaded(id, targets)
    end
    local ids = {}
    for _, itemID in ipairs(waitIDs) do
        if not wait(itemID) then
            releaseUnneeded(ids)
            return U.deepCopy({ requestId = id, status = "unknown", results = rowsFor(targets, "unknown", "ITEM_QUEUE_FULL") })
        end
        ids[itemID] = true
    end
    state.jobSeq = state.jobSeq + 1
    state.jobs[key] = { request = request, targets = targets, itemIDs = ids, deferred = deferred, subs = { [id] = true },
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
        local response, rowDeps = evaluateOne(job.request, nil, job.targets, priorOf(job))
        affected[#affected + 1] = { key = k.key, response = response, rowDeps = rowDeps }
        for i, deps in pairs(rowDeps) do
            if deps[itemID] and response.results[i].reasons[1] ~= "FRAME_BUDGET" then computedMissing = true end
        end
    end
    local w = state.waiting[itemID]
    if state.protectionWaits[itemID] and GG.Compat.ItemLoaded(itemID) then
        -- A protection answer was pending on it: consumers (Shatter) re-ask.
        state.protectionWaits[itemID] = nil
        API._SignalItemData(itemID)
        if not next(jobsWaitingFor(itemID)) then unwait(itemID) end
    end
    if GG.Compat.ItemLoaded(itemID) then state.protectionGaveUp[itemID] = nil end
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
        if state.protectionWaits[itemID] then
            -- A protection answer waited for it: it is final now (unknown,
            -- kept), and the consumer is told to ask again.
            state.protectionWaits[itemID] = nil
            state.protectionGaveUp[itemID] = now
            API._SignalItemData(itemID)
        end
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

------------------------------------------------------------
-- Protection (GG-301, API.md "Protection", adr/0003, adr/0006)
------------------------------------------------------------

-- The protection scope: the tracked specs of the current character, then
-- the tracked alts' (GG-203), as Evaluate's "tracked" scope. Read from the
-- protection settings only, never from the tooltip or marker scopes.
local function protectionTargets()
    if not GG.player then return {} end
    return targetsFor({ scope = "tracked" })
end

-- A short opaque hash (djb2) so consumers compare tokens, never parse them.
local function hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

-- The early answers (not ready, no item, nothing tracked, errors): the shape
-- of Policy.Protection's, no token (consumers never store an override for them).
local function verdictOf(verdict, reasons)
    return { verdict = verdict, token = nil, expiresAt = nil, recipients = {}, unchecked = {}, reasons = reasons }
end

local NO_WEIGHTS_MODES = { ignore = true, keep = true }
API.PROTECTION_RETRY = 60    -- seconds an item whose load gave up stays unknown before a new try

local function assess(itemRef, opts)
    opts = type(opts) == "table" and opts or {}
    if not state.ready then return verdictOf("unknown", { "NOT_READY" }) end
    -- One scope: the tracked specs. Anything else is refused, never narrowed.
    if opts.scope ~= nil and opts.scope ~= "tracked" then return verdictOf("unsupported", { "SCOPE_UNSUPPORTED" }) end
    -- A baseline a previous answer depended on went stale meanwhile: the
    -- freshness generation advances first, so this token differs.
    if state.nextExpiry and time() >= state.nextExpiry then
        state.nextExpiry = nil
        API._Invalidate("freshness", GG.player and { GG.player.key } or nil)
    end
    local targets, tooMany = protectionTargets()
    if not targets then return verdictOf("unknown", { tooMany }) end
    if #targets == 0 then return verdictOf("unknown", { "NO_PROTECTION_TARGETS" }) end
    local link, instance = GG.Compat.ResolveItemRef(itemRef)
    if not link then return verdictOf("unknown", { "NO_ITEM" }) end
    state.stats.protections = state.stats.protections + 1
    -- Computed now, every time: protection never reads a cached answer
    -- (instance bind state, GUID and expiry are re-read on every call).
    local response, rowDeps = evaluateOne({ item = itemRef }, nil, targets, nil, nil,
        { protection = true, link = link, instance = instance })
    local s = GG.db and GG.db.settings.protection or GG.DB.DEFAULTS.settings.protection
    -- noWeights: "ignore" or "keep"; anything else keeps the item (fail-closed).
    local noWeights = opts.noWeights
    if noWeights == nil then noWeights = NO_WEIGHTS_MODES[s.noWeights] and s.noWeights or "keep"
    elseif not NO_WEIGHTS_MODES[noWeights] then noWeights = "keep" end
    local out = GG.Engine.Policy.Protection(response.results, { noWeights = noWeights })
    if out.verdict == "pending" then
        -- Load what it needs; when the data arrives (or gives up),
        -- EvaluationInvalidated(itemData) tells the consumer to ask again.
        -- No verdict is ever delivered later by itself.
        local needed, seen = {}, {}
        for _, deps in pairs(rowDeps) do
            for itemID in pairs(deps) do
                if not seen[itemID] then seen[itemID] = true; needed[#needed + 1] = itemID end
            end
        end
        table.sort(needed)
        local gaveUp = false
        for _, itemID in ipairs(needed) do
            local at = state.protectionGaveUp[itemID]
            if at and GetTime() - at < API.PROTECTION_RETRY then gaveUp = true
            else state.protectionGaveUp[itemID] = nil end           -- long enough: try loading again
        end
        if gaveUp then
            out.verdict = "unknown"
            out.reasons[#out.reasons + 1] = "ITEM_DATA_UNAVAILABLE"
        else
            local added, full = {}, false
            for _, itemID in ipairs(needed) do
                if wait(itemID) then
                    local w = state.waiting[itemID]
                    -- Taken for loaded by another job, yet a row here can't
                    -- use it: its retries resume (never pinned forever).
                    if w.ready then w.ready, w.since = nil, GetTime() end
                    if not state.protectionWaits[itemID] then added[#added + 1] = itemID end
                    state.protectionWaits[itemID] = true
                else
                    full = true
                    break
                end
            end
            if full then
                -- Nothing half-queued for an answer that is already final.
                local release = {}
                for _, itemID in ipairs(added) do state.protectionWaits[itemID] = nil; release[itemID] = true end
                releaseUnneeded(release)
                out.verdict = "unknown"
                out.reasons[#out.reasons + 1] = "ITEM_QUEUE_FULL"
            end
        end
    end
    local expiresAt = expiryOf(response)
    if expiresAt and (not state.nextExpiry or expiresAt < state.nextExpiry) then state.nextExpiry = expiresAt end
    out.expiresAt = expiresAt
    local guid = instance and instance.guid
    out.token = hash(table.concat({ tostring(guid or link), tostring(instance and instance.bound and 1 or 0),
        tostring(state.generation), noWeights, keyFor("", nil, targets, "") }, "|"))
    out.instance = instance and { guid = guid, bound = instance.bound } or nil
    return out
end

-- Synchronous and bounded (the protection targets only, never deferred).
-- Any failure answers "unknown": consumers keep the item (fail-closed).
function API.AssessProtection(itemRef, opts)
    local ok, out = pcall(assess, itemRef, opts)
    if not ok then
        geterrorhandler()("GlassGear AssessProtection: " .. tostring(out))
        return verdictOf("unknown", { "INTERNAL_ERROR" })
    end
    return U.deepCopy(out)
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
    if GG.Alts then GG.Alts.Forget() end
    state.gens[reason] = (state.gens[reason] or 0) + 1
    GG.Callbacks.Fire("EvaluationInvalidated", { reason = reason, charKeys = charKeys })
end

-- Item data a protection answer waited for has arrived (or gave up): tell
-- consumers to ask again. Coalesced to one event per frame; it does not
-- advance the generation: no cached answer depends on an item that wasn't
-- loaded (pending answers are never cached).
function API._SignalItemData(itemID)
    if state.itemDataSignal then
        state.itemDataSignal[#state.itemDataSignal + 1] = itemID
        return
    end
    state.itemDataSignal = { itemID }
    C_Timer.After(0, function()
        local ids = state.itemDataSignal or {}
        state.itemDataSignal = nil
        table.sort(ids)
        GG.Callbacks.Fire("EvaluationInvalidated", { reason = "itemData", itemIDs = ids,
            charKeys = GG.player and { GG.player.key } or nil })
    end)
end

-- Test seam: drop every pending job, subscription and item load.
function API._ResetQueues()
    state.jobs, state.requests, state.waiting = {}, {}, {}
    state.jobRows, state.requestCount, state.waitingCount = 0, 0, 0
    state.protectionWaits, state.protectionGaveUp, state.nextExpiry = {}, {}, nil
    state.equippedMemo = nil
end

return API
