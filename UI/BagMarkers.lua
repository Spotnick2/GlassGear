------------------------------------------------------------
-- UI/BagMarkers.lua - upgrade markers on Blizzard's bag buttons (GG-109).
--
--   green: a current-spec upgrade (always wins) - Blizzard's own filled
--          upgrade arrow (atlas "bags-greenarrow", EquipmentFlyout.xml:10);
--   amber: another own spec's upgrade on a transferable item (default on), or
--          on any item while the reveal modifier is held (GG-110) - the same
--          arrow drawn as an amber outline, so the two differ by shape too.
-- What shows is Policy.Marker's decision (adr/0006), over the shared answers
-- of UI/Results.lua and the instance's bind state read on every pass.
--
-- Hooks: hooksecurefunc on each bag frame's UpdateItems (Mainline
-- ContainerFrame.lua:1191, over EnumerateValidItems :575), made once - the
-- pattern of GlassPearls Core/BagMarks.lua. Each mark is our own child frame,
-- kept in a weak table keyed by Blizzard's button: nothing is written on
-- Blizzard's buttons. Buttons are pooled, so bag and slot are read every
-- pass. None is created in combat: a button first met then is decorated after
-- PLAYER_REGEN_ENABLED. Showing and hiding our own frames is combat-safe.
------------------------------------------------------------

local GG = GlassGear
local Markers = {}
GG.BagMarkers = Markers

Markers.ATLAS = "bags-greenarrow"
Markers.SIZE = 14
Markers.STYLE = {
    green = { color = { 1, 1, 1, 1 }, fallback = { 0.25, 1, 0.25, 0.95 } },
    amber = { color = { 1, 0.72, 0.15, 1 }, desaturate = true, inner = { 0.08, 0.05, 0, 0.9 },
        fallback = { 1, 0.72, 0.15, 0.95 } },
}

local marks = setmetatable({}, { __mode = "k" })     -- [button] = mark
local pending = setmetatable({}, { __mode = "k" })   -- buttons met in combat
local bagFrames = {}
local hooked, scheduled = false, false
local events
local atlasOK

local function where(button)
    local okB, bag = pcall(button.GetBagID, button)
    local okS, slot = pcall(button.GetID, button)
    if not (okB and okS) or type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    return bag, slot
end

local function newMark(button)
    local m = CreateFrame("Frame", nil, button)
    m:SetSize(Markers.SIZE, Markers.SIZE)
    m:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    m:EnableMouse(false)
    m.fill = m:CreateTexture(nil, "OVERLAY")
    m.fill:SetAllPoints(m)
    -- The inner cut-out that turns the amber arrow into an outline.
    m.inner = m:CreateTexture(nil, "OVERLAY", nil, 1)
    m.inner:SetPoint("TOPLEFT", m, "TOPLEFT", 3, -3)
    m.inner:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -3, 3)
    if atlasOK == nil then atlasOK = GG.Compat.AtlasKnown(Markers.ATLAS) end
    if atlasOK then
        m.fill:SetAtlas(Markers.ATLAS)
        m.inner:SetAtlas(Markers.ATLAS)
    end
    marks[button] = m
    return m
end

local function paint(m, kind)
    if m.kind == kind then return end
    m.kind = kind
    local s = Markers.STYLE[kind]
    if atlasOK then
        m.fill:SetDesaturated(s.desaturate == true)
        m.fill:SetVertexColor(s.color[1], s.color[2], s.color[3], s.color[4])
        if s.inner then
            m.inner:SetDesaturated(true)
            m.inner:SetVertexColor(s.inner[1], s.inner[2], s.inner[3], s.inner[4])
            m.inner:Show()
        else
            m.inner:Hide()
        end
    else
        m.fill:SetColorTexture(s.fallback[1], s.fallback[2], s.fallback[3], s.fallback[4])
        if s.inner then
            m.inner:SetColorTexture(s.inner[1], s.inner[2], s.inner[3], s.inner[4])
            m.inner:Show()
        else
            m.inner:Hide()
        end
    end
end

-- The marker for one bag slot: "green" | "amber" | nil.
function Markers.For(bag, slot, ctx)
    local link, bound, itemID = GG.Compat.BagSlotLink(bag, slot)
    if not link or not GG.Data.Slots.IsEquippable(GG.Compat.EquipLoc(itemID)) then return nil end
    local response = GG.Results.Get({ bag = bag, slot = slot }, GG.Compat.BagKey(bag, slot, link, bound))
    return GG.Engine.Policy.Marker(GG.MarkerView.View(response, bound, "bags"), ctx.settings, ctx.reveal)
end

-- One pass's shared inputs, or false when markers are off.
local function context()
    if not (GG.API.IsReady() and GG.player) then return false end
    local specs = {}
    for _, s in ipairs(GG.Data.Classes.Specs(GG.player.class)) do specs[#specs + 1] = s.key end
    return {
        reveal = GG.Reveal.Update(true),
        settings = GG.MarkerView.Settings(GG.db.settings.markers, specs),
    }
end

local function decorate(button, ctx)
    local kind
    if ctx then
        local bag, slot = where(button)
        if bag then kind = Markers.For(bag, slot, ctx) end
    end
    local m = marks[button]
    if not m then
        if not kind then return end
        if GG.Compat.InCombat() then
            pending[button] = true
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        m = newMark(button)
    end
    if kind then
        paint(m, kind)
        m:Show()
    else
        m:Hide()
    end
end

local function pass(cf, ctx)
    if ctx == nil then ctx = context() end
    for _, button in cf:EnumerateValidItems() do decorate(button, ctx) end
end

local function guarded(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()("GlassGear bag markers: " .. tostring(err)) end
end

local function onUpdateItems(cf) guarded(pass, cf) end

-- Redecorate the open bags now (never Blizzard's UpdateItems).
function Markers.Refresh()
    local ctx
    for _, cf in ipairs(bagFrames) do
        if cf:IsShown() then
            if ctx == nil then ctx = context() end
            guarded(pass, cf, ctx)
        end
    end
end

-- Many answers can arrive in one frame: one redecoration for all of them.
function Markers.RequestRefresh()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, function()
        scheduled = false
        Markers.Refresh()
    end)
end

local function afterCombat()
    events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local ctx = context()
    for button in pairs(pending) do
        pending[button] = nil
        decorate(button, ctx)
    end
end

-- Once, after login. Returns true, count | false, reason.
function Markers.Initialize()
    if hooked then return true, #bagFrames end
    hooked = true
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then guarded(afterCombat) end
    end)
    local list = {}
    local container = rawget(_G, "ContainerFrameContainer")
    if type(container) == "table" and type(container.ContainerFrames) == "table" then
        for _, cf in ipairs(container.ContainerFrames) do list[#list + 1] = cf end
    end
    local combined = rawget(_G, "ContainerFrameCombinedBags")
    if type(combined) == "table" then list[#list + 1] = combined end
    for _, cf in ipairs(list) do
        if type(cf.UpdateItems) == "function" and type(cf.EnumerateValidItems) == "function" then
            hooksecurefunc(cf, "UpdateItems", onUpdateItems)
            cf:HookScript("OnShow", function(self) GG.Reveal.SurfaceShown(self, true) end)
            cf:HookScript("OnHide", function(self) GG.Reveal.SurfaceShown(self, false) end)
            bagFrames[#bagFrames + 1] = cf
        end
    end
    GG.Results.Listen(Markers.RequestRefresh)
    GG.Reveal.Listen(Markers.Refresh)
    if #bagFrames == 0 then return false, "Blizzard's bag frames missing" end
    return true, #bagFrames
end

-- Test seams.
Markers._marks = marks
Markers._pending = pending

return Markers
