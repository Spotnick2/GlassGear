------------------------------------------------------------
-- Integrations/GlassUI.lua - the Glass UI suite (adr/0004, GlassUI docs/SUITE.md).
-- Detection follows Shatter/Suite.lua:43-61: rawget, API == 1 exactly,
-- functions type-checked, every call under pcall. Glass UI lists Glass Gear
-- as a dynamic member (GUI-001, GlassUI#167); Presentation/Theme.lua decides
-- the look from the answer and reports what it built.
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
local GlassUI = {}
GG.Integrations.GlassUI = GlassUI

function GlassUI.SuiteAPI(env)
    env = env or _G
    local g = rawget(env, "GlassUI")
    local s = type(g) == "table" and rawget(g, "Suite")
    if type(s) ~= "table" or rawget(s, "API") ~= 1 then return nil end
    if type(rawget(s, "Theme")) ~= "function" or type(rawget(s, "Report")) ~= "function" then return nil end
    return s
end

-- Asked once, before any glass is built. Returns { following, theme, reason, code }:
-- `code` is "absent", "error" or Glass UI's own reason ("not-following", "not-ready", "unknown").
function GlassUI.Ask(env)
    local s = GlassUI.SuiteAPI(env)
    if not s then return { following = false, code = "absent", reason = L["Glass UI not loaded"] } end
    local ok, theme, why = pcall(s.Theme, GG.NAME)
    if not ok then return { following = false, code = "error", reason = L["Glass UI error"] } end
    if type(theme) ~= "table" or type(theme.preset) ~= "string" then
        local code = type(why) == "string" and why or "not-following"
        return { following = false, code = code, reason = code }
    end
    return { following = true, theme = theme }
end

-- One of the suite's optional functions (Look, Body, Accent), feature-detected
-- on its own; nil when it's missing, throws or Glass UI isn't here.
function GlassUI.Optional(name, ...)
    local s = GlassUI.SuiteAPI()
    local fn = s and rawget(s, name)
    if type(fn) ~= "function" then return nil end
    local ok, r = pcall(fn, ...)
    if ok then return r end
end

-- Report our state; Glass UI ignores reports from addons not on its roster.
function GlassUI.Report(state, env)
    local s = GlassUI.SuiteAPI(env)
    if s then pcall(s.Report, GG.NAME, state) end
end

return GlassUI
