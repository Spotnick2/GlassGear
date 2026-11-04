------------------------------------------------------------
-- UI/BagAddons.lua - upgrade markers on bag addons' buttons (GG-401).
--
-- Bagnon: its windows come from BagBrother (a global: WildAddon's NewAddon
-- writes _G[name]); a bag or bank item button is a ContainerItem, whose
-- Update(info) runs on every redraw. Guild-bank and void items
-- are other classes (their "bag" is a tab): never hooked. One
-- hooksecurefunc on ContainerItem.Update decorates the button with the same marker
-- as Blizzard's bags (UI/BagMarkers.lua: Policy.Marker, UI/Marks.lua), read
-- from the button's bag and slot. A button showing a cached inventory
-- (another character, an offline bank: IsCached) is never decorated: its
-- bag and slot would read the current character's item.
--
-- Baganator (Forever build): no hook. Its
-- public API takes a corner widget (RegisterCornerWidget, the way it adds
-- other addons' arrows): onInit makes
-- our mark for each of its item buttons, onUpdate(widget, details) says
-- whether it shows (Baganator shows or hides it, and the player can move or
-- remove it in Baganator's corner settings). `details.itemLocation` is
-- {bagID, slotIndex}; Baganator sets it from the current character's bags
-- even when the view shows another character, so the item there must be
-- the one shown (same link), else no mark. Answers still computing: no mark
-- now, and a widget refresh (RequestItemButtonsRefresh) once they arrive.
--
-- Other bag replacements (AdiBags, ArkInventory, BetterBags,
-- EllesmereUIBags) are reported as "markers unavailable" until each has an
-- adapter; tooltips still work there.
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
local BagAddons = {}
GG.BagAddons = BagAddons

BagAddons.UNSUPPORTED = { "AdiBags", "ArkInventory", "BetterBags", "EllesmereUIBags" }
BagAddons.WIDGET_ID = "glassgear"            -- Baganator's corner widget id (its saved settings use it)
BagAddons.WIDGET_LABEL = L["Glass Gear upgrades"]   -- the name Baganator's corner settings show

local buttons = setmetatable({}, { __mode = "k" })   -- Bagnon buttons met: [button] = true
local frames = setmetatable({}, { __mode = "k" })    -- their windows, hooked for the reveal
local scheduled = false
BagAddons.active = nil                               -- "Bagnon" | "Baganator" once attached

local function onShow(f) GG.Reveal.SurfaceShown(f, true) end
local function onHide(f) GG.Reveal.SurfaceShown(f, false) end

-- A window met for the first time becomes a reveal surface (the key is
-- polled while it shows). Registered on the next frame: a reveal change
-- must not redraw every button from inside the bag addon's own update.
local function watchWindow(f)
    if type(f) ~= "table" or frames[f] or type(f.HookScript) ~= "function" then return end
    frames[f] = true
    f:HookScript("OnShow", onShow)
    f:HookScript("OnHide", onHide)
    if f.IsShown and f:IsShown() then C_Timer.After(0, function() if f:IsShown() then onShow(f) end end) end
end

-- One context per frame and generation: Bagnon updates every button of a
-- window in one frame; building the context for each would repeat it.
local ctxCache
local function frameContext()
    local now, gen = GetTime(), GG.API._state.generation
    if not (ctxCache and ctxCache.time == now and ctxCache.gen == gen) then
        ctxCache = { time = now, gen = gen, ctx = GG.BagMarkers.Context() }
    end
    return ctxCache.ctx
end

-- A Bagnon button's bag and slot, or nil for a cached view (never ours).
local function where(button)
    if type(button.IsCached) == "function" then
        local ok, cached = pcall(button.IsCached, button)
        if not ok or cached then return nil end
    end
    local bag = button.bag
    if type(button.GetBag) == "function" then
        local ok, b = pcall(button.GetBag, button)
        if ok then bag = b end
    end
    local okS, slot = pcall(button.GetID, button)
    if type(bag) ~= "number" or not okS or type(slot) ~= "number" then return nil end
    return bag, slot
end

local function decorate(button, ctx)
    buttons[button] = true
    watchWindow(button.frame)
    local bag, slot = where(button)
    GG.BagMarkers.Decorate(button, ctx, bag, slot, where)
end

local function visible(button)
    if type(button.IsVisible) == "function" then return button:IsVisible() end
    return button:IsShown()
end

local function guarded(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()("GlassGear bag addons: " .. tostring(err)) end
end

------------------------------------------------------------
-- Baganator: a corner widget.
------------------------------------------------------------

local function baganatorAPI()
    local B = rawget(_G, "Baganator")
    local A = type(B) == "table" and B.API
    if type(A) == "table" and type(A.RegisterCornerWidget) == "function" then return A end
end

-- The top-level window an item button sits in (below UIParent).
local function topWindow(f)
    for _ = 1, 16 do
        local okP, p = pcall(f.GetParent, f)
        if not okP or type(p) ~= "table" or p == rawget(_G, "UIParent") then return f end
        f = p
    end
    return f
end

-- The live bag slot a Baganator button shows, or nil (another character's
-- or an offline view, a dummy button, an empty slot).
function BagAddons.BaganatorWhere(details)
    local loc = type(details) == "table" and details.itemLocation
    if type(loc) ~= "table" then return nil end
    local bag, slot = loc.bagID, loc.slotIndex
    if type(bag) ~= "number" or type(slot) ~= "number" or not details.itemLink then return nil end
    local link = GG.Compat.BagSlotLink(bag, slot)
    if link ~= details.itemLink then return nil end
    return bag, slot
end

-- onUpdate(widget, details) -> true (show) | false.
function BagAddons.BaganatorUpdate(widget, details)
    local ok, shown = pcall(function()
        local bag, slot = BagAddons.BaganatorWhere(details)
        local ctx = bag and frameContext()
        local kind = ctx and GG.BagMarkers.For(bag, slot, ctx) or nil
        if widget.button then watchWindow(topWindow(widget.button)) end
        GG.Marks.Set(widget, kind)
        return kind ~= nil
    end)
    if not ok then
        geterrorhandler()("GlassGear bag addons: " .. tostring(shown))
        return false
    end
    return shown
end

-- onInit(itemButton) -> our mark (Baganator anchors it in its corner).
function BagAddons.BaganatorInit(itemButton)
    local m = GG.Marks.New(itemButton)
    m.button = itemButton
    m:Hide()
    return m
end

local function attachBaganator(A)
    A.RegisterCornerWidget(BagAddons.WIDGET_LABEL, BagAddons.WIDGET_ID, BagAddons.BaganatorUpdate,
        BagAddons.BaganatorInit, { corner = "top_left", priority = 1 })
end

local function baganatorRefresh()
    local A = baganatorAPI()
    if not (A and type(A.RequestItemButtonsRefresh) == "function") then return end
    local B = rawget(_G, "Baganator")
    local R = type(B.Constants) == "table" and B.Constants.RefreshReason
    -- Only the widgets: no search or layout work on Baganator's side.
    A.RequestItemButtonsRefresh(R and R.ItemWidgets and { R.ItemWidgets } or nil)
end

-- Redecorate the bag addon's buttons on screen (answers arrived, the reveal key).
-- The reveal state is part of the context: one built earlier this frame is
-- stale now.
function BagAddons.Refresh()
    if not BagAddons.active then return end
    ctxCache = nil
    if BagAddons.active == "Baganator" then
        guarded(baganatorRefresh)
        return
    end
    local ctx = GG.BagMarkers.Context()
    for button in pairs(buttons) do
        -- On screen only: a closed Bagnon window's buttons stay "shown".
        if visible(button) then guarded(decorate, button, ctx) end
    end
end

function BagAddons.RequestRefresh()
    if scheduled or not BagAddons.active then return end
    scheduled = true
    C_Timer.After(0, function()
        scheduled = false
        BagAddons.Refresh()
    end)
end

-- The bag replacement loaded, if any: name, supported.
function BagAddons.Detect()
    local BB = rawget(_G, "BagBrother")
    if type(BB) == "table" and type(BB.ContainerItem) == "table" and type(BB.ContainerItem.Update) == "function" then
        -- BagBrother serves other frontends too: name what is loaded.
        return GG.Compat.AddOnLoaded("Bagnon") and "Bagnon" or "BagBrother", true
    end
    if baganatorAPI() then return "Baganator", true end
    for _, name in ipairs(BagAddons.UNSUPPORTED) do
        if GG.Compat.AddOnLoaded(name) then return name, false end
    end
end

-- Once, after login. Returns name, supported | nil.
function BagAddons.Initialize()
    local name, supported = BagAddons.Detect()
    if supported and not BagAddons.active then
        if name == "Baganator" then
            attachBaganator(baganatorAPI())
        else
            hooksecurefunc(rawget(_G, "BagBrother").ContainerItem, "Update", function(button)
                guarded(decorate, button, frameContext())
            end)
        end
        BagAddons.active = name
        GG.Results.Listen(BagAddons.RequestRefresh)
        GG.Reveal.Listen(BagAddons.Refresh)
    end
    return name, supported
end

-- One line for /gg.
function BagAddons.Status()
    local name, supported = BagAddons.Detect()
    if not name then return L["bag addon: none (Blizzard's bags)"] end
    if supported and BagAddons.active == "Baganator" then
        local okW, on = pcall(baganatorAPI().IsCornerWidgetActive, BagAddons.WIDGET_ID)
        if okW and on == false then
            return L["bag addon: Baganator - markers off (add '%s' to an icon corner in Baganator's settings)"]:format(
                BagAddons.WIDGET_LABEL)
        end
        return L["bag addon: Baganator (markers in an icon corner: '%s')"]:format(BagAddons.WIDGET_LABEL)
    end
    if supported and BagAddons.active then return L["bag addon: %s (markers on its buttons)"]:format(name) end
    if supported then return L["bag addon: %s - markers unavailable (the hook failed: see the error)"]:format(name) end
    return L["bag addon: %s - markers unavailable there (tooltips work)"]:format(name)
end

-- Test seams.
BagAddons._buttons = buttons

return BagAddons
