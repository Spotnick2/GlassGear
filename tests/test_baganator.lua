------------------------------------------------------------
-- test_baganator.lua - GG-401: markers in Baganator. A fake Baganator
-- shaped like its public API (RegisterCornerWidget, IsCornerWidgetActive,
-- RequestItemButtonsRefresh; onInit once per button, the widget hidden on
-- every redraw, onUpdate(widget, details) -> shown). Green / amber /
-- nothing as on Blizzard's bags, never on another character's view, the
-- reveal key and arriving data ask Baganator for a widget refresh, and /gg
-- says where the mark is (or that the player removed it).
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

-- The fake Baganator.
local widgets, refreshes = {}, {}
local cornerOn = true
rawset(_G, "Baganator", {
    Constants = { RefreshReason = { ItemWidgets = "ItemWidgets", Searches = "Searches" } },
    API = {
        RegisterCornerWidget = function(label, id, onUpdate, onInit, defaultPosition, isFast)
            assert(id and label and onUpdate and onInit and not widgets[id])
            widgets[id] = { label = label, onUpdate = onUpdate, onInit = onInit, position = defaultPosition }
        end,
        IsCornerWidgetActive = function(id) return cornerOn and widgets[id] ~= nil end,
        RequestItemButtonsRefresh = function(reason) refreshes[#refreshes + 1] = reason or "all" end,
    },
})
WoW.loadedAddOns.Baganator = true
local window = CreateFrame("Frame", nil, UIParent)
local indexFrame = CreateFrame("Frame", nil, window)
local function newButton() return CreateFrame("Button", nil, indexFrame) end
-- What Baganator does on each redraw of a button.
local function redraw(button, details)
    local w = widgets.glassgear
    button.cornerPlugins = button.cornerPlugins or {}
    if not button.cornerPlugins.glassgear then button.cornerPlugins.glassgear = w.onInit(button) end
    local widget = button.cornerPlugins.glassgear
    widget:Hide()
    if w.onUpdate(widget, details) then widget:Show() end
    return widget
end
local function shown(widget) return widget:IsShown() and widget.kind or nil end
local function live(bag, slot, itemID) return { itemLink = WoW.link(itemID), itemID = itemID, itemLocation = { bagID = bag, slotIndex = slot } } end

local GG = WoW.loadAddon()
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1 )')
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy": Class=Priest, Healing=1 )')
WoW.flush()

H.eq(GG.BagAddons.active, "Baganator", "Baganator detected at login")
H.check(widgets.glassgear ~= nil, "...a corner widget registered through its API (no hook)")
H.eq(widgets.glassgear.label, "Glass Gear upgrades", "...labelled for Baganator's corner settings")
H.eq(widgets.glassgear.position.corner, "top_left", "...top left by default, like Blizzard's arrow")
SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("bag addon: Baganator (markers in an icon corner: 'Glass Gear upgrades')", 1, true) ~= nil, "/gg names it")

-- Green, amber, nothing: as on Blizzard's bags.
local up, off = newButton(), newButton()
local wUp = redraw(up, live(0, 1, 60))
local wOff = redraw(off, live(0, 2, 70))
H.eq(shown(wUp), "green", "a current-spec upgrade: green")
H.eq(wUp.parent, up, "...the mark is our own frame, made for Baganator's button")
H.eq(shown(wOff), nil, "a soulbound off-spec upgrade: quiet")
WoW.flush(1)
H.eq(GG.Reveal._surfaces[window], true, "Baganator's open window is a reveal surface")
window:Hide()
H.eq(GG.Reveal._surfaces[window], nil, "...closed: not any more")
window:Show()

-- The reveal key: Baganator is asked to redraw its widgets (nothing else).
refreshes = {}
WoW.keys.CTRL = true
WoW.fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
WoW.flush()
H.check(#refreshes > 0, "Ctrl held: a widget refresh is requested")
H.eq(type(refreshes[1]) == "table" and refreshes[1][1], "ItemWidgets", "...widgets only (no search or layout work)")
H.eq(shown(redraw(off, live(0, 2, 70))), "amber", "...and the off-spec upgrade shows amber")
WoW.keys.CTRL = nil
WoW.fire("MODIFIER_STATE_CHANGED", "LCTRL", 0)
WoW.flush()
H.eq(shown(redraw(off, live(0, 2, 70))), nil, "...released: gone")

-- Another character's bags: Baganator still fills itemLocation from this
-- character's bags. Never marked unless the item there is the one shown.
local alt = newButton()
H.eq(shown(redraw(alt, { itemLink = WoW.link(70), itemID = 70, itemLocation = { bagID = 0, slotIndex = 1 } })), nil,
    "another character's item over a slot where this one holds an upgrade: no mark")
H.eq(shown(redraw(alt, { itemLink = WoW.link(60), itemID = 60 })), nil, "no location (an offline view): no mark")
H.eq(shown(redraw(alt, { itemLink = WoW.link(60), itemID = 60, itemLocation = { bagID = 0, slotIndex = 9 } })), nil,
    "an empty slot here: no mark")
H.eq(shown(redraw(alt, {})), nil, "an empty button: no mark")
H.eq(widgets.glassgear.onUpdate(alt.cornerPlugins.glassgear, nil), false, "no details at all: false, never an error")

-- Data still loading: no mark now, a widget refresh when it arrives.
WoW.items[80] = shoulder("Late Mantle", { [INT] = 40 })
WoW.cacheMiss[80] = true
WoW.bags[0][3] = { itemID = 80, isBound = true }
local late = newButton()
H.eq(shown(redraw(late, live(0, 3, 80))), nil, "data still loading: no mark yet")
refreshes = {}
WoW.cacheMiss[80] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 80, true)
WoW.flush()
H.check(#refreshes > 0, "...it arrives: Baganator is asked to redraw its widgets")
H.eq(#refreshes, 1, "...once")
H.eq(shown(redraw(late, live(0, 3, 80))), "green", "...and then it is green")

-- A pooled button reused for another item follows it.
WoW.bags[0][4] = { itemID = 50, isBound = true }
H.eq(shown(redraw(up, live(0, 4, 50))), nil, "a button reused for an item that isn't an upgrade: cleared")

-- The player removed the widget from Baganator's corners.
cornerOn = false
H.check(GG.BagAddons.Status():find("markers off (add 'Glass Gear upgrades' to an icon corner", 1, true) ~= nil,
    "the widget removed in Baganator: /gg says how to bring it back")
cornerOn = true

H.eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
for name in pairs(WoW.globalWrites) do H.check(false, "undeclared global written: " .. name) end
H.done("test_baganator")
