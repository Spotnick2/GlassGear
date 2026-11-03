------------------------------------------------------------
-- test_settings.lua - GG-112: the settings model (Core/Prefs.lua) and the
-- options page (UI/Options.lua). PRD section 5 defaults, validation, every
-- policy change firing EvaluationInvalidated, settings -> policy inputs
-- (threshold, marker scope, tooltip scope, set-bonus warnings, level window,
-- tracked specs), and the page: built on first show, re-read on every show,
-- radios / checkboxes / sliders writing through Prefs, Shift refused,
-- Defaults, the live preview, the protection note.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local INT, SP, HEAL = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT"
local function shoulder(name, stats, minLevel)
    return { name = name, equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = stats, minLevel = minLevel }
end
WoW.items[50] = shoulder("Old Mantle", { [INT] = 100 })
WoW.items[51] = shoulder("Slightly Better Mantle", { [INT] = 101 })   -- +1 % for both specs
WoW.items[70] = shoulder("Healer Mantle", { [INT] = 60, [HEAL] = 60 }) -- Holy up, Shadow down
WoW.items[75] = shoulder("Future Mantle", { [INT] = 200 }, 62)         -- two levels away
WoW.equipped[3] = 50
WoW.bags[0] = {
    [1] = { itemID = 51, isBound = true },
    [2] = { itemID = 70, isBound = true },
}

local GG = WoW.loadAddon()
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1, SpellDamage=1 )')
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy": Class=Priest, Intellect=1, Healing=1 )')
WoW.flush()

local P = GG.Prefs
local invalidations = {}
GG.API.RegisterCallback("EvaluationInvalidated", function(_, payload)
    invalidations[#invalidations + 1] = payload and payload.reason
end, "test_settings")
local function invalidatedSince(n) WoW.flush(); return #invalidations - n end
-- The count before a change, once earlier changes' callbacks have run.
local function mark0() WoW.flush(); return #invalidations end

------------------------------------------------------------
-- PRD section 5 defaults
------------------------------------------------------------
H.eq(P.Get("tooltip.specs"), "all", "tooltip: all my specs")
H.eq(P.Get("tooltip.alts"), true, "tooltip alts on")
H.eq(P.Get("markers.scope"), "current", "marker scope: current spec")
H.eq(P.Get("markers.markTransferable"), true, "mark transferable upgrades on")
H.eq(P.Get("reveal.modifier"), "CTRL", "reveal: Ctrl")
H.eq(P.MinimumUpgrade(), 0.005, "minimum upgrade 0.5 %")
H.eq(GG.db.settings.protection.threshold, 0.005, "...the same for protection")
H.eq(P.Get("levelWindow.enabled"), true, "level-appropriate upgrades only: on")
H.eq(P.Get("levelWindow.lookAhead"), 0, "look-ahead 0")
H.eq(P.Get("specArmor"), true, "spec armor rules on")
H.eq(P.Get("setBonusWarnings"), true, "set-bonus warnings on")
H.eq(P.Get("protection.noWeights"), "ignore", "specs without weights: ignore")
H.eq(P.IsTracked(GG.player.key, "PRIEST.HOLY"), true, "own specs tracked by default")
H.eq(P.IsTracked("Player-9-ALT", "MAGE.FROST"), false, "an alt is not tracked until chosen")

------------------------------------------------------------
-- Validation
------------------------------------------------------------
local ok, why = P.Set("reveal.modifier", "SHIFT")
H.eq(ok, false, "Shift refused")
H.eq(why, P.SHIFT_REASON, "...with its reason")
H.eq(select(2, P.Set("markers.scope", "bogus")), "invalid value", "unknown scope refused")
H.eq(select(2, P.Set("levelWindow.lookAhead", 11)), "invalid value", "look-ahead above 10 refused")
H.eq(select(2, P.Set("levelWindow.lookAhead", 1.5)), "invalid value", "fractional look-ahead refused")
H.eq(select(2, P.Set("tooltip.alts", "yes")), "invalid value", "a non-boolean switch refused")
H.eq(select(2, P.Set("nope.never", true)), "unknown setting", "unknown setting refused")
H.eq(select(2, P.SetMinimumUpgrade(0.06)), "invalid value", "minimum upgrade above 5 % refused")
H.eq(select(2, P.SetSpec("tooltip", "MAGE.FROST.X", true)), "unknown spec", "unknown spec refused")
H.eq(P.Get("markers.scope"), "current", "a refused value leaves the setting alone")

------------------------------------------------------------
-- Every policy change fires EvaluationInvalidated; the reveal key doesn't
------------------------------------------------------------
local n = mark0()
P.Set("markers.scope", "current")
H.eq(invalidatedSince(n), 0, "an unchanged value fires nothing")
P.Set("tooltip.specs", "current")
H.eq(invalidatedSince(n), 1, "tooltip scope change -> EvaluationInvalidated")
H.eq(invalidations[#invalidations], "settings", "...reason settings")
P.Set("tooltip.specs", "all")
n = mark0()
P.Set("reveal.modifier", "ALT")
H.eq(invalidatedSince(n), 0, "the reveal key is not a policy input")
WoW.keys.ALT = true
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 1)
H.eq(GG.Reveal.Active(), true, "Alt now reveals")
WoW.keys.ALT = nil
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 0)
P.Set("reveal.modifier", "CTRL")

-- Minimum upgrade: one setting for markers and protection; the arrows follow.
local bag = ContainerFrameContainer.ContainerFrames[1]
local function mark(i)
    local m = GG.BagMarkers._marks[bag.Items[i]]
    return m and m:IsShown() and m.kind or nil
end
WoW.showBag(bag, { { 0, 1 }, { 0, 2 } })
H.eq(mark(1), "green", "+1 % Shadow upgrade: green at 0.5 %")
n = mark0()
H.eq(P.SetMinimumUpgrade(0.02), true, "minimum upgrade 2 %")
H.eq(invalidatedSince(n), 1, "...fires EvaluationInvalidated")
H.eq(GG.db.settings.protection.threshold, 0.02, "...protection follows")
WoW.flush()
H.eq(mark(1), nil, "+1 % is below 2 %: the arrow goes")
local r = GG.API.Evaluate({ item = WoW.link(51), scope = "own" })
H.eq(r.results[1].status, "no_upgrade", "...and the API answers no_upgrade")
P.SetMinimumUpgrade(0.005)
WoW.flush()
H.eq(mark(1), "green", "back at 0.5 %: green again")

-- Marker scope "selected": the chosen own specs are amber without the reveal.
H.eq(mark(2), nil, "soulbound Holy upgrade: quiet by default")
P.Set("markers.scope", "selected")
WoW.flush()
H.eq(mark(2), nil, "selected scope, nothing chosen: still quiet")
P.SetSpec("markers", "PRIEST.HOLY", true)
WoW.flush()
H.eq(mark(2), "amber", "Holy selected: amber")
P.SetSpec("markers", "PRIEST.HOLY", false)
WoW.flush()
H.eq(mark(2), nil, "Holy unselected: quiet")
P.Set("markers.scope", "current")

-- Tooltip scope.
local tip = WoW.newTooltip("GameTooltip")
local function holyRows()
    WoW.showItem(tip, { type = 0, id = 70, hyperlink = WoW.link(70) })
    local count = 0
    for _, l in ipairs(tip.lines) do if l.left and l.left:find("^Holy") then count = count + 1 end end
    return count
end
WoW.flush()
H.eq(holyRows(), 1, "all my specs: a Holy row")
P.Set("tooltip.specs", "current")
WoW.flush()
H.eq(holyRows(), 0, "current spec only: no Holy row")
P.Set("tooltip.specs", "selected")
P.SetSpec("tooltip", "PRIEST.HOLY", true)
WoW.flush()
H.eq(holyRows(), 1, "selected Holy: the Holy row is back")
P.Set("tooltip.specs", "all")

-- Set-bonus warnings.
local setResponse = { results = { { status = "upgrade", spec = "PRIEST.SHADOW", current = true,
    score = { pct = 0.05, delta = 1 }, reasons = {}, eligibility = { equipNow = true, reasons = {} },
    limitations = { "SET_BONUS_GAINED:42:2", "SET_BONUS_NOT_SCORED" } } } }
local function hasLine(lines, text)
    for _, l in ipairs(lines or {}) do if l.left == text then return true end end
    return false
end
H.check(hasLine(GG.TooltipView.Build(setResponse, GG.Tooltip.ViewSettings(), { currentSpec = "PRIEST.SHADOW" }),
    "Completes a 2-piece set bonus (not scored)"), "set-bonus warning shown by default")
P.Set("setBonusWarnings", false)
local quiet = GG.TooltipView.Build(setResponse, GG.Tooltip.ViewSettings(), { currentSpec = "PRIEST.SHADOW" })
H.check(not hasLine(quiet, "Completes a 2-piece set bonus (not scored)"), "set-bonus warnings off: no warning")
H.check(hasLine(quiet, "Set item: bonus not scored"), "...the item still says its bonus isn't scored")
P.Set("setBonusWarnings", true)

-- Level window: look-ahead reaches the item two levels away.
r = GG.API.Evaluate({ item = WoW.link(75), scope = "own" })
WoW.flush()
r = GG.API.Evaluate({ item = WoW.link(75), scope = "own" })
H.eq(r.results[1].status, "ineligible", "two levels away, look-ahead 0: not an upgrade")
P.Set("levelWindow.lookAhead", 2)
WoW.flush()
r = GG.API.Evaluate({ item = WoW.link(75), scope = "own" })
H.eq(r.results[1].eligibility.equipNow, false, "look-ahead 2: inside the window, for later")
H.eq(r.results[1].status, "upgrade", "...scored as an upgrade at level 62")
P.Set("levelWindow.lookAhead", 0)

-- Tracked specs: the first edit writes down the default, then changes one.
n = mark0()
local keys = { "PRIEST.DISCIPLINE", "PRIEST.HOLY", "PRIEST.SHADOW" }
P.SetTracked(GG.player.key, "PRIEST.DISCIPLINE", false, keys)
H.eq(P.IsTracked(GG.player.key, "PRIEST.DISCIPLINE"), false, "Discipline untracked")
H.eq(P.IsTracked(GG.player.key, "PRIEST.HOLY"), true, "...Holy still tracked")
H.eq(invalidatedSince(n), 1, "tracking change fires EvaluationInvalidated")

------------------------------------------------------------
-- The options page
------------------------------------------------------------
H.eq(#WoW.settingsCategories, 1, "one Settings category")
H.eq(WoW.settingsCategories[1].name, "Glass Gear", "...named Glass Gear")
local panel = GG.Options._Panel()
H.eq(panel.shown, false, "the page is hidden at creation (porting guide: else blank on first visit)")
H.eq(panel.built, nil, "...and not built before it is shown")
WoW.missingTemplates.UIRadioButtonTemplate = true    -- the radio art fallback must work too
SlashCmdList.GLASSGEAR("options")
H.eq(WoW.openedCategory, "Glass Gear", "/gg options opens the category")
H.eq(panel.built, true, "first show builds the page")
WoW.missingTemplates.UIRadioButtonTemplate = nil

local function widgets(text)
    local out = {}
    for _, f in ipairs(WoW.frames) do
        if f.label and f.label.text == text then out[#out + 1] = f end
    end
    return out
end
local function widget(text, i) return widgets(text)[i or 1] end
local function fontText(text)
    for _, f in ipairs(WoW.frames) do
        for _, fs in ipairs(f._fs or {}) do if fs.text == text then return fs end end
    end
end

-- Values are read on show.
H.eq(widget("Ctrl"):GetChecked(), true, "reveal radio shows Ctrl")
H.eq(widget("Current spec"):GetChecked(), true, "arrow scope radio shows Current spec")
H.eq(widget("Karuzo \194\183 Discipline"):GetChecked(), false, "untracked Discipline shown unchecked")
H.eq(widget("Karuzo \194\183 Shadow (current)"):GetChecked(), true, "tracked Shadow (current) checked")

-- Radios write through Prefs; Shift is shown, disabled, and refused.
widget("Alt"):Click()
H.eq(P.Get("reveal.modifier"), "ALT", "clicking Alt sets the reveal key")
H.eq(widget("Alt"):GetChecked(), true, "...Alt checked")
H.eq(widget("Ctrl"):GetChecked(), false, "...Ctrl unchecked")
local shift = widget("Shift")
H.eq(shift:IsEnabled(), false, "Shift is disabled")
shift.enabled = true                                -- even if a click got through
shift:Click()
H.eq(P.Get("reveal.modifier"), "ALT", "Shift never becomes the reveal key")
H.eq(shift:GetChecked(), false, "...and the radio snaps back")
widget("Ctrl"):Click()

-- Selected specs: dimmed until the scope is "selected".
local markerHoly = widget("Holy", 2)                 -- 1: tooltip list, 2: arrow list
H.eq(markerHoly:IsEnabled(), false, "arrow spec list dimmed while the scope is Current spec")
widget("Current + selected specs:"):Click()
H.eq(P.Get("markers.scope"), "selected", "scope selected")
H.eq(markerHoly:IsEnabled(), true, "...spec list enabled")
markerHoly:Click()
H.eq(P.SpecSelected("markers", "PRIEST.HOLY"), true, "Holy chosen for the arrows")
H.eq(P.SpecSelected("tooltip", "PRIEST.HOLY"), true, "the tooltip list is separate (set earlier)")

-- The current spec is always included (Codex, PR #44): its box is checked and
-- disabled in both lists, whatever the scope, so it never looks like a choice.
local curMarker = widget("Shadow (current, always shown)", 2)
H.eq(curMarker:GetChecked(), true, "current spec shown checked in the arrow list")
H.eq(curMarker:IsEnabled(), false, "...and disabled, even with the scope on selected")
curMarker.enabled = true
curMarker:Click()
GG.Options.Refresh()
H.eq(P.SpecSelected("markers", "PRIEST.SHADOW"), false, "...a forced click is undone by the refresh")
H.eq(curMarker:GetChecked(), true, "...and it reads checked again")
local tooltipRows = GG.Engine.Policy.TooltipRows({ current = { spec = "PRIEST.SHADOW", status = "upgrade" }, own = {} },
    { specs = "selected", selected = {} }, false)
H.eq(#tooltipRows, 1, "tooltip 'Selected specs' still shows the current spec, as the box says")
widget("Current spec"):Click()

-- "(current)" follows /gg spec while the page is open, in all three lists.
SlashCmdList.GLASSGEAR("spec 1 PRIEST.HOLY")
WoW.flush()
H.eq(#widgets("Holy (current, always shown)"), 2, "both selected lists relabel Holy as current")
H.eq(#widgets("Shadow (current, always shown)"), 0, "...and Shadow no longer")
H.check(widget("Karuzo \194\183 Holy (current)") ~= nil, "protection list relabels Holy")
H.check(widget("Karuzo \194\183 Shadow") ~= nil, "...and Shadow plain")
widget("Current + selected specs:"):Click()
H.eq(widget("Shadow", 2):IsEnabled(), true, "the former current spec is a choice again")
widget("Current spec"):Click()
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
WoW.flush()
H.eq(#widgets("Shadow (current, always shown)"), 2, "...and back")

-- Sliders.
local function sliderWith(labelText)
    for _, f in ipairs(WoW.frames) do
        if f.kind == "Slider" and f.label and f.label.text == labelText then return f end
    end
end
local minUp = sliderWith("Minimum upgrade")
minUp:SetValue(2.0)
H.eq(P.MinimumUpgrade(), 0.02, "minimum upgrade slider -> 2 %")
H.eq(minUp.valueText.text, "2.0 %", "...shown as 2.0 %")
minUp:SetValue(0.5)
local ahead = sliderWith("Look ahead")
widget("Only level-appropriate upgrades"):Click()
H.eq(P.Get("levelWindow.enabled"), false, "level window off")
H.eq(ahead:IsEnabled(), false, "...look-ahead slider dimmed")
widget("Only level-appropriate upgrades"):Click()
H.eq(ahead:IsEnabled(), true, "...and back")
ahead:SetValue(3)
H.eq(P.Get("levelWindow.lookAhead"), 3, "look-ahead slider -> 3 levels")
H.eq(ahead.valueText.text, "3 levels", "...shown as 3 levels")

-- A change made elsewhere shows on an open page (after the callback) and on reopen.
P.Set("markers.markTransferable", false)
WoW.flush()
H.eq(widget("Mark transferable off-spec upgrades (amber)"):GetChecked(), false, "open page follows a change made elsewhere")
panel:Hide()
P.Set("markers.markTransferable", true)
panel:Show()
H.eq(widget("Mark transferable off-spec upgrades (amber)"):GetChecked(), true, "reopened page re-reads the value")

-- The protection note and the appearance status.
H.check(fontText("Hiding a marker does not disable disenchant protection.") ~= nil,
    "'Hiding a marker does not disable disenchant protection' is on the page")
H.check(GG.Options.AppearanceText():find("WoW Forever", 1, true) ~= nil, "appearance: WoW Forever without Glass UI")

-- Preview: drawn by the real view code, following the settings.
local lines, kind = GG.Options.PreviewModel()
H.eq(kind, "amber", "preview: a transferable item that's a Holy upgrade is amber")
H.check(lines[2] and lines[2].left:find("CURRENT", 1, true) ~= nil, "preview: the current spec row first")
P.Set("markers.markTransferable", false)
lines, kind = GG.Options.PreviewModel()
H.eq(kind, nil, "preview: transferable marking off -> no arrow")
P.Set("tooltip.specs", "current")
lines = GG.Options.PreviewModel()
local specRows = 0
for _, l in ipairs(lines) do if l.right then specRows = specRows + 1 end end
H.eq(specRows, 1, "preview: current spec only -> one row")
WoW.flush()
H.eq(GG.Options._controls and #GG.Options._controls > 0, true, "page controls registered")

-- Defaults.
n = mark0()
local defaults = GG.Options.defaultsButton
defaults:Click()
H.eq(P.Get("tooltip.specs"), "all", "Defaults: tooltip scope back to all")
H.eq(P.Get("markers.markTransferable"), true, "Defaults: transferable marking back on")
H.eq(P.Get("levelWindow.lookAhead"), 0, "Defaults: look-ahead back to 0")
H.eq(P.IsTracked(GG.player.key, "PRIEST.DISCIPLINE"), true, "Defaults: all own specs tracked again")
H.eq(P.SpecSelected("markers", "PRIEST.HOLY"), false, "Defaults: selected specs cleared")
H.eq(invalidatedSince(n), 1, "Defaults fires EvaluationInvalidated")
H.eq(widget("Karuzo \194\183 Discipline"):GetChecked(), true, "the page shows the defaults")
H.eq(GlassGearDB.settings, GG.db.settings, "Defaults wrote the saved table")

H.eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))

-- No undeclared globals from the page.
for name in pairs(WoW.globalWrites) do H.check(false, "undeclared global written: " .. name) end

H.done("test_settings")
