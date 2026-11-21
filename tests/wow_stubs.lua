------------------------------------------------------------
-- wow_stubs.lua - the WoW: Forever surface Glass Gear calls, so the addon
-- loads and runs under stock Lua 5.1. Drive it through `WoW`:
--
--     dofile("tests/wow_stubs.lua")      -- FIRST, in every test file that loads the addon
--     local H = dofile("tests/harness.lua")
--     WoW.items[19019] = { name = "...", equipLoc = "INVTYPE_WEAPON", ... }
--     WoW.loadAddon()                    -- TOC order, ADDON_LOADED, PLAYER_LOGIN
--
-- The mechanics are WowTestKit's (tests/kit.lua, at the commit and build
-- tests/kit.pin names): widgets that record every method called
-- (Kit.checkMethods), events checked against the build, strict globals,
-- timers and the clock (WoW.now, WoW.flushTimers), WoW.fire, WoW.tick,
-- print (WoW.chat) and check / eq / done. This file adds Glass Gear's own
-- client APIs, the templates it uses, and its drivers. Every name here is in
-- the API dump References/Forever/api/forever-api-1.60.1.70888.md (or
-- Blizzard's Lua in wow-ui-source for ItemLocation, DEFAULT_CHAT_FRAME,
-- SlashCmdList and the templates).
--   * Reading a global nobody defines is an error (Kit.strict, last line),
--     except the addon's own declared globals.
--   * Writing a global other than the addon's own is recorded in
--     WoW.globalWrites; test_load fails on anything undeclared.
-- Never add something because a test failed; confirm it exists first.
------------------------------------------------------------

dofile("tests/kit.lua")
local Methods = WoW.Methods

local OWN_GLOBALS = { GlassGear = true, GlassGearDB = true, GlassGearChar = true,
    SLASH_GLASSGEAR1 = true, SLASH_GLASSGEAR2 = true }

UISpecialFrames = {}      -- Blizzard's Escape list (addons append entries to it)    -- FrameXML

-- Glass Gear's state; the kit's own (frames, chat, timers, combat, locale)
-- is cleared by WoW.reset before this runs.
local function reset()
    WoW.now = 1000        -- GetTime(); the tests' times are relative to it
    WoW.epoch = 1793500000
    WoW.globalWrites = {}
    WoW.errors = {}       -- errors caught by xpcall (geterrorhandler)
    WoW.itemRequests = {}
    WoW.player = { name = "Karuzo", realm = "", class = "PRIEST", className = "Priest",
        level = 60, faction = "Alliance", guid = "Player-1-0000AAAA", dualWield = false }
    WoW.specGroup = 1
    WoW.numSpecGroups = 2   -- GetNumSpecGroups (1 without dual spec)
    WoW.loadedAddOns = {}   -- C_AddOns.IsAddOnLoaded
    WoW.items = {}        -- [itemID] = { name, equipLoc, classID, subclassID, minLevel, bindType, setID, stats, spell, unique = {cat,max} }
    WoW.cacheMiss = {}    -- [itemID] = true -> GetItemInfo / GetItemStats return nothing
    WoW.statsMiss = {}    -- [itemID] = true -> only GetItemStats returns nothing (name known, stats not)
    WoW.equipped = {}     -- [slot] = itemID
    WoW.bags = {}         -- [bag] = { [slot] = { itemID, isBound, guid, enchant } }
    WoW.sets = {}         -- [setID] = { name, items = { [slot] = itemID | 0 | -1 }, ignored = { [slot] = true }, specGroup }
    WoW.settingsCategories = {}
    WoW.postCalls = {}    -- [tooltip data type] = { fn, ... } (TooltipDataProcessor)
    WoW.keys = {}         -- { CTRL = true, ALT = true } held modifiers
    WoW.focus = nil       -- the edit box with keyboard focus
    for i = #UISpecialFrames, 1, -1 do UISpecialFrames[i] = nil end
    WoW.atlases = { ["bags-greenarrow"] = true }
    WoW.missingTemplates = {}
    WoW.openedCategory = nil
    WoW.loot = {}         -- [lootSlot] = { itemID = n } | { money = true }
    WoW.rolls = {}        -- [rollID] = itemID
    if WoW.makeBagFrames then WoW.makeBagFrames() end
    if WoW.makeLootFrames then WoW.makeLootFrames() end
end
table.insert(WoW.onReset, reset)

-- The player types into an edit box: focus, text (OnTextChanged with
-- userInput true, as typing fires it), then Enter. Typing stops at the box's
-- SetMaxLetters.
function WoW.type(box, text, enter)
    box:SetFocus()
    text = tostring(text)
    if box._maxLetters and box._maxLetters > 0 and #text > box._maxLetters then text = text:sub(1, box._maxLetters) end
    box._text = text
    if box._scripts.OnTextChanged then box._scripts.OnTextChanged(box, true) end
    if enter ~= false and box._scripts.OnEnterPressed then box._scripts.OnEnterPressed(box) end
end

function WoW.link(itemID, enchant)
    local it = WoW.items[itemID] or {}
    return string.format("|cff0070dd|Hitem:%d:%d:0:0:0:0:0:0|h[%s]|h|r", itemID, enchant or 0, it.name or "?")
end

local function idOf(info)
    if type(info) == "number" then return info end
    if type(info) == "string" then return tonumber(info:match("item:(%d+)")) end
end

-- Timers: every C_Timer.After callback runs on WoW.flush(), whatever its
-- delay; one scheduled while flushing runs in the next round.
function WoW.flush(rounds)
    for _ = 1, rounds or 5 do
        if #WoW.timers == 0 then return end
        WoW.flushTimers()
    end
end

-- Everything the addon sent to the chat frame, as one string.
function WoW.chatText() return table.concat(WoW.chat, "\n") end

------------------------------------------------------------
-- Widgets: what the core doesn't have, and the templates
------------------------------------------------------------

-- Whether a frame was made in combat (the markers must never make one then).
-- A record for the tests, not a client field.
local coreCreateFrame = CreateFrame
function CreateFrame(...)
    local w = coreCreateFrame(...)
    w._madeInCombat = WoW.combat
    return w
end

-- What a Blizzard template adds that Glass Gear checks or uses.
-- WoW.missingTemplates[name] = true makes CreateFrame return a bare frame.
local function template(name, build)
    WoW.templates[name] = function(w, t)
        if not WoW.missingTemplates[name] then build(w, t) end
    end
end
-- Blizzard_SharedXML/Shared/Button/CheckButtonTemplates.xml (wow-ui-source
-- forever, 70959): UICheckButtonTemplate's $parentText (parentKey Text,
-- GameFontNormalSmall), which its OnLoad also sets as .text
-- (UICheckButtonFontString_SetParentKeyAlias, Mainline/SharedUIPanelTemplates.lua:1088);
-- UIRadioButtonTemplate's (parentKey text). Their state textures aren't modelled.
template("UICheckButtonTemplate", function(w)
    w.Text = Methods.CreateFontString(w, nil, "ARTWORK", "GameFontNormalSmall")
    w.text = w.Text
end)
template("UIRadioButtonTemplate", function(w)
    w.text = Methods.CreateFontString(w, nil, "BACKGROUND", "GameFontNormalSmall")
end)
-- UIPanelButtonNoTooltipTemplate's ButtonText, parentKey Text
-- (Blizzard_SharedXML/SecureUIPanelTemplates.xml:39).
template("UIPanelButtonTemplate", function(w)
    w.Text = Methods.CreateFontString(w, nil, "ARTWORK", "GameFontNormal")
end)
-- The core's scroll frame (ScrollBar and its buttons), behind the switch.
local coreScroll = WoW.templates.UIPanelScrollFrameTemplate
template("UIPanelScrollFrameTemplate", coreScroll)
-- BackdropTemplate's mixin (Blizzard_SharedXML/Backdrop.xml:5, mixin
-- BackdropTemplateMixin, Backdrop.lua:336, 406, 429). A mixin is copied onto
-- the frame, so only frames made with the template have these, and the
-- addon's `if f.SetBackdrop` reads nil on the others, as on the client. Each
-- call is recorded as Frame:<name>; test_methods allows the three.
template("BackdropTemplate", function(w)
    local function mixin(name, fn)
        w[name] = function(self, ...)
            WoW.methodsCalled[self._type .. ":" .. name] = true
            return fn(self, ...)
        end
    end
    mixin("SetBackdrop", function(self, b) self._backdrop = b end)
    mixin("SetBackdropColor", function(self, r, g, b, a) self._backdropColor = { r, g, b, a } end)
    mixin("SetBackdropBorderColor", function(self, r, g, b, a) self._backdropBorderColor = { r, g, b, a } end)
end)
-- InputBoxTemplate is not modelled (its Left/Right/Middle textures): an edit
-- box made with it is a bare EditBox here, and the addon draws its own.

-- FontString (each in the dump's SimpleFontStringAPI). A wrapped string's
-- height isn't laid out here: one line.
function Methods.GetStringHeight() return 14 end
function Methods.SetJustifyH(fs, j) fs._justifyH = j end

-- ScrollFrame (SimpleScrollFrameAPI): nothing scrolls here.
function Methods.SetScrollChild(sf, c) sf._scrollChild = c end
function Methods.GetVerticalScrollRange() return 0 end
function Methods.GetVerticalScroll() return 0 end

-- EditBox (SimpleEditBoxAPI). Keyboard focus is WoW.focus.
function Methods.SetMultiLine(eb, v) eb._multiLine = v end
function Methods.SetMaxLetters(eb, n) eb._maxLetters = n end
function Methods.HighlightText(eb, from, to) eb._highlighted = not (from == 0 and to == 0) end
function Methods.SetFocus(eb)
    if WoW.focus == eb then return end
    if type(WoW.focus) == "table" then Methods.ClearFocus(WoW.focus) end
    WoW.focus = eb
    if eb._scripts.OnEditFocusGained then eb._scripts.OnEditFocusGained(eb) end
end
function Methods.ClearFocus(eb)
    if WoW.focus ~= eb then return end
    WoW.focus = nil
    if eb._scripts.OnEditFocusLost then eb._scripts.OnEditFocusLost(eb) end
end
function Methods.HasFocus(eb) return WoW.focus == eb end

-- WowTestKit #87: a click on a CheckButton toggles its checked state before
-- its OnClick runs, which reads the new state (Blizzard_GlueXML/Mainline/
-- CinematicsMenu.lua:276, wow-ui-source forever 70959). The core's Click
-- doesn't toggle; the options tests click check and radio buttons.
function Methods.Click(b, button, down)
    if b._disabled then return end
    if b._type == "CheckButton" then b._checked = not b._checked end
    WoW.click(b, button, down)
end

-- Frame (SimpleFrameAPI): moving is the player's drag; nothing moves here.
function Methods.SetMovable(f, v) f._movable = v end
function Methods.StartMoving(f) f._moving = true end
function Methods.StopMovingOrSizing(f) f._moving = false end

------------------------------------------------------------
-- API surface (dump line numbers in comments)
------------------------------------------------------------
function time() return WoW.epoch end
function GetBuildInfo() return "1.60.1", "70888", "Nov  9 2026", 16001 end    -- 4726
function geterrorhandler() return function(e) WoW.errors[#WoW.errors + 1] = e end end

function UnitName(u) if u == "player" then return WoW.player.name end end
function UnitClass(u) if u == "player" then return WoW.player.className, WoW.player.class, 5 end end   -- 6422
function UnitGUID(u) if u == "player" then return WoW.player.guid end end                             -- 6441
function UnitLevel(u) if u == "player" then return WoW.player.level end end                           -- 6521
function UnitFactionGroup(u) if u == "player" then return WoW.player.faction, WoW.player.faction end end -- 6439
-- WoW.player.realm is "": Forever hides the realm since the 2026-11-20 hotfix (#88).
function GetRealmName() return WoW.player.realm end                                                    -- 5160
function CanDualWield() return WoW.player.dualWield end                                                -- 4461
function GetInventoryItemLink(unit, slot)                                                              -- 19226
    local id = unit == "player" and WoW.equipped[slot]
    return id and WoW.link(id) or nil
end

C_AddOns = { IsAddOnLoaded = function(name) return WoW.loadedAddOns[name] == true, WoW.loadedAddOns[name] == true end }  -- 198
function GetNumSpecGroups() return WoW.numSpecGroups end                                     -- 19269 (undocumented)
C_SpecializationInfo = { GetActiveSpecGroup = function() return WoW.specGroup end }                   -- 3494
C_SpellBook = { IsSpellKnown = function() return false end }                                          -- 3638

C_Item = {}
function C_Item.GetItemInfoInstant(info)                                                               -- 2247
    local id = idOf(info)
    local it = id and WoW.items[id]
    if not it then return nil end
    return id, "Armor", "Cloth", it.equipLoc, 0, it.classID, it.subclassID
end
function C_Item.GetItemInfo(info)                                                                      -- 2246
    local id = idOf(info)
    local it = id and WoW.items[id]
    if not it or WoW.cacheMiss[id] then return nil end
    return it.name, WoW.link(id), 3, 60, it.minLevel or 1, "Armor", "Cloth", 1, it.equipLoc, 0, 0,
        it.classID, it.subclassID, it.bindType or 1, 0, it.setID, false, ""
end
function C_Item.GetItemStats(link)                                                                     -- 2269
    local id = idOf(link)
    local it = id and WoW.items[id]
    if not it or WoW.cacheMiss[id] or WoW.statsMiss[id] then return nil end
    local copy = {}
    for k, v in pairs(it.stats or {}) do copy[k] = v end
    return copy
end
function C_Item.GetItemSpell(info)                                                                     -- 2267
    local it = WoW.items[idOf(info) or 0]
    if it and it.spell then return it.spell, 1 end
    return nil
end
function C_Item.GetItemUniqueness(info)                                                                -- 2271
    local it = WoW.items[idOf(info) or 0]
    if it and it.unique then return it.unique.cat, it.unique.max end
    return 0, 0
end
function C_Item.RequestLoadItemDataByID(info) WoW.itemRequests[#WoW.itemRequests + 1] = idOf(info) end  -- 2318
function C_Item.DoesItemExist(loc)                                                                     -- 2213
    local b = WoW.bags[loc.bagID]
    return b ~= nil and b[loc.slotIndex] ~= nil
end
function C_Item.GetItemGUID(loc) return WoW.bags[loc.bagID][loc.slotIndex].guid end                   -- 2238
function C_Item.GetItemLinkByGUID(guid)                                                                -- 2254
    for _, b in pairs(WoW.bags) do
        for _, s in pairs(b) do if s.guid == guid then return WoW.link(s.itemID) end end
    end
end

function IsControlKeyDown() return WoW.keys.CTRL == true end                                          -- 5450
function IsAltKeyDown() return WoW.keys.ALT == true end                                                 -- 5435
function GetCurrentKeyBoardFocus() return WoW.focus end                                                 -- 19064
C_Texture = {                                                                                          -- 3752, 3754
    GetAtlasExists = function(name) return WoW.atlases[name] == true end,
    GetAtlasInfo = function(name) if WoW.atlases[name] then return { width = 16 } end end,
}

C_Container = {}
function C_Container.GetContainerNumSlots(bag)                                                         -- 1179
    local n = 0
    for slot in pairs(WoW.bags[bag] or {}) do if slot > n then n = slot end end
    return n
end

-- Equipment sets (dump 1560-1579; EquipmentManagerDocumentation.lua).
C_EquipmentSet = {
    GetEquipmentSetIDs = function()                                                                     -- 1571
        local ids = {}
        for id in pairs(WoW.sets) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end,
    GetEquipmentSetInfo = function(id)                                                                  -- 1572
        local set = WoW.sets[id]
        if set then return set.name, 0, id, false, 0, 0, 0, 0, 0 end
    end,
    GetItemIDs = function(id)                                                                           -- 1574
        local set = WoW.sets[id]
        if not set then return nil end
        local out = {}
        for k, v in pairs(set.items or {}) do out[k] = v end
        return out
    end,
    GetIgnoredSlots = function(id)                                                                      -- 1573
        local set = WoW.sets[id]
        local out = {}
        for k, v in pairs(set and set.ignored or {}) do out[k] = v end
        return out
    end,
    GetEquipmentSetForSpec = function(group)                                                            -- 1569
        for id, set in pairs(WoW.sets) do if set.specGroup == group then return id end end
        return nil
    end,
}
function C_Container.GetContainerItemID(bag, slot)                                                     -- 1171
    local b = WoW.bags[bag]
    return b and b[slot] and b[slot].itemID or nil
end
function C_Container.GetContainerItemInfo(bag, slot)                                                   -- 1172
    local b = WoW.bags[bag]
    local s = b and b[slot]
    if not s then return nil end
    return { hyperlink = WoW.link(s.itemID, s.enchant), isBound = s.isBound == true, itemID = s.itemID, stackCount = 1 }
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
    RegisterCanvasLayoutCategory = function(frame, name)
        return { frame = frame, name = name, GetID = function() return name end }
    end,
    RegisterAddOnCategory = function(c) WoW.settingsCategories[#WoW.settingsCategories + 1] = c end,
    -- Blizzard Lua (Blizzard_Settings_Shared): shows the category's canvas frame.
    OpenToCategory = function(id)
        for _, c in ipairs(WoW.settingsCategories) do
            if c:GetID() == id then WoW.openedCategory = id; c.frame:Show(); return true end
        end
        return false
    end,
}
GameTooltip = {                                                                                         -- GameTooltip.xml
    SetOwner = function() end, SetText = function() end, Show = function() end, Hide = function() end,
}

-- Generated API docs (TooltipInfoSharedDocumentation.lua:89-96) and Blizzard
-- Lua (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:199).
Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2 },
    LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 } }      -- LootConstantsDocumentation.lua:41-44

function GetLootSlotType(slot)                                                                          -- 19306
    local s = WoW.loot[slot]
    if not s then return Enum.LootSlotType.None end
    return s.money and Enum.LootSlotType.Money or Enum.LootSlotType.Item
end
function GetLootSlotLink(slot)                                                                          -- 19305
    local s = WoW.loot[slot]
    return s and s.itemID and WoW.link(s.itemID) or nil
end
function GetLootRollItemLink(rollID)                                                                    -- 19302
    local id = WoW.rolls[rollID]
    return id and WoW.link(id) or nil
end
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn)
        WoW.postCalls[kind] = WoW.postCalls[kind] or {}
        table.insert(WoW.postCalls[kind], fn)
    end,
}

-- A GameTooltip with the widget methods Glass Gear calls. Lines are recorded.
function WoW.newTooltip(name)
    local t = { name = name, lines = {}, shown = false, forbidden = false, refreshes = 0 }
    function t:GetName() return self.name end
    function t:IsForbidden() return self.forbidden end
    function t:IsShown() return self.shown end
    function t:GetOwner() return self.owner end
    function t:GetPrimaryTooltipData() return self.data end
    function t:AddLine(text, r, g, b) self.lines[#self.lines + 1] = { left = text, lc = { r, g, b } } end
    function t:AddDoubleLine(l, rt, lr, lg, lb, rr, rg, rb)
        self.lines[#self.lines + 1] = { left = l, right = rt, lc = { lr, lg, lb }, rc = { rr, rg, rb } }
    end
    function t:RefreshData() self.refreshes = self.refreshes + 1; WoW.showItem(self, self.data, self.owner) end
    function t:Hide() self.shown = false end
    return t
end

-- Show an item tooltip: Blizzard sets the lines, then runs the post-calls.
function WoW.showItem(tooltip, data, owner)
    tooltip.lines, tooltip.data, tooltip.owner, tooltip.shown = { { left = "item lines" } }, data, owner, true
    for _, fn in ipairs(WoW.postCalls[Enum.TooltipDataType.Item] or {}) do fn(tooltip, data) end
end

-- A Blizzard bag item button (ContainerFrameItemButton: GetBagID, GetID).
function WoW.bagButton(bag, slot, updates)
    local b = { bag = bag, slot = slot }
    function b:GetBagID() return self.bag end
    function b:GetID() return self.slot end
    if updates then function b:UpdateTooltip() end end
    return b
end

-- Blizzard's bag frames (Mainline/ContainerFrame.xml:229-231: ContainerFrameContainer
-- and its ContainerFrames; ContainerFrameCombinedBags), UpdateItems (:1191) walking
-- EnumerateValidItems (:575), item buttons with GetBagID (:1830) and GetID.
local function newBagFrame(name)
    local f = CreateFrame("Frame", name)
    WoW.setShown(f, false)
    f.Items, f._size = {}, 0
    f.EnumerateValidItems = function(self)
        local i = 0
        return function()
            i = i + 1
            if i <= self._size then return i, self.Items[i] end
        end
    end
    f.UpdateItems = function() end
    return f
end
-- Fresh, unhooked bag frames on every WoW.reset() (a reloaded addon hooks anew).
function WoW.makeBagFrames()
    local container = { ContainerFrames = {} }
    -- The same frames are the ContainerFrame1..N globals (ContainerFrame.lua:141).
    for i = 1, 6 do
        container.ContainerFrames[i] = newBagFrame("ContainerFrame" .. i)
    end
    rawset(_G, "ContainerFrameContainer", container)
    newBagFrame("ContainerFrameCombinedBags")
end
-- Show `frame` holding `slots` ({ {bag, slot}, ... }, pooled buttons reused in
-- order), then run its UpdateItems as Blizzard does.
function WoW.showBag(frame, slots)
    for i, sl in ipairs(slots) do
        local b = frame.Items[i] or CreateFrame("Button", nil, frame)
        frame.Items[i] = b
        b._bag = sl[1]
        b.GetBagID = function(self) return self._bag end
        b:SetID(sl[2])
    end
    frame._size = #slots
    frame:Show()
    frame:UpdateItems()
end

-- Blizzard's loot UI on Forever (Mainline): LootFrame with a ScrollBox of pooled
-- elements (LootFrame.lua:74-96; GetSlotIndex :433, icon button .Item), the
-- ScrollBox OnInitializedFrame event (ScrollBox.lua:744) and
-- ScrollUtil.AddInitializedFrameCallback (ScrollUtil.lua:21); GroupLootFrame1..4
-- (GroupLootFrame.xml:641-644) with rollID and the .IconFrame button.
ScrollBoxListMixin = { Event = { OnInitializedFrame = "OnInitializedFrame" } }
ScrollUtil = {
    AddInitializedFrameCallback = function(scrollBox, callback, owner, iterateExisting)
        if iterateExisting then scrollBox:ForEachFrame(callback) end
        scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, function(o, frame, data)
            callback(o, frame, data)
        end, owner)
    end,
}
function WoW.makeLootFrames()
    local lf = CreateFrame("Frame", "LootFrame")
    WoW.setShown(lf, false)
    local sb = { _callbacks = {}, _frames = {}, _size = 0 }
    function sb:RegisterCallback(event, fn, owner)
        self._callbacks[event] = self._callbacks[event] or {}
        table.insert(self._callbacks[event], { fn = fn, owner = owner })
    end
    function sb:ForEachFrame(fn)
        for i = 1, self._size do fn(self._frames[i], { slotIndex = self._frames[i]._slot }) end
    end
    lf.ScrollBox = sb
    for i = 1, 4 do
        local f = CreateFrame("Frame", "GroupLootFrame" .. i)
        WoW.setShown(f, false)
        f.IconFrame = CreateFrame("Button", nil, f)
    end
end
-- Open the loot window on `slots` (loot slot indices), as LootFrame:Open does:
-- the elements are (re)initialised, then the frame shows.
function WoW.openLoot(slots)
    local lf = LootFrame
    local sb = lf.ScrollBox
    for i, slot in ipairs(slots) do
        local money = WoW.loot[slot] and WoW.loot[slot].money
        local el = sb._frames[i]
        if not el or (el.Item == nil) ~= (money == true) then
            el = CreateFrame("Frame", nil, lf)
            if not money then el.Item = CreateFrame("Button", nil, el) end
            el.GetSlotIndex = function(self) return self._slot end
            sb._frames[i] = el
        end
        el._slot = slot
        el:Show()
    end
    sb._size = #slots
    for i = 1, sb._size do
        for _, cb in ipairs(sb._callbacks.OnInitializedFrame or {}) do
            cb.fn(cb.owner, sb._frames[i], { slotIndex = sb._frames[i]._slot })
        end
    end
    lf:Show()
end
function WoW.closeLoot()
    LootFrame:Hide()
    LootFrame.ScrollBox._size = 0
end
-- A group roll in roll frame i (GroupLootContainer_OpenNewFrame sets rollID, then shows).
function WoW.startRoll(i, rollID)
    local f = _G["GroupLootFrame" .. i]
    f.rollID = rollID
    f:Hide()
    f:Show()
end

-- Every line the addon writes to chat goes through the kit's print: in
-- WoW.chat, and checked for a stray "|" by done().
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) print(msg) end }
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
        if file and not file:match("^Libs\\") then
            dofile((file:gsub("\\", "/")))
            if opts.afterFile then opts.afterFile(file) end   -- e.g. a test locale after Core\Locale.lua
        end
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

-- Strict globals from here on; a write of a global other than the addon's
-- own is recorded (the kit's strict reads only).
Kit.strict(OWN_GLOBALS)
getmetatable(_G).__newindex = function(t, k, v)
    if not OWN_GLOBALS[k] then WoW.globalWrites[k] = true end
    rawset(t, k, v)
end
