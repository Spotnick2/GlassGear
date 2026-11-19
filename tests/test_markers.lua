------------------------------------------------------------
-- test_markers.lua - bag markers (GG-109) and the reveal modifier (GG-110):
-- PRD matrix rows 2-3, green precedence, BoE -> soulbound, press/release,
-- release while typing, reopened bags, None, combat, pending data.
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

-- Whether the addon hooked one of w's scripts (its call log: the kit's
-- HookScript chains the hook into _scripts).
local function hooked(w)
    for _, c in ipairs(w._log or {}) do if c[1] == "HookScript" then return true end end
    return false
end

local INT, SP, HEAL = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT"
local function shoulder(name, stats) return { name = name, equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = stats } end
WoW.items[50] = shoulder("Old Mantle", { [INT] = 10 })
WoW.items[60] = shoulder("Shadow Mantle", { [INT] = 5, [SP] = 10 })     -- Shadow up, Holy down
WoW.items[70] = shoulder("Healer Mantle", { [HEAL] = 30 })             -- Holy only
WoW.items[72] = { name = "Elixir", equipLoc = "", classID = 0, subclassID = 0 }
WoW.items[73] = shoulder("Late Mantle", { [INT] = 40 })
WoW.items[74] = shoulder("Big Mantle", { [INT] = 30 })                  -- every spec up
WoW.equipped[3] = 50
WoW.bags[0] = {
    [1] = { itemID = 60, isBound = true },
    [2] = { itemID = 70, isBound = true },     -- soulbound off-spec
    [3] = { itemID = 70, isBound = false },    -- BoE off-spec
    [4] = { itemID = 72, isBound = true },
    [5] = { itemID = 74, isBound = true },
}

local GG = WoW.loadAddon()
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1, SpellDamage=1 )')
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy": Class=Priest, Intellect=1, Healing=1 )')
WoW.flush()

local bag = ContainerFrameContainer.ContainerFrames[1]
local function mark(i)
    local m = GG.BagMarkers._marks[bag.Items[i]]
    return m and m:IsShown() and m.kind or nil
end
local function press(key, down)
    WoW.keys[key] = down or nil
    WoW.fire("MODIFIER_STATE_CHANGED", "L" .. key, down and 1 or 0)
end

-- Hooked once at login.
eq(GG.bagMarkersOn, true, "bag markers on")
eq(GG.bagMarkersInfo, 7, "six bag frames and the combined bags hooked")
SlashCmdList.GLASSGEAR("")
check(WoW.chatText():find("bag markers: on (7 bag frames)", 1, true) ~= nil, "/gg reports the markers")
check(WoW.chatText():find("reveal: hold CTRL", 1, true) ~= nil, "/gg reports the reveal key")

-- PRD matrix rows 2 and 3.
WoW.showBag(bag, { { 0, 1 }, { 0, 2 }, { 0, 3 }, { 0, 4 }, { 0, 5 } })
eq(mark(1), nil, "a Shadow upgrade, but the Big Mantle in the same bags is better: no arrow (owned better, GG-122)")
eq(mark(2), nil, "soulbound off-spec upgrade: quiet")
eq(mark(3), "amber", "transferable off-spec upgrade: amber by default (row 3)")
eq(mark(4), nil, "not equippable: nothing")
eq(GG.BagMarkers._marks[bag.Items[4]], nil, "...and no frame made for it")
eq(mark(5), "green", "an upgrade for every spec is green (green wins)")
local m1 = GG.BagMarkers._marks[bag.Items[5]]
eq(m1.fill._atlas, "bags-greenarrow", "green uses Blizzard's upgrade arrow")
eq(m1.inner._shown, false, "green is filled")
local m3 = GG.BagMarkers._marks[bag.Items[3]]
eq(m3.fill._desaturated, true, "amber is the arrow recoloured...")
eq(m3.inner._shown, true, "...with an inner cut-out: an outline, a different shape")
eq(m1._parent, bag.Items[5], "marks are our own child frames")
eq(bag.Items[1]._type, "Button", "nothing written on Blizzard's button")

-- Reveal: press and release.
press("CTRL", true)
eq(GG.Reveal.Active(), true, "Ctrl down: reveal on")
eq(mark(2), "amber", "revealed: soulbound off-spec upgrade amber")
eq(mark(5), "green", "green stays green while revealed")
press("CTRL", false)
eq(GG.Reveal.Active(), false, "Ctrl up: reveal off")
eq(mark(2), nil, "released: soulbound off-spec quiet again at once")
eq(mark(3), "amber", "transferable amber is not reveal-gated")

-- Typing: an edit box with focus means no reveal; a release while typing is
-- caught by the poll even with no modifier event.
WoW.focus = { name = "ChatFrame1EditBox" }
press("CTRL", true)
eq(GG.Reveal.Active(), false, "Ctrl while typing: no reveal")
WoW.focus = nil
WoW.tick(0.1)
eq(GG.Reveal.Active(), true, "focus gone, Ctrl still held: the poll reveals")
eq(mark(2), "amber", "...and the bag follows")
WoW.focus = { name = "ChatFrame1EditBox" }
WoW.keys.CTRL = nil                       -- released while typing: no event reaches us
WoW.tick(0.05)
eq(GG.Reveal.Active(), true, "the poll waits its 0.1 s")
WoW.tick(0.05)
eq(GG.Reveal.Active(), false, "a release while typing clears the reveal")
eq(mark(2), nil, "...and the soulbound amber")
WoW.focus = nil

-- The poll runs only while a reveal surface is visible.
check(GG.Reveal._Poller()._scripts.OnUpdate ~= nil, "poll on while bags are open")
bag:Hide()
eq(GG.Reveal._Poller()._scripts.OnUpdate, nil, "poll off when the last bag closes")

-- Reopened bags show the current state, whatever happened while closed.
WoW.keys.CTRL = true                      -- pressed while the bags were closed, event missed
WoW.showBag(bag, { { 0, 1 }, { 0, 2 }, { 0, 3 }, { 0, 4 }, { 0, 5 } })
eq(mark(2), "amber", "reopened with Ctrl held: revealed")
press("CTRL", false)
-- A redraw of an open bag (BAG_UPDATE) reads the live state too, before any poll.
WoW.keys.CTRL = true                      -- no event, no poll tick yet
bag:UpdateItems()
eq(mark(2), "amber", "a bag redraw uses the live modifier state")
press("CTRL", false)

-- Modifier None disables the reveal; Alt can be chosen instead.
GG.db.settings.reveal.modifier = "NONE"
press("CTRL", true)
eq(GG.Reveal.Active(), false, "None: Ctrl does nothing")
eq(mark(2), nil, "...no amber")
press("CTRL", false)
GG.db.settings.reveal.modifier = "ALT"
press("ALT", true)
eq(GG.Reveal.Active(), true, "Alt chosen: Alt reveals")
press("ALT", false)
GG.db.settings.reveal.modifier = "CTRL"

-- A BoE that binds loses its transferable amber on the next update.
WoW.bags[0][3].isBound = true
bag:UpdateItems()
eq(mark(3), nil, "BoE now soulbound: quiet")
WoW.bags[0][3].isBound = false
bag:UpdateItems()

-- Marker settings are their own (adr/0006).
GG.db.settings.markers.markTransferable = false
GG.BagMarkers.Refresh()
eq(mark(3), nil, "Mark transferable upgrades off: no amber for the BoE")
GG.db.settings.markers.markTransferable = true
GG.db.settings.markers.scope = "own"
GG.BagMarkers.Refresh()
eq(mark(2), "amber", "marker scope own: off-spec amber without the reveal")
GG.db.settings.markers.scope = "current"
GG.BagMarkers.Refresh()

-- Item data still loading: no marker yet, then the right one once it arrives.
WoW.cacheMiss[73] = true
WoW.bags[0][6] = { itemID = 73, isBound = true }
WoW.showBag(bag, { { 0, 1 }, { 0, 2 }, { 0, 3 }, { 0, 4 }, { 0, 5 }, { 0, 6 } })
eq(mark(6), nil, "pending item: no marker yet")
WoW.cacheMiss[73] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 73, true)
WoW.flush()
eq(mark(6), "green", "data arrived: marked without reopening the bag")

-- Combat: no frame is created in combat; the button is marked afterwards.
local bag2 = ContainerFrameContainer.ContainerFrames[2]
WoW.combat = true
WoW.bags[1] = { [1] = { itemID = 73, isBound = true } }   -- the best mantle owned (GG-122)
WoW.showBag(bag2, { { 1, 1 } })
eq(GG.BagMarkers._marks[bag2.Items[1]], nil, "in combat: no mark frame created")
press("CTRL", true)
eq(mark(2), "amber", "in combat: existing marks still follow the reveal")
press("CTRL", false)
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
local late = GG.BagMarkers._marks[bag2.Items[1]]
eq(late and late.kind, "green", "after combat: the button met in combat is marked")
eq(late and late._madeInCombat, false, "...with a frame made out of combat")

-- New weights re-evaluate: Holy no longer wants the healer mantle.
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy2": Class=Priest, Intellect=1 )')
WoW.flush()
eq(mark(3), nil, "after an import, the BoE is no longer an upgrade")
eq(mark(5), "green", "...and the Shadow upgrade stays green")

-- No click handlers anywhere: Ctrl-click still reaches Blizzard (dressing room).
for _, b in ipairs(bag.Items) do
    check(not hooked(b) and b._scripts.OnClick == nil, "no click hook on a bag button")
end

done("test_markers")
