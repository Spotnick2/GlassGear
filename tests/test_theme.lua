------------------------------------------------------------
-- test_theme.lua - GG-115: the Glass look through Glass UI's suite
-- (Presentation/Theme.lua, GlassUI docs/SUITE.md and SUITE-LOOK.md).
--
-- Glass UI and LibGlass are fakes defined here, shaped as their contracts
-- say: GlassUI.Suite (API 1: Theme, Report, Look, Body, Accent) and a
-- LibStub answering "LibGlass-1.0" with a MINOR. The decision is made once,
-- at ADDON_LOADED, and reported; every fallback keeps WoW Forever and the
-- saved appearance keys untouched.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

-- Masks are LibGlass's (Theme only hands a mask to AddMaskTexture): this
-- file's textures take one. Kept here, not in the shared stubs (#65).
local baseCreateFrame = CreateFrame
rawset(_G, "CreateFrame", function(...)
    local f = baseCreateFrame(...)
    local createTexture = f.CreateTexture
    f.CreateTexture = function(self, ...)
        local t = createTexture(self, ...)
        t.layer = select(2, ...)
        t.AddMaskTexture = function(tex, m) tex.mask = m end
        return t
    end
    return f
end)

------------------------------------------------------------
-- The fakes
------------------------------------------------------------

local glass = { minor = 12, presets = { classic = true, clean = true, pearl = true }, built = {}, throw = nil }
local function newInstance(preset)
    local inst = { preset = preset, STYLE = { wash = 0.10 }, calls = {},
        SIZES = { thin_small = { mask = "thin_small_mask", maskMargin = 4 } } }
    local function rec(name) return function(...) inst.calls[#inst.calls + 1] = { name, ... } end end
    function inst.Apply(host, size)
        local g = { size = size, mask = { kind = "mask" }, host = host, tint = {}, alphas = {} }
        inst.calls[#inst.calls + 1] = { "Apply", host, size }
        return g
    end
    function inst.SetSurfaceTint(g, r, gg, b, a) g.tint = { r, gg, b, a } end
    function inst.SetWash(g, w) g.wash = w end
    function inst.SetSurfaceAlpha(g, part, a) g.alphas[part] = a end
    function inst.SetEdge(g, ...) g.edge = { ... } end
    function inst.Reflect(g, host, opts) g.reflect = { host = host, opts = opts } end
    inst.Mask = function(host, file, margin, inset, anchor) return { kind = "mask", file = file } end
    inst.rec = rec
    return inst
end
local lib = {}
function lib:New(opts)
    if glass.throw then error(glass.throw) end
    if opts.preset and not glass.presets[opts.preset] then
        error('LibGlass-1.0: unknown preset ' .. opts.preset .. ' (use "classic", "clean" or "pearl", or omit it)')
    end
    local inst = newInstance(opts.preset)
    glass.built[#glass.built + 1] = inst
    return inst
end
rawset(_G, "LibStub", setmetatable({}, { __call = function(_, name, silent)
    if name == "LibGlass-1.0" and glass.minor then return lib, glass.minor end
    if not silent then error("no " .. name) end
end }))

local suite = {
    answer = { name = "pearl", preset = "pearl" }, why = nil, throw = false,
    look = { tint = "smoked", hover = "glow", press = "flash", emptySlots = "frosted", accent = "ice" },
    reports = {}, asked = 0,
}
local function makeSuite()
    local S = { API = 1 }
    function S.Theme(addon)
        suite.asked = suite.asked + 1
        suite.askedFor = addon
        if suite.throw then error("boom") end
        if suite.answer then
            local t = {}
            for k, v in pairs(suite.answer) do t[k] = v end
            return t
        end
        return nil, suite.why
    end
    function S.Report(addon, state) suite.reports[#suite.reports + 1] = { addon = addon, state = state } end
    function S.Look() return suite.look end
    function S.Body(tint)
        if tint == "smoked" then return { tint = { 0.05, 0.06, 0.08, 0.62 }, backing = { 0.04, 0.05, 0.07, 0.92 }, wash = 0.14 } end
        if tint == "class" then return { classShade = 0.6, backing = { 0.04, 0.05, 0.07, 0.35 }, wash = 1 } end
    end
    function S.Accent(name)
        if name == "ice" then return { 0.65, 0.835, 0.905 } end
        if name == "gold" then return { 1, 0.82, 0 } end
    end
    return S
end
rawset(_G, "GlassUI", { Suite = makeSuite() })
local function lastReport() local r = suite.reports[#suite.reports]; return r and r.state end

------------------------------------------------------------
-- 1. The real load: Glass UI follows, Pearl built and reported
------------------------------------------------------------

local GG = WoW.loadAddon()
local T = GG.Theme
H.eq(suite.askedFor, "GlassGear", "Glass Gear asks the suite under its roster name")
H.eq(suite.asked, 1, "asked once, at ADDON_LOADED")
H.eq(GG.themeName, "glass", "following Glass UI: the glass look")
H.eq(GG.themeInfo.code, "following", "...recorded as following")
H.eq(#suite.reports, 1, "one report")
H.eq(suite.reports[1].addon, "GlassGear", "reported under the roster name")
local r = lastReport()
H.eq(r.api, 1, "report api 1")
H.eq(r.built, "pearl", "report: Pearl built")
H.eq(r.minor, 12, "report: LibGlass's minor at the build")
H.eq(r.live, false, "report: not live (a change waits for /reload)")
H.eq(r.declined, nil, "report: not declined")
H.eq(r.reason, nil, "report: no failure")
H.eq(r.look and r.look.tint, "smoked", "report: the tint it built")
H.eq(r.look and r.look.accent, "ice", "report: the accent it built")
H.eq(r.own, nil, "report: nothing of its own")
H.eq(type(r.options), "function", "report: an options opener")
H.eq(glass.built[1].preset, "pearl", "the instance is the suite's preset")
H.eq(GlassGearDB.settings.appearance.theme, "forever", "the saved appearance is untouched")
H.eq(GlassGearDB.settings.appearance.followGlassUI, true, "following is the default")

-- Glass UI's link to our settings opens them.
local opened = 0
local realOpen = GG.Options.Open
GG.Options.Open = function() opened = opened + 1; return true end
H.eq(r.options(), true, "the options function opens the settings")
H.eq(opened, 1, "...through Options.Open")
GG.Options.Open = realOpen

-- A window in glass: shell, backing in the suite's body, reflection under the title, accent title.
local win = GG.Window.New({ name = "GlassGearThemeTestWindow", key = "themetest", width = 300, height = 200, title = "T" })
H.check(win.glass ~= nil, "the window gets a glass shell")
H.eq(win.backdrop, nil, "...and no WoW Forever backdrop")
local g = win.glass
H.eq(g.size, "large", "a large shell")
H.eq(g.backing.mask, g.mask, "the backing is clipped by the glass mask")
H.eq(g.backing.color[4], 0.92, "the backing is the suite's (smoked) body")
H.eq(g.tint[4], 0.62, "the tint is the suite's body")
H.check(math.abs(g.wash - 0.10 * 0.14) < 1e-9, "the wash is the body's factor of the preset's own")
H.eq(g.reflect.opts.header, 28, "the reflection lights the title bar")
H.eq(g.edge[1], 0, "no edge: the reflection's top line replaces it")
H.eq(win.titleText.color[1], 0.65, "the title wears the suite's accent")
local pane = baseCreateFrame("Frame")
pane.CreateTexture = win.CreateTexture
H.eq(T.Reading(pane), true, "a reading pane in glass")
H.eq(pane.glassReading.mask.file, "thin_small_mask", "...masked")

-- The real windows: the profiles window's shell and its import box as a reading pane.
GG.ProfilesWindow.Open()
local profilesFrame, readings = nil, 0
for _, f in ipairs(WoW.frames) do
    if f.glassReading then readings = readings + 1 end
    if f.name == GG.ProfilesWindow.NAME then profilesFrame = f end
end
H.check(profilesFrame and profilesFrame.glass ~= nil, "the profiles window opens in glass")
H.eq(readings, 2, "...its import box is a glass reading pane (with the test's own pane)")

local diagGlass = false
for _, line in ipairs(GG.Diagnostics.Lines()) do
    if line:find("theme: glass (pearl)", 1, true) then diagGlass = true end
end
H.check(diagGlass, "/gg diag names the glass preset")

-- Init again in the same session changes nothing and reports nothing more.
H.eq(T.Init(false), "glass", "the look is fixed for the session")
H.eq(#suite.reports, 1, "...and not reported again")

------------------------------------------------------------
-- 2. The switch in our settings: saved, pending until /reload, no invalidation
------------------------------------------------------------

local invalid = 0
GG.API.RegisterCallback("EvaluationInvalidated", function() invalid = invalid + 1 end, "test_theme")
H.eq(GG.Prefs.Set("appearance.followGlassUI", false), true, "the switch is a setting")
WoW.flush()
H.eq(invalid, 0, "...that invalidates nothing")
H.eq(GlassGearDB.settings.appearance.followGlassUI, false, "...saved")
H.eq(GG.themeName, "glass", "...and this session keeps its look")
H.check(GG.Options.AppearanceText():find("/reload", 1, true) ~= nil, "the page says /reload")
H.eq(select(2, GG.Prefs.Set("appearance.followGlassUI", "yes")), "invalid value", "a junk value is refused")
GG.Prefs.Set("appearance.followGlassUI", true)
H.check(GG.Options.AppearanceText():find("/reload", 1, true) == nil, "switched back: nothing pending")
H.check(GG.Options.AppearanceText():find("Pearl glass", 1, true) ~= nil, "the page names the Pearl glass")

-- The switch on the page, shown because Glass UI is here (Glass UI #152's own-switch rule).
SlashCmdList.GLASSGEAR("options")
local function widget(text)
    for _, f in ipairs(WoW.frames) do
        if f.label and f.label.text == text then return f end
    end
end
local followRadio, foreverRadio = widget("Follow Glass UI"), widget("WoW Forever")
H.check(followRadio ~= nil and foreverRadio ~= nil, "the page offers Follow Glass UI / WoW Forever")
H.eq(followRadio:GetChecked(), true, "...Follow Glass UI selected by default")
foreverRadio:Click()
H.eq(GlassGearDB.settings.appearance.followGlassUI, false, "choosing WoW Forever saves the switch")
H.eq(foreverRadio:GetChecked(), true, "...and the page shows it")
followRadio:Click()
H.eq(GlassGearDB.settings.appearance.followGlassUI, true, "and back")
WoW.flush()
H.eq(invalid, 0, "the page's switch invalidates nothing either")

------------------------------------------------------------
-- 3. Every other answer: WoW Forever, and what's reported
------------------------------------------------------------

local function fresh(follow)
    T._test.reset()
    suite.reports, suite.asked = {}, 0
    glass.built = {}
    return T.Init(follow, function() end)
end
local function restore()
    suite.answer, suite.why, suite.throw = { name = "pearl", preset = "pearl" }, nil, false
    glass.minor, glass.throw = 12, nil
    rawset(_G, "GlassUI", { Suite = makeSuite() })
end

-- Declined in our settings: no question, WoW Forever, reported by its name.
local look, info = fresh(false)
H.eq(look, "forever", "declined: WoW Forever")
H.eq(info.code, "declined", "...by choice")
H.eq(suite.asked, 0, "...without asking the suite")
H.eq(lastReport().declined, "WoW Forever", "reported as declined, with our look's name")
H.eq(lastReport().built, nil, "...nothing built")
H.eq(lastReport().reason, nil, "...not a failure")
H.check(GG.Options.AppearanceText():find("your choice", 1, true) ~= nil, "the page says it's the player's choice")
local w2 = GG.Window.New({ name = "GlassGearThemeTestWindow2", key = "themetest2", width = 300, height = 200, title = "T" })
H.eq(w2.glass, nil, "declined: no glass on a window")
H.check(w2.backdrop ~= nil, "...the WoW Forever backdrop instead")
H.eq(w2.titleText.color, nil, "...and the title keeps its font's colour")
H.eq(T.Reading(pane), false, "...and no glass reading pane")

-- Glass UI's own switch off for us: its reason, a plain report.
suite.answer, suite.why = nil, "not-following"
look, info = fresh(true)
H.eq(look, "forever", "not following in Glass UI: WoW Forever")
H.eq(info.code, "not-following", "...with Glass UI's reason")
H.eq(#suite.reports, 1, "...still reported (never 'asked, but no report')")
H.eq(lastReport().built, nil, "...nothing built")
H.eq(lastReport().declined, nil, "...not declined by us")
H.check(GG.Options.AppearanceText():find("Glass UI's settings", 1, true) ~= nil, "the page points at Glass UI's switch")
local function diagHas(text)
    for _, line in ipairs(GG.Diagnostics.Lines()) do
        if line:find(text, 1, true) then return true end
    end
    return false
end
H.check(diagHas("theme: forever (not-following)"), "/gg diag gives the fallback's reason (PR #74 review)")

suite.why = "not-ready"
look, info = fresh(true)
H.eq(info.code, "not-ready", "a not-ready suite falls back too")

suite.answer, suite.throw = { name = "pearl", preset = "pearl" }, true
look, info = fresh(true)
H.eq(look, "forever", "Theme throwing: WoW Forever")
H.eq(info.code, "error", "...recorded as an error")
H.eq(#suite.reports, 1, "...and reported")
restore()

suite.answer = { name = "pearl" }   -- junk: no preset
look = fresh(true)
H.eq(look, "forever", "an answer without a preset is not following")
restore()

-- LibGlass too old, missing, or failing.
glass.minor = 10
look, info = fresh(true)
H.eq(look, "forever", "LibGlass older than r11: WoW Forever")
H.eq(info.code, "library-too-old", "...library-too-old")
H.eq(lastReport().reason, "library-too-old", "...reported as the reason")
H.eq(lastReport().minor, 10, "...with the minor at the attempt")
H.eq(lastReport().built, nil, "...nothing built")
H.eq(#glass.built, 0, "...and New never called")
H.check(GG.Options.AppearanceText():find("couldn't be built", 1, true) ~= nil, "the page says the glass couldn't be built")
H.check(diagHas("theme: forever (library-too-old)"), "/gg diag names a failed build's reason")
restore()

glass.presets.pearl = nil      -- an r11 claim without the preset
look, info = fresh(true)
H.eq(info.code, "library-too-old", "an unknown preset is library-too-old")
glass.presets.pearl = true

glass.throw = "kaboom"
look, info = fresh(true)
H.eq(info.code, "build-failed", "New throwing anything else: build-failed")
H.eq(lastReport().reason, "build-failed", "...reported")
restore()

glass.minor = nil
look, info = fresh(true)
H.eq(info.code, "build-failed", "no LibGlass at all: build-failed")
restore()

-- Glass UI absent, or not speaking API 1: nothing asked, nothing reported.
for label, g2 in pairs({ absent = false, ["no Suite"] = {}, ["Suite not a table"] = { Suite = 1 },
        ["API 2"] = { Suite = (function() local s = makeSuite(); s.API = 2; return s end)() },
        ["Report missing"] = { Suite = (function() local s = makeSuite(); s.Report = nil; return s end)() } }) do
    rawset(_G, "GlassUI", g2 or nil)
    look, info = fresh(true)
    H.eq(look, "forever", label .. ": WoW Forever")
    H.eq(info.code, "absent", label .. ": counts as absent")
    H.eq(suite.asked, 0, label .. ": nothing asked")
    H.eq(#suite.reports, 0, label .. ": nothing reported")
end
H.eq(T.Pending(false), false, "without Glass UI the switch is never pending")
H.check(GG.Options.AppearanceText():find("With Glass UI loaded", 1, true) ~= nil, "the page says Glass UI isn't loaded")
restore()

------------------------------------------------------------
-- 4. The look without Look/Body/Accent, and a class body
------------------------------------------------------------

local S = GlassUI.Suite
S.Look, S.Body, S.Accent = nil, nil, nil
look = fresh(true)
H.eq(look, "glass", "an API-1 suite without Look still gives Pearl")
H.eq(lastReport().own and lastReport().own.tint, true, "...the tint reported as our own")
H.eq(lastReport().own and lastReport().own.accent, true, "...and the accent")
local w3 = GG.Window.New({ name = "GlassGearThemeTestWindow3", key = "themetest3", width = 300, height = 200, title = "T" })
H.eq(w3.glass.tint[4], T._test.SHELL.tint[4], "...the shell in the recipe's tint")
H.eq(w3.glass.backing.color[4], T._test.SHELL.backing[4], "...and the recipe's backing")
H.eq(w3.titleText.color, nil, "...the title keeps its colour")
restore()

suite.look = { tint = "class", accent = "gold" }
rawset(_G, "C_ClassColor", nil)        -- unreadable early in a login
look = fresh(true)
local w4 = GG.Window.New({ name = "GlassGearThemeTestWindow4", key = "themetest4", width = 300, height = 200, title = "T" })
H.eq(w4.glass.tint[1], nil, "class tint unreadable: the built colour kept (SetSurfaceTint with nothing)")
rawset(_G, "C_ClassColor", { GetClassColor = function(c) return c == "PRIEST" and { r = 1, g = 1, b = 1 } or nil end })
T.Retry()
H.check(math.abs((w4.glass.tint[1] or 0) - 0.6) < 1e-9, "...painted at the retry: the class colour by its shade")
H.eq(w4.titleText.color[2], 0.82, "the gold accent on the title")
H.eq(lastReport().look.tint, "class", "the class tint reported")

H.done("test_theme")
