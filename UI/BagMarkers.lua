------------------------------------------------------------
-- UI/BagMarkers.lua - upgrade markers on Blizzard's bag buttons (GG-109).
--
--   green: a current-spec upgrade (always wins);
--   amber: another own spec's upgrade on a transferable item (default on), or
--          on any item while the reveal modifier is held (GG-110).
-- The look (filled green arrow, amber outline) is UI/Marks.lua's.
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
local L = GG.L
local Markers = {}
GG.BagMarkers = Markers

Markers.MAX_CONTAINER_FRAMES = 20      -- NUM_CONTAINER_FRAMES is 13 on Mainline

local marks = setmetatable({}, { __mode = "k" })     -- [button] = mark
local pending = setmetatable({}, { __mode = "k" })   -- buttons met in combat
local bagFrames = {}
local hooked, scheduled = false, false
local events

local function where(button)
    local okB, bag = pcall(button.GetBagID, button)
    local okS, slot = pcall(button.GetID, button)
    if not (okB and okS) or type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    return bag, slot
end

-- The marker for one bag slot: "green" | "amber" | nil.
function Markers.For(bag, slot, ctx)
    local link, bound, itemID = GG.Compat.BagSlotLink(bag, slot)
    if not link or not GG.Data.Slots.IsEquippable(GG.Compat.EquipLoc(itemID)) then return nil end
    local response = GG.Results.Get({ bag = bag, slot = slot }, GG.Compat.BagKey(bag, slot, link, bound))
    return GG.Engine.Policy.Marker(GG.MarkerView.View(response, bound, "bags"), ctx.settings, ctx.reveal)
end

-- One pass's shared inputs, or false when markers are off.
-- (Markers.Context: shared with the bag addons' adapter, UI/BagAddons.lua.)
local function context()
    if not (GG.API.IsReady() and GG.player) then return false end
    local specs = {}
    for _, s in ipairs(GG.Data.Classes.Specs(GG.player.class)) do specs[#specs + 1] = s.key end
    return {
        reveal = GG.Reveal.Update(true),
        settings = GG.MarkerView.Settings(GG.db.settings.markers, specs),
    }
end

-- Decorate any button: Blizzard's (bag/slot read here) or a bag addon's
-- (bag/slot given; nil bag clears its mark). `rewhere` is the adapter's
-- own reader, used again for a button first met in combat.
local function decorate(button, ctx, bag, slot, given, rewhere)
    local kind
    if ctx then
        if not given then bag, slot = where(button) end
        if bag then kind = Markers.For(bag, slot, ctx) end
    end
    local m = marks[button]
    if not m then
        if not kind then return end
        if GG.Compat.InCombat() then
            pending[button] = rewhere or true
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        m = GG.Marks.New(button)
        marks[button] = m
    end
    GG.Marks.Set(m, kind)
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
    for button, how in pairs(pending) do
        pending[button] = nil
        if type(how) == "function" then
            -- A bag addon's button: its own reader, never Blizzard's GetBagID.
            local bag, slot = how(button)
            decorate(button, ctx, bag, slot, true, how)
        else
            decorate(button, ctx)
        end
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
    -- Both routes, each frame once: the ContainerFrame1..N globals (GlassUI
    -- hooks UpdateItems on those, measured on 70450, GlassUI docs/BAGS.md:127)
    -- and the ContainerFrameContainer list (Mainline ContainerFrame.lua:2282),
    -- plus the combined bag.
    local list, seen = {}, {}
    local function add(cf)
        if type(cf) == "table" and not seen[cf] then
            seen[cf] = true
            list[#list + 1] = cf
        end
    end
    for i = 1, Markers.MAX_CONTAINER_FRAMES do add(rawget(_G, "ContainerFrame" .. i)) end
    local container = rawget(_G, "ContainerFrameContainer")
    if type(container) == "table" and type(container.ContainerFrames) == "table" then
        for _, cf in ipairs(container.ContainerFrames) do add(cf) end
    end
    add(rawget(_G, "ContainerFrameCombinedBags"))
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
    if #bagFrames == 0 then return false, L["Blizzard's bag frames missing"] end
    return true, #bagFrames
end

Markers.Context = context
function Markers.Decorate(button, ctx, bag, slot, rewhere) decorate(button, ctx, bag, slot, true, rewhere) end

-- Test seams.
Markers._marks = marks
Markers._pending = pending

return Markers
