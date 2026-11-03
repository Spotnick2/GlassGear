------------------------------------------------------------
-- UI/Options.lua - the settings page in Esc > Options > AddOns (GG-112).
--
-- The porting guide's recipe ("An Options page with sub-pages", measured by
-- the Glass addons) and GlassUnitFrames/Options.lua's widgets (the owner's
-- MIT code): a canvas page registered at PLAYER_LOGIN, hidden at creation so
-- its first display builds it, every value re-read on every show; check and
-- radio buttons from UICheckButtonTemplate / UIRadioButtonTemplate with our
-- own art if one is missing; a hand-built slider; radio groups, never a
-- dropdown; a scroll frame for the height.
--
-- Sections follow the three independent scopes (adr/0006, mockups 04 and G2),
-- after Specs (which spec each spec group is, GG-104): Tooltips; Bag and loot arrows with the reveal key; Upgrade rules (minimum
-- upgrade, level window, spec armor); Disenchant protection (tracked specs);
-- Appearance (Glass UI's decision, and a live preview drawn by the same
-- Policy and TooltipView code as the real tooltip and arrows).
-- Every change goes through GG.Prefs; nothing here writes GlassGearDB.
------------------------------------------------------------

local GG = GlassGear
local Options = {}
GG.Options = Options

Options.NAME = "Glass Gear"
Options.PREVIEW_ICON = "Interface\\Icons\\INV_Shoulder_02"

local panel, scroll, content, category
local controls = {}          -- refresh functions, run on every show
local refreshing = false     -- set while syncing controls: a SetValue doesn't save
local preview

------------------------------------------------------------
-- Widgets
------------------------------------------------------------

-- CreateFrame with a template that may be missing: a missing template returns
-- a bare frame, so `proof` names a field the template makes.
local function safeFrame(kind, parent, template, proof)
    local ok, f = pcall(CreateFrame, kind, nil, parent, template)
    if ok and f then return f, proof == nil or f[proof] ~= nil end
    return CreateFrame(kind, nil, parent), false
end

local function label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function column(x, top, width)
    return { x = x, y = top, width = width, parent = content }
end

local function place(col, region, height, indent)
    region:SetPoint("TOPLEFT", col.parent, "TOPLEFT", col.x + (indent or 0), col.y)
    col.y = col.y - height
    return region
end

local function header(col, text)
    col.y = col.y - 8
    place(col, label(col.parent, text, "GameFontNormal"), 22)
end

local function note(col, text, indent, template)
    local fs = label(col.parent, text, template or "GameFontHighlightSmall")
    fs:SetWidth(col.width - (indent or 4))
    local h = fs:GetStringHeight()
    if type(h) ~= "number" or h ~= h or h <= 0 then h = 14 end
    place(col, fs, math.max(16, math.ceil(h) + 4), indent or 4)
    return fs
end

local CHECK_ART = {
    normal = "Interface\\Buttons\\UI-CheckBox-Up", pushed = "Interface\\Buttons\\UI-CheckBox-Down",
    highlight = "Interface\\Buttons\\UI-CheckBox-Highlight", checked = "Interface\\Buttons\\UI-CheckBox-Check",
}
local RADIO_ART = "Interface\\Buttons\\UI-RadioButton"   -- 4 cells: normal, checked, highlight, pushed

local function checkButton(parent, text, radio)
    local cb, templated = safeFrame("CheckButton", parent, radio and "UIRadioButtonTemplate" or "UICheckButtonTemplate", "text")
    if not templated then
        if radio then
            cb:SetSize(16, 16)
            cb:SetNormalTexture(RADIO_ART)
            cb:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
            cb:SetCheckedTexture(RADIO_ART)
            cb:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
            cb:SetHighlightTexture(RADIO_ART)
            cb:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
        else
            cb:SetNormalTexture(CHECK_ART.normal)
            cb:SetPushedTexture(CHECK_ART.pushed)
            cb:SetHighlightTexture(CHECK_ART.highlight)
            cb:SetCheckedTexture(CHECK_ART.checked)
        end
    end
    if not radio then cb:SetSize(24, 24) end
    cb.label = label(parent, text)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    return cb
end

-- Off and seen to be: our labels don't grey with SetEnabled (GlassUnitFrames).
local function dim(widget, off)
    widget:SetEnabled(not off)
    widget:SetAlpha(off and 0.5 or 1)
    if widget.label then
        local c = off and 0.5 or 1
        widget.label:SetTextColor(c, c, c)
    end
end

local function tip(widget, text)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function checkbox(col, text, get, set, indent)
    local cb = checkButton(col.parent, text, false)
    place(col, cb, 26, indent or 4)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        Options.Refresh()
    end)
    controls[#controls + 1] = function() cb:SetChecked(get() and true or false) end
    return cb
end

-- { {value, text, disabledReason}, ... }, one per line, or on one row.
local function radios(col, options, get, set, row)
    local group, x0 = {}, col.x + 8
    for i, o in ipairs(options) do
        local rb = checkButton(col.parent, o[2], true)
        rb.value = o[1]
        rb:SetScript("OnClick", function()
            set(o[1])                  -- Prefs refuses what isn't allowed (Shift)
            Options.Refresh()          -- a refused choice snaps back
        end)
        if o[3] then tip(rb, o[3]) end
        if row then
            rb:SetPoint("TOPLEFT", col.parent, "TOPLEFT", x0 + (i - 1) * 72, col.y)
        else
            place(col, rb, 22, 8)
        end
        group[#group + 1] = rb
    end
    if row then col.y = col.y - 24 end
    controls[#controls + 1] = function()
        local current = get()
        for i, rb in ipairs(group) do
            rb:SetChecked(rb.value == current)
            if options[i][3] then dim(rb, true) end
        end
    end
    return group
end

-- Hand-built slider: label + value on one line, the track under it.
-- t = { label, min, max, step, get(), set(v), fmt(v) }
local function slider(col, t)
    local parent = col.parent
    local fs = label(parent, t.label)
    local value = label(parent, "")
    value:SetPoint("LEFT", fs, "LEFT", 200, 0)
    place(col, fs, 18, 4)
    local s = CreateFrame("Slider", nil, parent)
    s.label, s.valueText = fs, value
    s:SetSize(220, 16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(t.min, t.max)
    s:SetValueStep(t.step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.25, 0.25, 0.3, 0.9)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    place(col, s, 26, 8)
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / t.step + 0.5) * t.step
        value:SetText(t.fmt(v))
        if refreshing then return end
        t.set(v)
        Options.RefreshPreview()
    end)
    controls[#controls + 1] = function()
        local v = t.get()
        s:SetValue(v)
        value:SetText(t.fmt(v))
    end
    return s
end

------------------------------------------------------------
-- Content
------------------------------------------------------------

local function specs()
    return GG.player and GG.Data.Classes.Specs(GG.player.class) or {}
end

-- Read on every refresh: /gg spec can change the current spec while the page is open.
local function specLabel(s, always)
    if s.key ~= GG.currentSpec then return s.name end
    return s.name .. (always and " (current, always shown)" or " (current)")
end

-- A scope's "selected" spec list, dimmed unless that scope is "selected".
-- The current spec is always included in both scopes (its tooltip row and its
-- green arrow come first, PRD section 3), so its box is checked and disabled.
local function specChecks(col, list, scopePath)
    local boxes = {}
    for _, s in ipairs(specs()) do
        local cb = checkbox(col, specLabel(s, true),
            function() return GG.Prefs.SpecSelected(list, s.key) end,
            function(on) GG.Prefs.SetSpec(list, s.key, on) end, 28)
        cb.spec = s
        boxes[#boxes + 1] = cb
    end
    controls[#controls + 1] = function()
        local off = GG.Prefs.Get(scopePath) ~= "selected"
        for _, cb in ipairs(boxes) do
            local current = cb.spec.key == GG.currentSpec
            cb.label:SetText(specLabel(cb.spec, true))
            if current then cb:SetChecked(true) end
            dim(cb, off or current)
        end
    end
    return boxes
end

-- Which spec each spec group is (GG-104): one line per spec, one radio
-- column per spec group, and "Not set". Through GG.Spec.Map, like /gg spec.
local function specMapping(col)
    local groups = {}
    local X = { col.x + 170, col.x + 240 }
    local heads = {}
    for g = 1, GG.Spec.MAX_GROUPS do
        heads[g] = label(col.parent, "Group " .. g, "GameFontHighlightSmall")
        heads[g]:SetPoint("TOPLEFT", col.parent, "TOPLEFT", X[g] - 8, col.y)
        groups[g] = {}
    end
    col.y = col.y - 16
    local rows = {}
    for _, s in ipairs(specs()) do rows[#rows + 1] = { key = s.key, name = s.name } end
    rows[#rows + 1] = { key = "none", name = "Not set" }
    for _, r in ipairs(rows) do
        local name = label(col.parent, r.name)
        place(col, name, 22, 8)
        for g = 1, GG.Spec.MAX_GROUPS do
            local rb = checkButton(col.parent, "", true)
            rb:SetPoint("TOPLEFT", col.parent, "TOPLEFT", X[g], col.y + 22)
            rb.value, rb.group = r.key, g
            rb:SetScript("OnClick", function()
                local ok, why = GG.Spec.Map(g, r.key ~= "none" and r.key or nil)
                if not ok then Options.lastRefusal = why end
                Options.Refresh()     -- a refused choice snaps back
            end)
            groups[g][#groups[g] + 1] = rb
        end
    end
    local status = note(col, "")
    controls[#controls + 1] = function()
        local map = GG.charDB and GG.charDB.specMap or {}
        local n = GG.Compat.NumSpecGroups()
        for g = 1, GG.Spec.MAX_GROUPS do
            local mapped = map[g] or "none"
            for _, rb in ipairs(groups[g]) do
                rb:SetChecked(rb.value == mapped)
                dim(rb, GG.readOnly)
            end
            local tag = (GG.specGroup == g and " (active)") or ((n and g > n) and " (not learned)") or ""
            heads[g]:SetText("Group " .. g .. tag)
        end
        status:SetText(GG.currentSpec and ("Current spec: " .. (GG.Data.Classes.Spec(GG.currentSpec) or {}).name)
            or "Current spec: not set. Choose the spec of your active group.")
    end
    Options.specRadios, Options.specHeads = groups, heads
    return groups
end

local function set(path) return function(v) GG.Prefs.Set(path, v) end end
local function get(path) return function() return GG.Prefs.Get(path) end end

-- A sample answer for the player's specs: the current spec slightly down,
-- the next one up, a third without weights. Drawn by the real view code.
function Options.PreviewResponse()
    local results = {}
    local list = specs()
    local current = GG.currentSpec or (list[1] and list[1].key)
    local samples = {
        { status = "no_upgrade", pct = -0.024 },
        { status = "upgrade", pct = 0.031 },
        { status = "unknown", reasons = { "NO_WEIGHTS" } },
    }
    local order = {}
    for _, s in ipairs(list) do if s.key == current then order[#order + 1] = s end end
    for _, s in ipairs(list) do if s.key ~= current then order[#order + 1] = s end end
    for i, s in ipairs(order) do
        local sample = samples[i] or samples[#samples]
        results[#results + 1] = { status = sample.status, spec = s.key, current = s.key == current,
            score = sample.pct and { pct = sample.pct, delta = sample.pct * 100 } or nil,
            reasons = sample.reasons or {}, limitations = {},
            eligibility = { equipNow = true, reasons = {} } }
    end
    return { status = "upgrade", results = results }
end

-- Preview lines and the arrow the sample transferable item would get now.
function Options.PreviewModel()
    local response = Options.PreviewResponse()
    local lines = GG.TooltipView.Build(response, GG.Tooltip.ViewSettings(), { currentSpec = GG.currentSpec }) or {}
    local keys = {}
    for _, s in ipairs(specs()) do keys[#keys + 1] = s.key end
    local kind = GG.Engine.Policy.Marker(GG.MarkerView.View(response, false, "bags"),
        GG.MarkerView.Settings(GG.db.settings.markers, keys), false)
    return lines, kind
end

local function buildPreview(col)
    local box = CreateFrame("Frame", nil, col.parent)
    box:SetSize(col.width, 170)
    place(col, box, 176, 4)
    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
    icon:SetTexture(Options.PREVIEW_ICON)
    local holder = CreateFrame("Frame", nil, box)
    holder:SetSize(36, 36)
    holder:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
    local caption = label(box, "Transferable item (not bound)", "GameFontNormalSmall")
    caption:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    local mark = GG.Marks.New(holder)
    local rows = {}
    preview = { box = box, mark = mark, rows = rows }
    function preview.Draw()
        local lines, kind = Options.PreviewModel()
        GG.Marks.Set(mark, kind)
        preview.kind = kind
        for i, l in ipairs(lines) do
            local r = rows[i]
            if not r then
                r = { left = label(box, "", "GameFontHighlightSmall"), right = label(box, "", "GameFontHighlightSmall") }
                r.left:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -48 - (i - 1) * 15)
                r.right:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, -48 - (i - 1) * 15)
                r.right:SetJustifyH("RIGHT")
                rows[i] = r
            end
            r.left:SetText(l.left)
            r.left:SetTextColor(l.lc[1], l.lc[2], l.lc[3])
            r.right:SetText(l.right or "")
            if l.rc then r.right:SetTextColor(l.rc[1], l.rc[2], l.rc[3]) end
            r.left:Show()
            r.right:Show()
        end
        for i = #lines + 1, #rows do
            rows[i].left:Hide()
            rows[i].right:Hide()
        end
        preview.lines = lines
    end
    controls[#controls + 1] = preview.Draw
end

function Options.AppearanceText()
    if GG.themeName == "glass" then
        return "Look: Glass, following Glass UI. Change it in Glass UI's settings; /reload to apply."
    end
    local why = GG.themeInfo and GG.themeInfo.reason
    return "Look: WoW Forever" .. (why and (" (" .. why .. ")") or "")
        .. ". Glass Gear follows Glass UI once Glass UI lists it (GUI-001)."
end

local function build()
    local W = 300
    local left, right = column(12, -8, W), column(W + 36, -8, W)

    local title = label(content, "Glass Gear", "GameFontNormalLarge")
    place(left, title, 24, 4)
    right.y = left.y
    local who = label(content, "", "GameFontHighlightSmall")
    who:SetPoint("LEFT", title, "RIGHT", 10, 0)
    controls[#controls + 1] = function()
        who:SetText(GG.player and (GG.player.name .. " \194\183 " .. tostring(GG.player.class)) or "")
    end

    -- Weights live in their own window (GG-105).
    local profiles, ptemplated = safeFrame("Button", content, "UIPanelButtonTemplate", "Text")
    profiles:SetSize(150, 22)
    if not ptemplated then
        local bg = profiles:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(profiles)
        bg:SetColorTexture(0.2, 0.2, 0.25, 0.9)
    end
    profiles:SetText("Weight profiles...")
    profiles:SetPoint("TOPLEFT", content, "TOPLEFT", W * 2 - 116, -8)
    profiles:SetScript("OnClick", function() GG.ProfilesWindow.Open() end)
    Options.profilesButton = profiles

    -- Specs
    header(left, "SPECS")
    note(left, "Which spec each spec group is. Automatic detection comes after the in-game probe (GG-101).")
    specMapping(left)

    -- Tooltips
    header(left, "TOOLTIPS")
    radios(left, { { "all", "All my specs" }, { "current", "Current spec only" }, { "selected", "Selected specs:" } },
        get("tooltip.specs"), set("tooltip.specs"))
    specChecks(left, "tooltip", "tooltip.specs")
    local alts = checkbox(left, "Show eligible alt upgrades", get("tooltip.alts"), set("tooltip.alts"))
    tip(alts, "Alt rows need AltStable and arrive with GG-203. The setting is kept until then.")
    checkbox(left, "Set-bonus warnings", get("setBonusWarnings"), set("setBonusWarnings"))

    -- Bag and loot arrows
    header(left, "BAG AND LOOT ARROWS")
    radios(left, { { "current", "Current spec" }, { "selected", "Current + selected specs:" }, { "own", "All my specs" } },
        get("markers.scope"), set("markers.scope"))
    specChecks(left, "markers", "markers.scope")
    checkbox(left, "Mark transferable off-spec upgrades (amber)", get("markers.markTransferable"),
        set("markers.markTransferable"))
    header(left, "REVEAL KEY")
    radios(left, { { "CTRL", "Ctrl" }, { "ALT", "Alt" }, { "NONE", "None" }, { "SHIFT", "Shift", GG.Prefs.SHIFT_REASON } },
        get("reveal.modifier"), set("reveal.modifier"), true)
    note(left, "Hold it to show other specs' upgrades as amber arrows. Releasing it restores the normal arrows. "
        .. "Shift is used by item comparison.")

    -- Upgrade rules
    header(right, "UPGRADE RULES")
    slider(right, { label = "Minimum upgrade", min = 0, max = GG.Prefs.THRESHOLD_MAX * 100, step = 0.1,
        get = function() return GG.Prefs.MinimumUpgrade() * 100 end,
        set = function(v) GG.Prefs.SetMinimumUpgrade(v / 100) end,
        fmt = function(v) return string.format("%.1f %%", v) end })
    note(right, "For arrows and protection; tooltip rows always show the change.")
    checkbox(right, "Only level-appropriate upgrades", get("levelWindow.enabled"), set("levelWindow.enabled"))
    local ahead = slider(right, { label = "Look ahead", min = 0, max = GG.Prefs.LOOK_AHEAD_MAX, step = 1,
        get = get("levelWindow.lookAhead"), set = set("levelWindow.lookAhead"),
        fmt = function(v) return string.format("%d level%s", v, v == 1 and "" or "s") end })
    controls[#controls + 1] = function()
        local off = not GG.Prefs.Get("levelWindow.enabled")
        ahead:SetEnabled(not off)
        ahead:SetAlpha(off and 0.5 or 1)
    end
    checkbox(right, "Spec armor rules", get("specArmor"), set("specArmor"))
    note(right, "Each spec gets its armor types: a Holy Paladin can use cloth, Protection can't.")

    -- Protection
    header(right, "DISENCHANT PROTECTION")
    note(right, "Specs Shatter keeps upgrades for (Shatter's integration: GG-301, SH-001).")
    local charsBtn, ctemplated = safeFrame("Button", content, "UIPanelButtonTemplate", "Text")
    charsBtn:SetSize(150, 22)
    if not ctemplated then
        local bg = charsBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(charsBtn)
        bg:SetColorTexture(0.2, 0.2, 0.25, 0.9)
    end
    charsBtn:SetText("All characters...")
    place(right, charsBtn, 26, 8)
    charsBtn:SetScript("OnClick", function() GG.CharactersWindow.Open() end)
    Options.charactersButton = charsBtn
    for _, s in ipairs(specs()) do
        local keys = {}
        for _, x in ipairs(specs()) do keys[#keys + 1] = x.key end
        local function text() return (GG.player and GG.player.name or "") .. " \194\183 " .. specLabel(s) end
        local cb = checkbox(right, text(),
            function() return GG.player and GG.Prefs.IsTracked(GG.player.key, s.key) end,
            function(on) if GG.player then GG.Prefs.SetTracked(GG.player.key, s.key, on, keys) end end, 8)
        controls[#controls + 1] = function() cb.label:SetText(text()) end
    end
    note(right, "Specs without weights:", 4, "GameFontHighlight")
    radios(right, { { "ignore", "Ignore" }, { "keep", "Keep" } }, get("protection.noWeights"),
        set("protection.noWeights"), true)
    note(right, "Hiding a marker does not disable disenchant protection.", 4, "GameFontNormalSmall")

    -- Appearance
    header(right, "APPEARANCE")
    local look = note(right, Options.AppearanceText())
    controls[#controls + 1] = function() look:SetText(Options.AppearanceText()) end
    buildPreview(right)

    -- Defaults
    local bottom = math.min(left.y, right.y) - 8
    local reset, templated = safeFrame("Button", content, "UIPanelButtonTemplate", "Text")
    reset:SetSize(110, 22)
    if not templated then
        local bg = reset:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(reset)
        bg:SetColorTexture(0.2, 0.2, 0.25, 0.9)
    end
    reset:SetText("Defaults")
    reset:SetPoint("TOPLEFT", content, "TOPLEFT", 16, bottom)
    reset:SetScript("OnClick", function()
        GG.Prefs.Reset()
        Options.Refresh()
    end)
    Options.defaultsButton = reset
    content:SetHeight(-bottom + 40)
end

function Options.RefreshAll()
    refreshing = true
    for i, fn in ipairs(controls) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()("GlassGear options " .. i .. ": " .. tostring(err)) end
    end
    refreshing = false
end

-- After a change: an open page follows (a refused choice snaps back too).
function Options.Refresh()
    if panel and panel.built and panel:IsShown() then Options.RefreshAll() end
end

function Options.RefreshPreview()
    if preview then pcall(preview.Draw) end
end

------------------------------------------------------------
-- Registration (PLAYER_LOGIN, once)
------------------------------------------------------------

local function makePanel()
    panel = CreateFrame("Frame")
    panel.name = Options.NAME
    -- Created shown, Settings' first display fires no OnShow and the page is
    -- blank until a later visit (porting guide). Hidden, the first display builds it.
    panel:Hide()
    scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(660, 760)
    scroll:SetScrollChild(content)
    if not scroll.ScrollBar then
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
        end)
    end
    panel:SetScript("OnShow", function(self)
        if not self.built then
            self.built = true
            -- Opened through a pcall (Settings.OpenToCategory): report, never swallow.
            local ok, err = pcall(build)
            if not ok then geterrorhandler()("GlassGear options page: " .. tostring(err)) end
        end
        Options.RefreshAll()
    end)
end

-- Returns true | false, reason.
function Options.Register()
    if category then return true end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return false, "no Settings API"
    end
    makePanel()
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    -- Settings changed elsewhere (a slash command, Defaults, an import): follow.
    GG.Callbacks.Register("EvaluationInvalidated", function() Options.Refresh() end, "GlassGear.Options")
    return true
end

-- Open the page; false when the Settings framework can't.
function Options.Open()
    if not (category and Settings and Settings.OpenToCategory) then return false end
    local ok = pcall(Settings.OpenToCategory, category:GetID())
    return ok
end

-- Test seams.
function Options._Panel() return panel end
function Options._Category() return category end
Options._controls = controls

return Options
