------------------------------------------------------------
-- UI/ProfilesWindow.lua - the profiles window (GG-105, mockups 05 and G3):
-- per spec, up to four weight profiles; the active one; Pawn and WoWSims
-- Pawn EP import with live validation; weight, name and armor editing;
-- Pawn export.
--
-- Glass Gear's own window (the owner's choice, 2026-11-02), built on first
-- open with UI/Window.lua (the WoW Forever look, Escape, combat, position).
--
-- Every change goes through GG.Profiles with the version the window showed;
-- a stale one is refused, reported, and the window re-reads. Texts come from
-- Presentation/ProfileView.lua.
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
local Win = {}
GG.ProfilesWindow = Win

Win.NAME = "GlassGearProfilesFrame"
Win.W, Win.H = 660, 590
Win.ROW_H = 20
Win.DELETE_CONFIRM = 4      -- seconds the second click has to confirm a delete

local V = function() return GG.ProfileView end
local frame
local W = {}                -- widgets (test seam: Win._W)
local state = { spec = nil, id = nil, version = nil, showAll = false, deleteArmed = nil }

local UIW = GG.Window          -- the shared window and widgets (UI/Window.lua)
local COLORS = UIW.COLORS
local label, backdrop, fill, button = UIW.Label, UIW.Backdrop, UIW.Fill, UIW.Button
local checkButton, dim, editBox, color = UIW.CheckButton, UIW.Dim, UIW.EditBox, UIW.Color

local function at(region, x, y, parent)
    region:SetPoint("TOPLEFT", parent or frame, "TOPLEFT", x, y)
    return region
end

------------------------------------------------------------
-- Actions
------------------------------------------------------------

local function message(text, level)
    if not W.message then return end
    W.message:SetText(text or "")
    color(W.message, level or "error")
end

local function charKey() return GG.player and GG.player.key end

-- Run a store change; report a refusal; tell the rest of Glass Gear.
local function act(fn)
    if GG.readOnly then message(V().ErrorText("read-only")) return false end
    local entry, err = fn()
    if entry then
        message("")
        GG.Profiles.Changed(charKey())
    elseif err ~= "UNCHANGED" then
        message(V().ErrorText(err))
    end
    Win.Refresh()
    return entry ~= nil
end

local function selected()
    local e = state.id and GG.store:Get(state.id)
    if e and not e.deleted and not e.conflict then return e end
end

function Win.SelectSpec(specKey)
    state.spec, state.id, state.deleteArmed = specKey, nil, nil
    message("")
    Win.Refresh()
end

function Win.SelectProfile(id)
    state.id, state.deleteArmed = id, nil
    message("")
    Win.Refresh()
end

function Win.MakeActive()
    act(function() return GG.Profiles.SetActive(GG.store, state.id, state.version, time()) end)
end

-- A typed field commits against the version it began editing (`version`):
-- a change that arrived meanwhile makes it stale, never silently overwritten.
function Win.CommitName(text, version)
    act(function() return GG.Profiles.Rename(GG.store, state.id, version or state.version, text, time()) end)
end

function Win.CommitWeight(token, text, version)
    act(function() return GG.Profiles.SetWeight(GG.store, state.id, version or state.version, token, text, time()) end)
end

-- A text field remembers what it showed, and for which version, when the
-- player started typing. A refresh while it has focus leaves the draft alone.
local function draftField(box, commit)
    box:SetScript("OnEditFocusGained", function(self)
        self.baseVersion, self.baseText, self.baseId = state.version, self.shown, state.id
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)    -- what InputBoxTemplate's own handler does
        local base, baseText, text = self.baseVersion, self.baseText, self:GetText()
        local same = self.baseId == state.id
        self.baseVersion, self.baseText, self.baseId = nil, nil, nil
        if same and base and text ~= (baseText or "") then
            commit(self, text, base)
        else
            Win.Refresh()           -- nothing typed: show what is stored now
        end
    end)
end

function Win.SetArmorDefault(on)
    local e = selected()
    if not e then return end
    local armor = nil
    if not on then
        local spec = GG.Data.Classes.Spec(state.spec)
        armor = {}
        for _, a in ipairs(spec and spec.armor or {}) do armor[#armor + 1] = a end
    end
    act(function() return GG.Profiles.SetArmor(GG.store, state.id, state.version, armor, time()) end)
end

function Win.ToggleArmor(subclass, on)
    local e = selected()
    if not e then return end
    local list, have = {}, false
    for _, a in ipairs(e.data.armor or {}) do
        if a == subclass then have = true end
        if a ~= subclass or on then list[#list + 1] = a end
    end
    if on and not have then list[#list + 1] = subclass end
    act(function() return GG.Profiles.SetArmor(GG.store, state.id, state.version, list, time()) end)
end

-- Delete takes two clicks within DELETE_CONFIRM seconds (no popup).
function Win.Delete()
    local now = GetTime()
    if not (state.deleteArmed and state.deleteArmed.id == state.id and now - state.deleteArmed.at <= Win.DELETE_CONFIRM) then
        state.deleteArmed = { id = state.id, at = now }
        message(L["Click Delete again to delete this profile"], "warn")
        Win.Refresh()
        return
    end
    state.deleteArmed = nil
    if act(function() return GG.Profiles.Delete(GG.store, state.id, state.version) end) then
        state.id = nil
        Win.Refresh()
    end
end

function Win.Export()
    local e = selected()
    if not e then return end
    local text = GG.PawnString.Export(GG.Profiles.Shape(e), V().ClassLabel(GG.player.class))
    W.input:SetText(text)
    W.input:SetFocus()
    W.input:HighlightText()
    message(L["Exported: press Ctrl+C to copy"], "ok")
end

function Win.ImportNew()
    local text = W.input:GetText()
    local entry
    act(function()
        local e, err = GG.Profiles.ImportNew(GG.store, charKey(), state.spec, text, time(), GG.player.class)
        entry = e
        return e, err
    end)
    if entry then
        state.id = entry.id
        W.input:SetText("")
        message(L["Imported \"%s\": now the active profile"]:format(entry.data.name), "ok")
        Win.Refresh()
    end
end

function Win.ImportReplace()
    local text = W.input:GetText()
    if act(function() return GG.Profiles.ImportReplace(GG.store, state.id, state.version, text, time(), GG.player.class) end) then
        W.input:SetText("")
        message(L["Weights replaced"], "ok")
        Win.Refresh()
    end
end

------------------------------------------------------------
-- Building (first open)
------------------------------------------------------------

local function buildWeightRow(i)
    local row = CreateFrame("Frame", nil, W.weightsChild)
    row:SetSize(440, Win.ROW_H)
    at(row, 0, -(i - 1) * Win.ROW_H, W.weightsChild)
    row.name = label(row, "")
    row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.box = editBox(row, 80)
    row.box:SetPoint("LEFT", row, "LEFT", 240, 0)
    row.box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()      -- focus lost commits
    end)
    draftField(row.box, function(_, text, version)
        if row.token then Win.CommitWeight(row.token, text, version) end
    end)
    row.box:SetScript("OnEscapePressed", function(self)
        self:SetText(row.shown or "")
        self:ClearFocus()
    end)
    W.rows[i] = row
    return row
end

local function build()
    frame = UIW.New({ name = Win.NAME, key = "profiles", width = Win.W, height = Win.H,
        title = L["Glass Gear \194\183 Profiles"], onShow = function() Win.Refresh() end })
    W.who = at(label(frame, "", "GameFontHighlightLarge"), 14, -32)

    -- Specs (left)
    W.specs = {}
    for i, s in ipairs(GG.Data.Classes.Specs(GG.player.class)) do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(150, 36)
        at(b, 12, -60 - (i - 1) * 40)
        b.name = label(b, s.name, "GameFontNormal")
        b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -4)
        b.sub = label(b, "", "GameFontHighlightSmall")
        b.sub:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -20)
        b.sub:SetWidth(138)
        b.specKey = s.key
        b:SetScript("OnClick", function() Win.SelectSpec(s.key) end)
        W.specs[#W.specs + 1] = b
    end

    -- Profile panel (right)
    local X = 172
    W.tabs = {}
    for i = 1, GG.Profiles.MAX_PER_SPEC do
        local t = CreateFrame("Button", nil, frame)
        t:SetSize(112, 22)
        at(t, X + (i - 1) * 118, -60)
        t.text = label(t, "", "GameFontHighlightSmall")
        t.text:SetPoint("LEFT", t, "LEFT", 6, 0)
        t.text:SetWidth(104)
        t:SetScript("OnClick", function() Win.SelectProfile(t.id) end)
        W.tabs[i] = t
    end
    W.empty = at(label(frame, "", "GameFontHighlight"), X, -96)
    W.empty:SetWidth(470)
    W.name = at(editBox(frame, 200), X + 6, -92)
    W.name:SetMaxLetters(GG.Profiles.MAX_NAME)
    W.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    draftField(W.name, function(_, text, version)
        if state.id then Win.CommitName(text, version) end
    end)
    W.active = at(label(frame, L["Active"], "GameFontNormal"), X + 216, -96)
    color(W.active, "ok")
    W.makeActive = at(button(frame, L["Make active"], 110, function() Win.MakeActive() end), X + 216, -91)
    W.source = at(label(frame, "", "GameFontHighlightSmall"), X, -118)
    W.source:SetWidth(470)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetSize(450, 160)
    at(scroll, X, -136)
    if not scroll.ScrollBar then
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
        end)
    end
    W.weightsScroll = scroll
    W.weightsChild = CreateFrame("Frame", nil, scroll)
    W.weightsChild:SetSize(440, 160)
    scroll:SetScrollChild(W.weightsChild)
    W.rows = {}

    W.showAll = at(checkButton(frame, L["Show all stats"], function(self)
        state.showAll = self:GetChecked() and true or false
        Win.Refresh()
    end), X, -300)
    W.notes = at(label(frame, "", "GameFontHighlightSmall"), X, -326)
    W.notes:SetWidth(470)

    W.armorLabel = at(label(frame, L["Armor types:"], "GameFontHighlightSmall"), X, -354)
    W.armorDefault = at(checkButton(frame, L["Spec default"], function(self)
        Win.SetArmorDefault(self:GetChecked() and true or false)
    end), X + 76, -348)
    W.armor = {}
    local ids = { GG.Data.Classes.ARMOR.CLOTH, GG.Data.Classes.ARMOR.LEATHER, GG.Data.Classes.ARMOR.MAIL,
        GG.Data.Classes.ARMOR.PLATE, GG.Data.Classes.ARMOR.SHIELD }
    for i, a in ipairs(ids) do
        local cb = checkButton(frame, GG.Data.Classes.ARMOR_NAME[a], function(self)
            Win.ToggleArmor(a, self:GetChecked() and true or false)
        end)
        at(cb, X + 76 + i * 72, -348)
        cb.subclass = a
        W.armor[#W.armor + 1] = cb
    end
    W.export = at(button(frame, L["Export Pawn"], 110, function() Win.Export() end), X, -380)
    W.delete = at(button(frame, L["Delete"], 90, function() Win.Delete() end), X + 118, -380)

    -- Import (bottom)
    at(label(frame, L["Import weights"], "GameFontNormal"), 14, -414)
    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetSize(632, 64)
    at(box, 12, -432)
    backdrop(box, COLORS.pane)
    local inScroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    inScroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
    inScroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -28, 6)
    W.input = editBox(inScroll, 590, true)
    inScroll:SetScrollChild(W.input)
    W.input:SetHeight(48)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() W.input:SetFocus() end)   -- the whole box takes a click
    W.input:SetScript("OnTextChanged", function() Win.RefreshPreview() end)
    W.preview = at(label(frame, "", "GameFontHighlightSmall"), 14, -502)
    W.preview:SetWidth(632)
    at(label(frame, L["Character exports (SimulationCraft profiles, WoWSims JSON) are not weights: they need a simulation first."],
        "GameFontDisableSmall"), 14, -536):SetWidth(632)
    W.importNew = at(button(frame, L["Add as new profile"], 150, function() Win.ImportNew() end), 12, -554)
    W.importReplace = at(button(frame, L["Replace weights"], 210, function() Win.ImportReplace() end), 170, -554)
    W.clear = at(button(frame, L["Clear"], 70, function() W.input:SetText("") end), 388, -554)
    W.message = at(label(frame, "", "GameFontHighlightSmall"), 466, -558)
    W.message:SetWidth(180)

    GG.Callbacks.Register("ProfilesChanged", function() if frame:IsShown() then Win.Refresh() end end,
        "GlassGear.ProfilesWindow")
end

------------------------------------------------------------
-- Refresh: everything re-read from the store
------------------------------------------------------------

local function statTokens(e)
    if state.showAll then return GG.Data.Stats.ORDER end
    local list = {}
    for _, t in ipairs(GG.Data.Stats.ORDER) do
        if e.data.weights[t] or (e.data.ignored and e.data.ignored[t]) then list[#list + 1] = t end
    end
    return list
end

local function refreshWeights(e, off)
    local tokens = e and statTokens(e) or {}
    local p = e and GG.Profiles.Shape(e)
    for i, t in ipairs(tokens) do
        local row = W.rows[i] or buildWeightRow(i)
        row.token = t
        row.name:SetText(V().StatLabel(t))
        row.shown = V().WeightText(p, t)
        row.box.shown = row.shown
        if not row.box:HasFocus() then row.box:SetText(row.shown) end
        dim(row.box, off)
        row:Show()
    end
    for i = #tokens + 1, #W.rows do
        W.rows[i].token = nil
        W.rows[i]:Hide()
    end
    W.weightsChild:SetHeight(math.max(160, #tokens * Win.ROW_H))
end

function Win.RefreshPreview()
    if not W.preview then return end
    local pv = V().Preview(W.input:GetText(), GG.player and GG.player.class)
    local texts, level = {}, "info"
    for i, l in ipairs(pv.lines) do
        texts[#texts + 1] = l.text
        if i == 1 then level = l.level end
    end
    W.preview:SetText(table.concat(texts, "\n"))
    color(W.preview, level == "ok" and (#pv.lines > 1 and "warn" or "ok") or level)
    local count = state.spec and #GG.Profiles.ForSpec(GG.store, charKey(), state.spec) or 0
    local ro = GG.readOnly
    dim(W.importNew, ro or not pv.ok or count >= GG.Profiles.MAX_PER_SPEC)
    dim(W.importReplace, ro or not pv.ok or selected() == nil)
    W.preview.ok = pv.ok
end

function Win.Refresh()
    if not (frame and GG.player and GG.store) then return end
    local key = charKey()
    local who = GG.player.name .. " \194\183 " .. V().ClassDisplay(GG.player.class)
    if GG.readOnly then who = L["%s   (read-only this session)"]:format(who) end
    W.who:SetText(who)
    local specs = GG.Data.Classes.Specs(GG.player.class)
    if not state.spec then state.spec = GG.currentSpec ~= "UNKNOWN" and GG.currentSpec or (specs[1] and specs[1].key) end
    for _, b in ipairs(W.specs) do
        local active = GG.Profiles.ActiveEntry(GG.store, key, b.specKey)
        -- No import: the default it scores with, if any (GG-120).
        local sub = active and active.data.name
            or (GG.Profiles.Effective(GG.store, key, b.specKey) and L["default weights"]) or L["no weights"]
        if b.specKey == GG.currentSpec then sub = L["%s  \194\183 current"]:format(sub) end
        b.sub:SetText(sub)
        color(b.sub, active and "info" or "warn")
        fill(b, b.specKey == state.spec and COLORS.selected or COLORS.plain)
    end

    local list = GG.Profiles.ForSpec(GG.store, key, state.spec)
    local active = GG.Profiles.ActiveEntry(GG.store, key, state.spec)
    if not selected() or selected().data.specKey ~= state.spec then state.id = active and active.id or nil end
    for i, t in ipairs(W.tabs) do
        local e = list[i]
        t.id = e and e.id
        t:SetShown(e ~= nil)
        if e then
            t.text:SetText(e.data.name .. (active and e.id == active.id and " *" or ""))
            fill(t, e.id == state.id and COLORS.selected or COLORS.plain)
        end
    end

    local e = selected()
    state.version = e and e.version
    local off = GG.readOnly
    local has = e ~= nil
    local specName = (GG.Data.Classes.Spec(state.spec) or {}).name or tostring(state.spec)
    W.empty:SetShown(not has)
    W.empty:SetText(L["%s: no profile yet. Paste weights below and choose Add as new profile."]:format(specName))
    for _, w in ipairs({ W.name, W.source, W.weightsScroll, W.showAll, W.showAll.label, W.notes, W.armorLabel,
        W.armorDefault, W.armorDefault.label, W.export, W.delete }) do w:SetShown(has) end
    for _, cb in ipairs(W.armor) do cb:SetShown(has); cb.label:SetShown(has) end
    W.active:SetShown(has and active ~= nil and e.id == active.id)
    W.makeActive:SetShown(has and not (active and e.id == active.id))
    dim(W.makeActive, off)
    refreshWeights(e, off)
    W.importReplace:SetText(has and L["Replace weights of %s"]:format(e.data.name) or L["Replace weights"])
    if has then
        local p = GG.Profiles.Shape(e)
        W.name.shown = e.data.name
        if not W.name:HasFocus() then W.name:SetText(e.data.name) end
        dim(W.name, off)
        W.source:SetText(V().SourceLabel(e.data.source)
            .. (e.data.origin and e.data.origin ~= e.data.name and (" (" .. e.data.origin .. ")") or "")
            .. "  \194\183  " .. V().Freshness(e.data.updatedAt, time()))
        W.showAll:SetChecked(state.showAll)
        local notes = {}
        local kept = {}
        for k in pairs(p.ignoredTokens) do kept[#kept + 1] = k end
        table.sort(kept)
        if #kept > 0 then notes[#notes + 1] = L["Kept for export, not scored: %s"]:format(table.concat(kept, ", ")) end
        if #p.missing > 0 then
            local names = {}
            for _, t in ipairs(p.missing) do names[#names + 1] = V().StatLabel(t) end
            notes[#notes + 1] = L["Missing (not zero): %s"]:format(table.concat(names, ", "))
        end
        if not GG.Prefs.Get("specArmor") then notes[#notes + 1] = L["Spec armor rules are off in the settings."] end
        W.notes:SetText(table.concat(notes, "\n"))
        local default = e.data.armor == nil
        W.armorDefault:SetChecked(default)
        W.armorDefault.label:SetText(default
            and L["Spec default (%s)"]:format(V().ArmorText(p, state.spec, true))
            or L["Spec default"])
        dim(W.armorDefault, off)
        local allowed = {}
        for _, a in ipairs(e.data.armor or {}) do allowed[a] = true end
        for _, cb in ipairs(W.armor) do
            cb:SetShown(has and not default)
            cb.label:SetShown(has and not default)
            cb:SetChecked(allowed[cb.subclass] == true)
            dim(cb, off)
        end
        dim(W.delete, off)
        W.delete:SetText(state.deleteArmed and state.deleteArmed.id == e.id and L["Confirm delete"] or L["Delete"])
    end
    Win.RefreshPreview()
end

------------------------------------------------------------
-- Open / close
------------------------------------------------------------

-- Returns true | false, reason.
function Win.Open(specKey)
    if not (GG.player and GG.store) then return false, L["not ready"] end
    if not frame then
        local ok, err = pcall(build)
        if not ok then
            frame = nil
            geterrorhandler()("GlassGear profiles window: " .. tostring(err))
            return false, L["build failed"]
        end
    end
    if specKey then state.spec, state.id = specKey, nil end
    if frame:IsShown() then Win.Refresh() else frame:Show() end
    return true
end

function Win.Toggle()
    if frame and frame:IsShown() then frame:Hide() return true end
    return Win.Open()
end

-- Test seams.
function Win._Frame() return frame end
Win._W = W
Win._state = state
function Win._Reset() frame = nil; for k in pairs(W) do W[k] = nil end
    state.spec, state.id, state.version, state.showAll, state.deleteArmed = nil, nil, nil, false, nil end

return Win
