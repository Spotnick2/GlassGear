------------------------------------------------------------
-- wow_stubs.lua - the WoW: Forever surface Glass Gear calls, so the addon
-- loads and runs under stock Lua 5.1. Drive it through `WoW`:
--
--     dofile("tests/wow_stubs.lua")      -- FIRST, in every test file that loads the addon
--     WoW.items[19019] = { name = "...", equipLoc = "INVTYPE_WEAPON", ... }
--     WoW.loadAddon()                    -- TOC order, ADDON_LOADED, PLAYER_LOGIN
--
-- Strict like Shatter's stubs (Shatter/tests/wow_stubs.lua):
--   * Reading a global this file doesn't define is an error, except the
--     addon's own declared globals. Every name here is in the API dump
--     References/Forever/api/forever-api-1.60.1.70532.md (or Blizzard's Lua
--     in wow-ui-source for ItemLocation, DEFAULT_CHAT_FRAME, SlashCmdList).
--   * Writing a global other than the addon's own is recorded in
--     WoW.globalWrites; test_load fails on anything undeclared.
-- Never add something because a test failed; confirm it exists first.
------------------------------------------------------------

WoW = {}
local WoW = WoW

local OWN_GLOBALS = { GlassGear = true, GlassGearDB = true, GlassGearChar = true,
    SLASH_GLASSGEAR1 = true, SLASH_GLASSGEAR2 = true }

function WoW.reset()
    WoW.time = 1000
    WoW.epoch = 1793500000
    WoW.timers = {}
    WoW.frames = {}
    WoW.chatLines = {}
    WoW.globalWrites = {}
    WoW.errors = {}       -- errors caught by xpcall (geterrorhandler)
    WoW.itemRequests = {}
    WoW.player = { name = "Karuzo", realm = "Forever", class = "PRIEST", className = "Priest",
        level = 60, faction = "Alliance", guid = "Player-1-0000AAAA", dualWield = false }
    WoW.specGroup = 1
    WoW.items = {}        -- [itemID] = { name, equipLoc, classID, subclassID, minLevel, bindType, setID, stats, spell, unique = {cat,max} }
    WoW.cacheMiss = {}    -- [itemID] = true -> GetItemInfo / GetItemStats return nothing
    WoW.equipped = {}     -- [slot] = itemID
    WoW.bags = {}         -- [bag] = { [slot] = { itemID, isBound, guid } }
    WoW.settingsCategories = {}
end

function WoW.link(itemID, enchant)
    local it = WoW.items[itemID] or {}
    return string.format("|cff0070dd|Hitem:%d:%d:0:0:0:0:0:0|h[%s]|h|r", itemID, enchant or 0, it.name or "?")
end

local function idOf(info)
    if type(info) == "number" then return info end
    if type(info) == "string" then return tonumber(info:match("item:(%d+)")) end
end

-- Timers: C_Timer.After callbacks run on WoW.flush().
function WoW.flush(rounds)
    for _ = 1, rounds or 5 do
        local due = WoW.timers
        WoW.timers = {}
        if #due == 0 then return end
        for _, t in ipairs(due) do t() end
    end
end

-- Fire an event at every frame that registered it.
function WoW.fire(event, ...)
    for _, f in ipairs(WoW.frames) do
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end

function WoW.chat() return table.concat(WoW.chatLines, "\n") end

------------------------------------------------------------
-- Widgets (only the methods Glass Gear calls)
------------------------------------------------------------
local function newFontString()
    local fs = {}
    function fs:SetPoint() end
    function fs:SetText(t) self.text = t end
    return fs
end

function CreateFrame(kind, name)
    local f = { _events = {}, _scripts = {}, kind = kind, name = name }
    function f:RegisterEvent(e) self._events[e] = true end
    function f:UnregisterEvent(e) self._events[e] = nil end
    function f:SetScript(s, fn) self._scripts[s] = fn end
    function f:CreateFontString() return newFontString() end
    WoW.frames[#WoW.frames + 1] = f
    return f
end

------------------------------------------------------------
-- API surface (dump line numbers in comments)
------------------------------------------------------------
C_Timer = { After = function(_, fn) WoW.timers[#WoW.timers + 1] = fn end }   -- 3760
function GetTime() return WoW.time end
function time() return WoW.epoch end
function GetBuildInfo() return "1.60.1", "70532", "Oct 30 2026", 16001 end    -- 4722
function geterrorhandler() return function(e) WoW.errors[#WoW.errors + 1] = e end end

function UnitName(u) if u == "player" then return WoW.player.name end end
function UnitClass(u) if u == "player" then return WoW.player.className, WoW.player.class, 5 end end   -- 6418
function UnitGUID(u) if u == "player" then return WoW.player.guid end end                             -- 6437
function UnitLevel(u) if u == "player" then return WoW.player.level end end                           -- 6517
function UnitFactionGroup(u) if u == "player" then return WoW.player.faction, WoW.player.faction end end -- 6435
function GetRealmName() return WoW.player.realm end                                                    -- 5156
function CanDualWield() return WoW.player.dualWield end                                                -- 4457
function GetInventoryItemLink(unit, slot)                                                              -- 19049
    local id = unit == "player" and WoW.equipped[slot]
    return id and WoW.link(id) or nil
end

C_SpecializationInfo = { GetActiveSpecGroup = function() return WoW.specGroup end }                   -- 3490
C_SpellBook = { IsSpellKnown = function() return false end }                                          -- 3634

C_Item = {}
function C_Item.GetItemInfoInstant(info)                                                               -- 2244
    local id = idOf(info)
    local it = id and WoW.items[id]
    if not it then return nil end
    return id, "Armor", "Cloth", it.equipLoc, 0, it.classID, it.subclassID
end
function C_Item.GetItemInfo(info)                                                                      -- 2243
    local id = idOf(info)
    local it = id and WoW.items[id]
    if not it or WoW.cacheMiss[id] then return nil end
    return it.name, WoW.link(id), 3, 60, it.minLevel or 1, "Armor", "Cloth", 1, it.equipLoc, 0, 0,
        it.classID, it.subclassID, it.bindType or 1, 0, it.setID, false, ""
end
function C_Item.GetItemStats(link)                                                                     -- 2266
    local id = idOf(link)
    local it = id and WoW.items[id]
    if not it or WoW.cacheMiss[id] then return nil end
    local copy = {}
    for k, v in pairs(it.stats or {}) do copy[k] = v end
    return copy
end
function C_Item.GetItemSpell(info)                                                                     -- 2264
    local it = WoW.items[idOf(info) or 0]
    if it and it.spell then return it.spell, 1 end
    return nil
end
function C_Item.GetItemUniqueness(info)                                                                -- 2268
    local it = WoW.items[idOf(info) or 0]
    if it and it.unique then return it.unique.cat, it.unique.max end
    return 0, 0
end
function C_Item.RequestLoadItemDataByID(info) WoW.itemRequests[#WoW.itemRequests + 1] = idOf(info) end  -- 2315
function C_Item.DoesItemExist(loc)                                                                     -- 2210
    local b = WoW.bags[loc.bagID]
    return b ~= nil and b[loc.slotIndex] ~= nil
end
function C_Item.GetItemGUID(loc) return WoW.bags[loc.bagID][loc.slotIndex].guid end                   -- 2235

C_Container = {}
function C_Container.GetContainerItemInfo(bag, slot)                                                   -- 1170
    local b = WoW.bags[bag]
    local s = b and b[slot]
    if not s then return nil end
    return { hyperlink = WoW.link(s.itemID), isBound = s.isBound == true, itemID = s.itemID, stackCount = 1 }
end

-- Blizzard Lua (Blizzard_ObjectAPI/Mainline/ItemLocation.lua): fields bagID,
-- slotIndex, equipmentSlotIndex and the accessor methods Glass Gear calls.
local ItemLocationMixin = {}
ItemLocationMixin.__index = ItemLocationMixin
function ItemLocationMixin:GetBagAndSlot() return self.bagID, self.slotIndex end
function ItemLocationMixin:IsBagAndSlot() return self.bagID ~= nil and self.slotIndex ~= nil end
function ItemLocationMixin:GetEquipmentSlot() return self.equipmentSlotIndex end
function ItemLocationMixin:IsEquipmentSlot() return self.equipmentSlotIndex ~= nil end
ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot) return setmetatable({ bagID = bag, slotIndex = slot }, ItemLocationMixin) end,
    CreateFromEquipmentSlot = function(_, s) return setmetatable({ equipmentSlotIndex = s }, ItemLocationMixin) end,
}

Settings = {                                                                                            -- 28257, 28260
    RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end,
    RegisterAddOnCategory = function(c) WoW.settingsCategories[#WoW.settingsCategories + 1] = c end,
}

DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) WoW.chatLines[#WoW.chatLines + 1] = msg end }
SlashCmdList = {}

------------------------------------------------------------
-- Load the addon in TOC order (Libs\ lines skipped: LibGlass is optional
-- for the WoW Forever look), then ADDON_LOADED and PLAYER_LOGIN.
------------------------------------------------------------
function WoW.loadAddon(opts)
    opts = opts or {}
    local toc = assert(io.open("GlassGear.toc", "rb")):read("*a"):gsub("\r\n", "\n")
    for line in (toc .. "\n"):gmatch("([^\n]*)\n") do
        local file = line:match("^%s*([^#%s].-)%s*$")
        if file and not file:match("^Libs\\") then dofile((file:gsub("\\", "/"))) end
    end
    if opts.db then GlassGearDB = opts.db end
    if opts.charDB then GlassGearChar = opts.charDB end
    WoW.fire("ADDON_LOADED", "GlassGear")
    if not opts.noLogin then WoW.fire("PLAYER_LOGIN") end
    WoW.flush()
    return GlassGear
end

WoW.reset()

-- Every global defined above, by identity: test_load fails if the addon
-- replaces one (assigning an existing key never reaches __newindex).
local protected = {}
for k, v in pairs(_G) do protected[k] = v end
function WoW.replacedGlobals()
    local out = {}
    for k, v in pairs(protected) do
        if k ~= "WoW" and rawget(_G, k) ~= v then out[#out + 1] = k end
    end
    table.sort(out)
    return out
end

-- Strict globals from here on.
setmetatable(_G, {
    __index = function(_, k)
        if OWN_GLOBALS[k] then return nil end
        error("undefined global read: " .. tostring(k), 2)
    end,
    __newindex = function(t, k, v)
        if not OWN_GLOBALS[k] then WoW.globalWrites[k] = true end
        rawset(t, k, v)
    end,
})
