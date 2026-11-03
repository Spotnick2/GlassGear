------------------------------------------------------------
-- UI/Tooltip.lua - Glass Gear rows on item tooltips (GG-107).
--
-- One TooltipDataProcessor post-call (OnTooltipSetItem throws on Forever,
-- PORTING:979-990), registered once and run under pcall: lines only, never a
-- restyle (adr/0004). Every own spec is evaluated (scope "own"); rows follow
-- the tooltip policy (adr/0006). Models: Shatter Tooltip.lua (refresh guards),
-- the bag-slot owner pattern for instances.
--
-- Answers come from UI/Results.lua, shared with the bag markers: a bag button
-- rebuilding its tooltip every 0.2 s costs a lookup, and a pending item makes
-- one API request, not one per rebuild or per surface.
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
local Tooltip = {}
GG.Tooltip = Tooltip

local shown = setmetatable({}, { __mode = "k" })   -- [tooltip] = { key, itemID }
local registered = false

local function isComparison(tooltip)
    local ok, name = pcall(tooltip.GetName, tooltip)
    return ok and type(name) == "string" and name:find("ShoppingTooltip", 1, true) ~= nil
end

-- The item a tooltip shows -> API item reference, cache key. A Blizzard bag
-- button (GetBagID + GetID) whose slot still holds the item gives the instance,
-- under the same key the bag markers use.
function Tooltip.ItemRef(tooltip, data)
    local id = tonumber(data.id)
    if not id then return nil end
    local okO, owner = pcall(tooltip.GetOwner, tooltip)
    if okO and type(owner) == "table" and type(owner.GetBagID) == "function" then
        local okB, bag = pcall(owner.GetBagID, owner)
        local okS, slot = pcall(owner.GetID, owner)
        if okB and okS and bag and slot then
            local link, bound = GG.Compat.BagSlotLink(bag, slot, id)
            if link then return { bag = bag, slot = slot }, GG.Compat.BagKey(bag, slot, link, bound) end
        end
    end
    local link
    if data.guid then link = GG.Compat.LinkByGUID(data.guid) end
    if not link and type(data.hyperlink) == "string" and data.hyperlink ~= "" then link = data.hyperlink end
    if not link and type(tooltip.GetItem) == "function" then
        local ok, _, l = pcall(tooltip.GetItem, tooltip)
        if ok then link = l end
    end
    if type(link) ~= "string" or link == "" then return nil end
    return link, "link:" .. link
end

function Tooltip.Render(tooltip, lines)
    for _, l in ipairs(lines) do
        if l.right then
            tooltip:AddDoubleLine(l.left, l.right, l.lc[1], l.lc[2], l.lc[3], l.rc[1], l.rc[2], l.rc[3])
        else
            tooltip:AddLine(l.left, l.lc[1], l.lc[2], l.lc[3])
        end
    end
end

-- The tooltip scope plus the set-bonus warning switch (PRD section 5).
function Tooltip.ViewSettings()
    local s = GG.db.settings
    return { specs = s.tooltip.specs, selected = s.tooltip.selected, alts = s.tooltip.alts,
        setBonusWarnings = s.setBonusWarnings }
end

local function onItemTooltip(tooltip, data)
    if not tooltip or type(data) ~= "table" or not GG.API.IsReady() then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    shown[tooltip] = nil
    if isComparison(tooltip) then return end
    local itemID = tonumber(data.id)
    if not itemID then return end
    if not GG.Data.Slots.IsEquippable(GG.Compat.EquipLoc(itemID)) then return end
    local ref, key = Tooltip.ItemRef(tooltip, data)
    if not ref then return end
    local lines = GG.TooltipView.Build(GG.Results.Get(ref, key), Tooltip.ViewSettings(),
        { currentSpec = GG.currentSpec })
    if not lines then return end
    shown[tooltip] = { key = key, itemID = itemID }
    -- /gg compare with nothing pasted compares this one (GG-113): the item's
    -- link, not its bag position (a sort would move another item there).
    Tooltip.lastRef = (type(ref) == "string") and ref or GG.Compat.ResolveItemRef(ref)
    Tooltip.Render(tooltip, lines)
end
Tooltip._OnItemTooltip = onItemTooltip   -- test seam

-- Rebuild open tooltips showing `key` (or any, when nil). Shatter's guards:
-- still shown, not forbidden, same item; owners with UpdateTooltip rebuild
-- themselves within 0.2 s.
local function refresh(key)
    local stale = {}
    for tooltip, s in pairs(shown) do
        if (key == nil or s.key == key) and tooltip:IsShown()
            and not (tooltip.IsForbidden and tooltip:IsForbidden())
            and tooltip.RefreshData and tooltip.GetPrimaryTooltipData then
            local owner = tooltip:GetOwner()
            local data = tooltip:GetPrimaryTooltipData()
            if not (owner and owner.UpdateTooltip) and type(data) == "table"
                and tonumber(data.id) == s.itemID then
                stale[#stale + 1] = tooltip
            end
        end
    end
    for _, tooltip in ipairs(stale) do tooltip:RefreshData() end
end

-- Forget every cached answer (shared with the markers).
function Tooltip.Reset() GG.Results.Reset() end

-- Once, after login. A client without the processor gets no rows.
function Tooltip.Initialize()
    if registered then return true end
    local TDP = rawget(_G, "TooltipDataProcessor")
    local enum = rawget(_G, "Enum")
    local kind = type(enum) == "table" and enum.TooltipDataType and enum.TooltipDataType.Item
    if not (TDP and TDP.AddTooltipPostCall and kind) then return false, L["TooltipDataProcessor missing"] end
    registered = true
    local handler = geterrorhandler()
    TDP.AddTooltipPostCall(kind, function(tooltip, data)
        local ok, err = pcall(onItemTooltip, tooltip, data)
        if not ok then handler("GlassGear tooltip: " .. tostring(err)) end
    end)
    GG.Results.Listen(refresh)
    return true
end

return Tooltip
