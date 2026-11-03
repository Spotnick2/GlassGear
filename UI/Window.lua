------------------------------------------------------------
-- UI/Window.lua - Glass Gear's own windows (the profiles window GG-105, the
-- comparison window GG-113): the WoW Forever look (the tooltip backdrop,
-- as Shatter's "forever" skin; the Glass look is GG-115) and the shared
-- widgets.
--
--   Window.New{ name, key, width, height, title, onShow } -> frame
--     draggable by its title bar (position saved in GlassGearDB.ui.windows[key]),
--     a close button, Escape closes it. Not protected, but its Escape entry
--     leaves UISpecialFrames during combat, as Shatter's does: an addon entry
--     taints that pass and would block hiding a protected frame after it.
--   Window.Label / Button / CheckButton / EditBox / Fill / Backdrop / Color / Dim
------------------------------------------------------------

local GG = GlassGear
local Window = {}
GG.Window = Window

Window.BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
}
Window.COLORS = {
    window = { 0.09, 0.09, 0.19, 0.94 }, pane = { 0, 0, 0, 0.30 },
    ok = { 0.25, 1, 0.25 }, warn = { 1, 0.82, 0 }, error = { 1, 0.35, 0.35 }, info = { 0.75, 0.75, 0.75 },
    muted = { 0.55, 0.55, 0.55 }, white = { 1, 1, 1 },
    selected = { 0.30, 0.25, 0.08, 0.9 }, plain = { 0.12, 0.12, 0.15, 0.9 },
}
local COLORS = Window.COLORS

-- CreateFrame with a template that may be missing: a missing template returns
-- a bare frame, so `proof` names a field the template makes.
function Window.SafeFrame(kind, parent, template, proof)
    local ok, f = pcall(CreateFrame, kind, nil, parent, template)
    if ok and f then return f, proof == nil or f[proof] ~= nil end
    return CreateFrame(kind, nil, parent), false
end
local safeFrame = Window.SafeFrame

function Window.Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

function Window.Backdrop(f, color)
    if f.SetBackdrop then
        f:SetBackdrop(Window.BACKDROP)
        f:SetBackdropColor(unpack(color))
    else
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(f)
        bg:SetColorTexture(unpack(color))
    end
end

function Window.Fill(f, color)
    if not f.fillTex then
        f.fillTex = f:CreateTexture(nil, "BACKGROUND")
        f.fillTex:SetAllPoints(f)
    end
    f.fillTex:SetColorTexture(unpack(color))
end

function Window.Button(parent, text, width, onClick)
    local b, templated = safeFrame("Button", parent, "UIPanelButtonTemplate", "Text")
    b:SetSize(width, 22)
    if not templated then Window.Fill(b, COLORS.plain) end
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function Window.CheckButton(parent, text, onClick)
    local cb, templated = safeFrame("CheckButton", parent, "UICheckButtonTemplate", "text")
    if not templated then
        cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end
    cb:SetSize(22, 22)
    cb.label = Window.Label(parent, text)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb:SetScript("OnClick", onClick)
    return cb
end

function Window.Dim(widget, off)
    widget:SetEnabled(not off)
    widget:SetAlpha(off and 0.5 or 1)
end

function Window.EditBox(parent, width, multi)
    local eb, templated = safeFrame("EditBox", parent, not multi and "InputBoxTemplate" or nil, not multi and "Left" or nil)
    eb:SetAutoFocus(false)
    local font = rawget(_G, multi and "ChatFontNormal" or "GameFontHighlight")
    if font then eb:SetFontObject(font) end
    eb:SetWidth(width)
    if multi then
        eb:SetMultiLine(true)
        eb:SetMaxLetters(4000)        -- a 40-stat Pawn string is ~1 000 characters
    else
        eb:SetHeight(20)
        eb:SetMaxLetters(32)
        if not templated then
            local bg = eb:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(eb)
            bg:SetColorTexture(0, 0, 0, 0.5)
            eb:SetTextInsets(4, 4, 0, 0)
        end
    end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

-- A level name ("ok", "warn", ...) or an {r, g, b}.
function Window.Color(fs, level)
    local c = type(level) == "table" and level or COLORS[level] or COLORS.info
    fs:SetTextColor(c[1], c[2], c[3])
end

local function setEscapeCloses(name, on)
    local list = rawget(_G, "UISpecialFrames")
    if type(list) ~= "table" then return end
    for i = #list, 1, -1 do if list[i] == name then table.remove(list, i) end end
    if on then table.insert(list, name) end
end

function Window.New(opts)
    local frame = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
    frame:SetSize(opts.width, opts.height)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    Window.Backdrop(frame, COLORS.window)

    local function savePosition()
        local point, _, relPoint, x, y = frame:GetPoint()
        if point and GG.db and not GG.readOnly then
            GG.db.ui.windows[opts.key] = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end
    frame:ClearAllPoints()
    local p = GG.db and GG.db.ui and GG.db.ui.windows[opts.key]
    if type(p) == "table" and type(p.point) == "string" and type(p.x) == "number" and type(p.y) == "number" then
        frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x, p.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", opts.offsetX or 0, opts.offsetY or 40)
    end

    -- Opened first during a fight: no REGEN_DISABLED comes for it, so the
    -- Escape entry waits for REGEN_ENABLED.
    setEscapeCloses(opts.name, not GG.Compat.InCombat())
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            setEscapeCloses(opts.name, false)
            frame:StopMovingOrSizing()
        else
            setEscapeCloses(opts.name, true)
        end
    end)
    if opts.onShow then frame:SetScript("OnShow", opts.onShow) end

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    bar:SetHeight(28)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)
    frame.titleText = Window.Label(frame, opts.title, "GameFontNormal")
    frame.titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -10)
    local close, templated = safeFrame("Button", frame, "UIPanelCloseButton")
    if not templated then close:SetSize(22, 22); close:SetText("x") end
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.closeButton = close
    return frame
end

return Window
