------------------------------------------------------------
-- Data/Stats.lua - stat tokens (docs/FORMATS.md is the contract;
-- tests/test_formats_doc.lua fails when the two disagree).
--
-- Tokens are Pawn's scale-string names, so a Pawn string imports unchanged.
-- Item stats come from C_Item.GetItemStats, whose keys are locale-independent
-- global-string names (ITEM_MOD_*, RESISTANCE*_NAME). Measured on 70425
-- (Wanderful's probe log, docs/FOREVER-PROBE.md P4): spell power, school
-- damage, resistance, spirit, DPS. Keys marked "expected" are not sampled yet
-- (GG-103). An unmapped key is reported as UNSUPPORTED_STAT, never scored as
-- zero (adr/0003).
------------------------------------------------------------

local GG = GlassGear
local Stats = {}
GG.Data.Stats = Stats

-- Every token Glass Gear accepts in a profile (Pawn's Forever set).
Stats.TOKENS = {}
Stats.ORDER = {     -- the export order (FORMATS.md: "in the order of the token table")
    "Strength", "Agility", "Stamina", "Intellect", "Spirit", "Armor",
    "HitRating", "CritRating", "HasteRating", "ExpertiseRating", "SpellPenetration",
    "Ap", "Rap", "FeralAp", "SpellDamage", "Healing",
    "DefenseRating", "DodgeRating", "ParryRating", "BlockRating", "BlockValue",
    "Mp5", "Hp5",
    "FireResist", "NatureResist", "FrostResist", "ShadowResist", "ArcaneResist",
    "FireSpellDamage", "ShadowSpellDamage", "NatureSpellDamage", "ArcaneSpellDamage",
    "FrostSpellDamage", "HolySpellDamage",
    "Dps", "Speed", "MinDamage", "MaxDamage",
    "MeleeDps", "MeleeMinDamage", "MeleeMaxDamage", "MeleeSpeed",
    "RangedDps", "RangedMinDamage", "RangedMaxDamage", "RangedSpeed",
    "MainHandDps", "MainHandMinDamage", "MainHandMaxDamage", "MainHandSpeed",
    "OffHandDps", "OffHandMinDamage", "OffHandMaxDamage", "OffHandSpeed",
    "OneHandDps", "OneHandMinDamage", "OneHandMaxDamage", "OneHandSpeed",
    "TwoHandDps", "TwoHandMinDamage", "TwoHandMaxDamage", "TwoHandSpeed",
    "SpeedBaseline",
    "IsCloth", "IsLeather", "IsMail", "IsPlate", "IsShield",
    "IsAxe", "Is2HAxe", "IsBow", "IsCrossbow", "IsDagger", "IsFist", "IsGun",
    "IsMace", "Is2HMace", "IsPolearm", "IsRelic", "IsStaff", "IsSword", "Is2HSword",
    "IsThrown", "IsWand", "IsOffHand", "IsFrill",
}
for _, t in ipairs(Stats.ORDER) do Stats.TOKENS[t] = true end

-- GetItemStats key -> the tokens it feeds.
Stats.ITEM_MOD = {
    ITEM_MOD_STRENGTH_SHORT = { "Strength" },
    ITEM_MOD_AGILITY_SHORT = { "Agility" },
    ITEM_MOD_STAMINA_SHORT = { "Stamina" },
    ITEM_MOD_INTELLECT_SHORT = { "Intellect" },
    ITEM_MOD_SPIRIT_SHORT = { "Spirit" },
    RESISTANCE0_NAME = { "Armor" },
    ITEM_MOD_HIT_RATING_SHORT = { "HitRating" },
    ITEM_MOD_CRIT_RATING_SHORT = { "CritRating" },
    ITEM_MOD_HASTE_RATING_SHORT = { "HasteRating" },
    ITEM_MOD_EXPERTISE_RATING_SHORT = { "ExpertiseRating" },
    ITEM_MOD_SPELL_PENETRATION_SHORT = { "SpellPenetration" },
    ITEM_MOD_ATTACK_POWER_SHORT = { "Ap" },
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = { "Rap" },
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = { "FeralAp" },
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = { "SpellDamage" },   -- expected, GG-103
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = { "Healing" },      -- expected, GG-103
    -- "Increases damage and healing done by magical spells": one spell-power key,
    -- feeding both (measured 70425: items 11287, 11288).
    ITEM_MOD_SPELL_POWER_SHORT = { "SpellDamage", "Healing" },
    -- School damage has its own key (measured 70425: Shadow on 7001, Arcane on
    -- 12984; the other schools by the same pattern, not sampled).
    ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = { "ShadowSpellDamage" },
    ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT = { "ArcaneSpellDamage" },
    ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = { "FireSpellDamage" },
    ITEM_MOD_FROST_DAMAGE_DONE_SHORT = { "FrostSpellDamage" },
    ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = { "NatureSpellDamage" },
    ITEM_MOD_HOLY_DAMAGE_DONE_SHORT = { "HolySpellDamage" },
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = { "DefenseRating" },
    ITEM_MOD_DODGE_RATING_SHORT = { "DodgeRating" },
    ITEM_MOD_PARRY_RATING_SHORT = { "ParryRating" },
    ITEM_MOD_BLOCK_RATING_SHORT = { "BlockRating" },
    ITEM_MOD_BLOCK_VALUE_SHORT = { "BlockValue" },
    ITEM_MOD_POWER_REGEN0_SHORT = { "Mp5" },        -- expected (Pawn's mapping), GG-103
    ITEM_MOD_MANA_REGENERATION_SHORT = { "Mp5" },   -- alternative name, GG-103
    ITEM_MOD_HEALTH_REGEN_SHORT = { "Hp5" },
    RESISTANCE2_NAME = { "FireResist" },
    RESISTANCE3_NAME = { "NatureResist" },
    RESISTANCE4_NAME = { "FrostResist" },
    RESISTANCE5_NAME = { "ShadowResist" },
    RESISTANCE6_NAME = { "ArcaneResist" },
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = { "Dps" },
}

-- Resistance comes back twice, under both names (measured 70425, item
-- 279896: ITEM_MOD_FIRE_RESISTANCE_SHORT=3 and RESISTANCE2_NAME=3). The
-- ITEM_MOD_ form counts only when its RESISTANCEn_NAME twin is absent.
Stats.SAME_AS = {
    ITEM_MOD_FIRE_RESISTANCE_SHORT = "RESISTANCE2_NAME",
    ITEM_MOD_NATURE_RESISTANCE_SHORT = "RESISTANCE3_NAME",
    ITEM_MOD_FROST_RESISTANCE_SHORT = "RESISTANCE4_NAME",
    ITEM_MOD_SHADOW_RESISTANCE_SHORT = "RESISTANCE5_NAME",
    ITEM_MOD_ARCANE_RESISTANCE_SHORT = "RESISTANCE6_NAME",
}

-- Armor subclass (Enum.ItemArmorSubclass) -> type token; 7-11 are the class relics.
Stats.ARMOR_TOKEN = { [1] = "IsCloth", [2] = "IsLeather", [3] = "IsMail", [4] = "IsPlate", [6] = "IsShield",
    [7] = "IsRelic", [8] = "IsRelic", [9] = "IsRelic", [10] = "IsRelic", [11] = "IsRelic" }
-- Weapon subclass (Enum.ItemWeaponSubclass) -> type token.
Stats.WEAPON_TOKEN = { [0] = "IsAxe", [1] = "Is2HAxe", [2] = "IsBow", [3] = "IsGun", [4] = "IsMace",
    [5] = "Is2HMace", [6] = "IsPolearm", [7] = "IsSword", [8] = "Is2HSword", [10] = "IsStaff",
    [13] = "IsFist", [15] = "IsDagger", [16] = "IsThrown", [18] = "IsCrossbow", [19] = "IsWand" }
local RANGED_LOC = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

-- Status of every token: supported | derived | reported-unsupported.
Stats.STATUS = {}
for t in pairs(Stats.TOKENS) do Stats.STATUS[t] = "reported-unsupported" end
for _, tokens in pairs(Stats.ITEM_MOD) do
    for _, t in ipairs(tokens) do Stats.STATUS[t] = "supported" end
end
for _, t in pairs(Stats.ARMOR_TOKEN) do Stats.STATUS[t] = "supported" end
for _, t in pairs(Stats.WEAPON_TOKEN) do Stats.STATUS[t] = "supported" end
Stats.STATUS.IsOffHand, Stats.STATUS.IsFrill = "supported", "supported"
Stats.STATUS.MeleeDps, Stats.STATUS.RangedDps = "derived", "derived"

-- Maps a GetItemStats table to { [token] = value } plus the keys it could not
-- map. `facts` (optional: classID, subclassID, equipLoc) adds type tokens and
-- the derived Melee/RangedDps.
function Stats.FromItemStats(raw, facts)
    local out, unsupported = {}, {}
    for key, value in pairs(raw or {}) do
        local tokens = Stats.ITEM_MOD[key]
        local twin = Stats.SAME_AS[key]
        if twin then tokens = raw[twin] == nil and Stats.ITEM_MOD[twin] or {} end
        if tokens then
            for _, t in ipairs(tokens) do out[t] = (out[t] or 0) + value end
        elseif type(value) == "number" and value ~= 0 then
            unsupported[#unsupported + 1] = key
        end
    end
    if facts then
        local typeToken
        if facts.classID == 4 then typeToken = Stats.ARMOR_TOKEN[facts.subclassID] end
        if facts.classID == 2 then typeToken = Stats.WEAPON_TOKEN[facts.subclassID] end
        if typeToken then out[typeToken] = 1 end
        if facts.equipLoc == "INVTYPE_HOLDABLE" then out.IsFrill = 1 end
        if facts.equipLoc == "INVTYPE_WEAPONOFFHAND" then out.IsOffHand = 1 end
        if facts.classID == 2 and out.Dps then
            if RANGED_LOC[facts.equipLoc or ""] then out.RangedDps = out.Dps else out.MeleeDps = out.Dps end
        end
    end
    table.sort(unsupported)
    return out, unsupported
end

-- Tokens that only exist on weapons: an unscored one matters only for weapons.
local WEAPON_ONLY = {}
for _, t in ipairs({ "Speed", "MinDamage", "MaxDamage", "SpeedBaseline" }) do WEAPON_ONLY[t] = true end
for _, part in ipairs({ "Melee", "Ranged", "MainHand", "OffHand", "OneHand", "TwoHand" }) do
    for _, suffix in ipairs({ "Dps", "MinDamage", "MaxDamage", "Speed" }) do WEAPON_ONLY[part .. suffix] = true end
end

-- Profile tokens (weighted or X) that are never scored and that could matter
-- for this item: TOKEN_NOT_SCORED limitations (FORMATS.md, adr/0003).
function Stats.UnscoredTokens(profile, facts)
    local out, seen = {}, {}
    local function consider(token)
        if seen[token] or Stats.STATUS[token] ~= "reported-unsupported" then return end
        if WEAPON_ONLY[token] and not (facts and facts.classID == 2) then return end
        seen[token] = true
        out[#out + 1] = token
    end
    for token, w in pairs(profile and profile.weights or {}) do if w ~= 0 then consider(token) end end
    for token in pairs(profile and profile.ignored or {}) do consider(token) end
    table.sort(out)
    return out
end

return Stats
