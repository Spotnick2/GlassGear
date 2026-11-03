------------------------------------------------------------
-- Core/Prefs.lua - the settings model behind the options page (GG-112) and
-- anything else that changes a setting. Every write is validated here; the
-- page never touches GlassGearDB.settings itself.
--
--   Prefs.Get(path)                 "markers.scope" -> value
--   Prefs.Set(path, value)          -> true | false, reason
--   Prefs.SetSpec(list, spec, on)   tooltip/markers "selected" specs
--   Prefs.MinimumUpgrade() / SetMinimumUpgrade(fraction)
--   Prefs.IsTracked / SetTracked    protection's tracked specs
--   Prefs.Reset()                   PRD section 5 defaults
--
-- Three independent scopes (adr/0006): tooltip, markers, protection. A change
-- to any policy input fires EvaluationInvalidated (reason "settings"), so
-- stored answers, open tooltips, bag and loot marks and Shatter (GG-301) all
-- follow. The reveal key is not a policy input: it only re-reads the reveal.
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
local Prefs = {}
GG.Prefs = Prefs

Prefs.THRESHOLD_MAX = 0.05     -- 5 %
Prefs.LOOK_AHEAD_MAX = 10

local function oneOf(...)
    local set = {}
    for i = 1, select("#", ...) do set[select(i, ...)] = true end
    return function(v) return set[v] == true end
end
local function bool(v) return v == true or v == false end

-- path -> validator. Shift is refused on purpose (PRD section 4).
local RULES = {
    ["tooltip.specs"] = oneOf("all", "current", "selected"),
    ["tooltip.alts"] = bool,
    ["markers.scope"] = oneOf("current", "selected", "own"),
    ["markers.markTransferable"] = bool,
    ["reveal.modifier"] = oneOf("CTRL", "ALT", "NONE"),
    ["levelWindow.enabled"] = bool,
    ["levelWindow.lookAhead"] = function(v)
        return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= Prefs.LOOK_AHEAD_MAX
    end,
    ["specArmor"] = bool,
    ["setBonusWarnings"] = bool,
    ["protection.noWeights"] = oneOf("ignore", "keep"),
}
Prefs.SHIFT_REASON = L["Shift is used by item comparison"]   -- shown by the options page

local function settings() return GG.db.settings end

local function walk(path)
    local t = settings()
    local parent, key = nil, nil
    for part in path:gmatch("[^%.]+") do
        if key then
            parent = (parent or t)[key]
            if type(parent) ~= "table" then return nil end
        end
        key = part
    end
    return parent or t, key
end

local function changed(path)
    if path == "reveal.modifier" then
        if GG.Reveal then GG.Reveal.Update() end
        return
    end
    GG.API._Invalidate("settings")
end

function Prefs.Get(path)
    local t, key = walk(path)
    if not t then return nil end
    return t[key]
end

function Prefs.Set(path, value)
    if path == "reveal.modifier" and value == "SHIFT" then return false, Prefs.SHIFT_REASON end
    local rule = RULES[path]
    if not rule then return false, "unknown setting" end
    if not rule(value) then return false, "invalid value" end
    local t, key = walk(path)
    if not t then return false, "unknown setting" end
    if t[key] == value then return true end
    t[key] = value
    changed(path)
    return true
end

-- The "selected" specs of the tooltip or marker scope.
function Prefs.SetSpec(list, specKey, on)
    if list ~= "tooltip" and list ~= "markers" then return false, "unknown list" end
    if not GG.Data.Classes.Spec(specKey) then return false, "unknown spec" end
    local s = settings()[list]
    if type(s.selected) ~= "table" then s.selected = {} end
    local v = on and true or nil
    if s.selected[specKey] == v then return true end
    s.selected[specKey] = v
    changed(list .. ".selected")
    return true
end

function Prefs.SpecSelected(list, specKey)
    local s = settings()[list]
    return type(s) == "table" and type(s.selected) == "table" and s.selected[specKey] == true
end

-- One "Minimum upgrade" (PRD section 5): it applies to markers and protection
-- alike, never to the tooltip rows themselves.
function Prefs.MinimumUpgrade() return settings().markers.threshold end

function Prefs.SetMinimumUpgrade(fraction)
    if type(fraction) ~= "number" or fraction ~= fraction or fraction < 0 or fraction > Prefs.THRESHOLD_MAX then
        return false, "invalid value"
    end
    fraction = math.floor(fraction * 1000 + 0.5) / 1000      -- 0.1 % steps
    local s = settings()
    if s.markers.threshold == fraction and s.protection.threshold == fraction then return true end
    s.markers.threshold, s.protection.threshold = fraction, fraction
    changed("threshold")
    return true
end

-- Protection's tracked specs. A character nobody edited tracks all of its own
-- specs (the PRD default "all tracked specs"); an alt is tracked only when
-- chosen (GG-201/GG-203 bring alts).
function Prefs.IsTracked(charKey, specKey)
    local t = GG.db.tracked[charKey]
    if t == nil then return GG.player ~= nil and charKey == GG.player.key end
    return t[specKey] == true
end

function Prefs.SetTracked(charKey, specKey, on, allSpecs)
    if type(charKey) ~= "string" or not GG.Data.Classes.Spec(specKey) then return false, "unknown spec" end
    local t = GG.db.tracked[charKey]
    if t == nil then
        -- First edit: write down the implicit default before changing one spec.
        t = {}
        for _, key in ipairs(allSpecs or {}) do
            if Prefs.IsTracked(charKey, key) then t[key] = true end
        end
        GG.db.tracked[charKey] = t
    end
    local v = on and true or nil
    if t[specKey] == v then return true end
    t[specKey] = v
    changed("tracked")
    return true
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

function Prefs.Reset()
    GG.db.settings = copy(GG.DB.DEFAULTS.settings)
    GG.db.tracked = {}
    if GG.Reveal then GG.Reveal.Update() end
    GG.API._Invalidate("settings")
end

return Prefs
