------------------------------------------------------------
-- Data/Classes.lua - spec keys (adr/0002), class proficiency and per-spec
-- armor rules (adr/0003). Keys are stable: they are part of sync entry ids.
-- Add keys; never rename them.
------------------------------------------------------------

local GG = GlassGear
local Classes = {}
GG.Data.Classes = Classes

-- Armor subclass ids (Enum.ItemArmorSubclass): 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield.
local CLOTH, LEATHER, MAIL, PLATE, SHIELD = 1, 2, 3, 4, 6
local LIBRAM, IDOL, TOTEM, SIGIL, RELIC = 7, 8, 9, 10, 11
Classes.ARMOR = { CLOTH = CLOTH, LEATHER = LEATHER, MAIL = MAIL, PLATE = PLATE, SHIELD = SHIELD }
Classes.ARMOR_NAME = { [CLOTH] = "Cloth", [LEATHER] = "Leather", [MAIL] = "Mail", [PLATE] = "Plate", [SHIELD] = "Shield",
    [LIBRAM] = "Libram", [IDOL] = "Idol", [TOTEM] = "Totem", [SIGIL] = "Sigil", [RELIC] = "Relic" }

-- Specs in talent-tree order. `armor` = the spec's allowed body-armor types
-- (editable per profile). `early` = types also allowed while the spec's best
-- type can't be worn yet (a Protection Paladin wears mail until plate at 40).
Classes.SPECS = {
    WARRIOR = {
        { key = "WARRIOR.ARMS", name = "Arms", armor = { PLATE }, early = { MAIL } },
        { key = "WARRIOR.FURY", name = "Fury", armor = { PLATE }, early = { MAIL } },
        { key = "WARRIOR.PROTECTION", name = "Protection", armor = { PLATE }, early = { MAIL } },
    },
    PALADIN = {
        { key = "PALADIN.HOLY", name = "Holy", armor = { CLOTH, LEATHER, MAIL, PLATE } },
        { key = "PALADIN.PROTECTION", name = "Protection", armor = { PLATE }, early = { MAIL } },
        { key = "PALADIN.RETRIBUTION", name = "Retribution", armor = { PLATE }, early = { MAIL } },
    },
    HUNTER = {
        { key = "HUNTER.BEAST_MASTERY", name = "Beast Mastery", armor = { LEATHER, MAIL } },
        { key = "HUNTER.MARKSMANSHIP", name = "Marksmanship", armor = { LEATHER, MAIL } },
        { key = "HUNTER.SURVIVAL", name = "Survival", armor = { LEATHER, MAIL } },
    },
    ROGUE = {
        { key = "ROGUE.ASSASSINATION", name = "Assassination", armor = { LEATHER } },
        { key = "ROGUE.COMBAT", name = "Combat", armor = { LEATHER } },
        { key = "ROGUE.SUBTLETY", name = "Subtlety", armor = { LEATHER } },
    },
    PRIEST = {
        { key = "PRIEST.DISCIPLINE", name = "Discipline", armor = { CLOTH } },
        { key = "PRIEST.HOLY", name = "Holy", armor = { CLOTH } },
        { key = "PRIEST.SHADOW", name = "Shadow", armor = { CLOTH } },
    },
    SHAMAN = {
        { key = "SHAMAN.ELEMENTAL", name = "Elemental", armor = { CLOTH, LEATHER, MAIL } },
        { key = "SHAMAN.ENHANCEMENT", name = "Enhancement", armor = { LEATHER, MAIL } },
        { key = "SHAMAN.RESTORATION", name = "Restoration", armor = { CLOTH, LEATHER, MAIL } },
    },
    MAGE = {
        { key = "MAGE.ARCANE", name = "Arcane", armor = { CLOTH } },
        { key = "MAGE.FIRE", name = "Fire", armor = { CLOTH } },
        { key = "MAGE.FROST", name = "Frost", armor = { CLOTH } },
    },
    WARLOCK = {
        { key = "WARLOCK.AFFLICTION", name = "Affliction", armor = { CLOTH } },
        { key = "WARLOCK.DEMONOLOGY", name = "Demonology", armor = { CLOTH } },
        { key = "WARLOCK.DESTRUCTION", name = "Destruction", armor = { CLOTH } },
    },
    DRUID = {
        { key = "DRUID.BALANCE", name = "Balance", armor = { CLOTH, LEATHER } },
        { key = "DRUID.FERAL_TANK", name = "Feral (tank)", armor = { LEATHER } },
        { key = "DRUID.FERAL_CAT", name = "Feral (cat)", armor = { LEATHER } },
        { key = "DRUID.RESTORATION", name = "Restoration", armor = { CLOTH, LEATHER } },
    },
}

-- What the class can wear, with the level it is learned at on Forever
-- (Vanilla rules: mail/plate at 40). At runtime the character's known skills
-- override this fallback (Compat.KnownArmor, probe GG-118).
Classes.PROFICIENCY = {
    WARRIOR = { armor = { [CLOTH] = 1, [LEATHER] = 1, [MAIL] = 1, [PLATE] = 40, [SHIELD] = 1 } },
    PALADIN = { armor = { [CLOTH] = 1, [LEATHER] = 1, [MAIL] = 1, [PLATE] = 40, [SHIELD] = 1, [LIBRAM] = 1 } },
    HUNTER = { armor = { [CLOTH] = 1, [LEATHER] = 1, [MAIL] = 40 } },
    ROGUE = { armor = { [CLOTH] = 1, [LEATHER] = 1 } },
    PRIEST = { armor = { [CLOTH] = 1 } },
    SHAMAN = { armor = { [CLOTH] = 1, [LEATHER] = 1, [MAIL] = 40, [SHIELD] = 1, [TOTEM] = 1 } },
    MAGE = { armor = { [CLOTH] = 1 } },
    WARLOCK = { armor = { [CLOTH] = 1 } },
    DRUID = { armor = { [CLOTH] = 1, [LEATHER] = 1, [IDOL] = 1 } },
}

-- Weapon subclasses (Enum.ItemWeaponSubclass) each class can train on Forever
-- (Vanilla trainers). 0 1H axe, 1 2H axe, 2 bow, 3 gun, 4 1H mace, 5 2H mace,
-- 6 polearm, 7 1H sword, 8 2H sword, 10 staff, 13 fist, 15 dagger, 16 thrown,
-- 18 crossbow, 19 wand. Trainable is not known: runtime skills refine it.
local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end
Classes.WEAPONS = {
    WARRIOR = set({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }),
    PALADIN = set({ 0, 1, 4, 5, 6, 7, 8 }),
    HUNTER = set({ 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }),
    ROGUE = set({ 2, 3, 4, 7, 13, 15, 16, 18 }),
    PRIEST = set({ 4, 10, 15, 19 }),
    SHAMAN = set({ 0, 1, 4, 5, 10, 13, 15 }),
    MAGE = set({ 7, 10, 15, 19 }),
    WARLOCK = set({ 7, 10, 15, 19 }),
    DRUID = set({ 4, 5, 10, 13, 15 }),
}

-- Can this class use the item at all? `facts` has classID (2 weapon, 4 armor)
-- and subclassID. Returns ok, reason, learnLevel:
--   false, "PROFICIENCY"            the class never uses it
--   false, "NEEDS_TRAINING", lvl    learnable at lvl <= level, but the known
--                                    skills (runtime) say it isn't trained
--   true,  "LATER_LEVEL", lvl       learnable at a later level
--   true                             usable now
function Classes.CanUse(classToken, level, facts, knownArmor)
    if facts.classID == 2 then
        local w = Classes.WEAPONS[classToken or ""]
        if not (w and w[facts.subclassID]) then return false, "PROFICIENCY" end
        return true
    end
    if facts.classID == 4 and Classes.ARMOR_NAME[facts.subclassID] then
        local learn = Classes.LearnLevel(classToken, facts.subclassID)
        if not learn then return false, "PROFICIENCY" end
        if (level or 0) < learn then return true, "LATER_LEVEL", learn end
        local wearable = Classes.WearableArmor(classToken, level, knownArmor)
        if not wearable[facts.subclassID] then return false, "NEEDS_TRAINING", learn end
    end
    return true
end

-- The spec's allowed body-armor types for this character: the profile's own
-- set, else the spec default, plus `early` while the best type isn't wearable.
function Classes.AllowedArmor(specKey, profileArmor, classToken, level, knownArmor)
    if profileArmor then return profileArmor end
    local spec = Classes.Spec(specKey)
    if not spec or not spec.armor then return nil end
    local out, wearable = {}, Classes.WearableArmor(classToken, level, knownArmor)
    local bestWearable = false
    for _, a in ipairs(spec.armor) do
        out[#out + 1] = a
        if wearable[a] then bestWearable = true end
    end
    if not bestWearable then
        for _, a in ipairs(spec.early or {}) do out[#out + 1] = a end
    end
    return out
end

function Classes.Specs(classToken)
    return Classes.SPECS[classToken or ""] or {}
end

function Classes.Spec(specKey)
    local class = specKey and specKey:match("^([%u_]+)%.")
    for _, s in ipairs(Classes.Specs(class)) do
        if s.key == specKey then return s end
    end
end

-- The armor types this character can wear now. `known` (optional) is the
-- runtime set { [subclass] = true } read from skills; it wins when present.
function Classes.WearableArmor(classToken, level, known)
    if known then return known end
    local out = {}
    local p = Classes.PROFICIENCY[classToken or ""]
    for subclass, atLevel in pairs(p and p.armor or {}) do
        if (level or 0) >= atLevel then out[subclass] = true end
    end
    return out
end

-- The armor types a class learns later (subclass -> level), for LATER_LEVEL.
function Classes.LearnLevel(classToken, subclass)
    local p = Classes.PROFICIENCY[classToken or ""]
    return p and p.armor[subclass]
end

return Classes
