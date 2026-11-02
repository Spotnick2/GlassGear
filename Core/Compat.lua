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

-- The baseline form of an equipped item (docs/SCHEMA.md): the same trimmed
-- item string AltStable's GetCharacterGear returns (AltStable Scanner.lua:96-129
-- @1b35918, docs/PUBLIC-API.md), so own and alt baselines compare alike.
-- Forever links are the Mainline layout:
--   item:id:enchant:gem1:gem2:gem3:gem4:suffix:unique:linkLevel:spec:
--        modifiersMask:context:numBonus[:bonus...]:numModifiers[:type:value...]:...
-- A random suffix is a BONUS ID on Forever; the classic suffix field is always
-- empty (measured by AltStable on 205 links). So the bonus and modifier block is
-- kept; linkLevel and spec (the scanning character's) are blanked; what follows
-- the modifiers (crafter GUID, relics) is dropped; trailing empties trimmed.
--   "Beaded Wraps of the Sorcerer" -> "item:14094::::::::::::1:12745"
function Compat.GearItemString(link)
    if type(link) ~= "string" then return nil end
    local body = link:match("item:([^|]+)")
    if not body then return nil end
    local f, n = {}, 0
    for v in (body .. ":"):gmatch("([^:]*):") do n = n + 1; f[n] = v end
    if not tonumber(f[1]) then return nil end
    f[9], f[10] = "", ""
    local bonuses = tonumber(f[13]) or 0
    local mods = tonumber(f[14 + bonuses]) or 0
    local last = 12
    if bonuses > 0 or mods > 0 then last = 14 + bonuses + 2 * mods end
    while last > 1 and (f[last] == nil or f[last] == "") do last = last - 1 end
    local out = {}
    for i = 1, last do out[i] = f[i] or "" end
    return "item:" .. table.concat(out, ":")
end

-- Everything the engine needs about an item link. ready=false on a cache miss
-- (GetItemInfo or GetItemStats returning nothing) - a pending result, never 0.
-- It never requests a load itself: the API's queue owns load attempts.
-- Stats are read from the enchant-stripped item string (adr/0003); whether the
-- client's stats include enchants at all is probe P4.
function Compat.ItemFacts(link)
    if type(link) ~= "string" then return nil, "no-link" end
    local itemID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
    if not itemID then return nil, "unknown-item" end
    local stripped = GG.Engine.Score.StripEnchant(Compat.ItemString(link))
    local facts = { itemID = itemID, equipLoc = equipLoc, classID = classID, subclassID = subclassID,
        itemString = stripped, ready = false }
    local name, _, _, _, minLevel, _, _, _, _, _, _, _, _, bindType, _, setID = C_Item.GetItemInfo(link)
    local raw = C_Item.GetItemStats(stripped)
    if not name or type(raw) ~= "table" then return facts end
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

-- Tooltip helpers (GG-107). The equip location from the instant cache only.
function Compat.EquipLoc(itemID)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    return equipLoc
end

-- The link of the bag slot when it still holds itemID, else nil.
-- The bag slot's link and bind state, when it still holds itemID (any item
-- when itemID is nil); else nil.
function Compat.BagSlotLink(bag, slot, itemID)
    local here = C_Container.GetContainerItemID(bag, slot)
    if not here or (itemID and here ~= itemID) then return nil end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not (info and info.hyperlink) then return nil end
    return info.hyperlink, info.isBound == true, here
end

-- The cache key of a bag slot's item, shared by tooltips and markers: it
-- changes when the item, its link or its bind state changes.
function Compat.BagKey(bag, slot, link, bound)
    return "bag:" .. bag .. ":" .. slot .. ":" .. (bound and "b" or "u") .. ":" .. link
end

-- Loot surfaces (GG-111). A loot-window slot's link, items only (money and
-- currency slots give nil); a group roll's link.
function Compat.LootSlotLink(slot)
    if GetLootSlotType(slot) ~= Enum.LootSlotType.Item then return nil end
    return GetLootSlotLink(slot)
end

function Compat.RollLink(rollID)
    if not rollID then return nil end
    return GetLootRollItemLink(rollID)
end

-- The item's bind type (1 = on pickup, 2 = on equip, ...), nil on a cache miss.
function Compat.BindType(link)
    return (select(14, C_Item.GetItemInfo(link)))
end

-- Reveal inputs (GG-110). modifier = "CTRL" | "ALT" | anything else (none).
function Compat.ModifierDown(modifier)
    if modifier == "CTRL" then return IsControlKeyDown() == true end
    if modifier == "ALT" then return IsAltKeyDown() == true end
    return false
end

function Compat.KeyboardFocused()
    return GetCurrentKeyBoardFocus() ~= nil
end

function Compat.InCombat()
    return InCombatLockdown() == true
end

function Compat.AtlasKnown(name)
    if not name or not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and type(info) == "table"
end

-- An item instance's current link (TooltipUtil.GetDisplayedItem's guid path).
function Compat.LinkByGUID(guid)
    return C_Item.GetItemLinkByGUID(guid)
end

function Compat.RequestItem(itemID)
    C_Item.RequestLoadItemDataByID(itemID)
end

-- A request's item reference -> link, instance | nil. Accepts a link string, a
-- {bag, slot} table, or a client ItemLocation (bag/slot or equipment slot,
-- Blizzard_ObjectAPI ItemLocation.lua:42-60).
function Compat.ResolveItemRef(ref)
    if type(ref) == "string" then return ref, nil end
    if type(ref) ~= "table" then return nil end
    local bag, slot
    if type(ref.IsBagAndSlot) == "function" then
        if ref:IsBagAndSlot() then
            bag, slot = ref:GetBagAndSlot()
        elseif ref:IsEquipmentSlot() then
            local link = GetInventoryItemLink("player", ref:GetEquipmentSlot())
            return link, link and { equipSlot = ref:GetEquipmentSlot(), bound = true } or nil
        end
    else
        bag, slot = ref.bag, ref.slot
    end
    if not (bag and slot) then return nil end
    local b = Compat.BagItem(bag, slot)
    if not b then return nil end
    return b.link, { bag = b.bag, slot = b.slot, guid = b.guid, bound = b.isBound }
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

-- The current equipment as a baseline-shaped table (adr/0003 source 3), plus
-- the itemIDs whose data isn't loaded yet (their slots are "unknown").
function Compat.EquippedBaseline(now)
    local slots, missing = {}, {}
    for _, slot in ipairs(GG.Data.Slots.GEAR) do
        local link = GetInventoryItemLink("player", slot)
        if not link then
            slots[slot] = { state = "empty" }
        else
            local f = Compat.ItemFacts(link)
            if f and f.ready then
                slots[slot] = { state = "occupied", itemID = f.itemID, equipLoc = f.equipLoc,
                    classID = f.classID, subclassID = f.subclassID,
                    itemString = f.itemString, item = Compat.GearItemString(link), tokens = f.tokens,
                    unique = f.unique, setID = f.setID, hasSpell = f.hasSpell, unsupported = f.unsupported }
            else
                slots[slot] = { state = "unknown" }
                if f then missing[#missing + 1] = f.itemID end
            end
        end
    end
    return { slots = slots, capturedAt = now }, missing
end

-- A bag instance: link, bind state and GUID.
function Compat.BagItem(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.hyperlink then return nil end
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)   -- Blizzard Lua mixin
    local guid = C_Item.DoesItemExist(loc) and C_Item.GetItemGUID(loc) or nil
    return { link = info.hyperlink, isBound = info.isBound == true, guid = guid, bag = bag, slot = slot }
end

return Compat
