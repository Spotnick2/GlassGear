------------------------------------------------------------
-- test_api_runtime.lua - GG-114: the API runtime. The result cache (hits,
-- copies, keys by instance / targets / context, LRU eviction), generations
-- (any invalidation, and freshness advancing before the call returns), the
-- per-frame budget (placeholders, completion on a later frame, progress
-- whatever the budget), deduplicated jobs (one computation, one callback per
-- request, cancel), the job and request bounds (OVERLOADED, terminal, not
-- cached), and no recomputation or roster scan on tooltip redraws.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local INT, HEAL = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT"
local function shoulder(name, stats, bindType)
    return { name = name, equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = stats, bindType = bindType }
end
WoW.items[50] = shoulder("Old Mantle", { [INT] = 10 })
WoW.items[51] = shoulder("Mantle A", { [INT] = 20 })
WoW.items[52] = shoulder("Mantle B", { [INT] = 21 })
WoW.items[53] = shoulder("Mantle C", { [INT] = 22 })
WoW.items[54] = shoulder("Healer Spaulders", { [HEAL] = 30 })
WoW.items[55] = shoulder("Mantle D", { [INT] = 23 })
WoW.items[60] = shoulder("Boe Mantle", { [INT] = 25 }, 2)
WoW.equipped = { [3] = 50 }
WoW.bags[0] = { [1] = { itemID = 60, isBound = false, guid = "Item-1-BOE" } }

local GG = WoW.loadAddon()
local api, S = GG.API, GG.API._state
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR("spec 2 PRIEST.HOLY")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1 )')
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy": Class=Priest, Intellect=1, Healing=1 )')
WoW.flush()
local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end return false end
local ready = {}
api.RegisterCallback("EvaluationReady", function(_, p) ready[#ready + 1] = p end, "test_api_runtime")
local inval = {}
api.RegisterCallback("EvaluationInvalidated", function(_, p) inval[#inval + 1] = p.reason end, "test_api_runtime")

local caps = api.GetCapabilities()
H.eq(caps.features.frameBudget, true, "features.frameBudget")
H.eq(caps.features.resultCache, true, "features.resultCache")
H.eq(caps.limits.perFrame, 200, "limits are published")

------------------------------------------------------------
-- The cache.
------------------------------------------------------------
local function evals() return S.stats.evaluations end
local e0 = evals()
local a = api.Evaluate({ item = WoW.link(51), scope = "own" })
H.eq(evals() - e0, 3, "first look: three rows computed")
local b = api.Evaluate({ item = WoW.link(51), scope = "own" })
H.eq(evals() - e0, 3, "same item, scope and context again: nothing computed")
H.check(b.requestId ~= a.requestId, "...a new request id")
H.eq(b.results[1].score.delta, a.results[1].score.delta, "...the same answer")
b.results[1].status = "mangled"
H.eq(api.Evaluate({ item = WoW.link(51), scope = "own" }).results[1].status, a.results[1].status,
    "...and a returned copy can't change the cache")
api.Evaluate({ item = WoW.link(51), scope = "current" })
H.eq(evals() - e0, 4, "another scope (other targets): computed")
api.Evaluate({ item = WoW.link(51), scope = "own", context = "loot" })
H.eq(evals() - e0, 7, "another context: computed")

-- Any invalidation: computed again.
local e1 = evals()
api._Invalidate("settings", { GG.player.key })
api.Evaluate({ item = WoW.link(51), scope = "own" })
H.eq(evals() - e1, 3, "after any invalidation nothing old is served")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow2": Class=Priest, Intellect=2 )')
local c = api.Evaluate({ item = WoW.link(51), scope = "current" })
H.eq(c.results[1].score.delta, 20, "a weight change shows at once (Intellect 2: +20)")

-- Bag instances: the key follows the instance's state.
local e2 = evals()
api.Evaluate({ item = { bag = 0, slot = 1 }, scope = "current" })
api.Evaluate({ item = { bag = 0, slot = 1 }, scope = "current" })
H.eq(evals() - e2, 1, "a bag instance is cached too")
WoW.bags[0][1].isBound = true                -- the BoE was equipped and put back: soulbound now
local bound = api.Evaluate({ item = { bag = 0, slot = 1 }, scope = "current" })
H.eq(evals() - e2, 2, "...its bind state changing: computed again")
H.eq(bound.results[1].candidate.instance.bound, true, "...with the new state")
WoW.bags[0][2], WoW.bags[0][1] = WoW.bags[0][1], nil
local moved = api.Evaluate({ item = { bag = 0, slot = 2 }, scope = "current" })
H.eq(moved.results[1].candidate.instance.slot, 2, "moved to another slot: its own answer, with the new slot")

-- LRU: the least recently used answer goes first.
local savedCache = api.LIMITS.cache
api.LIMITS.cache = 3
api._cache.clear()
local function look(id) api.Evaluate({ item = WoW.link(id), scope = "current" }) end
look(51); look(52); look(53)
look(51)                                     -- 51 used again: 52 is now the oldest
look(55)                                     -- a fourth: evicts 52
local e3 = evals()
look(51); look(53); look(55)
H.eq(evals() - e3, 0, "the three most recent answers stay")
look(52)
H.eq(evals() - e3, 1, "the least recently used one was evicted")
H.eq(api._cache.size, 3, "the cache never holds more than its limit")
api.LIMITS.cache = savedCache

------------------------------------------------------------
-- Freshness: a stored baseline going stale.
------------------------------------------------------------
WoW.specGroup = 2
WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
WoW.equipped = { [3] = 54 }
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
WoW.flush()
WoW.specGroup = 1
WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", 1, 2)
WoW.equipped = { [3] = 50 }
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
WoW.flush()
local function holy(r) for _, x in ipairs(r.results) do if x.spec == "PRIEST.HOLY" then return x end end end
local fresh = api.Evaluate({ item = WoW.link(53), scope = "own" })
H.eq(holy(fresh).baseline.source, "observed", "Holy compares with its recorded gear")
H.eq(holy(fresh).baseline.stale, false, "...fresh")
local e4 = evals()
api.Evaluate({ item = WoW.link(53), scope = "own" })
H.eq(evals() - e4, 0, "cached while fresh")
WoW.flush(); inval = {}
local gen = S.generation
WoW.epoch = holy(fresh).baseline.expiresAt + 1
local after = api.Evaluate({ item = WoW.link(53), scope = "own" })
H.check(S.generation > gen, "past expiresAt: the generation advanced before the call returned")
H.eq(evals() - e4, 3, "...the answer is computed again")
H.eq(holy(after).baseline.stale, true, "...and says the baseline is stale")
WoW.flush()
H.check(has(inval, "freshness"), "...then EvaluationInvalidated(freshness) follows")

------------------------------------------------------------
-- The frame budget.
------------------------------------------------------------
api._cache.clear()
local savedBudget = api.LIMITS.perFrame
api.LIMITS.perFrame = 2
WoW.time = WoW.time + 1                      -- a new frame
ready = {}
local r = api.Evaluate({ item = WoW.link(52), scope = "own" })
H.eq(r.results[1].status ~= "pending" and r.results[2].status ~= "pending", true, "the first two rows fit the budget")
H.eq(r.results[3].status, "pending", "the third is a placeholder")
H.eq(r.results[3].reasons[1], "FRAME_BUDGET", "...reason FRAME_BUDGET")
local r2 = api.Evaluate({ item = WoW.link(53), scope = "own" })
H.eq(r2.results[1].reasons[1], "FRAME_BUDGET", "the budget spent: another request waits whole")
api.LIMITS.perFrame = 1                      -- less than a request's rows: still progresses
for _ = 1, 6 do WoW.time = WoW.time + 1; WoW.flush(1) end
local got = {}
for _, p in ipairs(ready) do got[p.requestId] = p.response end
H.check(got[r.requestId] ~= nil, "a later frame completes the first request")
H.eq(got[r.requestId] and got[r.requestId].results[3].status ~= "pending", true, "...every row computed")
H.check(got[r2.requestId] ~= nil, "...and the second, one row per frame (finished rows are kept)")
api.LIMITS.perFrame = savedBudget
local e5 = evals()
api.Evaluate({ item = WoW.link(52), scope = "own" })
H.eq(evals() - e5, 0, "a completed deferred answer is cached")

------------------------------------------------------------
-- One job for the same pending item; cancel.
------------------------------------------------------------
WoW.items[70] = shoulder("Loading Mantle", { [INT] = 30 })
WoW.cacheMiss[70] = true
ready = {}
local p1 = api.Evaluate({ item = WoW.link(70), scope = "own" })
local p2 = api.Evaluate({ item = WoW.link(70), scope = "own" })
local jobs = 0
for _ in pairs(S.jobs) do jobs = jobs + 1 end
H.eq(jobs, 1, "two requests for the same pending item: one job")
H.eq(S.requestCount, 2, "...two subscriptions")
H.eq(p2.results[1].status, "pending", "...the second gets the placeholders too")
local e6 = evals()
WoW.cacheMiss[70] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 70, true)
WoW.flush()
H.eq(evals() - e6, 3, "the data arrives: computed once")
local ids = {}
for _, p in ipairs(ready) do ids[p.requestId] = p.response end
H.check(ids[p1.requestId] and ids[p2.requestId], "...and each request gets its EvaluationReady")
H.eq(ids[p2.requestId] and ids[p2.requestId].requestId, p2.requestId, "...with its own request id")
H.eq(S.requestCount, 0, "nothing outstanding")

WoW.items[71] = shoulder("Slow Mantle", { [INT] = 31 })
WoW.cacheMiss[71] = true
local q1 = api.Evaluate({ item = WoW.link(71), scope = "own" })
local q2 = api.Evaluate({ item = WoW.link(71), scope = "own" })
api.CancelRequest(q1.requestId)
H.check(S.waiting[71] ~= nil, "cancelling one subscriber keeps the job for the other")
api.CancelRequest(q2.requestId)
H.eq(S.waiting[71], nil, "cancelling the last drops the job and its item load")
H.eq(next(S.jobs), nil, "...no job left")
WoW.cacheMiss[71] = nil

------------------------------------------------------------
-- Bounds: OVERLOADED, terminal, never cached.
------------------------------------------------------------
local savedJobs = api.LIMITS.jobs
api.LIMITS.jobs = 2
WoW.items[72] = shoulder("Busy Mantle", { [INT] = 32 })
WoW.cacheMiss[72] = true
ready = {}
local o = api.Evaluate({ item = WoW.link(72), scope = "own" })
H.eq(#o.results, 3, "three pending rows over a 2-row job bound: one row per target")
H.eq(o.results[1].reasons[1], "OVERLOADED", "...each OVERLOADED")
H.eq(S.waiting[72], nil, "...nothing queued")
WoW.flush()
H.eq(#ready, 0, "...terminal: no callback")
api.LIMITS.jobs = savedJobs
WoW.cacheMiss[72] = nil
H.eq(api.Evaluate({ item = WoW.link(72), scope = "own" }).results[1].status ~= "unknown", true,
    "an overloaded answer isn't cached: the next call computes")

-- A request that gave up (item data unavailable) isn't cached either.
WoW.items[74] = shoulder("Never Mantle", { [INT] = 34 })
WoW.cacheMiss[74] = true
ready = {}
local gaveUp = api.Evaluate({ item = WoW.link(74), scope = "current" })
for _ = 1, 20 do WoW.time = WoW.time + 1; WoW.flush(1) end
local final
for _, p in ipairs(ready) do if p.requestId == gaveUp.requestId then final = p.response end end
H.eq(final and final.results[1].reasons[1], "ITEM_DATA_UNAVAILABLE", "after the last load attempt: unavailable")
WoW.cacheMiss[74] = nil
H.eq(api.Evaluate({ item = WoW.link(74), scope = "current" }).results[1].status, "upgrade",
    "...not cached: once the data is there, the next look computes it")

local savedReq = api.LIMITS.requests
WoW.items[73] = shoulder("Queued Mantle", { [INT] = 33 })
WoW.cacheMiss[73] = true
local first = api.Evaluate({ item = WoW.link(73), scope = "own" })
api.LIMITS.requests = 1
local dup = api.Evaluate({ item = WoW.link(73), scope = "own" })
H.eq(dup.results[1].reasons[1], "OVERLOADED", "joining a job past the request bound: OVERLOADED")
api.LIMITS.requests = savedReq
api.CancelRequest(first.requestId)
WoW.cacheMiss[73] = nil

------------------------------------------------------------
-- Tooltip redraws: no recomputation, no roster scan.
------------------------------------------------------------
GG.Results.Reset()
local tip = WoW.newTooltip("GameTooltip")
WoW.showItem(tip, { type = 0, id = 55, hyperlink = WoW.link(55) })
local e7, scans = evals(), GG.Integrations.RosterProvider.scans
for _ = 1, 25 do WoW.showItem(tip, { type = 0, id = 55, hyperlink = WoW.link(55) }) end
H.eq(evals() - e7, 0, "25 tooltip redraws: nothing recomputed")
H.eq(GG.Integrations.RosterProvider.scans - scans, 0, "...and the roster is never read")
GG.Results.Reset()                            -- the UI's own cache dropped (e.g. a bag refresh)
WoW.showItem(tip, { type = 0, id = 55, hyperlink = WoW.link(55) })
H.eq(evals() - e7, 0, "...even past the UI's cache, the API's answer serves")

H.eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
H.done("test_api_runtime")
