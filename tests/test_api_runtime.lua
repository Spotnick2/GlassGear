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
-- A pending job joined after an invalidation: nothing from before it.
------------------------------------------------------------
api._cache.clear()
api.LIMITS.perFrame = 2
WoW.time = WoW.time + 1
ready = {}
local before = api.Evaluate({ item = WoW.link(53), scope = "own" })
H.eq(before.results[1].status ~= "pending" and before.results[3].status, "pending", "a job half done (budget)")
local oldDelta = before.results[1].score.delta
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow3": Class=Priest, Intellect=3 )')
local joined = api.Evaluate({ item = WoW.link(53), scope = "own" })
H.check(joined.results[1].status == "pending" or joined.results[1].score.delta ~= oldDelta,
    "after an invalidation, a new subscriber never gets the old finished row")
api.LIMITS.perFrame = savedBudget
for _ = 1, 4 do WoW.time = WoW.time + 1; WoW.flush(1) end
local outs = {}
for _, p in ipairs(ready) do outs[p.requestId] = p.response end
H.eq(outs[joined.requestId] and outs[joined.requestId].results[1].score.delta, 36, "...it completes with the new weights (3 x 22 - 3 x 10)")
H.eq(outs[before.requestId] and outs[before.requestId].results[1].score.delta, 36, "...and so does the earlier subscriber")

-- A finished row whose baseline went stale while its job waited.
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
api._cache.clear()
api.LIMITS.perFrame = 1
WoW.time = WoW.time + 1
local targets = { { char = GG.player.key, spec = "PRIEST.HOLY" }, { char = GG.player.key, spec = "PRIEST.SHADOW" } }
local hp = api.Evaluate({ item = WoW.link(52), scope = "targets", targets = targets })
H.eq(hp.results[1].baseline.stale, false, "Holy's row finished against fresh recorded gear")
H.eq(hp.results[2].status, "pending", "...Shadow waits for the budget")
WoW.epoch = hp.results[1].baseline.expiresAt + 1
inval = {}                                    -- (no flush: the deferred runner would recompute first)
local genJ = S.generation
local hp2 = api.Evaluate({ item = WoW.link(52), scope = "targets", targets = targets })
H.check(hp2.results[1].status == "pending" or hp2.results[1].baseline.stale == true,
    "past expiresAt, a new subscriber doesn't get the fresh-looking old row")
H.check(S.generation > genJ, "...the freshness generation advanced before the call returned")
WoW.flush(1)
H.check(has(inval, "freshness"), "...and EvaluationInvalidated(freshness) followed")
api.LIMITS.perFrame = savedBudget
for _ = 1, 4 do WoW.time = WoW.time + 1; WoW.flush(1) end

-- A load that gives up ends only the rows that waited for it.
SlashCmdList.GLASSGEAR("spec 2 PRIEST.HOLY")
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
api._cache.clear()
GG.Capture._Reset()                           -- a new session: Holy's recorded mantle isn't loaded
WoW.cacheMiss[54] = true
ready = {}
api.LIMITS.perFrame = 1
WoW.time = WoW.time + 1
local t = api.Evaluate({ item = WoW.link(51), scope = "targets", targets = targets })
H.eq(t.results[1].reasons[1], "BASELINE_ITEM_DATA_PENDING", "Holy waits for its recorded mantle")
H.eq(t.results[2].reasons[1], "FRAME_BUDGET", "...Shadow waits for the budget")
api.LIMITS.perFrame = 0                       -- no budget while the loads time out
for _ = 1, 3 do WoW.time = WoW.time + 6; api._Tick(WoW.time) end
H.eq(S.waiting[54], nil, "the mantle gave up after its last attempt")
api.LIMITS.perFrame = savedBudget
for _ = 1, 4 do WoW.time = WoW.time + 1; WoW.flush(1) end
local tr
for _, p in ipairs(ready) do if p.requestId == t.requestId then tr = p.response end end
H.eq(tr and tr.results[1].reasons[1], "ITEM_DATA_UNAVAILABLE", "...Holy's row is unavailable")
H.check(tr and tr.results[2].status ~= "unknown" and tr.results[2].status ~= "pending",
    "...Shadow's row, only waiting for the budget, still completes")
WoW.cacheMiss[54] = nil

-- A "loaded" event while the budget is spent: whether the item is usable is
-- read from the item, and an unusable one keeps its attempt count.
local idsReady = {}
api.RegisterCallback("ItemDataReady", function(_, p) for _, i in ipairs(p.itemIDs) do idsReady[i] = true end end,
    "test_api_runtime")
WoW.items[75] = shoulder("Stubborn Mantle", { [INT] = 35 })
WoW.cacheMiss[75] = true
ready = {}
WoW.time = WoW.time + 1
local loads0 = #WoW.itemRequests
local st = api.Evaluate({ item = WoW.link(75), scope = "own" })
H.eq(S.waiting[75] and S.waiting[75].attempts, 1, "the item waits (attempt 1)")
api.LIMITS.perFrame = 0
WoW.fire("ITEM_DATA_LOAD_RESULT", 75, true)  -- "success", data still unusable, no budget left
WoW.flush(1)                                  -- callbacks are delivered on the next frame
H.eq(S.waiting[75] and S.waiting[75].attempts, 1, "a success event with no budget keeps the record and its attempts")
H.eq(idsReady[75], nil, "...and doesn't announce ItemDataReady")
api.LIMITS.perFrame = savedBudget
for _ = 1, 25 do WoW.time = WoW.time + 1; WoW.flush(1) end
local loads75 = 0
for i = loads0 + 1, #WoW.itemRequests do if WoW.itemRequests[i] == 75 then loads75 = loads75 + 1 end end
H.eq(loads75, 3, "...still three load attempts in all")
local stDone
for _, p in ipairs(ready) do if p.requestId == st.requestId then stDone = p.response end end
H.eq(stDone and stDone.results[1].reasons[1], "ITEM_DATA_UNAVAILABLE", "...and then it gives up")
WoW.cacheMiss[75] = nil

-- A real arrival while the budget is spent: announced, the job finishes later.
WoW.items[76] = shoulder("Late Mantle", { [INT] = 36 })
WoW.cacheMiss[76] = true
ready = {}
WoW.time = WoW.time + 1
local lt = api.Evaluate({ item = WoW.link(76), scope = "own" })
api.LIMITS.perFrame = 0
WoW.cacheMiss[76] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 76, true)
WoW.flush(1)
H.eq(idsReady[76], true, "data usable, budget spent: ItemDataReady still fires")
for _ = 1, 4 do WoW.time = WoW.time + 6; api._Tick(WoW.time) end   -- 24 s without budget
H.check(S.waiting[76] ~= nil, "...a loaded item isn't retried or given up while its rows wait for the budget")
api.LIMITS.perFrame = savedBudget
for _ = 1, 3 do WoW.time = WoW.time + 1; WoW.flush(1) end
local ltDone
for _, p in ipairs(ready) do if p.requestId == lt.requestId then ltDone = p.response end end
H.eq(ltDone and ltDone.results[1].status, "upgrade", "...and the job completes on a later frame")
H.eq(S.waiting[76], nil, "...its load record released")

-- Its name loads but not its stats: taken for loaded, then a computed row
-- still can't use it, so the retries resume and it still ends.
WoW.items[77] = shoulder("Half Mantle", { [INT] = 37 })
WoW.statsMiss[77] = true
ready = {}
WoW.time = WoW.time + 1
local hm = api.Evaluate({ item = WoW.link(77), scope = "own" })
api.LIMITS.perFrame = 0
WoW.fire("ITEM_DATA_LOAD_RESULT", 77, true)
WoW.flush(1)
H.eq(idsReady[77], nil, "name known, stats not: no ItemDataReady")
api.LIMITS.perFrame = savedBudget
for _ = 1, 25 do WoW.time = WoW.time + 1; WoW.flush(1) end
local hmDone
for _, p in ipairs(ready) do if p.requestId == hm.requestId then hmDone = p.response end end
H.eq(hmDone and hmDone.results[1].reasons[1], "ITEM_DATA_UNAVAILABLE",
    "an item whose stats never load still ends (its retries resumed)")
H.eq(idsReady[77], nil, "...and was never announced as ready")
WoW.statsMiss[77] = nil

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
