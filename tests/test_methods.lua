------------------------------------------------------------
-- test_methods.lua - every widget method Glass Gear calls exists on that
-- widget type in the pinned build (WowTestKit's Kit.checkMethods, #65).
--
-- The exercise reaches as much of the addon as is cheap: load, every
-- registered event, every /gg command, every window (options, profiles,
-- characters, compare), the item tooltip, bag and loot arrows with the
-- reveal key, combat in and out, then every script on every widget made
-- and a keystroke in every edit box.
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local INT, SP, SPI = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPIRIT_SHORT"
local function shoulder(name, stats, bindType)
    return { name = name, equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = stats, bindType = bindType }
end
WoW.items[50] = shoulder("Old Mantle", { [INT] = 10 })
WoW.items[60] = shoulder("Shadow Mantle", { [INT] = 5, [SP] = 10 }, 2)
WoW.items[70] = shoulder("Big Mantle", { [INT] = 30, [SP] = 20, [SPI] = 10 }, 2)
WoW.equipped[3] = 50
WoW.bags[0] = { [1] = { itemID = 60, isBound = false, guid = "Item-1-AAA" },
                [2] = { itemID = 70, isBound = false, guid = "Item-1-BBB" } }
WoW.sets[1] = { name = "Holy Set", items = { [3] = 50 }, specGroup = 2 }
WoW.loot[1], WoW.loot[2] = { itemID = 60 }, { money = true }
WoW.rolls[11] = 70

local GG = WoW.loadAddon()
WoW.fireAllRegistered()
WoW.flush()
WoW.tick(0.1)

-- Weights, so the windows, tooltip and arrows have something to say.
local function gg(cmd) SlashCmdList.GLASSGEAR(cmd); WoW.flush(); WoW.tick(0.1) end
gg('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Intellect=1.0, SpellDamage=0.8 )')
gg('import PRIEST.HOLY ( Pawn: v1: "Holy": Intellect=1.0, Spirit=0.9 )')

-- Every /gg command.
for _, cmd in ipairs({ "", "spec 1 PRIEST.SHADOW", "spec 2 PRIEST.HOLY", "set PRIEST.HOLY Holy Set",
    "set PRIEST.SHADOW none", "set PRIEST.SHADOW auto", "stats", "stats reset", "options", "config",
    "profiles", "profiles PRIEST.HOLY", "weights", "characters", "chars", "compare",
    "compare " .. WoW.link(70), "bogus" }) do
    gg(cmd)
end

-- The item tooltip, then /gg compare on what it showed.
local tip = WoW.newTooltip("GameTooltip")
WoW.showItem(tip, { type = 0, id = 70, guid = "Item-1-BBB" }, WoW.bagButton(0, 2, true))
gg("compare")

-- Bag and loot arrows, revealed with the modifier, a roll frame.
local function press(key, down)
    WoW.keys[key] = down or nil
    WoW.fire("MODIFIER_STATE_CHANGED", "L" .. key, down and 1 or 0)
end
WoW.showBag(ContainerFrame1, { { 0, 1 }, { 0, 2 } })
WoW.openLoot({ 1, 2 })
WoW.startRoll(1, 11)
press("CTRL", true); WoW.tick(0.2)
press("CTRL", false); WoW.tick(0.2)
WoW.fire("BAG_UPDATE_DELAYED"); WoW.flush(); WoW.tick(0.1)

-- Combat in and out, with the windows open.
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.showBag(ContainerFrame2, { { 0, 1 } })
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.flush(); WoW.tick(0.1)

-- Every script on every widget made so far, then a keystroke in each edit
-- box. A script may make more widgets; those are left for the next pass.
local SCRIPTS = { "OnEnter", "OnLeave", "OnShow", "OnHide", "OnMouseWheel", "OnDragStart", "OnDragStop",
    "OnEditFocusGained", "OnEditFocusLost", "OnTextChanged", "OnEscapePressed" }
local widgets = {}
for _, w in ipairs(WoW.widgets) do widgets[#widgets + 1] = w end
for _, w in ipairs(widgets) do
    for _, s in ipairs(SCRIPTS) do
        local fn = w._scripts and w._scripts[s]
        if fn then
            if s == "OnMouseWheel" then fn(w, -1)
            elseif s == "OnTextChanged" then fn(w, false)
            else fn(w) end
        end
    end
    if w._type == "EditBox" and w:IsVisible() then WoW.type(w, "1") end
    if w._type == "Slider" and w._scripts.OnValueChanged then w:SetValue((w._value or 0) + 1) end
    WoW.flush()
end
-- Every button, clicked. A click may close the window, so each one again
-- after reopening isn't attempted: one click each.
for _, w in ipairs(widgets) do
    if (w._type == "Button" or w._type == "CheckButton") and w._scripts.OnClick then
        w:Click()
        WoW.flush()
    end
end
WoW.tick(0.1)

local recorded = Kit.checkMethods({ allow = {
    ["Frame:SetBackdrop"] = "BackdropTemplateMixin:SetBackdrop (Blizzard_SharedXML/Backdrop.lua:336), mixed into frames made with BackdropTemplate",
    ["Frame:SetBackdropColor"] = "BackdropTemplateMixin:SetBackdropColor (Blizzard_SharedXML/Backdrop.lua:406)",
    ["Frame:SetBackdropBorderColor"] = "BackdropTemplateMixin:SetBackdropBorderColor (Blizzard_SharedXML/Backdrop.lua:429)",
} })
-- The floor: what the exercise records today (104), rounded down, so it
-- can't quietly shrink.
check(recorded >= 100, "the exercise reached the windows (" .. recorded .. " recorded)")
-- The windows build inside a pcall that reports to geterrorhandler: a
-- missing method there must still fail here, by name.
eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))

done("test_methods")
