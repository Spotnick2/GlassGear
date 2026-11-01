------------------------------------------------------------
-- test_load.lua - loads in TOC order under the strict Forever stubs, writes
-- only declared globals, becomes Ready, and /gg answers (GG-001, GG-004).
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local ready = 0
H.ok(function() WoW.loadAddon({ noLogin = true }) end, "TOC-order load, ADDON_LOADED")
local GG = GlassGear
H.eq(GG.API.IsReady(), false, "API table exists before login, data not ready")
GG.API.RegisterCallback("Ready", function() ready = ready + 1 end, "consumer")
WoW.fire("PLAYER_LOGIN")
WoW.flush()
H.eq(GG.API.IsReady(), true, "ready after login")
H.eq(ready, 1, "Ready fired once to a consumer registered before login")
H.eq(GG.API.API_VERSION, 1, "API major 1")
H.eq(type(GlassGearDB), "table", "account SavedVariables created")
H.eq(GlassGearDB.schema, 1, "schema stamped")
H.eq(GlassGearDB.settings.reveal.modifier, "CTRL", "reveal default Ctrl")
H.eq(GlassGearDB.settings.levelWindow.enabled, true, "level window on by default")
H.eq(GlassGearDB.settings.specArmor, true, "spec armor rules on by default")
H.eq(GG.themeName, "forever", "WoW Forever look without Glass UI")
H.eq(#WoW.settingsCategories, 1, "a Settings category is registered")
H.eq(GG.currentSpec, nil, "no spec mapping yet: unknown-spec, never a guess")
H.eq(GG.specReason, "unknown-spec", "reason recorded")

for name in pairs(WoW.globalWrites) do
    H.check(false, "undeclared global written: " .. name)
end
for _, name in ipairs(WoW.replacedGlobals()) do
    H.check(false, "existing global replaced: " .. name)
end

SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("AltStable: absent", 1, true) ~= nil, "/gg reports AltStable absent")
H.check(WoW.chat():find("PRIEST.DISCIPLINE: no weights", 1, true) ~= nil, "/gg shows specs without weights as 'no weights'")
local invalidated = 0
GG.API.RegisterCallback("EvaluationInvalidated", function() invalidated = invalidated + 1 end, "consumer")
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
WoW.flush()
H.eq(invalidated, 1, "changing the spec mapping invalidates consumers")
H.eq(GG.currentSpec, "PRIEST.SHADOW", "manual mapping sets the current spec")
H.eq(GlassGearChar.specMap[1], "PRIEST.SHADOW", "mapping saved per character")

-- A newer SavedVariables schema is left untouched: read-only session.
WoW.reset()
GlassGear, GlassGearDB, GlassGearChar = nil, nil, nil
WoW.loadAddon({ db = { schema = 99, keep = "me" } })
H.eq(GlassGear.readOnly, true, "newer data -> read-only")
H.eq(GlassGearDB.keep, "me", "newer data untouched")
H.eq(GlassGearDB.schema, 99, "schema not downgraded")

H.done("test_load")
