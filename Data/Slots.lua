------------------------------------------------------------
-- Data/Slots.lua - equip locations and inventory slots (locale-independent).
------------------------------------------------------------

local GG = GlassGear
local Slots = {}
GG.Data.Slots = Slots

Slots.MAIN_HAND, Slots.OFF_HAND, Slots.RANGED = 16, 17, 18

-- The slots a baseline records (shirt 4 and tabard 19 carry no stats).
Slots.GEAR = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

-- INVTYPE_* -> candidate slots. INVTYPE_WEAPON's off-hand slot needs dual wield.
Slots.FOR_EQUIP_LOC = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}

Slots.TWO_HAND = { INVTYPE_2HWEAPON = true }

function Slots.IsEquippable(equipLoc)
    return Slots.FOR_EQUIP_LOC[equipLoc or ""] ~= nil
end

return Slots
