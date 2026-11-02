------------------------------------------------------------
-- test_loot_markers.lua - loot window and group roll markers (GG-111):
-- PRD matrix row 1 (green current spec; off-spec amber only while revealed,
-- BoP and BoE alike), reveal surfaces, combat pool, pending data, slot
-- changes, roll frame reuse, shared answers with the tooltip.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local INT, SP, HEAL = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT"
local function shoulder(name, stats, bindType)
    return { name = name, equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = stats, bindType = bindType }
end
WoW.items[50] = shoulder("Old Mantle", { [INT] = 10 })
WoW.items[60] = shoulder("Shadow Mantle", { [INT] = 5, [SP] = 10 }, 1)   -- Shadow up
WoW.items[70] = shoulder("Healer Mantle", { [HEAL] = 30 }, 1)          -- Holy only, BoP
WoW.items[71] = shoulder("Healer Drape", { [HEAL] = 30 }, 2)           -- Holy only, BoE
WoW.items[72] = { name = "Elixir", equipLoc = "", classID = 0, subclassID = 0 }
WoW.items[73] = shoulder("Late Mantle", { [INT] = 40 }, 1)
WoW.equipped[3] = 50
WoW.loot = {
    [1] = { itemID = 60 }, [2] = { itemID = 70 }, [3] = { itemID = 71 },
    [4] = { money = true }, [5] = { itemID = 72 },
}

local GG = WoW.loadAddon()
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1, SpellDamage=1 )')
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy": Class=Priest, Intellect=1, Healing=1 )')
WoW.flush()

local Loot = GG.LootMarkers
local sb = LootFrame.ScrollBox
local function markOn(button)
    local m = Loot._marks[button]
    return m and m:IsShown() and m.kind or nil
end
local function mark(i) return markOn(sb._frames[i].Item) end
local function roll(i) return markOn(_G["GroupLootFrame" .. i].IconFrame) end
local function press(key, down)
    WoW.keys[key] = down or nil
    WoW.fire("MODIFIER_STATE_CHANGED", "L" .. key, down and 1 or 0)
end

-- Hooked once at login; the pool is made out of combat.
H.eq(GG.lootMarkersOn, true, "loot markers on")
H.eq(GG.lootMarkersInfo, "loot window, 4 roll frames", "loot window and the four roll frames hooked")
H.eq(#Loot._spare, Loot.POOL, "mark pool filled at login")
SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("loot markers: on (loot window, 4 roll frames)", 1, true) ~= nil, "/gg reports the loot markers")
H.check(WoW.chat():find("loot markers (GG-111)", 1, true) == nil, "...and no longer lists them unavailable")

-- PRD matrix row 1.
WoW.openLoot({ 1, 2, 3, 4, 5 })
H.eq(mark(1), "green", "current-spec upgrade: green")
H.eq(mark(2), nil, "BoP off-spec upgrade: quiet")
H.eq(mark(3), nil, "BoE off-spec upgrade: quiet too (no transferable amber on loot)")
H.eq(sb._frames[4].Item, nil, "money element: no button, nothing to mark")
H.eq(mark(5), nil, "not equippable: nothing")
H.eq(Loot._marks[sb._frames[5].Item], nil, "...and no mark taken for it")
local m1 = Loot._marks[sb._frames[1].Item]
H.eq(m1.parent, sb._frames[1].Item, "the mark sits on the element's icon button")
H.eq(m1.fill.atlas, "bags-greenarrow", "same look as the bag markers")
H.eq(#Loot._spare, Loot.POOL - 1, "the mark came from the pool")
H.check(GG.Results.Peek("link:" .. WoW.link(60)) ~= nil, "answer stored under the tooltip's link key")

-- Reveal: the loot window is a reveal surface.
H.check(GG.Reveal._Poller()._scripts.OnUpdate ~= nil, "poll on while the loot window shows")
press("CTRL", true)
H.eq(mark(2), "amber", "revealed: BoP off-spec amber")
H.eq(mark(3), "amber", "revealed: BoE off-spec amber")
H.eq(mark(1), "green", "green stays green")
local m2 = Loot._marks[sb._frames[2].Item]
H.eq(m2.inner.shown, true, "amber is the outline")
press("CTRL", false)
H.eq(mark(2), nil, "released: quiet again")
H.eq(mark(3), nil, "released: BoE quiet again")

-- Opened while Ctrl is already held (event missed): the live state is used.
WoW.closeLoot()
H.eq(GG.Reveal._Poller()._scripts.OnUpdate, nil, "poll off when the loot window closes")
WoW.keys.CTRL = true
WoW.openLoot({ 1, 2, 3 })
H.eq(mark(2), "amber", "opened with Ctrl held: revealed")
press("CTRL", false)
H.eq(mark(2), nil, "...and released")
-- A redraw of the open window (no show, no event, no poll tick yet) reads it too.
WoW.keys.CTRL = true
WoW.fire("LOOT_SLOT_CHANGED", 2)
WoW.flush()
H.eq(mark(2), "amber", "a loot redraw uses the live modifier state")
press("CTRL", false)

-- Marker scope own: off-spec amber without the reveal.
GG.db.settings.markers.scope = "own"
Loot.Refresh()
H.eq(mark(2), "amber", "marker scope own: off-spec amber on loot")
GG.db.settings.markers.scope = "current"
Loot.Refresh()
H.eq(mark(2), nil, "scope current again: quiet")

-- A slot whose content changes is redecorated (LOOT_SLOT_CHANGED).
WoW.loot[1] = { itemID = 72 }
WoW.fire("LOOT_SLOT_CHANGED", 1)
WoW.flush()
H.eq(mark(1), nil, "slot 1 now holds a non-equippable: mark hidden")
WoW.loot[1] = { itemID = 60 }
WoW.fire("LOOT_SLOT_CHANGED", 1)
WoW.flush()
H.eq(mark(1), "green", "...and back")

-- Item data still loading: no mark yet, then the right one.
WoW.cacheMiss[73] = true
WoW.loot[6] = { itemID = 73 }
WoW.openLoot({ 1, 2, 3, 4, 5, 6 })
H.eq(mark(6), nil, "pending item: no marker yet")
WoW.cacheMiss[73] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 73, true)
WoW.flush()
H.eq(mark(6), "green", "data arrived: marked with the window still open")
WoW.closeLoot()

-- Group rolls.
WoW.rolls[11], WoW.rolls[12] = 60, 70
WoW.startRoll(1, 11)
WoW.startRoll(2, 12)
H.eq(roll(1), "green", "roll frame: current-spec upgrade green")
H.eq(roll(2), nil, "roll frame: off-spec quiet")
H.check(GG.Reveal._Poller()._scripts.OnUpdate ~= nil, "roll frames are reveal surfaces")
press("CTRL", true)
H.eq(roll(2), "amber", "roll frame: off-spec amber while revealed")
press("CTRL", false)
H.eq(roll(2), nil, "roll frame: released")
WoW.rolls[13] = 70
WoW.startRoll(1, 13)
H.eq(roll(1), nil, "a reused roll frame shows its new item's marker")
GroupLootFrame1:Hide()
GroupLootFrame2:Hide()
H.eq(GG.Reveal._Poller()._scripts.OnUpdate, nil, "poll off when the last roll frame closes")

-- Combat: marks come from the pool, never a new frame.
WoW.combat = true
WoW.loot[7] = { itemID = 60 }
WoW.openLoot({ 1, 2, 3, 4, 5, 6, 7 })
local m7 = Loot._marks[sb._frames[7].Item]
H.eq(mark(7), "green", "in combat: marked at once from the pool")
H.eq(m7 and m7.inCombatCreate, false, "...with a frame made out of combat")
-- Pool empty in combat: marked after combat if the window still shows.
while #Loot._spare > 0 do table.remove(Loot._spare) end
WoW.loot[8] = { itemID = 60 }
WoW.openLoot({ 1, 2, 3, 4, 5, 6, 7, 8 })
H.eq(Loot._marks[sb._frames[8].Item], nil, "in combat, pool empty: no frame created")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
local m8 = Loot._marks[sb._frames[8].Item]
H.eq(m8 and m8:IsShown() and m8.kind, "green", "after combat: marked")
H.eq(m8 and m8.inCombatCreate, false, "...with a frame made out of combat")
H.eq(#Loot._spare, Loot.POOL, "...and the pool refilled")
-- Pool empty in combat, window closed before combat ends: nothing is made.
WoW.combat = true
while #Loot._spare > 0 do table.remove(Loot._spare) end
WoW.loot[9] = { itemID = 60 }
WoW.openLoot({ 1, 2, 3, 4, 5, 6, 7, 8, 9 })
local el9 = sb._frames[9]
WoW.closeLoot()
el9:Hide()
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
H.eq(Loot._marks[el9.Item], nil, "closed before combat ended: no late mark")

-- New weights re-evaluate the open loot.
WoW.openLoot({ 1, 2, 3 })
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow2": Class=Priest, Healing=1 )')
WoW.flush()
H.eq(mark(1), nil, "after an import, the Shadow mantle is no longer an upgrade")

-- No click handlers: modified clicks still reach Blizzard.
for i = 1, 3 do
    local b = sb._frames[i].Item
    H.check(next(b._hooks) == nil and b._scripts.OnClick == nil, "no click hook on a loot button")
end
H.check(next(GroupLootFrame1.IconFrame._hooks) == nil, "no hook on a roll icon")

H.done("test_loot_markers")
