------------------------------------------------------------
-- Core/Compat.lua - the only file that calls item/character game APIs.
-- Every name is in the 1.60.1.70532 dump; the behaviour (return shapes on a
-- cache miss, stat keys) is probed by docs/FOREVER-PROBE.md before it is
-- trusted. A missing API returns nil, "unavailable".
------------------------------------------------------------

local GG = GlassGear
local Compat = {}
GG.Compat = Compat

-- Known armor skills are only read once probe P9/GG-118 confirms them.
Compat.USE_KNOWN_SKILLS = false
Compat.ARMOR_SPELLS = { [1] = 9078, [2] = 9077, [3] = 8737, [4] = 750, [6] = 9116 }

-- "item:..." payload of a link, or the input when it is already a string.
function Compat.ItemString(link)
    if type(link) ~= "string" then return nil end
    return link:match("(item:[%-%d:]+)") or link
end

-- Compact baseline form "id:enchant:suffix" (docs/SCHEMA.md).
-- item:itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:...
function Compat.CompactItem(link)
    local s = Compat.ItemString(link)
    if not s then return nil end
    local f = {}
    for v in (s:gsub("^item:", "") .. ":"):gmatch("([^:]*):") do f[#f + 1] = v end
    local id = tonumber(f[1])
    if not id then return nil end
    return string.format("%d:%s:%s", id, f[2] ~= "" and f[2] or "0", f[7] ~= nil and f[7] ~= "" and f[7] or "0")
end

-- Everything the engine needs about an item link. ready=false on a cache miss
-- (GetItemInfo or GetItemStats returning nothing) - a pending result, never 0.
function Compat.ItemFacts(link)
    if type(link) ~= "string" then return nil, "no-link" end
    local itemID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
    if not itemID then return nil, "unknown-item" end
    local facts = { itemID = itemID, equipLoc = equipLoc, classID = classID, subclassID = subclassID,
        itemString = GG.Engine.Score.StripEnchant(Compat.ItemString(link)), ready = false }
    local name, _, _, _, minLevel, _, _, _, _, _, _, _, _, bindType, _, setID = C_Item.GetItemInfo(link)
    local raw = C_Item.GetItemStats(link)
    if not name or type(raw) ~= "table" then
        C_Item.RequestLoadItemDataByID(itemID)
        return facts
    end
    facts.ready = true
    facts.reqLevel = minLevel
    facts.bindType = bindType
    facts.setID = (setID and setID > 0) and setID or nil
    facts.hasSpell = C_Item.GetItemSpell(link) ~= nil
    local cat, max = C_Item.GetItemUniqueness(link)
    if cat and cat > 0 then facts.unique = { key = "cat:" .. cat, max = max or 1 } end
    facts.tokens, facts.unsupported = GG.Data.Stats.FromItemStats(raw, facts)
    return facts
end

function Compat.Player()
    local name = UnitName("player")
    local _, class = UnitClass("player")
    local faction = UnitFactionGroup("player")
    return { key = UnitGUID("player"), guid = UnitGUID("player"), name = name, realm = GetRealmName(),
        class = class, level = UnitLevel("player"), faction = faction, provenance = "self",
        canDualWield = CanDualWield(), current = true }
end

function Compat.ActiveSpecGroup()
    if not (C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup) then return nil, "unavailable" end
    return C_SpecializationInfo.GetActiveSpecGroup()
end

-- { [subclass] = true } from known proficiency spells, or nil (fallback table).
function Compat.KnownArmor()
    if not Compat.USE_KNOWN_SKILLS then return nil end
    local out = {}
    for subclass, spell in pairs(Compat.ARMOR_SPELLS) do
        if C_SpellBook.IsSpellKnown(spell) then out[subclass] = true end
    end
    return out
end

-- The current equipment as a baseline-shaped table (adr/0003 source 3).
function Compat.EquippedBaseline(now)
    local slots = {}
    for _, slot in ipairs(GG.Data.Slots.GEAR) do
        local link = GetInventoryItemLink("player", slot)
        if not link then
            slots[slot] = { state = "empty" }
        else
            local f = Compat.ItemFacts(link)
            if f and f.ready then
                slots[slot] = { state = "occupied", itemID = f.itemID, equipLoc = f.equipLoc,
                    itemString = f.itemString, item = Compat.CompactItem(link), tokens = f.tokens,
                    unique = f.unique, setID = f.setID }
            else
                slots[slot] = { state = "unknown" }
            end
        end
    end
    return { slots = slots, capturedAt = now }
end

-- A bag instance: link, bind state and GUID.
function Compat.BagItem(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.hyperlink then return nil end
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local guid = C_Item.DoesItemExist(loc) and C_Item.GetItemGUID(loc) or nil
    return { link = info.hyperlink, isBound = info.isBound == true, guid = guid, bag = bag, slot = slot }
end

return Compat
