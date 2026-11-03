------------------------------------------------------------
-- test_bag_addons.lua - GG-401: markers on Bagnon's buttons. A fake
-- BagBrother shaped like the reference (Bagnon 12.1.7: Item:Update, a
-- ContainerItem whose Update calls it, button.bag + GetID, IsCached,
-- button.frame): green / amber / nothing as on Blizzard's bags, never on a
-- cached view (another character), following the reveal key and arriving
-- item data; /gg names the bag addon, and an unsupported one is reported.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local INT, HEAL = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT"
local function shoulder(name, stats) return { name = name, equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = stats } end
WoW.items[50] = shoulder("Old Mantle", { [INT] = 10 })
WoW.items[60] = shoulder("Big Mantle", { [INT] = 30 })
WoW.items[70] = shoulder("Healer Mantle", { [HEAL] = 30 })
WoW.equipped[3] = 50
WoW.bags[0] = { [1] = { itemID = 60, isBound = true }, [2] = { itemID = 70, isBound = true } }

-- The fake BagBrother (class methods resolved at call time, as Bagnon's).
local Item = {}
function Item.Update(self, info) self.info = info or {} end
local ContainerItem = {}
function ContainerItem.Update(self, ...) Item.Update(self, ...); self.cooldownUpdated = true end
local GuildItem = {}                          -- a guild-bank button: its "bag" is a tab
function GuildItem.Update(self, ...) Item.Update(self, ...) end
rawset(_G, "BagBrother", { Item = Item, ContainerItem = ContainerItem, GuildItem = GuildItem })
WoW.loadedAddOns.Bagnon = true
local bagFrame = CreateFrame("Frame")
local function button(bag, slot, cached)
    local b = CreateFrame("Button", nil, bagFrame)
    b.bag = bag
    b:SetID(slot)
    function b:GetBag() return self.bag end
    function b:IsCached() return cached == true end
    b.frame = bagFrame
    return b
end

local GG = WoW.loadAddon()
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1 )')
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy": Class=Priest, Healing=1 )')
WoW.flush()
local function mark(b)
    local m = GG.BagMarkers._marks[b]
    return m and m:IsShown() and m.kind or nil
end

H.eq(GG.BagAddons.active, "Bagnon", "Bagnon detected and hooked at login")
SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("bag addon: Bagnon (markers on its buttons)", 1, true) ~= nil, "/gg names it")

local up, off = button(0, 1), button(0, 2)
local contexts = 0
local realContext = GG.BagMarkers.Context
GG.BagMarkers.Context = function(...) contexts = contexts + 1; return realContext(...) end
WoW.time = WoW.time + 1
ContainerItem.Update(up)
ContainerItem.Update(off)
H.eq(contexts, 1, "two buttons updated in one frame: one context")
GG.BagMarkers.Context = realContext
WoW.flush(1)                                  -- the window becomes a reveal surface on the next frame
H.eq(mark(up), "green", "a Bagnon button with a current-spec upgrade: green")
H.eq(off.cooldownUpdated, true, "...Bagnon's own update still runs")
H.eq(mark(off), nil, "a soulbound off-spec upgrade: quiet, as on Blizzard's bags")
H.eq(GG.BagMarkers._marks[up].parent, up, "...the mark is our own child frame")
H.eq(GG.Reveal._surfaces[bagFrame], true, "Bagnon's open window is a reveal surface (the key is polled while it shows)")
bagFrame:Hide()
H.eq(GG.Reveal._surfaces[bagFrame], nil, "...closed: not any more")
bagFrame:Show()

-- The reveal key shows the off-spec upgrade.
WoW.keys.CTRL = true
WoW.fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
WoW.flush()
H.eq(mark(off), "amber", "Ctrl held: the off-spec upgrade shows amber on Bagnon too")
WoW.keys.CTRL = nil
WoW.fire("MODIFIER_STATE_CHANGED", "LCTRL", 0)
WoW.flush()
H.eq(mark(off), nil, "...released: gone")

-- A cached view (another character's bags) is never decorated.
local other = button(0, 1, true)
ContainerItem.Update(other)
H.eq(mark(other), nil, "a cached inventory (another character): no mark")
local switching = button(0, 1)
ContainerItem.Update(switching)
H.eq(mark(switching), "green", "(a marked button)")
function switching:IsCached() return true end   -- the player picked another character in Bagnon
ContainerItem.Update(switching)
H.eq(mark(switching), nil, "...switched to a cached view: its mark is cleared")

-- Guild-bank buttons are never hooked (their bag is a tab, not the player's bag).
WoW.bags[2] = { [1] = { itemID = 60, isBound = true } }   -- the player's own bag 2 holds an upgrade
local guild = button(2, 1)
GuildItem.Update(guild)
H.eq(GG.BagMarkers._marks[guild], nil, "a guild-bank button: no mark from the player's bags")

-- A button first met in combat is marked after it, from its own bag and slot.
WoW.combat = true
local fought = button(0, 1)
fought.GetBagID = function() return 3 end      -- Blizzard's template reader would say bag 3
ContainerItem.Update(fought)
H.eq(GG.BagMarkers._marks[fought], nil, "in combat: no frame made")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
H.eq(mark(fought), "green", "after combat: marked from Bagnon's bag and slot (0, 1), not GetBagID")

-- A closed Bagnon window isn't redrawn.
local decorations = 0
local realDecorate = GG.BagMarkers.Decorate
GG.BagMarkers.Decorate = function(...) decorations = decorations + 1; return realDecorate(...) end
bagFrame:Hide()
GG.BagAddons.Refresh()
H.eq(decorations, 0, "a closed window: its buttons aren't redrawn")
bagFrame:Show()
GG.BagAddons.Refresh()
H.check(decorations > 0, "...open again: they are")
GG.BagMarkers.Decorate = realDecorate

-- Item data arriving redraws.
WoW.items[80] = shoulder("Late Mantle", { [INT] = 40 })
WoW.cacheMiss[80] = true
WoW.bags[0][3] = { itemID = 80, isBound = true }
local late = button(0, 3)
ContainerItem.Update(late)
H.eq(mark(late), nil, "data still loading: no mark yet")
WoW.cacheMiss[80] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 80, true)
WoW.flush()
H.eq(mark(late), "green", "...then green without another Bagnon update")

-- A pooled button reused for another slot follows it.
WoW.bags[0][4] = { itemID = 50, isBound = true }
up:SetID(4)
ContainerItem.Update(up)
H.eq(mark(up), nil, "a button reused for a slot with no upgrade: cleared")

-- A hook that failed is never reported as working.
GG.BagAddons.active = nil
H.check(GG.BagAddons.Status():find("hook failed", 1, true) ~= nil, "a failed hook: /gg says the markers are unavailable")
GG.BagAddons.active = "Bagnon"
WoW.loadedAddOns.Bagnon = nil
H.eq(GG.BagAddons.Detect(), "BagBrother", "BagBrother with another frontend: named as BagBrother, not Bagnon")
WoW.loadedAddOns.Bagnon = true

-- Unsupported bag addons are reported.
rawset(_G, "BagBrother", nil)
WoW.loadedAddOns.AdiBags = true
H.eq(GG.BagAddons.Status(), "bag addon: AdiBags - markers unavailable there (tooltips work)", "AdiBags: reported, not hooked")
WoW.loadedAddOns.AdiBags = nil
H.eq(GG.BagAddons.Status(), "bag addon: none (Blizzard's bags)", "none: Blizzard's bags")

H.eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
H.done("test_bag_addons")
