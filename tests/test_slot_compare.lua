------------------------------------------------------------
-- test_slot_compare.lua - legal resulting configurations (adr/0003):
-- rings/trinkets, 2H vs MH+OH, companions, unique, empty/unknown slots.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
local GG = H.loadPure()
local SC = GG.Engine.SlotCompare

local function slot(score, o)
    o = o or {}
    return { state = "occupied", itemID = o.itemID or score, equipLoc = o.equipLoc, score = score,
        unique = o.unique, itemString = tostring(o.itemID or score) }
end

-- Rings: compared against the weaker ring.
local base = { [11] = slot(50), [12] = slot(30) }
local best = SC.Best({ equipLoc = "INVTYPE_FINGER", score = 40 }, base)
eq(best.state, "legal", "ring config legal")
eq(best.slots[1], 12, "replaces the weaker ring")
eq(best.baseScore, 30, "baseline = displaced item")
eq(best.delta, 10, "delta vs weaker ring")

-- Unique: a second copy of an equipped unique ring is legal only by replacing it.
local u = { key = "cat:7", max = 1 }
base = { [11] = slot(50, { unique = u, itemID = 900 }), [12] = slot(30) }
best = SC.Best({ equipLoc = "INVTYPE_FINGER", score = 60, unique = u, itemID = 901 }, base)
eq(best.slots[1], 11, "unique category: must displace the stronger unique ring")
eq(best.delta, 10, "compared against the ring it legally replaces")
best = SC.Best({ equipLoc = "INVTYPE_FINGER", score = 45, unique = u }, base)
eq(best.state, "legal", "still legal")
check(best.delta < 0, "not an upgrade when the only legal swap is the stronger ring")

-- Trinkets behave like rings (Glass Gear scores them; effects are limitations).
best = SC.Best({ equipLoc = "INVTYPE_TRINKET", score = 5 }, { [13] = slot(0), [14] = slot(3) })
eq(best.slots[1], 13, "trinket into the weaker trinket slot")

-- 2H vs MH + OH sum.
base = { [16] = slot(40, { equipLoc = "INVTYPE_WEAPONMAINHAND" }), [17] = slot(25, { equipLoc = "INVTYPE_HOLDABLE" }) }
best = SC.Best({ equipLoc = "INVTYPE_2HWEAPON", score = 60 }, base)
eq(best.baseScore, 65, "2H compared against MH + OH")
eq(#best.slots, 2, "2H occupies both hands")
check(best.delta < 0, "60 < 65: not an upgrade")

-- 1H while a 2H is equipped: needs a companion.
base = { [16] = slot(70, { equipLoc = "INVTYPE_2HWEAPON" }), [17] = { state = "empty" } }
best = SC.Best({ equipLoc = "INVTYPE_WEAPONMAINHAND", score = 45 }, base)
eq(best.state, "unknown", "1H over 2H without an off-hand")
eq(best.reason, "NEEDS_COMPANION", "reason")
best = SC.Best({ equipLoc = "INVTYPE_WEAPONMAINHAND", score = 45 }, base,
    { companion = { [17] = slot(30, { equipLoc = "INVTYPE_HOLDABLE" }) } })
eq(best.state, "legal", "with an identified off-hand companion")
eq(best.candScore, 75, "candidate + companion")
eq(best.baseScore, 70, "vs the 2H")

-- One-hand into the off hand only with dual wield.
base = { [16] = slot(40, { equipLoc = "INVTYPE_WEAPON" }), [17] = slot(10, { equipLoc = "INVTYPE_WEAPON" }) }
best = SC.Best({ equipLoc = "INVTYPE_WEAPON", score = 30 }, base, { canDualWield = false })
eq(best.slots[1], 16, "no dual wield: main hand only")
best = SC.Best({ equipLoc = "INVTYPE_WEAPON", score = 30 }, base, { canDualWield = true })
eq(best.slots[1], 17, "dual wield: replaces the weaker off-hand weapon")

-- Empty vs unknown.
best = SC.Best({ equipLoc = "INVTYPE_CLOAK", score = 5 }, { [15] = { state = "empty" } })
eq(best.emptySlot, true, "confirmed empty slot")
best = SC.Best({ equipLoc = "INVTYPE_CLOAK", score = 5 }, {})
eq(best.state, "unknown", "missing occupancy is unknown, never empty")
best = SC.Best({ equipLoc = "INVTYPE_BAG", score = 5 }, {})
eq(best.state, "illegal", "not equippable")

done("test_slot_compare")
