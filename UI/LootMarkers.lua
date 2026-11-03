------------------------------------------------------------
-- UI/LootMarkers.lua - upgrade markers on the loot window and the group roll
-- frames (GG-111). PRD matrix row 1, via Policy.Marker's loot rules:
--
--   green: a current-spec upgrade (always wins);
--   amber: another own spec's upgrade, only while the reveal modifier is held
--          (BoP and BoE alike: no "transferable" amber on loot); always with
--          marker scope "own". BoE loot alts (GG-203) only while revealed.
--
-- Forever's loot UI is the Mainline one (Blizzard_UIPanels_Game.toc:127-130):
--   * LootFrame: a ScrollBox of pooled elements (Mainline/LootFrame.lua:74-96);
--     each has GetSlotIndex() and an icon button `.Item`. Blizzard's Init runs
--     on open and on LOOT_SLOT_CHANGED (:186-194). We use
--     ScrollUtil.AddInitializedFrameCallback (ScrollUtil.lua:21), which fires
--     after Blizzard's initializer (ScrollBoxListView.lua:397-409), and
--     LOOT_SLOT_CHANGED ourselves.
--   * GroupLootFrame1..4 (Mainline/GroupLootFrame.xml:641-644): `rollID`, icon
--     button `.IconFrame`, set up on OnShow (GroupLootFrame.lua:371). The
--     gamepad roll list is not covered.
-- Both are reveal surfaces (GG-110). Answers are UI/Results.lua's, under the
-- same "link:" key as the tooltip, so hovering a marked item asks nothing new.
--
-- Loot often opens in combat. Mark frames are never created then: a pool is
-- made out of combat, and in combat a mark is re-parented from it (our own
-- unprotected frame). A button met in combat with the pool empty is marked
-- after PLAYER_REGEN_ENABLED, if it still shows.
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
local Loot = {}
GG.LootMarkers = Loot

Loot.POOL = 12
Loot.ROLL_FRAMES = 4

local marks = setmetatable({}, { __mode = "k" })     -- [button] = mark
local pending = setmetatable({}, { __mode = "k" })   -- [source] = decorate fn
local spare = {}                                     -- pooled marks
local rollFrames = {}
local lootFrame
local hooked, scheduled = false, false
local events, holder

local function fillPool()
    if GG.Compat.InCombat() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    for _ = #spare + 1, Loot.POOL do
        local m = GG.Marks.New(holder)
        m:Hide()
        spare[#spare + 1] = m
    end
end

-- The mark of `button`, from the pool or new; nil in combat with none left.
local function acquire(button)
    local m = marks[button]
    if m then return m end
    m = table.remove(spare)
    if not m then
        if GG.Compat.InCombat() then return nil end
        m = GG.Marks.New(button)
    end
    GG.Marks.Attach(m, button)
    marks[button] = m
    return m
end

-- The marker for a loot link: "green" | "amber" | nil.
function Loot.For(link, ctx)
    if type(link) ~= "string" or link == "" then return nil end
    if not GG.Data.Slots.IsEquippable(GG.Compat.EquipLoc(link)) then return nil end
    local response = GG.Results.Get(link, "link:" .. link)
    local view = GG.MarkerView.View(response, nil, "loot", GG.Compat.BindType(link))
    return GG.Engine.Policy.Marker(view, ctx.settings, ctx.reveal)
end

local function context()
    if not (GG.API.IsReady() and GG.player) then return false end
    local specs = {}
    for _, s in ipairs(GG.Data.Classes.Specs(GG.player.class)) do specs[#specs + 1] = s.key end
    return {
        reveal = GG.Reveal.Update(true),
        settings = GG.MarkerView.Settings(GG.db.settings.markers, specs),
    }
end

local function decorate(source, button, link, ctx, again)
    local kind = ctx and Loot.For(link, ctx) or nil
    local m = marks[button]
    if not m then
        if not kind then return end
        m = acquire(button)
        if not m then
            pending[source] = again
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
    end
    GG.Marks.Set(m, kind)
end

local function elementLink(element)
    local ok, slot = pcall(element.GetSlotIndex, element)
    if not (ok and type(slot) == "number") then return nil end
    return GG.Compat.LootSlotLink(slot)
end

local decorateElement, decorateRoll

function decorateElement(element, ctx)
    local button = type(element) == "table" and element.Item
    if type(button) ~= "table" then return end           -- money / empty elements
    if ctx == nil then ctx = context() end
    decorate(element, button, elementLink(element), ctx, decorateElement)
end

function decorateRoll(frame, ctx)
    if ctx == nil then ctx = context() end
    decorate(frame, frame.IconFrame, GG.Compat.RollLink(frame.rollID), ctx, decorateRoll)
end

local function guarded(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()("GlassGear loot markers: " .. tostring(err)) end
end

-- Redecorate the shown loot surfaces now.
function Loot.Refresh()
    local ctx
    if lootFrame and lootFrame:IsShown() then
        ctx = context()
        lootFrame.ScrollBox:ForEachFrame(function(element) guarded(decorateElement, element, ctx) end)
    end
    for _, f in ipairs(rollFrames) do
        if f:IsShown() then
            if ctx == nil then ctx = context() end
            guarded(decorateRoll, f, ctx)
        end
    end
end

function Loot.RequestRefresh()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, function()
        scheduled = false
        Loot.Refresh()
    end)
end

local function afterCombat()
    events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local ctx = context()
    for source, fn in pairs(pending) do
        pending[source] = nil
        if source:IsShown() then fn(source, ctx) end
    end
    fillPool()
end

local function surface(frame)
    frame:HookScript("OnShow", function(self) GG.Reveal.SurfaceShown(self, true) end)
    frame:HookScript("OnHide", function(self) GG.Reveal.SurfaceShown(self, false) end)
end

-- Once, after login. Returns true, info | false, reason.
function Loot.Initialize()
    if hooked then return Loot.Info() end
    hooked = true
    events = CreateFrame("Frame")
    holder = CreateFrame("Frame")
    holder:Hide()
    events:RegisterEvent("LOOT_SLOT_CHANGED")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            guarded(afterCombat)
        elseif event == "LOOT_SLOT_CHANGED" then
            Loot.RequestRefresh()
        end
    end)

    local lf = rawget(_G, "LootFrame")
    local util = rawget(_G, "ScrollUtil")
    if type(lf) == "table" and type(lf.ScrollBox) == "table" and type(util) == "table"
        and type(util.AddInitializedFrameCallback) == "function" then
        util.AddInitializedFrameCallback(lf.ScrollBox, function(_, element)
            guarded(decorateElement, element)
        end, Loot)
        surface(lf)
        lootFrame = lf
    end
    for i = 1, Loot.ROLL_FRAMES do
        local f = rawget(_G, "GroupLootFrame" .. i)
        if type(f) == "table" and type(f.IconFrame) == "table" then
            surface(f)
            f:HookScript("OnShow", function(self) guarded(decorateRoll, self) end)
            rollFrames[#rollFrames + 1] = f
        end
    end
    GG.Results.Listen(Loot.RequestRefresh)
    GG.Reveal.Listen(Loot.Refresh)
    fillPool()
    return Loot.Info()
end

function Loot.Info()
    if not lootFrame and #rollFrames == 0 then return false, L["Blizzard's loot frames missing"] end
    return true, (lootFrame and L["loot window, %d roll frames"] or L["no loot window, %d roll frames"]):format(#rollFrames)
end

-- Test seams.
Loot._marks = marks
Loot._pending = pending
Loot._spare = spare

return Loot
