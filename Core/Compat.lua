------------------------------------------------------------
-- Core/Compat.lua - the only file that calls item/character game APIs.
-- Every name is in the 1.60.1.70888 dump; the behaviour (return shapes on a
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
-- Is an item's data usable, by the same test as ItemFacts' `ready`: its info
-- and its stats both answer (the name can arrive before the stats).
function Compat.ItemLoaded(itemID)
    if C_Item.GetItemInfo(itemID) == nil then return false end
    return type(C_Item.GetItemStats("item:" .. itemID)) == "table"
end

-- An item's name from a link or item string, or nil while its data loads.
function Compat.ItemName(item)
    if type(item) ~= "string" then return nil end
    local n = item:match("%[(.-)%]")
    if n then return n end
    local ok, name = pcall(C_Item.GetItemInfo, item)
    return ok and name or nil
end

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

-- C_Texture.GetAtlasExists first: the porting guide's measured guard
-- (GlassUnitFrames, 70009); GetAtlasInfo when it's missing.
function Compat.AtlasKnown(name)
    if not name or type(C_Texture) ~= "table" then return false end
    if type(C_Texture.GetAtlasExists) == "function" then
        local ok, exists = pcall(C_Texture.GetAtlasExists, name)
        return ok and exists == true
    end
    if type(C_Texture.GetAtlasInfo) ~= "function" then return false end
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

-- A class's name in the client's language, for display only (the client's
-- LOCALIZED_CLASS_NAMES_MALE, wow-ui-source forever
-- Blizzard_FrameXMLBase/Constants.lua:37); nil when the client has none.
-- An export's Class= stays ProfileView.ClassLabel's English.
function Compat.ClassName(token)
    local t = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
    local name = type(t) == "table" and type(token) == "string" and t[token]
    if type(name) == "string" and name ~= "" then return name end
end

function Compat.Player()
    local name = UnitName("player")
    local _, class = UnitClass("player")
    local faction = UnitFactionGroup("player")
    return { key = UnitGUID("player"), guid = UnitGUID("player"), name = name, realm = GetRealmName(),
        class = class, level = UnitLevel("player"), faction = faction, provenance = "self",
        canDualWield = CanDualWield(), current = true }
end

-- Milliseconds, for measuring (debugprofilestop, dump :6605; os.clock where
-- the client's timer is missing, as in the tests).
-- Resolved once at load (no per-call lookup); without either timer it
-- reads 0, and measuring simply measures nothing (never an error).
local clockFn = rawget(_G, "debugprofilestop")
if type(clockFn) ~= "function" then
    local os_ = rawget(_G, "os")
    clockFn = (type(os_) == "table" and type(os_.clock) == "function")
        and function() return os_.clock() * 1000 end or function() return 0 end
end
function Compat.Clock()
    return clockFn()
end

-- Is an addon loaded? (C_AddOns.IsAddOnLoaded, dump :197) false when unknown.
function Compat.AddOnLoaded(name)
    local A = rawget(_G, "C_AddOns")
    if not (A and type(A.IsAddOnLoaded) == "function") then return false end
    local ok, loaded = pcall(A.IsAddOnLoaded, name)
    return ok and loaded == true
end

function Compat.ActiveSpecGroup()
    if not (C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup) then return nil, "unavailable" end
    return C_SpecializationInfo.GetActiveSpecGroup()
end

-- How many spec groups the character has (2 once dual spec is learned).
-- GetNumSpecGroups is in the dump's undocumented list (no signature):
-- AltStableSync measured 1 without dual spec. nil when it can't be read.
function Compat.NumSpecGroups()
    local f = rawget(_G, "GetNumSpecGroups")
    if type(f) ~= "function" then return nil end
    local ok, n = pcall(f)
    if ok and type(n) == "number" then return n end
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
-- One slot from a full item link (the measured path: suffix kept, link-level
-- fields present). Appends to `missing` when the item's data isn't loaded.
-- A baseline-shaped item from facts already read (no second read).
local function slotFromFacts(f, link)
    return { state = "occupied", itemID = f.itemID, equipLoc = f.equipLoc,
        classID = f.classID, subclassID = f.subclassID,
        itemString = f.itemString, item = Compat.GearItemString(link), tokens = f.tokens,
        unique = f.unique, setID = f.setID, hasSpell = f.hasSpell, unsupported = f.unsupported,
        reqLevel = f.reqLevel }
end

local function slotFromLink(link, missing)
    local f = Compat.ItemFacts(link)
    if f and f.ready then return slotFromFacts(f, link) end
    if f then missing[#missing + 1] = f.itemID end
    return { state = "unknown" }
end

-- The usable gear in bags 0-4 (GG-122): { { link, bag, slot, facts, slotItem } },
-- plus the itemIDs of gear still loading. At most `max` items.
function Compat.BagGear(max)
    local items, waiting = {}, {}
    for _, bag in ipairs(Compat.BAGS) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local link = info and info.hyperlink
            if link and #items < (max or 120) then
                local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
                if GG.Data.Slots.IsEquippable(equipLoc) then
                    local facts = Compat.ItemFacts(link)
                    if facts and facts.ready then
                        items[#items + 1] = { link = link, bag = bag, slot = slot, facts = facts,
                            slotItem = slotFromFacts(facts, link) }
                    elseif facts then
                        waiting[facts.itemID] = true
                    end
                end
            end
        end
    end
    return items, waiting
end

-- A baseline-shaped item from a full link, or nil while its data loads.
function Compat.SlotItem(link)
    local missing = {}
    local item = slotFromLink(link, missing)
    if item.state ~= "occupied" then return nil end
    return item
end

function Compat.EquippedBaseline(now)
    local slots, missing = {}, {}
    for _, slot in ipairs(GG.Data.Slots.GEAR) do
        local link = GetInventoryItemLink("player", slot)
        slots[slot] = link and slotFromLink(link, missing) or { state = "empty" }
    end
    return { slots = slots, capturedAt = now }, missing
end

------------------------------------------------------------
-- Equipment sets (GG-108, adr/0003 source 1). C_EquipmentSet is in the 70888
-- dump and Forever's character sheet uses it (Camelot PaperDollFrame.lua:1550);
-- what GetItemIDs returns for an empty or ignored slot is probe P14.
------------------------------------------------------------
Compat.BAGS = { 0, 1, 2, 3, 4 }

local function setAPI()
    local E = rawget(_G, "C_EquipmentSet")
    if type(E) ~= "table" or type(E.GetEquipmentSetIDs) ~= "function" then return nil end
    return E
end

-- { { id, name }, ... } in the client's order, or nil without the API.
function Compat.EquipmentSets()
    local E = setAPI()
    if not E then return nil end
    local ok, ids = pcall(E.GetEquipmentSetIDs)
    if not ok or type(ids) ~= "table" then return nil end
    local out = {}
    for _, id in ipairs(ids) do
        local okI, name = pcall(E.GetEquipmentSetInfo, id)
        if okI and name then out[#out + 1] = { id = id, name = name } end
    end
    return out
end

-- The set the client itself assigned to a spec group, if any.
function Compat.EquipmentSetForGroup(group)
    local E = setAPI()
    if not (E and group and type(E.GetEquipmentSetForSpec) == "function") then return nil end
    local ok, id = pcall(E.GetEquipmentSetForSpec, group)
    if ok and type(id) == "number" and id >= 0 then return id end
end

-- itemID -> the distinct links of every instance worn or in the bags, for the
-- given itemIDs only (one pass over the gear and the bags).
local function instanceIndex(wanted)
    local index, seen = {}, {}
    local function add(itemID, link)
        if not (itemID and link and wanted[itemID]) or seen[link] then return end
        seen[link] = true
        index[itemID] = index[itemID] or {}
        local l = index[itemID]
        l[#l + 1] = link
    end
    for _, slot in ipairs(GG.Data.Slots.GEAR) do
        local link = GetInventoryItemLink("player", slot)
        if link then add(C_Item.GetItemInfoInstant(link), link) end
    end
    for _, bag in ipairs(Compat.BAGS) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and wanted[id] then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                add(id, info and info.hyperlink)
            end
        end
    end
    return index
end

-- A set's item IDs and ignored slots, or nil.
local function setSlots(E, setID)
    local okI, ids = pcall(E.GetItemIDs, setID)
    if not okI or type(ids) ~= "table" then return nil end
    local okG, ignored = pcall(E.GetIgnoredSlots, setID)
    if not okG or type(ignored) ~= "table" then ignored = {} end
    return ids, ignored
end

local function setItemIDs(ids, ignored)
    local wanted = {}
    for _, slot in ipairs(GG.Data.Slots.GEAR) do
        local id = ids[slot]
        if not ignored[slot] and type(id) == "number" and id > 0 then wanted[id] = true end
    end
    return wanted
end

-- Which instances the sets' items resolve to right now, as one string: it
-- changes when a set piece enters or leaves the bags (bank, sold, a second
-- copy), which changes those sets' baselines. Worn gear is covered by
-- PLAYER_EQUIPMENT_CHANGED. "" without the API or sets.
function Compat.SetSignature(setIDs)
    local E = setAPI()
    if not E then return "" end
    local parts = {}
    for _, setID in ipairs(setIDs) do
        local ids, ignored = setSlots(E, setID)
        if ids then
            local index = instanceIndex(setItemIDs(ids, ignored))
            for _, slot in ipairs(GG.Data.Slots.GEAR) do
                local id = ids[slot]
                if not ignored[slot] and type(id) == "number" and id > 0 then
                    parts[#parts + 1] = setID .. "/" .. slot .. "=" .. table.concat(index[id] or {}, ",")
                end
            end
        else
            parts[#parts + 1] = setID .. "=?"
        end
    end
    return table.concat(parts, ";")
end

-- A set as a baseline-shaped table, plus missing itemIDs; nil, reason when
-- the set can't be read. A set slot names an item ID only: the instance (with
-- its suffix) is the one worn or in the bags. Two different instances, or none
-- (bank, sold), make the slot unknown: never a guess. An ignored slot keeps
-- what is worn, as equipping the set would.
function Compat.EquipmentSetBaseline(setID, now)
    local E = setAPI()
    if not E then return nil, "no-api" end
    local ids, ignored = setSlots(E, setID)
    if not ids then return nil, "unknown-set" end
    local index = instanceIndex(setItemIDs(ids, ignored))
    local slots, missing = {}, {}
    for _, slot in ipairs(GG.Data.Slots.GEAR) do
        local id = ids[slot]
        if ignored[slot] or id == -1 then
            local link = GetInventoryItemLink("player", slot)
            slots[slot] = link and slotFromLink(link, missing) or { state = "empty" }
        elseif not id or id == 0 then
            slots[slot] = { state = "empty" }
        else
            local links = index[id] or {}
            slots[slot] = #links == 1 and slotFromLink(links[1], missing) or { state = "unknown" }
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
