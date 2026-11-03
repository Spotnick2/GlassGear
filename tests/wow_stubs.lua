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
    WoW.postCalls = {}    -- [tooltip data type] = { fn, ... } (TooltipDataProcessor)
    WoW.keys = {}         -- { CTRL = true, ALT = true } held modifiers
    WoW.focus = nil       -- the edit box with keyboard focus
    WoW.combat = false
    WoW.atlases = { ["bags-greenarrow"] = true }
    WoW.missingTemplates = {}
    WoW.openedCategory = nil
    WoW.loot = {}         -- [lootSlot] = { itemID = n } | { money = true }
    WoW.rolls = {}        -- [rollID] = itemID
    if WoW.makeBagFrames then WoW.makeBagFrames() end
    if WoW.makeLootFrames then WoW.makeLootFrames() end
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
    local fs = { shown = true }
    function fs:SetPoint() end
    function fs:SetText(t) self.text = t end
    function fs:GetText() return self.text end
    function fs:SetJustifyH() end
    function fs:SetWidth() end
    function fs:GetStringHeight() return 14 end
    function fs:SetTextColor(r, g, b) self.color = { r, g, b } end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    return fs
end

local function newTexture()
    local t = { shown = true }
    function t:SetAllPoints() end
    function t:SetPoint() end
    function t:SetAtlas(a) self.atlas = a end
    function t:SetDesaturated(d) self.desaturated = d end
    function t:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
    function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    function t:SetSize() end
    function t:SetHeight() end
    function t:SetTexture(p) self.texture = p end
    function t:SetTexCoord() end
    return t
end

-- What a Blizzard template adds that Glass Gear checks or uses (UICheckButtonTemplate
-- and UIRadioButtonTemplate: .text; UIPanelButtonTemplate: .Text; UIPanelScrollFrameTemplate:
-- .ScrollBar). WoW.missingTemplates[name] = true makes CreateFrame return a bare frame.
local TEMPLATE_FIELDS = {
    UICheckButtonTemplate = "text", UIRadioButtonTemplate = "text",
    UIPanelButtonTemplate = "Text", UIPanelScrollFrameTemplate = "ScrollBar",
}

function CreateFrame(kind, name, parent, template)
    local f = { _events = {}, _scripts = {}, _hooks = {}, kind = kind, name = name, parent = parent,
        shown = true, inCombatCreate = WoW.combat, template = template, enabled = true, alpha = 1 }
    local field = template and TEMPLATE_FIELDS[template]
    if field and not WoW.missingTemplates[template] then f[field] = field == "ScrollBar" and {} or newFontString() end
    function f:RegisterEvent(e) self._events[e] = true end
    function f:UnregisterEvent(e) self._events[e] = nil end
    function f:SetScript(s, fn) self._scripts[s] = fn end
    function f:GetScript(s) return self._scripts[s] end
    function f:HookScript(s, fn)
        self._hooks[s] = self._hooks[s] or {}
        table.insert(self._hooks[s], fn)
    end
    function f:CreateFontString()
        local fs = newFontString()
        self._fs = self._fs or {}
        self._fs[#self._fs + 1] = fs
        return fs
    end
    function f:CreateTexture() return newTexture() end
    function f:SetSize() end
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:SetParent(p) self.parent = p end
    function f:GetParent() return self.parent end
    function f:EnableMouse() end
    function f:SetID(id) self._id = id end
    function f:GetID() return self._id end
    function f:IsShown() return self.shown end
    function f:Show()
        local was = self.shown
        self.shown = true
        if not was then
            if self._scripts.OnShow then self._scripts.OnShow(self) end
            for _, fn in ipairs(self._hooks.OnShow or {}) do fn(self) end
        end
    end
    function f:Hide()
        local was = self.shown
        self.shown = false
        if was then
            if self._scripts.OnHide then self._scripts.OnHide(self) end
            for _, fn in ipairs(self._hooks.OnHide or {}) do fn(self) end
        end
    end
    function f:SetShown(v) if v then self:Show() else self:Hide() end end
    -- Options page widgets (UI/Options.lua).
    function f:SetWidth() end
    function f:SetHeight(h) self.height = h end
    function f:SetAlpha(a) self.alpha = a end
    function f:SetEnabled(v) self.enabled = v and true or false end
    function f:IsEnabled() return self.enabled end
    function f:SetChecked(v) self.checked = v and true or false end
    function f:GetChecked() return self.checked == true end
    function f:SetText(t) self.label_text = t end
    function f:SetNormalTexture() end
    function f:SetPushedTexture() end
    function f:SetHighlightTexture() end
    function f:SetCheckedTexture() end
    function f:GetNormalTexture() return newTexture() end
    function f:GetCheckedTexture() return newTexture() end
    function f:GetHighlightTexture() return newTexture() end
    -- A click as the client does it: a check button toggles, then OnClick and hooks run.
    function f:Click()
        if not self.enabled then return end
        if self.kind == "CheckButton" then self.checked = not self.checked end
        if self._scripts.OnClick then self._scripts.OnClick(self, "LeftButton", false) end
    end
    function f:SetScrollChild(c) self.scrollChild = c end
    function f:EnableMouseWheel() end
    function f:GetVerticalScrollRange() return 0 end
    function f:GetVerticalScroll() return 0 end
    function f:SetVerticalScroll() end
    function f:SetOrientation() end
    function f:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
    function f:SetValueStep(s) self.step = s end
    function f:SetObeyStepOnDrag() end
    function f:SetThumbTexture() end
    function f:GetValue() return self.value end
    function f:SetValue(v)
        if self.min then v = math.max(self.min, math.min(self.max, v)) end
        self.value = v
        if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end
    end
    WoW.frames[#WoW.frames + 1] = f
    return f
end

-- Run every frame's OnUpdate for one frame of `dt` seconds.
function WoW.tick(dt)
    WoW.time = WoW.time + dt
    for _, f in ipairs(WoW.frames) do
        if f._scripts.OnUpdate then f._scripts.OnUpdate(f, dt) end
    end
end

-- The client's secure hook (wraps t[name]).
function hooksecurefunc(t, name, fn)                                                                   -- 22859
    if type(t) == "string" then t, name, fn = _G, t, name end
    local orig = t[name]
    rawset(t, name, function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end)
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
function C_Item.GetItemLinkByGUID(guid)                                                                -- 2251
    for _, b in pairs(WoW.bags) do
        for _, s in pairs(b) do if s.guid == guid then return WoW.link(s.itemID) end end
    end
end

function IsControlKeyDown() return WoW.keys.CTRL == true end                                          -- 5446
function IsAltKeyDown() return WoW.keys.ALT == true end                                                 -- 5431
function GetCurrentKeyBoardFocus() return WoW.focus end                                                 -- 18891
function InCombatLockdown() return WoW.combat end                                                       -- 19837
C_Texture = {                                                                                          -- 3752, 3754
    GetAtlasExists = function(name) return WoW.atlases[name] == true end,
    GetAtlasInfo = function(name) if WoW.atlases[name] then return { width = 16 } end end,
}

C_Container = {}
function C_Container.GetContainerItemID(bag, slot)                                                     -- 1169
    local b = WoW.bags[bag]
    return b and b[slot] and b[slot].itemID or nil
end
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

function GetLootSlotType(slot)                                                                          -- 19129
    local s = WoW.loot[slot]
    if not s then return Enum.LootSlotType.None end
    return s.money and Enum.LootSlotType.Money or Enum.LootSlotType.Item
end
function GetLootSlotLink(slot)                                                                          -- 19128
    local s = WoW.loot[slot]
    return s and s.itemID and WoW.link(s.itemID) or nil
end
function GetLootRollItemLink(rollID)                                                                    -- 19125
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
    f.shown = false
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
        rawset(_G, "ContainerFrame" .. i, container.ContainerFrames[i])
    end
    rawset(_G, "ContainerFrameContainer", container)
    rawset(_G, "ContainerFrameCombinedBags", newBagFrame("ContainerFrameCombinedBags"))
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
    lf.shown = false
    local sb = { _callbacks = {}, _frames = {}, _size = 0 }
    function sb:RegisterCallback(event, fn, owner)
        self._callbacks[event] = self._callbacks[event] or {}
        table.insert(self._callbacks[event], { fn = fn, owner = owner })
    end
    function sb:ForEachFrame(fn)
        for i = 1, self._size do fn(self._frames[i], { slotIndex = self._frames[i]._slot }) end
    end
    lf.ScrollBox = sb
    rawset(_G, "LootFrame", lf)
    for i = 1, 4 do
        local f = CreateFrame("Frame", "GroupLootFrame" .. i)
        f.shown = false
        f.IconFrame = CreateFrame("Button", nil, f)
        rawset(_G, "GroupLootFrame" .. i, f)
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
