------------------------------------------------------------
-- Presentation/Theme.lua - which look renders the view-models (adr/0004, GG-115).
--
-- Two looks: "forever" (the default, native, no library) and "glass", the
-- material Glass UI's suite answers (Pearl today) from the embedded LibGlass,
-- in the suite's body (tint, backing, wash) and accent (window titles).
--
-- Following Glass UI (GlassUI docs/SUITE.md and SUITE-LOOK.md; the models
-- are Stakeout's and GlassPearls' Theme.lua). With Glass UI loaded, Glass
-- Gear follows it by default, as every member does. "Follow Glass UI" in our
-- settings (appearance.followGlassUI) turns it off: WoW Forever is then
-- reported as declined, never as a failure. Without Glass UI, WoW Forever.
--
-- Asked once, at ADDON_LOADED (`## OptionalDeps: GlassUI` has Glass UI ready
-- by then), before any window exists. Not live: a suite change waits for a
-- /reload, and the report says so (live = false).
--
-- The surfaces are the window recipe (C:\Projects\WoW\References\Docs\
-- LIBGLASS-WINDOW-STYLING.md): a reflective shell with a backing, and plain
-- masked reading panes. Every helper returns true when it dressed the frame
-- in glass; on false the caller paints its WoW Forever backdrop as before.
-- Bag and loot arrows keep their look: they are marks, not surfaces.
------------------------------------------------------------

local GG = GlassGear
local Theme = {}
GG.Theme = Theme

Theme.MIN_LIBGLASS = 11
-- Our own look's name in the report: data for Glass UI, so English.
Theme.DECLINED = "WoW Forever"

local active, info  -- the session's look and why, fixed by Init
local Glass         -- this session's LibGlass instance, under the glass look
local following     -- what the session built from Glass UI's suite, or nil
local shells = {}   -- every window shell, for a class tint painted late
local classPending  -- a class tint wanted before the class colour could be read
local retryFrame

-- The recipe's values, by surface role. The shell's tint over its backing
-- covers about 90%; the reading panes sit on top of it.
local SHELL = {
    tint = { 0.085, 0.095, 0.115, 0.78 }, backing = { 0.03, 0.03, 0.035, 0.55 },
    rim = 0.12, dark = 0.55, shadow = 0.18,
}
local READING = { 0.072, 0.082, 0.10, 0.94 }

local function Suite() return GG.Integrations.GlassUI end

-- A LibGlass instance in `preset`, and the library's minor; or nil, the
-- minor (when known) and the suite's reason code.
function Theme.NewGlass(preset)
    local stub = rawget(_G, "LibStub")
    if type(stub) ~= "table" and type(stub) ~= "function" then return nil, nil, "build-failed" end
    local ok, lib, minor = pcall(stub, "LibGlass-1.0", true)
    if not ok or type(lib) ~= "table" then return nil, nil, "build-failed" end
    if type(minor) ~= "number" or minor < Theme.MIN_LIBGLASS then return nil, minor, "library-too-old" end
    local okN, inst = pcall(lib.New, lib, { preset = preset })
    if not okN or type(inst) ~= "table" then
        local why = tostring(inst)
        return nil, minor, why:find("unknown preset", 1, true) and "library-too-old" or "build-failed"
    end
    return inst, minor
end

local function IsColor(c, n)
    if type(c) ~= "table" then return false end
    for i = 1, n do
        if type(c[i]) ~= "number" or c[i] < 0 or c[i] > 1 then return false end
    end
    return true
end

local function Copy(c) return { unpack(c) } end

-- The suite's body for a tint (Suite.Body, the one owner of its numbers),
-- checked and copied, or nil. A class body has no colour, only its shade.
local function SuiteBody(tint)
    local b = Suite().Optional("Body", tint)
    if type(b) ~= "table" or type(b.wash) ~= "number" or b.wash < 0 or not IsColor(b.backing, 4) then
        return nil
    end
    if IsColor(b.tint, 4) then
        return { tint = Copy(b.tint), backing = Copy(b.backing), wash = b.wash }
    elseif b.tint == nil and type(b.classShade) == "number" then
        return { classShade = b.classShade, backing = Copy(b.backing), wash = b.wash }
    end
end

local function ClassColor() return GG.Compat.ClassColor() end

-- What the session follows: the material's preset, the suite's look pulled
-- once (Look, then Body and Accent), and the keys it couldn't answer (own).
local function Follow(preset, minor, inst)
    local f = { preset = preset, minor = minor, own = {}, wash = inst.STYLE and inst.STYLE.wash or 0 }
    local look = Suite().Optional("Look")
    look = type(look) == "table" and look or {}
    if type(look.tint) == "string" then f.body = SuiteBody(look.tint) end
    if f.body then f.tint = look.tint else f.own.tint = true end
    local rgb = type(look.accent) == "string" and Suite().Optional("Accent", look.accent)
    if IsColor(rgb, 3) then
        f.accent, f.accentRGB = look.accent, { rgb[1], rgb[2], rgb[3] }
    else
        f.own.accent = true
    end
    return f
end

-- Is Glass UI here, speaking the suite's API? (The settings' switch shows only then.)
function Theme.SuiteAvailable()
    return Suite().SuiteAPI() ~= nil
end

-- Fix the session's look and tell Glass UI what was built. `follow` is our
-- "Follow Glass UI" (false: WoW Forever by choice); `options` opens our
-- settings (Glass UI's link to them). Returns the look and an info table:
-- { code, minor, preset }. code: "following", "absent" (no Glass UI),
-- "declined", "library-too-old", "build-failed", or Glass UI's own reason
-- ("not-following", "not-ready", "unknown", "error").
function Theme.Init(follow, options)
    if active then return active, info end
    if not Theme.SuiteAvailable() then
        active, info = "forever", { code = "absent" }
        return active, info
    end
    local report = { api = 1, live = false, options = options }
    if follow == false then
        active, info = "forever", { code = "declined" }
        report.declined = Theme.DECLINED
    else
        local answer = Suite().Ask()
        if not answer.following then
            active, info = "forever", { code = answer.code }
        else
            local preset = answer.theme.preset
            local inst, minor, code = Theme.NewGlass(preset)
            report.minor = minor
            if not inst then
                active, info = "forever", { code = code, minor = minor }
                report.reason = code
            else
                Glass, active = inst, "glass"
                following = Follow(preset, minor, inst)
                info = { code = "following", preset = preset, minor = minor }
                report.built = preset
                report.look = { tint = following.tint, accent = following.accent }
                report.own = next(following.own) and following.own or nil
            end
        end
    end
    Suite().Report(report)
    return active, info
end

function Theme.Active() return active or "forever" end
function Theme.Info() return info end
-- Is this session's glass Glass UI's?
function Theme.Following() return following ~= nil end

-- Does the saved switch differ from what this session built? (/reload to apply.)
function Theme.Pending(follow)
    if not (info and Theme.SuiteAvailable()) then return false end
    return (follow == false) ~= (info.code == "declined")
end

local function Paint(g, role)
    Glass.SetSurfaceTint(g, unpack(role.tint))
    Glass.SetWash(g, role.wash or 0)
    Glass.SetSurfaceAlpha(g, "rim", role.rim)
    Glass.SetSurfaceAlpha(g, "dark", role.dark)
    Glass.SetSurfaceAlpha(g, "shadow", role.shadow)
    Glass.SetSurfaceAlpha(g, "grain", 0)
end

-- A shell's body: the suite's, else the recipe's. A class tint keeps the
-- built alpha (SetSurfaceTint's nil), and the built colour until the class
-- colour can be read (Theme.Retry).
local function PaintShell(g)
    local body = following and following.body
    g.backing:SetColorTexture(unpack(body and body.backing or SHELL.backing))
    Paint(g, SHELL)
    if not body then return end
    if body.classShade then
        local r, gg, b = ClassColor()
        local s = body.classShade
        if r then
            Glass.SetSurfaceTint(g, r * s, gg * s, b * s)
        else
            Glass.SetSurfaceTint(g)
            classPending = true
        end
    else
        Glass.SetSurfaceTint(g, unpack(body.tint))
    end
    Glass.SetWash(g, following.wash * body.wash)
end

-- PLAYER_ENTERING_WORLD: the class colour can be read by now. Colours on our
-- own textures only, so it is safe in combat too.
function Theme.Retry()
    if not classPending or not ClassColor() then return end
    classPending = false
    for _, g in ipairs(shells) do PaintShell(g) end
end

local function WaitForClass()
    if retryFrame or not classPending then return end
    retryFrame = CreateFrame("Frame")
    retryFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    retryFrame:SetScript("OnEvent", Theme.Retry)
end

-- A window title in the suite's accent, while following; its font's own
-- colour otherwise.
function Theme.Accent(fs)
    local c = following and following.accentRGB
    if c then fs:SetTextColor(c[1], c[2], c[3]) end
end

-- A window's outer shell. opts.header: the height (px) of its title area,
-- which the shell's reflection lights and fades out over.
function Theme.Window(frame, opts)
    if active ~= "glass" then return false end
    opts = opts or {}
    local g = Glass.Apply(frame, "large")
    -- BACKGROUND -7: over the library's shadow (-8), under its tint (-6).
    -- Made before the first paint, which colours it.
    local backing = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    backing:SetAllPoints(frame)
    backing:AddMaskTexture(g.mask)
    g.backing = backing
    PaintShell(g)
    shells[#shells + 1] = g
    WaitForClass()
    -- No edge: the reflection's top highlight takes its place.
    Glass.SetEdge(g, 0, 0, 0)
    local header = opts.header
    Glass.Reflect(g, frame, (header and header > 0) and { header = header } or nil)
    frame.glass = g
    return true
end

-- A reading region under a list or text: one plain masked texture on `host`.
-- BACKGROUND 0: over a shell on the same frame (the library's layers stop at
-- -3), under the text.
function Theme.Reading(host)
    if active ~= "glass" then return false end
    local pane = host:CreateTexture(nil, "BACKGROUND", nil, 0)
    pane:SetAllPoints(host)
    pane:SetColorTexture(unpack(READING))
    local S = Glass.SIZES.thin_small
    pane:AddMaskTexture(Glass.Mask(host, S.mask, S.maskMargin, 0, pane))
    host.glassReading = pane
    return true
end

-- Test seam (tests/). Harmless in game.
Theme._test = {
    reset = function()
        active, info, Glass, following, classPending, retryFrame = nil, nil, nil, nil, nil, nil
        shells = {}
    end,
    following = function() return following end,
    Glass = function() return Glass end,
    SHELL = SHELL, READING = READING,
}

return Theme
