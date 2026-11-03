------------------------------------------------------------
-- UI/BagAddons.lua - upgrade markers on bag addons' buttons (GG-401).
--
-- Bagnon: its windows come from BagBrother (a global: WildAddon's NewAddon
-- writes _G[name]); a bag or bank item button is a ContainerItem, whose
-- Update(info) runs on every redraw (References Bagnon 12.1.7,
-- BagBrother/core/classes/containerItem.lua:62). Guild-bank and void items
-- are other classes (their "bag" is a tab): never hooked. One
-- hooksecurefunc on ContainerItem.Update decorates the button with the same marker
-- as Blizzard's bags (UI/BagMarkers.lua: Policy.Marker, UI/Marks.lua), read
-- from the button's bag and slot (item.lua:306-312). A button showing a
-- cached inventory (another character, an offline bank: containerItem.lua
-- :132 IsCached) is never decorated: its bag and slot would read the
-- current character's item.
--
-- Other bag replacements (Baganator, AdiBags, ArkInventory, BetterBags,
-- EllesmereUIBags) are reported as "markers unavailable" until each has an
-- adapter; tooltips still work there.
------------------------------------------------------------

local GG = GlassGear
local BagAddons = {}
GG.BagAddons = BagAddons

BagAddons.UNSUPPORTED = { "Baganator", "AdiBags", "ArkInventory", "BetterBags", "EllesmereUIBags" }

local buttons = setmetatable({}, { __mode = "k" })   -- Bagnon buttons met: [button] = true
local frames = setmetatable({}, { __mode = "k" })    -- their windows, hooked for the reveal
local scheduled = false
BagAddons.active = nil                               -- "Bagnon" once hooked

local function onShow(f) GG.Reveal.SurfaceShown(f, true) end
local function onHide(f) GG.Reveal.SurfaceShown(f, false) end

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
    local f = button.frame
    if type(f) == "table" and not frames[f] and type(f.HookScript) == "function" then
        frames[f] = true
        f:HookScript("OnShow", onShow)
        f:HookScript("OnHide", onHide)
        -- Registered on the next frame: a reveal change must not redraw
        -- every button from inside Bagnon's own update of one button.
        if f.IsShown and f:IsShown() then C_Timer.After(0, function() if f:IsShown() then onShow(f) end end) end
    end
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

-- Redecorate the Bagnon buttons on screen (answers arrived, the reveal key).
function BagAddons.Refresh()
    if not BagAddons.active then return end
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
    for _, name in ipairs(BagAddons.UNSUPPORTED) do
        if GG.Compat.AddOnLoaded(name) then return name, false end
    end
end

-- Once, after login. Returns name, supported | nil.
function BagAddons.Initialize()
    local name, supported = BagAddons.Detect()
    if supported and not BagAddons.active then
        hooksecurefunc(rawget(_G, "BagBrother").ContainerItem, "Update", function(button)
            guarded(decorate, button, frameContext())
        end)
        BagAddons.active = name
        GG.Results.Listen(BagAddons.RequestRefresh)
        GG.Reveal.Listen(BagAddons.Refresh)
    end
    return name, supported
end

-- One line for /gg.
function BagAddons.Status()
    local name, supported = BagAddons.Detect()
    if not name then return "bag addon: none (Blizzard's bags)" end
    if supported and BagAddons.active then return "bag addon: " .. name .. " (markers on its buttons)" end
    if supported then return "bag addon: " .. name .. " - markers unavailable (the hook failed: see the error)" end
    return "bag addon: " .. name .. " - markers unavailable there (tooltips work)"
end

-- Test seams.
BagAddons._buttons = buttons

return BagAddons
