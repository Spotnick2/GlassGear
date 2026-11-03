------------------------------------------------------------
-- Integrations/GlassUI.lua - the Glass UI suite (adr/0004).
-- Detection follows Shatter/Suite.lua:43-61: rawget, API == 1 exactly,
-- functions type-checked, every call under pcall. Glass UI answers only
-- addons on its fixed roster (GlassUI/Suite.lua:31-56); until GUI-001 adds
-- GlassGear the answer is "unknown" and Glass Gear keeps the WoW Forever look.
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
local GlassUI = {}
GG.Integrations.GlassUI = GlassUI

function GlassUI.SuiteAPI(env)
    env = env or _G
    local g = rawget(env, "GlassUI")
    local s = type(g) == "table" and rawget(g, "Suite")
    if type(s) ~= "table" or s.API ~= 1 then return nil end
    if type(s.Theme) ~= "function" or type(s.Report) ~= "function" then return nil end
    return s
end

-- Asked once, before any glass is built. Returns { following, theme, reason }.
function GlassUI.Ask(env)
    local s = GlassUI.SuiteAPI(env)
    if not s then return { following = false, reason = L["Glass UI not loaded"] } end
    local ok, theme, why = pcall(s.Theme, GG.NAME)
    if not ok then return { following = false, reason = L["Glass UI error"] } end
    if type(theme) ~= "table" then return { following = false, reason = tostring(why or "not-following") } end
    return { following = true, theme = theme }
end

-- Report our state; Glass UI ignores reports from addons not on its roster.
function GlassUI.Report(state, env)
    local s = GlassUI.SuiteAPI(env)
    if s then pcall(s.Report, GG.NAME, state) end
end

return GlassUI
