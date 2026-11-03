------------------------------------------------------------
-- test_owned.lua - GG-122: what the bags hold. A 1H candidate against a 2H
-- pairs with an off-hand from the bags (best usable; never a tie, never an
-- unusable one); "better gear already owned" (one position, two for rings);
-- owned items that can't be worn now don't count; the tooltip names it; the
-- bag index is built once per bag change, loading items are added when
-- they arrive, and only a change in carried gear invalidates answers.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local INT = "ITEM_MOD_INTELLECT_SHORT"
local function item(name, equipLoc, classID, subclassID, stats, extra)
    local t = { name = name, equipLoc = equipLoc, classID = classID, subclassID = subclassID, stats = stats }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end
WoW.items[10] = item("Staff", "INVTYPE_2HWEAPON", 2, 10, { [INT] = 20 })
WoW.items[11] = item("Mace", "INVTYPE_WEAPONMAINHAND", 2, 4, { [INT] = 15 })
WoW.items[12] = item("Orb", "INVTYPE_HOLDABLE", 4, 0, { [INT] = 10 })
WoW.items[13] = item("Bright Orb", "INVTYPE_HOLDABLE", 4, 0, { [INT] = 12 })
WoW.items[14] = item("Twin Orb", "INVTYPE_HOLDABLE", 4, 0, { [INT] = 12 })
WoW.items[15] = item("Shield", "INVTYPE_SHIELD", 4, 6, { [INT] = 50 })      -- priests can't use shields
WoW.items[20] = item("Old Mantle", "INVTYPE_SHOULDER", 4, 1, { [INT] = 10 })
WoW.items[21] = item("New Mantle", "INVTYPE_SHOULDER", 4, 1, { [INT] = 15 })
WoW.items[22] = item("Better Mantle", "INVTYPE_SHOULDER", 4, 1, { [INT] = 18 })
WoW.items[23] = item("Future Mantle", "INVTYPE_SHOULDER", 4, 1, { [INT] = 40 }, { minLevel = 62 })
WoW.items[30] = item("Old Ring", "INVTYPE_FINGER", 4, 0, { [INT] = 5 })
WoW.items[31] = item("New Ring", "INVTYPE_FINGER", 4, 0, { [INT] = 8 })
WoW.items[32] = item("Fine Ring", "INVTYPE_FINGER", 4, 0, { [INT] = 10 })
WoW.items[33] = item("Finer Ring", "INVTYPE_FINGER", 4, 0, { [INT] = 11 })
WoW.items[40] = item("Junk", "", 15, 0, {})
WoW.items[16] = item("Big Staff", "INVTYPE_2HWEAPON", 2, 10, { [INT] = 30 })
WoW.items[17] = item("Mace Two", "INVTYPE_WEAPONMAINHAND", 2, 4, { [INT] = 18 })
WoW.items[18] = item("Great Orb", "INVTYPE_HOLDABLE", 4, 0, { [INT] = 20 })
WoW.items[34] = item("Unique Band", "INVTYPE_FINGER", 4, 0, { [INT] = 15 }, { unique = { cat = 7, max = 1 } })
WoW.items[35] = item("Great Ring", "INVTYPE_FINGER", 4, 0, { [INT] = 100 })
WoW.equipped = { [3] = 20, [11] = 30, [12] = 30, [16] = 10 }
WoW.bags[0] = {}

local GG = WoW.loadAddon()
local api = GG.API
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1 )')
WoW.flush()
local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end return false end
local function bagsChanged() WoW.fire("BAG_UPDATE_DELAYED"); WoW.flush() end
local function shadow(id) return api.Evaluate({ item = WoW.link(id), scope = "current" }).results[1] end

------------------------------------------------------------
-- A companion from the bags.
------------------------------------------------------------
local r = shadow(11)
H.eq(r.status, "unknown", "a mace against the worn staff, no off-hand anywhere: unknown")
H.check(has(r.reasons, "NEEDS_COMPANION"), "...NEEDS_COMPANION")
WoW.bags[0][1] = { itemID = 12, isBound = true }
bagsChanged()
r = shadow(11)
H.eq(r.status, "upgrade", "an orb in the bags completes it: mace + orb (25) beat the staff (20)")
H.eq(r.score.candidate, 25, "...scored with the orb")
WoW.bags[0][2] = { itemID = 13, isBound = true }
bagsChanged()
H.eq(shadow(11).score.candidate, 27, "two orbs: the better one is the companion")
WoW.bags[0][3] = { itemID = 14, isBound = true }
WoW.bags[0][1] = nil
bagsChanged()
r = shadow(11)
H.eq(r.status, "unknown", "two different bag orbs tied at the top: none chosen (no coin toss)")
WoW.bags[0][2], WoW.bags[0][3] = { itemID = 13, isBound = true }, { itemID = 13, isBound = true }
bagsChanged()
H.eq(shadow(11).score and shadow(11).score.candidate, 27, "two copies of the same orb are no tie: either one pairs")
WoW.bags[0][2], WoW.bags[0][3] = nil, nil
-- An orb against the staff needs a main hand: a better two-hander in the
-- bags can't be that partner; the mace can.
WoW.bags[0][2], WoW.bags[0][3] = { itemID = 16, isBound = true }, { itemID = 11, isBound = true }
bagsChanged()
r = shadow(12)
H.eq(r.status, "upgrade", "an orb pairs with the bag mace, never with a bag two-hander (orb + mace 25 > staff 20)")
H.eq(r.score and r.score.candidate, 25, "...scored with the mace")
WoW.bags[0][2], WoW.bags[0][3] = nil, nil
WoW.bags[0][4] = { itemID = 15, isBound = true }
bagsChanged()
H.check(has(shadow(11).reasons, "NEEDS_COMPANION"), "a shield a priest can't use is never the companion")
WoW.bags[0][4] = nil
WoW.equipped[16] = nil
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
bagsChanged()

------------------------------------------------------------
-- Better gear already owned.
------------------------------------------------------------
r = shadow(21)
H.eq(r.status, "upgrade", "a better mantle, nothing better owned: upgrade")
WoW.bags[0][5] = { itemID = 22, isBound = true }
bagsChanged()
r = shadow(21)
H.eq(r.status, "no_upgrade", "a better one already in the bags: not presented as an upgrade")
H.check(has(r.reasons, "OWNED_BETTER"), "...OWNED_BETTER")
H.eq(r.ownedBetter and r.ownedBetter.itemID, 22, "...naming the owned item")
H.eq(shadow(22).status, "upgrade", "the owned better one itself is still an upgrade")
local tip = WoW.newTooltip("GameTooltip")
GG.Results.Reset()
WoW.showItem(tip, { type = 0, id = 21, hyperlink = WoW.link(21) })
local right, note
for _, l in ipairs(tip.lines) do
    if l.right == "you own better" then right = l.right end
    if l.left and l.left:find("You own better for Shadow: Better Mantle", 1, true) then note = l.left end
end
H.check(right ~= nil, "the tooltip row says 'you own better'")
H.check(note ~= nil, "...and names the item")
WoW.bags[0][5] = { itemID = 23, isBound = true }
GG.Prefs.Set("levelWindow.lookAhead", 5)       -- level 62 is inside the look-ahead: an upgrade later
bagsChanged()
H.eq(shadow(23).eligibility.equipNow, false, "(the level-62 mantle is an upgrade for later)")
H.eq(shadow(21).status, "upgrade", "an owned item too high level to wear now doesn't count")
GG.Prefs.Set("levelWindow.lookAhead", 0)
WoW.bags[0][5] = nil
bagsChanged()

-- Rings take two positions: one better owned ring isn't enough.
WoW.bags[0][6] = { itemID = 32, isBound = true }
bagsChanged()
H.eq(shadow(31).status, "upgrade", "one better ring owned: the new ring still fills the other finger")
WoW.bags[0][7] = { itemID = 33, isBound = true }
bagsChanged()
r = shadow(31)
H.eq(r.status, "no_upgrade", "two better rings owned: no longer an upgrade")
H.eq(r.ownedBetter and r.ownedBetter.itemID, 33, "...naming the best one")
H.eq(GG.Owned.Positions("INVTYPE_WEAPON", true), 2, "a one-hander with dual wield takes two positions")
H.eq(GG.Owned.Positions("INVTYPE_WEAPON", false), 1, "...without it, one")
WoW.bags[0][6], WoW.bags[0][7] = nil, nil
bagsChanged()

-- Different hands don't compete: a better orb owned doesn't stop a better mace.
WoW.equipped[16], WoW.equipped[17] = 11, 12
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
WoW.bags[0][10] = { itemID = 18, isBound = true }
bagsChanged()
r = shadow(17)
H.eq(r.status, "upgrade", "a better mace stays an upgrade although a much better orb is owned (other hand)")
WoW.bags[0][10] = nil
WoW.equipped[16], WoW.equipped[17] = nil, nil
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
bagsChanged()

-- Two copies of a unique ring take one finger only.
WoW.bags[0][6], WoW.bags[0][7] = { itemID = 34, isBound = true }, { itemID = 34, isBound = true }
bagsChanged()
H.eq(shadow(31).status, "upgrade", "two copies of a unique ring owned: the new ring still fills the other finger")
WoW.bags[0][6], WoW.bags[0][7] = nil, nil

-- A worn ring that beats everything takes its finger: one better owned ring is enough.
WoW.equipped[12] = 35
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 12, false)
WoW.bags[0][6] = { itemID = 32, isBound = true }
bagsChanged()
r = shadow(31)
H.eq(r.status, "no_upgrade", "one finger is taken by a far better worn ring: one better owned ring blocks it")
H.eq(r.ownedBetter and r.ownedBetter.itemID, 32, "...naming the owned ring")
WoW.bags[0][6] = nil
WoW.equipped[12] = 30
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 12, false)
bagsChanged()

-- Owned items are evaluated once per spec and generation, not per candidate.
WoW.bags[0][5] = { itemID = 22, isBound = true }
bagsChanged()
api._cache.clear()
shadow(21)
local oe = api._state.stats.ownedEvaluations or 0
api._cache.clear()
shadow(21)
H.eq((api._state.stats.ownedEvaluations or 0) - oe, 0, "the owned mantle's evaluation is reused, not redone")
WoW.bags[0][5] = nil
bagsChanged()

-- Two copies of the same non-unique one-hander, dual wield, a worn staff:
-- the candidate copy pairs with the other copy (never with itself).
WoW.items[19] = item("Twin Dagger", "INVTYPE_WEAPON", 2, 15, { [INT] = 12 })
GG.player.canDualWield = true
WoW.equipped[16] = 10
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
WoW.bags[0][13] = { itemID = 19, isBound = true }
bagsChanged()
local function bagShadow(bag, slot) return api.Evaluate({ item = { bag = bag, slot = slot }, scope = "current" }).results[1] end
r = bagShadow(0, 13)
H.check(has(r.reasons, "NEEDS_COMPANION"), "one dagger in the bags, nothing else: it can't pair with itself")
WoW.bags[0][14] = { itemID = 19, isBound = true }
bagsChanged()
r = bagShadow(0, 13)
H.eq(r.status, "upgrade", "a second copy of the dagger pairs with the first (12 + 12 > staff 20)")
H.eq(r.score and r.score.candidate, 24, "...scored as the pair")
H.eq(bagShadow(0, 14).status, "upgrade", "...either copy")
H.eq(shadow(19).status, "upgrade", "a bare link of the dagger leaves out one copy only")
WoW.bags[0][13], WoW.bags[0][14] = nil, nil
GG.player.canDualWield = false
WoW.equipped[16] = nil
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
bagsChanged()

-- The budget covers the owned checks: a row starts only when the frame can
-- pay for it and every owned check it could need, never going over.
WoW.items[27] = item("Mantle A", "INVTYPE_SHOULDER", 4, 1, { [INT] = 16 })
WoW.items[28] = item("Mantle B", "INVTYPE_SHOULDER", 4, 1, { [INT] = 17 })
WoW.items[29] = item("Mantle C", "INVTYPE_SHOULDER", 4, 1, { [INT] = 19 })
WoW.bags[0][5], WoW.bags[0][13] = { itemID = 22, isBound = true }, { itemID = 27, isBound = true }
WoW.bags[0][14], WoW.bags[0][15] = { itemID = 28, isBound = true }, { itemID = 29, isBound = true }
bagsChanged()
api._Invalidate("test")                           -- a new generation: no owned answer known yet
local S = api._state
local savedBudget = api.LIMITS.perFrame
api.LIMITS.perFrame = 5
api._cache.clear()
WoW.time = WoW.time + 1
shadow(30)                                        -- one row spent this frame (a ring, nothing competes)
H.eq(S.frameUsed, 1, "(one row spent)")
r = shadow(21)
H.eq(r.status, "pending", "the mantle and its four owned checks (5) don't fit the 4 left: put off")
H.eq(r.reasons[1], "FRAME_BUDGET", "...FRAME_BUDGET")
H.check(S.frameUsed <= 5, "...the frame never goes over its budget (" .. S.frameUsed .. ")")
local done
api.RegisterCallback("EvaluationReady", function(_, p) done = p.response end, "test_owned_budget")
WoW.time = WoW.time + 1
WoW.flush(1)                                      -- the deferred runner, a later frame
local usedThen = S.frameUsed
WoW.flush()                                       -- EvaluationReady, next frame
H.check(usedThen <= 5, "the next frame computes it within the budget (" .. usedThen .. ")")
H.eq(done and done.results[1].status, "no_upgrade", "...and it finishes: better mantles owned")
H.eq(done and done.results[1].ownedBetter and done.results[1].ownedBetter.itemID, 29, "...the best one named")
api.UnregisterCallback("EvaluationReady", "test_owned_budget")
api.LIMITS.perFrame = 1
api._Invalidate("test")                           -- owned answers unknown again
api._cache.clear()
WoW.time = WoW.time + 1
r = shadow(21)
H.check(r.status ~= "pending", "a budget smaller than one row's cost: the frame's first row still runs")
api.LIMITS.perFrame = savedBudget
WoW.bags[0][5], WoW.bags[0][13], WoW.bags[0][14], WoW.bags[0][15] = nil, nil, nil, nil
bagsChanged()

------------------------------------------------------------
-- The index: once per bag change, only gear changes invalidate.
------------------------------------------------------------
local scans = GG.Owned.scans
for _ = 1, 5 do api._cache.clear(); shadow(21) end
H.eq(GG.Owned.scans, scans, "evaluations scan no bags")
local inval = {}
api.RegisterCallback("EvaluationInvalidated", function(_, p) inval[#inval + 1] = p.reason end, "test_owned")
WoW.flush(); inval = {}
WoW.bags[0][8] = { itemID = 40, isBound = true }
bagsChanged()
H.eq(has(inval, "bags"), false, "junk added: no invalidation")
WoW.bags[0][8] = nil
WoW.items[24] = item("Slow Mantle", "INVTYPE_SHOULDER", 4, 1, { [INT] = 30 })
WoW.cacheMiss[24] = true
WoW.bags[0][9] = { itemID = 24, isBound = true }
bagsChanged()
H.eq(shadow(21).status, "upgrade", "a bag item still loading is never used")
H.check(has(WoW.itemRequests, 24), "...it is requested")
inval = {}
WoW.cacheMiss[24] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 24, true)
WoW.flush()
H.check(has(inval, "bags"), "it arrives: the index is rebuilt and answers invalidated")
H.eq(shadow(21).status, "no_upgrade", "...now it is the better mantle owned")

-- A burst of arrivals: one rebuild now, the rest in one rebuild next frame.
WoW.items[25] = item("Slow A", "INVTYPE_HEAD", 4, 1, { [INT] = 3 })
WoW.items[26] = item("Slow B", "INVTYPE_HEAD", 4, 1, { [INT] = 4 })
WoW.cacheMiss[25], WoW.cacheMiss[26] = true, true
WoW.bags[0][11], WoW.bags[0][12] = { itemID = 25, isBound = true }, { itemID = 26, isBound = true }
bagsChanged()
WoW.time = WoW.time + 1
local s0 = GG.Owned.scans
WoW.cacheMiss[25] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 25, true)
WoW.cacheMiss[26] = nil                       -- arrives after that rebuild, same frame
WoW.fire("ITEM_DATA_LOAD_RESULT", 26, true)
H.eq(GG.Owned.scans - s0, 1, "two arrivals in one frame: one rebuild now")
WoW.flush(1)
H.eq(GG.Owned.scans - s0, 2, "...and the second coalesced into the next frame")

H.eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
H.done("test_owned")
