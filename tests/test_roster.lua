------------------------------------------------------------
-- test_roster.lua - GG-201: the AltStable roster provider. A fake AltStable
-- built from its docs/PUBLIC-API.md: own characters only (self and
-- own-account; third-party never), the current one first and from Glass
-- Gear itself, a cached snapshot rebuilt on its callbacks (RosterChanged and
-- an invalidation only when something changed), GearChanged -> EquipmentChanged,
-- an older AltStable and a failing one reported exactly, GetSpecs for an alt.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local ME = "Player-1-0000AAAA"
local chars = {
    { guid = ME, name = "Karuzo", realm = "Forever", faction = "Alliance", class = "PRIEST", level = 60,
      account = "1", provenance = "self", hidden = false, current = true },
    { guid = "Player-1-ALT1", name = "Wanda", realm = "Forever", faction = "Alliance", class = "MAGE", level = 42,
      account = "1", provenance = "self", hidden = false, current = false },
    { guid = "Player-1-ALT2", name = "Drakuza", realm = "Forever", faction = "Alliance", class = "MAGE", level = 60,
      account = "2", provenance = "own-account", provenanceVia = "Tilly", hidden = false, current = false },
    { guid = "Player-1-FRIEND", name = "Friendo", realm = "Forever", faction = "Alliance", class = "ROGUE", level = 60,
      account = "2", provenance = "third-party", hidden = false, current = false },
    { guid = "Player-1-BANK", name = "Banky", realm = "Forever", faction = "Alliance", class = "WARRIOR", level = 5,
      account = "1", provenance = "self", hidden = true, current = false },
}
local callbacks = {}
local failing = false
local AS = {
    PUBLIC_API_VERSION = 1,
    PUBLIC_API_FEATURES = { provenance = true, gear = true, ownAccountChannel = true },
    GetCharacters = function()
        if failing then error("AltStable broke") end
        local out = {}
        for i, c in ipairs(chars) do local t = {} for k, v in pairs(c) do t[k] = v end out[i] = t end
        return out
    end,
    GetCharacterProvenance = function() return nil end,
    GetCharacterGear = function() return nil end,
    RegisterCallback = function(event, fn) callbacks[event] = callbacks[event] or {}; table.insert(callbacks[event], fn) end,
}
local function fire(event, ...) for _, fn in ipairs(callbacks[event] or {}) do fn(event, ...) end end
rawset(_G, "AltStable", AS)

local GG = WoW.loadAddon()
local api = GG.API
local RP = GG.Integrations.RosterProvider
local function names(list) local t = {} for _, c in ipairs(list) do t[#t + 1] = c.name end return table.concat(t, ",") end

H.eq(api.GetCapabilities().features.roster, true, "features.roster (AltStable usable)")
H.check(api.GetCapabilities().unavailable.alts:find("GG-203", 1, true) ~= nil, "unavailable.alts points at GG-203, not GG-201")
local list = api.GetCharacters()
H.eq(names(list), "Karuzo,Wanda,Drakuza,Banky", "the current character first, then the player's own others")
H.eq(list[1].current, true, "...the current one from Glass Gear itself")
H.eq(list[2].provenance, "self", "...an alt of this account: self")
H.eq(list[3].provenance, "own-account", "...one of the other account: own-account")
H.eq(list[3].provenanceVia, "Tilly", "...with who said so")
H.eq(list[4].hidden, true, "a hidden alt is listed, flagged (the page decides)")
for _, c in ipairs(list) do H.check(c.guid ~= "Player-1-FRIEND", "a third-party character is never listed: " .. c.name) end
H.eq(list[2].key, "Player-1-ALT1", "keys are GUIDs")
H.eq(RP.Find("Player-1-FRIEND"), nil, "Find doesn't know third-party characters")

SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("AltStable: 3 of your other characters (2 on this account, 1 on your other accounts), 1 not yours (never used)", 1, true) ~= nil,
    "/gg counts them by provenance")

-- GetSpecs for an alt: its class's specs.
local specs = api.GetSpecs("Player-1-ALT2")
H.eq(#specs, 3, "an alt mage: three specs")
H.eq(specs[1].key, "MAGE.ARCANE", "...the mage's")
H.eq(specs[1].current, false, "...none current (an alt's spec isn't known)")
H.eq(#api.GetSpecs("Player-1-FRIEND"), 0, "a third-party character has no specs here")

-- A cached snapshot, rebuilt on AltStable's callbacks.
local rebuilds = RP.rebuilds
for _ = 1, 5 do api.GetCharacters() end
H.eq(RP.rebuilds, rebuilds, "reading the roster doesn't rebuild it")
local roster, inval = 0, {}
api.RegisterCallback("RosterChanged", function() roster = roster + 1 end, "test_roster")
api.RegisterCallback("EvaluationInvalidated", function(_, p) inval[#inval + 1] = p.reason end, "test_roster")
WoW.flush(); inval = {}
fire("CharactersChanged")
WoW.flush()
H.eq(RP.rebuilds, rebuilds + 1, "CharactersChanged rebuilds it")
H.eq(roster, 0, "...nothing changed: no RosterChanged")
chars[4].provenance = "own-account"           -- a sync proved the friend's account is the player's own
fire("ProvenanceChanged")
WoW.flush()
H.eq(roster, 1, "a provenance change: RosterChanged")
H.eq(H.has(inval, "roster"), false, "...no invalidation: no answer depends on alts yet (GG-203)")
H.check(names(api.GetCharacters()):find("Friendo", 1, true) ~= nil, "...the character proven own is listed now")
chars[2].level = 43
fire("CharactersChanged")
WoW.flush()
H.eq(roster, 2, "a level-up: RosterChanged")
H.eq(api.GetCharacters()[2].level, 43, "...with the new level")

-- Gear of an alt changed: EquipmentChanged for those characters.
local eq
api.RegisterCallback("EquipmentChanged", function(_, p) eq = p end, "test_roster")
fire("GearChanged", { "Player-1-ALT1" })
WoW.flush()
H.eq(eq and eq.charKeys and eq.charKeys[1], "Player-1-ALT1", "GearChanged -> EquipmentChanged for that alt")
eq = nil
chars[4].provenance = "third-party"
fire("ProvenanceChanged")
WoW.flush()
fire("GearChanged", { "Player-1-FRIEND", ME })
WoW.flush()
H.eq(eq, nil, "a third-party character's or the current one's gear: no EquipmentChanged from AltStable")
eq = nil
fire("GearChanged", { "Player-1-FRIEND", "Player-1-ALT2" })
WoW.flush()
H.eq(eq and #eq.charKeys, 1, "...mixed: only the own alt is named")

-- Any field the page shows is a roster change.
local r0 = roster
chars[3].provenanceVia = "Bob"
fire("CharactersChanged")
WoW.flush()
H.eq(roster, r0 + 1, "who vouched for an own-account character changed: RosterChanged")
chars[2].account = "3"
fire("CharactersChanged")
WoW.flush()
H.eq(roster, r0 + 2, "an account label changed (the page groups by it): RosterChanged")

-- A retry doesn't register handlers twice.
local before = #(callbacks.CharactersChanged or {})
GG.Integrations.RosterProvider.Attach()
H.eq(#callbacks.CharactersChanged, before, "Attach again: no second handler")

-- AltStable failing: only this character, the reason reported.
failing = true
fire("CharactersChanged")
WoW.flush()
H.eq(names(api.GetCharacters()), "Karuzo", "GetCharacters failing: only this character")
H.check(RP.Status().reason:find("GetCharacters failed", 1, true) ~= nil, "...the reason reported")
SlashCmdList.GLASSGEAR("")
H.eq(#WoW.errors, 1, "...and the error goes to the error handler")
failing = false
fire("CharactersChanged")
WoW.flush()

-- An older AltStable: exactly what is missing.
AS.PUBLIC_API_FEATURES = { provenance = true }
RP._Reset()
RP.Refresh()
H.eq(names(api.GetCharacters()), "Karuzo", "an AltStable without AS-003: only this character")
SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("AltStable: present, AltStable lacks AS-003 - only this character is known", 1, true) ~= nil,
    "/gg says exactly what is missing")
H.check(api.GetCapabilities().unavailable.alts:find("AS-003", 1, true) ~= nil, "...so does the API")
H.eq(api.GetCapabilities().features.roster, false, "...features.roster is false then")
rawset(_G, "AltStable", nil)
RP._Reset()
RP.Refresh()
SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("AltStable: absent - only this character is known", 1, true) ~= nil, "no AltStable: said so")
H.eq(api.GetCapabilities().features.roster, false, "...features.roster false")

-- A registration that fails keeps its reason through later rebuilds.
local partial = {
    PUBLIC_API_VERSION = 1, PUBLIC_API_FEATURES = { provenance = true, gear = true },
    GetCharacters = AS.GetCharacters, GetCharacterProvenance = AS.GetCharacterProvenance,
    GetCharacterGear = AS.GetCharacterGear,
    RegisterCallback = function(event, fn) if event == "ProvenanceChanged" then error("no") end end,
}
rawset(_G, "AltStable", partial)
RP._Reset()
RP.Attach()
RP.Refresh()
H.check((RP.Status().reason or ""):find("callbacks unavailable", 1, true) ~= nil,
    "a failed callback registration is still reported after a rebuild")
rawset(_G, "AltStable", nil)

H.done("test_roster")
