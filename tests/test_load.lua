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
-- Count the spec mapping only: the capture that follows writes a baseline (GG-108) and
-- fires its own "baselines" invalidation.
GG.API.RegisterCallback("EvaluationInvalidated", function(_, p)
    if not (p and p.reason == "baselines") then invalidated = invalidated + 1 end
end, "consumer")
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
WoW.flush()
H.eq(invalidated, 1, "changing the spec mapping invalidates consumers")
H.eq(GG.currentSpec, "PRIEST.SHADOW", "manual mapping sets the current spec")
H.eq(GlassGearChar.specMap[1], "PRIEST.SHADOW", "mapping saved per character")

-- Only this class's specs and real spec groups can be mapped (PR #32 review).
SlashCmdList.GLASSGEAR("spec 1 MAGE.FROST")
WoW.flush()
H.eq(GlassGearChar.specMap[1], "PRIEST.SHADOW", "another class's spec is refused")
H.eq(GG.currentSpec, "PRIEST.SHADOW", "...and the current spec is unchanged")
H.eq(invalidated, 1, "...without invalidating anything")
SlashCmdList.GLASSGEAR("spec 3 PRIEST.HOLY")
H.eq(GlassGearChar.specMap[3], nil, "spec group 3 is refused")
SlashCmdList.GLASSGEAR("spec 0 PRIEST.HOLY")
H.eq(GlassGearChar.specMap[0], nil, "spec group 0 is refused")
-- A bad mapping already saved (edited or copied SavedVariables) is never used.
GlassGearChar.specMap[1] = "MAGE.FROST"
GG.ResolveSpec()
H.eq(GG.currentSpec, nil, "a saved mapping of another class is ignored")
H.eq(GG.specReason, "invalid-mapping", "...and reported")
for _, s in ipairs(GG.API.GetSpecs(GG.player.key) or {}) do
    H.check(s.key:find("^PRIEST%.") ~= nil, "GetSpecs lists only Priest specs: " .. tostring(s.key))
end
GlassGearChar.specMap[1] = "PRIEST.SHADOW"
GG.ResolveSpec()
H.eq(GG.currentSpec, "PRIEST.SHADOW", "a valid mapping resolves again")

-- Importing again replaces the spec's weights (PR #32 review), in the same
-- second too, and only this class's specs take an import.
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "First": Class=Priest, Intellect=1 )')
local first = assert(GG.API.GetProfile(GG.player.key, "PRIEST.SHADOW"), "first import active")
H.eq(first.weights.Intellect, 1, "first import's weights")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Second": Class=Priest, Intellect=2, Spirit=0.5 )')
local second = assert(GG.API.GetProfile(GG.player.key, "PRIEST.SHADOW"), "second import active")
H.eq(second.name, "Second", "the re-import is the active profile")
H.eq(second.weights.Intellect, 2, "...with the new weights")
H.eq(second.id, first.id, "...as a newer version of the same entry")
H.check(second.version ~= first.version, "...under a new version")
H.eq(#GG.Profiles.ForSpec(GG.store, GG.player.key, "PRIEST.SHADOW"), 1, "still one profile for the spec")
H.check(WoW.chat():find("replaced weights with Second", 1, true) ~= nil, "/gg says the weights were replaced")
SlashCmdList.GLASSGEAR('import MAGE.FROST ( Pawn: v1: "Frost": Class=Mage, Intellect=1 )')
H.eq(GG.Profiles.Active(GG.store, GG.player.key, "MAGE.FROST"), nil, "another class's spec takes no import")
-- A new profile never reuses an id, not even a deleted one's.
local tomb = GG.Profiles.ForSpec(GG.store, GG.player.key, "PRIEST.SHADOW")[1]
assert(GG.store:Delete(tomb.id, tomb.version))
local again = assert(GG.Profiles.ImportPawn(GG.store, GG.player.key, "PRIEST.SHADOW",
    '( Pawn: v1: "Third": Class=Priest, Intellect=3 )', time(), tomb.id:match("[^:]+$"), "PRIEST"))
H.check(again.id ~= tomb.id, "a tombstoned id is not reused")
H.eq(GG.API.GetProfile(GG.player.key, "PRIEST.SHADOW").name, "Third", "the new profile is active")

-- A newer SavedVariables schema is left untouched: read-only session.
WoW.reset()
GlassGear, GlassGearDB, GlassGearChar = nil, nil, nil
WoW.loadAddon({ db = { schema = 99, keep = "me" } })
H.eq(GlassGear.readOnly, true, "newer data -> read-only")
H.eq(GlassGearDB.keep, "me", "newer data untouched")
H.eq(GlassGearDB.schema, 99, "schema not downgraded")

-- Baseline item strings: AltStable's trimmed form (Scanner.lua:96-129 @1b35918).
local GIS = GlassGear.Compat.GearItemString
H.eq(GIS("|cff1eff00|Hitem:14094::::::::10:1482:::1:12745|h[Beaded Wraps of the Sorcerer]|h|r"),
    "item:14094::::::::::::1:12745", "suffix bonus ID kept; the scanner's level and spec blanked")
H.eq(GIS("|cffffffff|Hitem:288919::::::::60:258::::::|h[Plain]|h|r"), "item:288919", "a plain item is just item:<id>")
H.eq(GIS("item:5000:1883:::::::60:258:::2:9:1:1:28:2071:Player-1-0ABC"),
    "item:5000:1883" .. string.rep(":", 11) .. "2:9:1:1:28:2071", "enchant, bonuses and modifiers kept; crafter dropped")
H.eq(GIS("not a link"), nil, "not an item")

-- AltStable detection: a feature flag and its function (AltStable docs/PUBLIC-API.md).
local Detect = GlassGear.Integrations.RosterProvider.DetectAltStable
local fn = function() end
H.eq(Detect({}).present, false, "no AltStable")
local old = Detect({ AltStable = { PUBLIC_API_VERSION = 1, GetCharacterProvenance = fn, GetCharacterGear = fn } })
H.eq(table.concat(old.missing, ","), "AS-001,AS-003", "an AltStable without the flags table offers neither")
local half = Detect({ AltStable = { PUBLIC_API_VERSION = 1, PUBLIC_API_FEATURES = { provenance = true },
    GetCharacterProvenance = fn } })
H.eq(table.concat(half.missing, ","), "AS-003", "provenance only: AS-003 missing")
local noFn = Detect({ AltStable = { PUBLIC_API_VERSION = 1, PUBLIC_API_FEATURES = { provenance = true, gear = true },
    GetCharacterProvenance = fn } })
H.eq(table.concat(noFn.missing, ","), "AS-003", "a flag without its function is not enough")
local full = Detect({ AltStable = { PUBLIC_API_VERSION = 1, PUBLIC_API_FEATURES = { provenance = true, gear = true },
    GetCharacterProvenance = fn, GetCharacterGear = fn } })
H.eq(full.usable, true, "AS-001 and AS-003 flagged and present: usable")

H.done("test_load")
