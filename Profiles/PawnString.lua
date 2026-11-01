------------------------------------------------------------
-- Profiles/PawnString.lua - Pawn v1 scale strings (docs/FORMATS.md is the
-- contract: grammar, special keys, error and warning codes). Pure.
--
--   ( Pawn: v1: "Name": Class=Priest, Stamina=0.5, Intellect=1.2, Spirit=X )
--
-- Written from the documented format, not from Pawn's code (CC BY-NC-ND).
--   PawnString.Parse(text, opts) -> profile | nil, errorCode
--     opts.class = class token of the target character (CLASS_MISMATCH check)
--     profile = { version, name, origin, class, weights, ignored, ignoredTokens,
--                 missing, source = "imported-pawn"|"wowsims-pawn-ep", warnings }
--   PawnString.Export(profile, classLabel) -> text
------------------------------------------------------------

local GG = GlassGear
local Stats = GG.Data.Stats
local PawnString = {}
GG.PawnString = PawnString

PawnString.VERSION = 1
PawnString.MAX_NAME = 24
PawnString.MAX_TOKENS = 40
PawnString.MAX_ABS = 999.999

local META = { Class = true, Spec = true }

-- Stats WoWSims' Pawn EP export never carries (FORMATS.md, WoWSims section):
-- missing, not zero.
PawnString.WOWSIMS_DROPPED = { "HitRating", "CritRating", "HasteRating", "DefenseRating", "DodgeRating",
    "ParryRating", "BlockRating", "BlockValue", "SpellDamage", "Healing", "FeralAp",
    "FireSpellDamage", "ShadowSpellDamage", "NatureSpellDamage", "ArcaneSpellDamage",
    "FrostSpellDamage", "HolySpellDamage" }

-- Pawn class names and ids -> class tokens.
local CLASS = { WARRIOR = "WARRIOR", PALADIN = "PALADIN", HUNTER = "HUNTER", ROGUE = "ROGUE",
    PRIEST = "PRIEST", SHAMAN = "SHAMAN", MAGE = "MAGE", WARLOCK = "WARLOCK", DRUID = "DRUID",
    ["1"] = "WARRIOR", ["2"] = "PALADIN", ["3"] = "HUNTER", ["4"] = "ROGUE", ["5"] = "PRIEST",
    ["7"] = "SHAMAN", ["8"] = "MAGE", ["9"] = "WARLOCK", ["11"] = "DRUID" }

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- A character description (WoWSims JSON, SimulationCraft profile), not weights.
local function isCharacterExport(text)
    if text:match("^%s*{") then return true end
    local hasClassLine = text:match("\n?%s*%a+%s*=%s*\"[^\"]*\"") ~= nil
    return hasClassLine and text:find("spec=", 1, true) ~= nil and text:find("talents=", 1, true) ~= nil
end

function PawnString.Parse(text, opts)
    opts = opts or {}
    if type(text) ~= "string" or trim(text) == "" then return nil, "NOT_PAWN" end
    text = trim(text)
    local version, name, body = text:match('^%(%s*Pawn%s*:%s*v(%d+)%s*:%s*"([^"]+)"%s*:%s*(.-)%s*%)$')
    if not version then
        if isCharacterExport(text) then return nil, "CHARACTER_EXPORT_NOT_WEIGHTS" end
        return nil, "NOT_PAWN"
    end
    if tonumber(version) ~= PawnString.VERSION then return nil, "UNSUPPORTED_VERSION" end

    local p = { version = 1, name = name, origin = name, weights = {}, ignored = {}, ignoredTokens = {},
        missing = {}, warnings = {}, source = "imported-pawn" }
    local numeric, total, position = 0, 0, 0
    body = body:gsub(",%s*$", "")
    for pair in (body .. ","):gmatch("([^,]*),") do
        position = position + 1
        pair = trim(pair)
        local key, value = pair:match("^(%w+)%s*=%s*(%S+)$")
        if not key then return nil, "BAD_PAIR:" .. position end
        if META[key] then
            p[key:lower()] = value
        elseif not Stats.TOKENS[key] then
            p.ignoredTokens[key] = value
            total = total + 1
            p.warnings[#p.warnings + 1] = "UNSUPPORTED_TOKEN:" .. key
        elseif value == "X" then
            p.ignored[key] = true
            total = total + 1
        else
            if not value:match("^%-?%d+%.?%d*$") and not value:match("^%-?%.%d+$") then
                return nil, "BAD_PAIR:" .. position
            end
            local n = tonumber(value)
            if math.abs(n) > PawnString.MAX_ABS then return nil, "VALUE_OUT_OF_RANGE:" .. key end
            if n ~= 0 then p.weights[key] = n end
            numeric, total = numeric + 1, total + 1
        end
    end
    if numeric == 0 then return nil, "NO_WEIGHTS" end
    if total > PawnString.MAX_TOKENS then return nil, "TOO_MANY_TOKENS" end
    if #name > PawnString.MAX_NAME then p.name = name:sub(1, PawnString.MAX_NAME) end

    if p.class and opts.class then
        local c = CLASS[(p.class:upper():gsub("%s+", ""))]
        if c ~= opts.class then p.warnings[#p.warnings + 1] = "CLASS_MISMATCH" end
    end
    if name:find("WoWSims Weights", 1, true) then
        p.source = "wowsims-pawn-ep"
        p.warnings[#p.warnings + 1] = "WOWSIMS_DROPPED_STATS"
        for _, t in ipairs(PawnString.WOWSIMS_DROPPED) do
            if p.weights[t] == nil and not p.ignored[t] then p.missing[#p.missing + 1] = t end
        end
    end
    table.sort(p.warnings)
    return p
end

local function fmt(n)
    local s = string.format("%.3f", n)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
end

function PawnString.Export(profile, classLabel)
    local parts = {}
    if classLabel then parts[#parts + 1] = "Class=" .. classLabel end
    for _, t in ipairs(Stats.ORDER) do
        if profile.ignored and profile.ignored[t] then
            parts[#parts + 1] = t .. "=X"
        elseif profile.weights and profile.weights[t] then
            parts[#parts + 1] = t .. "=" .. fmt(profile.weights[t])
        end
    end
    local extra = {}
    for k in pairs(profile.ignoredTokens or {}) do extra[#extra + 1] = k end
    table.sort(extra)
    for _, k in ipairs(extra) do parts[#parts + 1] = k .. "=" .. profile.ignoredTokens[k] end
    local name = (profile.origin or profile.name or "Glass Gear"):gsub('"', "'")
    return string.format('( Pawn: v1: "%s": %s )', name, table.concat(parts, ", "))
end

return PawnString
