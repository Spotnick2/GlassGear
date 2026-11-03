------------------------------------------------------------
-- test_perf.lua - GG-402: performance, measured. A full bag (80 pieces of
-- gear x 3 specs = 240 rows) stays within the per-frame budget and
-- completes over the next frames with one marker redraw per frame; reopening
-- the bags and redrawing tooltips recompute nothing; the cache stays within
-- its limit; /gg stats reports the counters; the cost of one evaluation in
-- this interpreter is printed (an indication, not a promise for the client).
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local INT, SP, STA = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_STAMINA_SHORT"
local LOCS = { "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_WAIST", "INVTYPE_LEGS",
    "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_FINGER", "INVTYPE_CLOAK" }
WoW.equipped = {}
for i = 1, 80 do
    local loc = LOCS[(i - 1) % #LOCS + 1]
    WoW.items[1000 + i] = { name = "Piece " .. i, equipLoc = loc, classID = 4, subclassID = loc == "INVTYPE_CLOAK" and 1 or 1,
        stats = { [INT] = i % 17, [SP] = i % 11, [STA] = i % 7 } }
end
WoW.items[900] = { name = "Worn Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = { [INT] = 5 } }
WoW.equipped[3] = 900
WoW.bags = {}
for b = 0, 4 do WoW.bags[b] = {} end
for i = 1, 80 do WoW.bags[(i - 1) % 5][math.floor((i - 1) / 5) + 1] = { itemID = 1000 + i, isBound = true } end

local GG = WoW.loadAddon()
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1, SpellDamage=1 )')
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy": Class=Priest, Intellect=1, Healing=1 )')
WoW.flush()
local S = GG.API._state

-- A full bag: 80 pieces x 3 specs = 240 rows, over a 200-row frame budget.
local slots = {}
for b = 0, 4 do for s = 1, 16 do if WoW.bags[b][s] then slots[#slots + 1] = { b, s } end end end
H.eq(#slots, 80, "80 pieces of gear in the bags")
local bag = ContainerFrameContainer.ContainerFrames[1]
local refreshes = 0
local realRefresh = GG.BagMarkers.Refresh
GG.BagMarkers.Refresh = function(...) refreshes = refreshes + 1; return realRefresh(...) end
WoW.time = WoW.time + 1
local e0, d0 = S.stats.evaluations, S.stats.deferredRows
WoW.showBag(bag, slots)
local first = S.stats.evaluations - e0
H.check(first <= GG.API.LIMITS.perFrame, "opening a full bag computes at most the frame budget at once (" .. first .. " rows)")
H.check(S.stats.deferredRows - d0 > 0, "...the rest are put off to later frames")
local frames = 0
while next(S.jobs) and frames < 10 do
    WoW.time = WoW.time + 0.02
    WoW.flush(1)
    frames = frames + 1
end
H.eq(next(S.jobs), nil, "...and every row completes within a few frames (" .. frames .. ")")
H.eq(S.stats.evaluations - e0, 240, "...240 rows computed once each")
H.check(refreshes <= frames + 1, "...one marker redraw per frame at most (" .. refreshes .. " for " .. frames .. " frames)")

-- Reopening the bags and redrawing tooltips: no recomputation.
local e1 = S.stats.evaluations
bag:Hide()
WoW.showBag(bag, slots)
local tip = WoW.newTooltip("GameTooltip")
for i = 1, 20 do WoW.showItem(tip, { type = 0, id = 1000 + i, hyperlink = WoW.link(1000 + i) }) end
for _ = 1, 3 do for i = 1, 20 do WoW.showItem(tip, { type = 0, id = 1000 + i, hyperlink = WoW.link(1000 + i) }) end end
local tipFirst = S.stats.evaluations - e1
H.check(tipFirst <= 60, "reopening the bags recomputes nothing; 20 new tooltip links cost 60 rows at most (" .. tipFirst .. ")")
local e2 = S.stats.evaluations
for _ = 1, 10 do for i = 1, 20 do WoW.showItem(tip, { type = 0, id = 1000 + i, hyperlink = WoW.link(1000 + i) }) end end
H.eq(S.stats.evaluations - e2, 0, "200 more tooltip redraws: nothing recomputed")
H.check(GG.API._cache.size <= GG.API.LIMITS.cache, "the cache stays within its limit (" .. GG.API._cache.size .. ")")

-- /gg stats.
SlashCmdList.GLASSGEAR("stats")
H.check(WoW.chat():find("stats: %d+ evaluations, %d+ answers from the cache") ~= nil, "/gg stats reports the counters")
H.check(WoW.chat():find("limits: 200 rows per frame", 1, true) ~= nil, "...and the limits")
H.check((S.stats.maxFrameMs or 0) > 0, "the time spent comparing in the busiest frame is measured (" ..
    string.format("%.1f", S.stats.maxFrameMs or 0) .. " ms here)")
H.check(WoW.chat():find("the most time spent comparing in one frame: ", 1, true) ~= nil, "...and /gg stats reports it")

-- The cost of one evaluation here (an indication for the docs, not a test of the client).
local link = WoW.link(1005)
local facts = GG.Compat.ItemFacts(link)
local profile = GG.Profiles.Active(GG.store, GG.player.key, "PRIEST.SHADOW")
local baseline = GG.Compat.EquippedBaseline(time())
local N = 2000
local t0 = os.clock()
for _ = 1, N do
    GG.Engine.Evaluate.One({ item = facts, recipient = GG.player, spec = "PRIEST.SHADOW", current = true,
        profile = profile, baseline = baseline, settings = {}, transfer = { state = "eligible", reasons = {} } })
end
local per = (os.clock() - t0) / N * 1e6
print(string.format("  info: one Evaluate.One here: %.1f microseconds (%d runs); 200 rows ~ %.2f ms", per, N, per * 200 / 1000))
H.check(per < 5000, "an evaluation stays well under 5 ms even in a plain interpreter")

H.eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
H.done("test_perf")
