------------------------------------------------------------
-- Presentation/ProfileView.lua - the texts of the profiles window (GG-105,
-- mockups 05 and G3). Pure: codes and profiles in, plain text out, so every
-- message is tested without a client.
--
--   ProfileView.ErrorText(code)        an import or edit refusal, readable
--   ProfileView.WarningText(code, p)   an import warning, readable
--   ProfileView.SourceLabel(source)    "Imported Pawn weights", ...
--   ProfileView.Freshness(at, now)     "Updated 2 hours ago"
--   ProfileView.StatLabel(token)       "Spell Damage"
--   ProfileView.Preview(text, class)   the import box's verdict, live
--   ProfileView.WeightText(p, token)   the editor's value for a stat
--   ProfileView.ClassLabel(token)      "Priest" (the Class= of an export; English)
--   ProfileView.ClassDisplay(token)    the class's name in the client's language
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
local View = {}
GG.ProfileView = View

-- Every code PawnString.Parse and Profiles can return. A code with a ":"
-- suffix (BAD_PAIR:3) is looked up by its head; the suffix fills %s.
local ERRORS = {
    NOT_PAWN = L["Not a Pawn string. Expected ( Pawn: v1: \"Name\": Stat=value, ... )"],
    CHARACTER_EXPORT_NOT_WEIGHTS = L["This is a character export (SimulationCraft profile or WoWSims JSON), not weights. Run a simulation first, then import its Pawn string"],
    UNSUPPORTED_VERSION = L["Unsupported Pawn string version (only v1)"],
    BAD_PAIR = L["Can't read entry %s: expected Stat=number"],
    VALUE_OUT_OF_RANGE = L["A weight is out of range (-999.999 to 999.999): %s"],
    NO_WEIGHTS = L["No weight values found"],
    TOO_MANY_TOKENS = L["Too many stats: at most 40 per profile"],
    TOO_MANY_PROFILES = L["This spec already has 4 profiles: delete one, or replace one"],
    NOT_A_NUMBER = L["Not a number. Type a weight, X to ignore the stat, or leave it empty"],
    UNKNOWN_STAT = L["Unknown stat"],
    EMPTY_NAME = L["A profile needs a name"],
    BAD_NAME = L["A profile name can't contain a double quote"],
    NO_ARMOR = L["Allow at least one armor type, or use the spec's default"],
    UNKNOWN_ARMOR = L["Unknown armor type"],
    stale = L["Changed elsewhere (another session or a sync): the window now shows the latest"],
    deleted = L["This profile was deleted elsewhere"],
    ["conflict-copy"] = L["A conflict copy can't be edited"],
    ["unknown-id"] = L["This profile no longer exists"],
    ["read-only"] = L["Read-only this session: the saved data is newer than this version of Glass Gear"],
}

function View.ErrorText(code)
    code = tostring(code)
    local head, rest = code:match("^([^:]+):(.*)$")
    if code:match("^bad%-data") then return L["Glass Gear can't store this profile (%s)"]:format(code) end
    local t = ERRORS[head or code]
    if not t then return L["Can't do that (%s)"]:format(code) end
    if t:find("%s", 1, true) then return (t:format(rest or "?")) end
    return t
end

local WARNINGS = {
    UNSUPPORTED_TOKEN = L["Not scored by Glass Gear, kept for export: %s"],
    CLASS_MISMATCH = L["This string is for another class"],
    WOWSIMS_DROPPED_STATS = L["WoWSims' Pawn EP export leaves out hit, crit, haste and others: they count as missing, not as zero"],
}

function View.WarningText(code)
    code = tostring(code)
    local head, rest = code:match("^([^:]+):(.*)$")
    local t = WARNINGS[head or code]
    if not t then return code end
    if t:find("%s", 1, true) then return (t:format(rest or "?")) end
    return t
end

local SOURCES = {
    ["imported-pawn"] = L["Imported Pawn weights"],
    ["wowsims-pawn-ep"] = L["Imported WoWSims Pawn EP weights"],
    manual = L["Edited in Glass Gear"],
    default = L["Default weights"],
    ["sim-result"] = L["Simulation results"],
}

function View.SourceLabel(source) return SOURCES[source] or tostring(source) end

-- The import box names what it read.
local KINDS = { ["imported-pawn"] = L["Pawn string"], ["wowsims-pawn-ep"] = L["WoWSims Pawn EP export"] }

function View.Freshness(at, now)
    if type(at) ~= "number" then return "" end
    local s = math.max(0, (now or at) - at)
    if s < 60 then return L["Updated just now"] end
    if s < 3600 then
        local v = math.floor(s / 60)
        return (v == 1 and L["Updated %d minute ago"] or L["Updated %d minutes ago"]):format(v)
    end
    if s < 86400 then
        local v = math.floor(s / 3600)
        return (v == 1 and L["Updated %d hour ago"] or L["Updated %d hours ago"]):format(v)
    end
    local v = math.floor(s / 86400)
    return (v == 1 and L["Updated %d day ago"] or L["Updated %d days ago"]):format(v)
end

-- Every token's label (a token outside this table, e.g. one an import kept
-- for export, is spelled out from its name).
local LABELS = {
    Strength = L["Strength"], Agility = L["Agility"], Stamina = L["Stamina"], Intellect = L["Intellect"],
    Spirit = L["Spirit"], Armor = L["Armor"],
    HitRating = L["Hit Rating"], CritRating = L["Crit Rating"], HasteRating = L["Haste Rating"],
    ExpertiseRating = L["Expertise Rating"], SpellPenetration = L["Spell Penetration"],
    Ap = L["Attack Power"], Rap = L["Ranged Attack Power"], FeralAp = L["Feral Attack Power"],
    DefenseRating = L["Defense Rating"], DodgeRating = L["Dodge Rating"], ParryRating = L["Parry Rating"],
    BlockRating = L["Block Rating"], BlockValue = L["Block Value"],
    Mp5 = L["Mana per 5 sec"], Hp5 = L["Health per 5 sec"], Dps = L["Weapon DPS"], Speed = L["Weapon Speed"],
    SpellDamage = L["Spell Damage"], Healing = L["Healing"], SpeedBaseline = L["Weapon Speed Baseline"],
    FireResist = L["Fire Resist"], NatureResist = L["Nature Resist"], FrostResist = L["Frost Resist"],
    ShadowResist = L["Shadow Resist"], ArcaneResist = L["Arcane Resist"],
    FireSpellDamage = L["Fire Spell Damage"], ShadowSpellDamage = L["Shadow Spell Damage"],
    NatureSpellDamage = L["Nature Spell Damage"], ArcaneSpellDamage = L["Arcane Spell Damage"],
    FrostSpellDamage = L["Frost Spell Damage"], HolySpellDamage = L["Holy Spell Damage"],
    MinDamage = L["Min Damage"], MaxDamage = L["Max Damage"],
    MeleeDps = L["Melee DPS"], MeleeMinDamage = L["Melee Min Damage"], MeleeMaxDamage = L["Melee Max Damage"],
    MeleeSpeed = L["Melee Speed"],
    RangedDps = L["Ranged DPS"], RangedMinDamage = L["Ranged Min Damage"], RangedMaxDamage = L["Ranged Max Damage"],
    RangedSpeed = L["Ranged Speed"],
    MainHandDps = L["Main Hand DPS"], MainHandMinDamage = L["Main Hand Min Damage"],
    MainHandMaxDamage = L["Main Hand Max Damage"], MainHandSpeed = L["Main Hand Speed"],
    OffHandDps = L["Off Hand DPS"], OffHandMinDamage = L["Off Hand Min Damage"],
    OffHandMaxDamage = L["Off Hand Max Damage"], OffHandSpeed = L["Off Hand Speed"],
    OneHandDps = L["One Hand DPS"], OneHandMinDamage = L["One Hand Min Damage"],
    OneHandMaxDamage = L["One Hand Max Damage"], OneHandSpeed = L["One Hand Speed"],
    TwoHandDps = L["Two Hand DPS"], TwoHandMinDamage = L["Two Hand Min Damage"],
    TwoHandMaxDamage = L["Two Hand Max Damage"], TwoHandSpeed = L["Two Hand Speed"],
    IsCloth = L["Cloth"], IsLeather = L["Leather"], IsMail = L["Mail"], IsPlate = L["Plate"], IsShield = L["Shield"],
    IsAxe = L["Axe"], Is2HAxe = L["Two-Hand Axe"], IsBow = L["Bow"], IsCrossbow = L["Crossbow"], IsDagger = L["Dagger"],
    IsFist = L["Fist Weapon"], IsGun = L["Gun"], IsMace = L["Mace"], Is2HMace = L["Two-Hand Mace"], IsPolearm = L["Polearm"],
    IsRelic = L["Relic"], IsStaff = L["Staff"], IsSword = L["Sword"], Is2HSword = L["Two-Hand Sword"],
    IsThrown = L["Thrown"], IsWand = L["Wand"], IsOffHand = L["Off-Hand"], IsFrill = L["Held In Off-Hand"],
}

function View.StatLabel(token)
    if LABELS[token] then return LABELS[token] end
    local s = tostring(token):gsub("(%l)(%u)", "%1 %2"):gsub("Dps", "DPS")
    return s
end

-- { ok, kind, lines = { { text, level = "ok"|"warn"|"error"|"info" } } }
function View.Preview(text, classToken)
    if type(text) ~= "string" or text:match("^%s*$") then
        return { ok = false, lines = { { text = L["Paste a Pawn string or a WoWSims Pawn EP export"], level = "info" } } }
    end
    local p, err = GG.PawnString.Parse(text, { class = classToken })
    if not p then return { ok = false, lines = { { text = View.ErrorText(err), level = "error" } } } end
    local n = 0
    for _ in pairs(p.weights) do n = n + 1 end
    local valid = n == 1 and L["Valid %s \"%s\": %d weight"] or L["Valid %s \"%s\": %d weights"]
    local lines = { { text = valid:format(KINDS[p.source] or L["profile"], p.name, n), level = "ok" } }
    for _, w in ipairs(p.warnings) do lines[#lines + 1] = { text = View.WarningText(w), level = "warn" } end
    return { ok = true, kind = KINDS[p.source], parsed = p, lines = lines }
end

-- The value shown in the editor: "", "X" or the number (3 decimals at most).
function View.WeightText(p, token)
    if p.ignored and p.ignored[token] then return "X" end
    local v = p.weights and p.weights[token]
    if not v then return "" end
    return (string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", ""))
end

function View.ClassDisplay(token)
    return GG.Compat and GG.Compat.ClassName and GG.Compat.ClassName(token) or View.ClassLabel(token)
end

function View.ClassLabel(token)
    token = tostring(token or "")
    return token:sub(1, 1):upper() .. token:sub(2):lower()
end

-- The armor line of a profile: "Cloth (spec default)" / "Cloth, Leather".
-- `bare`: the armor names alone, never the "(spec default)" note.
function View.ArmorText(p, specKey, bare)
    local C = GG.Data.Classes
    local list, default = p and p.armor, false
    if not list then
        local spec = C.Spec(specKey)
        list, default = spec and spec.armor or {}, true
    end
    local names = {}
    for _, a in ipairs(list) do names[#names + 1] = C.ARMOR_NAME[a] or tostring(a) end
    local text = table.concat(names, ", ")
    if default and not bare then return L["%s (spec default)"]:format(text) end
    return text
end

return View
