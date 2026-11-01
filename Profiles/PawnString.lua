------------------------------------------------------------
-- Profiles/PawnString.lua - Pawn v1 scale strings (docs/FORMATS.md). Pure.
--
--   ( Pawn: v1: "Name": Class=Priest, Stamina=0.5, Intellect=1.2, Spirit=X )
--
-- Written from the documented format, not from Pawn's code (CC BY-NC-ND).
--   PawnString.Parse(text) -> profile | nil, err
--     profile = { version, name, class, spec, weights, ignored,
--                 unknownTokens = {..}, source = "imported-pawn"|"wowsims-pawn-ep",
--                 warnings = {..} }
--   PawnString.Export(profile, classLabel) -> text
------------------------------------------------------------

local GG = GlassGear
local Stats = GG.Data.Stats
local PawnString = {}
GG.PawnString = PawnString

PawnString.MAX_VERSION = 1
PawnString.MAX_NAME = 24
PawnString.MAX_TOKENS = 40

local META = { Class = true, Spec = true }

-- Stats WoWSims' Pawn EP export never carries (docs/FORMATS.md).
local WOWSIMS_DROPPED = { "HitRating", "CritRating", "HasteRating", "DefenseRating", "BlockRating",
    "SpellDamage", "Healing", "FeralAp" }

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

function PawnString.Parse(text)
    if type(text) ~= "string" then return nil, "EMPTY" end
    text = trim(text)
    if text == "" then return nil, "EMPTY" end
    local version, name, body = text:match('^%(%s*Pawn%s*:%s*v(%d+)%s*:%s*"([^"]+)"%s*:%s*(.-)%s*%)$')
    if not version then return nil, "NOT_A_PAWN_STRING" end
    version = tonumber(version)
    if version > PawnString.MAX_VERSION then return nil, "UNSUPPORTED_VERSION" end

    local p = { version = version, name = name, weights = {}, ignored = {}, unknownTokens = {},
        warnings = {}, source = "imported-pawn", origin = name }
    local count = 0
    for pair in (body .. ","):gmatch("([^,]*),") do
        pair = trim(pair)
        if pair ~= "" then
            local key, value = pair:match("^([%w]+)%s*=%s*([%-%w%.]+)$")
            if not key then return nil, "BAD_PAIR:" .. pair end
            if META[key] then
                p[key:lower()] = value
            elseif not Stats.TOKENS[key] then
                p.unknownTokens[#p.unknownTokens + 1] = key
            elseif value == "X" then
                p.ignored[key] = true
                count = count + 1
            else
                local n = tonumber(value)
                if not n then return nil, "BAD_VALUE:" .. key end
                if n ~= 0 then
                    p.weights[key] = math.max(-999.999, math.min(999.999, n))
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return nil, "NO_WEIGHTS" end
    if count > PawnString.MAX_TOKENS then return nil, "TOO_MANY_TOKENS" end
    table.sort(p.unknownTokens)
    for _, t in ipairs(p.unknownTokens) do p.warnings[#p.warnings + 1] = "UNKNOWN_STAT:" .. t end

    if name:find("WoWSims Weights", 1, true) then
        p.source = "wowsims-pawn-ep"
        for _, t in ipairs(WOWSIMS_DROPPED) do
            if p.weights[t] == nil and not p.ignored[t] then
                p.warnings[#p.warnings + 1] = "WOWSIMS_DROPS:" .. t
            end
        end
    end
    if #name > PawnString.MAX_NAME then p.name = name:sub(1, PawnString.MAX_NAME) end
    return p
end

local function fmt(n)
    local s = string.format("%.3f", n)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
end

function PawnString.Export(profile, classLabel)
    local keys = {}
    for k in pairs(profile.weights or {}) do keys[#keys + 1] = k end
    for k in pairs(profile.ignored or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    if classLabel then parts[#parts + 1] = "Class=" .. classLabel end
    for _, k in ipairs(keys) do
        if profile.ignored and profile.ignored[k] then
            parts[#parts + 1] = k .. "=X"
        else
            parts[#parts + 1] = k .. "=" .. fmt(profile.weights[k])
        end
    end
    local name = (profile.name or "Glass Gear"):gsub('"', "'")
    return string.format('( Pawn: v1: "%s": %s )', name, table.concat(parts, ", "))
end

return PawnString
