------------------------------------------------------------
-- Character/Owned.lua - the gear the character carries in its bags (GG-122),
-- for evaluations that know what is owned:
--   * a companion for a 1H candidate against a spec whose gear has a 2H
--     (an off-hand or main hand from the bags, not only the worn one);
--   * "better gear already owned" (Evaluate.ApplyOwned).
--
--   Owned.Items()          the usable bag gear: { { link, bag, slot, facts, slotItem }, ... }
--   Owned.Refresh()        rebuild after a bag change; invalidate answers if
--                          the gear carried changed (not on junk or moves)
--   Owned.ItemArrived(id)  an item it skipped while loading is now usable
--
-- Bags 0-4 only (the bank is out of reach). An item whose data isn't loaded
-- yet is never used: it is requested, and the index is rebuilt when it
-- arrives. Built once per bag change: an evaluation costs no bag scan.
------------------------------------------------------------

local GG = GlassGear
local Owned = {}
GG.Owned = Owned

Owned.MAX_ITEMS = 120        -- bag gear kept (a bound: bags 0-4 hold at most ~100 slots)
Owned.scans = 0              -- bag scans so far (one per bag change, never per evaluation)

local index, signature
local pending = {}           -- [itemID] = true: skipped while loading

local function scan()
    Owned.scans = Owned.scans + 1
    local items, links, waiting = {}, {}, {}
    for _, bag in ipairs(GG.Compat.BAGS) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local link = info and info.hyperlink
            if link and #items < Owned.MAX_ITEMS then
                local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
                if GG.Data.Slots.IsEquippable(equipLoc) then
                    local facts = GG.Compat.ItemFacts(link)
                    if facts and facts.ready then
                        local slotItem = GG.Compat.SlotItem(link)
                        if slotItem then
                            items[#items + 1] = { link = link, bag = bag, slot = slot, facts = facts, slotItem = slotItem }
                            links[#links + 1] = link
                        end
                    elseif facts then
                        waiting[facts.itemID] = true
                    end
                end
            end
        end
    end
    table.sort(links)
    return items, table.concat(links, ";"), waiting
end

function Owned.Refresh()
    local items, sig, waiting = scan()
    local changed = signature ~= nil and sig ~= signature
    index, signature, pending = items, sig, waiting
    for id in pairs(waiting) do GG.Compat.RequestItem(id) end
    if changed and GG.player and GG.API then GG.API._Invalidate("bags", { GG.player.key }) end
    return changed
end

function Owned.Items()
    if not index then Owned.Refresh() end
    return index
end

function Owned.ItemArrived(itemID)
    if pending[itemID] then Owned.Refresh() end
end

-- How many positions an item can take at once (rings, trinkets, and a
-- one-hander with dual wield: two), so "owned better" needs that many.
function Owned.Positions(equipLoc, canDualWield)
    if equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_TRINKET" then return 2 end
    if equipLoc == "INVTYPE_WEAPON" and canDualWield then return 2 end
    return 1
end

-- Do two equip locations compete for a slot?
function Owned.SameSlots(a, b)
    local sa, sb = GG.Data.Slots.FOR_EQUIP_LOC[a or ""], GG.Data.Slots.FOR_EQUIP_LOC[b or ""]
    if not (sa and sb) then return false end
    for _, x in ipairs(sa) do for _, y in ipairs(sb) do if x == y then return true end end end
    return false
end

-- Test seam.
function Owned._Reset() index, signature, pending = nil, nil, {} end

return Owned
