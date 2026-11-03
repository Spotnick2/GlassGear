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
--   ProfileView.ClassLabel(token)      "Priest" (the Class= of an export)
------------------------------------------------------------

local GG = GlassGear
local View = {}
GG.ProfileView = View

-- Every code PawnString.Parse and Profiles can return. A code with a ":"
-- suffix (BAD_PAIR:3) is looked up by its head; the suffix fills %s.
local ERRORS = {
    NOT_PAWN = "Not a Pawn string. Expected ( Pawn: v1: \"Name\": Stat=value, ... )",
    CHARACTER_EXPORT_NOT_WEIGHTS = "This is a character export (SimulationCraft profile or WoWSims JSON), "
        .. "not weights. Run a simulation first, then import its Pawn string",
    UNSUPPORTED_VERSION = "Unsupported Pawn string version (only v1)",
    BAD_PAIR = "Can't read entry %s: expected Stat=number",
    VALUE_OUT_OF_RANGE = "A weight is out of range (-999.999 to 999.999): %s",
    NO_WEIGHTS = "No weight values found",
    TOO_MANY_TOKENS = "Too many stats: at most 40 per profile",
    TOO_MANY_PROFILES = "This spec already has 4 profiles: delete one, or replace one",
    NOT_A_NUMBER = "Not a number. Type a weight, X to ignore the stat, or leave it empty",
    UNKNOWN_STAT = "Unknown stat",
    EMPTY_NAME = "A profile needs a name",
    BAD_NAME = "A profile name can't contain a double quote",
    NO_ARMOR = "Allow at least one armor type, or use the spec's default",
    UNKNOWN_ARMOR = "Unknown armor type",
    stale = "Changed elsewhere (another session or a sync): the window now shows the latest",
    deleted = "This profile was deleted elsewhere",
    ["conflict-copy"] = "A conflict copy can't be edited",
    ["unknown-id"] = "This profile no longer exists",
    ["read-only"] = "Read-only this session: the saved data is newer than this version of Glass Gear",
}

function View.ErrorText(code)
    code = tostring(code)
    local head, rest = code:match("^([^:]+):(.*)$")
    if code:match("^bad%-data") then return "Glass Gear can't store this profile (" .. code .. ")" end
    local t = ERRORS[head or code]
    if not t then return "Can't do that (" .. code .. ")" end
    if t:find("%s", 1, true) then return (t:format(rest or "?")) end
    return t
end

local WARNINGS = {
    UNSUPPORTED_TOKEN = "Not scored by Glass Gear, kept for export: %s",
    CLASS_MISMATCH = "This string is for another class",
    WOWSIMS_DROPPED_STATS = "WoWSims' Pawn EP export leaves out hit, crit, haste and others: "
        .. "they count as missing, not as zero",
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
    ["imported-pawn"] = "Imported Pawn weights",
    ["wowsims-pawn-ep"] = "Imported WoWSims Pawn EP weights",
    manual = "Edited in Glass Gear",
    default = "Default weights",
    ["sim-result"] = "Simulation results",
}

function View.SourceLabel(source) return SOURCES[source] or tostring(source) end

-- The import box names what it read.
local KINDS = { ["imported-pawn"] = "Pawn string", ["wowsims-pawn-ep"] = "WoWSims Pawn EP export" }

function View.Freshness(at, now)
    if type(at) ~= "number" then return "" end
    local s = math.max(0, (now or at) - at)
    local function n(v, unit) return string.format("Updated %d %s%s ago", v, unit, v == 1 and "" or "s") end
    if s < 60 then return "Updated just now" end
    if s < 3600 then return n(math.floor(s / 60), "minute") end
    if s < 86400 then return n(math.floor(s / 3600), "hour") end
    return n(math.floor(s / 86400), "day")
end

local LABELS = {
    Ap = "Attack Power", Rap = "Ranged Attack Power", FeralAp = "Feral Attack Power",
    Mp5 = "Mana per 5 sec", Hp5 = "Health per 5 sec", Dps = "Weapon DPS", Speed = "Weapon Speed",
    SpellDamage = "Spell Damage", Healing = "Healing", SpeedBaseline = "Weapon Speed Baseline",
    IsCloth = "Cloth", IsLeather = "Leather", IsMail = "Mail", IsPlate = "Plate", IsShield = "Shield",
    IsAxe = "Axe", Is2HAxe = "Two-Hand Axe", IsBow = "Bow", IsCrossbow = "Crossbow", IsDagger = "Dagger",
    IsFist = "Fist Weapon", IsGun = "Gun", IsMace = "Mace", Is2HMace = "Two-Hand Mace", IsPolearm = "Polearm",
    IsRelic = "Relic", IsStaff = "Staff", IsSword = "Sword", Is2HSword = "Two-Hand Sword",
    IsThrown = "Thrown", IsWand = "Wand", IsOffHand = "Off-Hand", IsFrill = "Held In Off-Hand",
}

function View.StatLabel(token)
    if LABELS[token] then return LABELS[token] end
    local s = tostring(token):gsub("(%l)(%u)", "%1 %2"):gsub("Dps", "DPS")
    return s
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

-- { ok, kind, lines = { { text, level = "ok"|"warn"|"error"|"info" } } }
function View.Preview(text, classToken)
    if type(text) ~= "string" or text:match("^%s*$") then
        return { ok = false, lines = { { text = "Paste a Pawn string or a WoWSims Pawn EP export", level = "info" } } }
    end
    local p, err = GG.PawnString.Parse(text, { class = classToken })
    if not p then return { ok = false, lines = { { text = View.ErrorText(err), level = "error" } } } end
    local n = 0
    for _ in pairs(p.weights) do n = n + 1 end
    local lines = { { text = string.format("Valid %s \"%s\": %s", KINDS[p.source] or "profile", p.name,
        plural(n, "weight", "weights")), level = "ok" } }
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

function View.ClassLabel(token)
    token = tostring(token or "")
    return token:sub(1, 1):upper() .. token:sub(2):lower()
end

-- The armor line of a profile: "Cloth (spec default)" / "Cloth, Leather".
function View.ArmorText(p, specKey)
    local C = GG.Data.Classes
    local list, default = p and p.armor, false
    if not list then
        local spec = C.Spec(specKey)
        list, default = spec and spec.armor or {}, true
    end
    local names = {}
    for _, a in ipairs(list) do names[#names + 1] = C.ARMOR_NAME[a] or tostring(a) end
    return table.concat(names, ", ") .. (default and " (spec default)" or "")
end

return View
