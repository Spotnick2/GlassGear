------------------------------------------------------------
-- test_characters.lua - GG-204: the characters page (mockup 06). Grouped by
-- account (this one first), each character's specs as protection "tracked"
-- boxes (alts opted in, the current one tracked by default), gear freshness
-- from AltStable (fresh, stale, none), "no weights", hidden alts dimmed,
-- "Open AltStable", the unavailable state, and following roster changes.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local ME = "Player-1-0000AAAA"
local NOW = 1793500000
local chars = {
    { guid = ME, name = "Karuzo", realm = "Forever", class = "PRIEST", level = 60, account = "1", provenance = "self", hidden = false },
    { guid = "Player-1-ALT1", name = "Elegia", realm = "Forever", class = "PALADIN", level = 60, account = "1", provenance = "self", hidden = false },
    { guid = "Player-1-ALT2", name = "Drakuza", realm = "Forever", class = "MAGE", level = 60, account = "2",
      provenance = "own-account", provenanceVia = "Tilly", hidden = false },
    { guid = "Player-1-FRIEND", name = "Friendo", realm = "Forever", class = "ROGUE", level = 60, account = "2", provenance = "third-party", hidden = false },
    { guid = "Player-1-BANK", name = "Banky", realm = "Forever", class = "WARRIOR", level = 5, account = "1", provenance = "self", hidden = true },
}
local gear = {
    ["Player-1-ALT1"] = { capturedAt = NOW - 6 * 86400 - 15 * 86400 },  -- 21 days: stale
    ["Player-1-ALT2"] = { capturedAt = NOW - 2 * 3600 },                 -- fresh
    ["Player-1-FRIEND"] = { capturedAt = NOW },                          -- never read
}
local callbacks, toggled = {}, 0
local opened = 0
local AS = {
    PUBLIC_API_VERSION = 1,
    PUBLIC_API_FEATURES = { provenance = true, gear = true },
    GetCharacters = function()
        local out = {}
        for i, c in ipairs(chars) do local t = {} for k, v in pairs(c) do t[k] = v end out[i] = t end
        return out
    end,
    GetCharacterProvenance = function() return nil end,
    GetCharacterGear = function(guid) return gear[guid] end,
    RegisterCallback = function(event, fn) callbacks[event] = callbacks[event] or {}; table.insert(callbacks[event], fn) end,
    ToggleSheet = function() toggled = toggled + 1 end,
    OpenSheet = function() opened = opened + 1 end,
}
local function fire(event, ...) for _, fn in ipairs(callbacks[event] or {}) do fn(event, ...) end end
rawset(_G, "AltStable", AS)
WoW.epoch = NOW

local GG = WoW.loadAddon()
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1 )')
WoW.flush()
local Win = GG.CharactersWindow

-- Groups: this account first, other accounts by their label.
local groups = Win.Groups(GG.API.GetCharacters())
H.eq(groups[1].title, "This account (Account 1)", "this account first, with its label")
H.eq(#groups[1].chars, 3, "...the current character, Elegia and the hidden bank alt")
H.eq(groups[2].title, "Account 2", "the other account, by its label (display only)")
H.eq(groups[2].chars[1].name, "Drakuza", "...Drakuza")
for _, g in ipairs(groups) do for _, c in ipairs(g.chars) do H.check(c.name ~= "Friendo", "never a third-party character: " .. c.name) end end
H.eq(GG.Integrations.RosterProvider.Gear("Player-1-FRIEND"), nil, "a third-party character's gear is never read")
H.eq(GG.Integrations.RosterProvider.Gear(ME), nil, "...nor the current one's from AltStable (Glass Gear reads it live)")
H.eq(GG.Integrations.RosterProvider.Gear("Player-1-ALT2").capturedAt, NOW - 2 * 3600, "an own alt's gear is")

SlashCmdList.GLASSGEAR("characters")
local frame = Win._Frame()
local Wd = Win._W
H.check(frame and frame:IsShown(), "/gg characters opens the page")
H.eq(Wd.status:GetText(), "AltStable connected", "AltStable connected")
H.eq(Wd.count, 4, "four rows: you, Elegia, Banky, Drakuza")
local function row(name)
    for _, r in ipairs(Wd.rows) do if r:IsShown() and r.char and r.char.name == name then return r end end
end
local me = row("Karuzo")
H.check(me.name:GetText():find("(you)", 1, true) ~= nil, "the current character is marked")
H.eq(me.checks[1].label:GetText(), "Discipline", "its specs as boxes")
H.eq(me.checks[3]:GetChecked(), true, "...the current character's specs tracked by default")
H.check(me.status:GetText():find("1 of 3 specs with weights", 1, true) ~= nil, "...weights counted")
local el = row("Elegia")
H.check(el.status:GetText():find("Gear snapshot 21 days old: refresh by playing this character", 1, true) ~= nil, "stale gear: said, with the fix")
H.check(el.status:GetText():find("no weights", 1, true) ~= nil, "no weights: said")
H.eq(el.checks[1]:GetChecked(), false, "an alt isn't tracked until ticked")
local dr = row("Drakuza")
H.check(dr.status:GetText():find("Gear 2 h ago", 1, true) ~= nil, "fresh gear: its age")
H.check(dr.sub:GetText():find("seen by Tilly", 1, true) ~= nil, "an own-account character: who vouched for it")
local bank = row("Banky")
H.check(bank.name:GetText():find("hidden in AltStable", 1, true) ~= nil, "a hidden alt: shown, dimmed")
H.check(bank.status:GetText():find("No gear recorded", 1, true) ~= nil, "...no gear recorded")

-- Without alt rows (an AltStable lacking AS-001/AS-003): alt boxes are
-- inactive, and the page says protection covers this character only.
local realActive = Win.AltProtectionActive
Win.AltProtectionActive = function() return false end
Win.Refresh()
dr = row("Drakuza")
H.eq(dr.checks[1]:IsEnabled(), false, "alts unavailable: an alt's spec box can't be ticked")
H.check(dr.checks[1].alpha < 1, "...and is shown dimmed")
H.eq(row("Karuzo").checks[1]:IsEnabled(), true, "the current character's boxes work")
H.check(Wd.note:GetText():find("this character's ticked specs; alts can't be protected yet", 1, true) ~= nil,
    "the page says protection covers this character only")
Win.SetTracked(dr, 1, true)
H.eq(GG.Prefs.IsTracked("Player-1-ALT2", "MAGE.ARCANE"), false, "...and an alt tick is refused, never stored")
Win.AltProtectionActive = realActive

-- With AltStable's extensions, alts are assessed (GG-203): ticking an alt's spec tracks it.
H.eq(GG.API.GetCapabilities().features.alts, true, "features.alts with AltStable AS-001 + AS-003")
H.eq(Win.AltProtectionActive(), true, "alt protection active")
Win.Refresh()
dr = row("Drakuza")
H.eq(dr.checks[1]:IsEnabled(), true, "...the alt's boxes work")
H.check(Wd.note:GetText():find("keeps upgrades for the ticked specs", 1, true) ~= nil, "...and the note covers every ticked spec")
H.check(Wd.note:GetText():find("amber bag arrows, for items you can mail it", 1, true) ~= nil, "...and says alts get tooltip rows and arrows")
dr.checks[1]:Click()
H.eq(GG.Prefs.IsTracked("Player-1-ALT2", "MAGE.ARCANE"), true, "ticking Arcane tracks it")
H.eq(GG.Prefs.IsTracked("Player-1-ALT2", "MAGE.FIRE"), false, "...and only it")

-- At most LIMITS.targets specs in all (each is a row on every bag item).
local limit = GG.API.LIMITS.targets
GG.API.LIMITS.targets = 5                       -- the priest's 3 + Arcane: one more fits
dr.checks[2]:Click()
H.eq(GG.Prefs.IsTracked("Player-1-ALT2", "MAGE.FIRE"), true, "below the limit: another alt spec ticks")
dr = row("Drakuza")
dr.checks[3]:Click()
H.eq(GG.Prefs.IsTracked("Player-1-ALT2", "MAGE.FROST"), false, "at the limit: refused, never stored")
H.check(Wd.note:GetText():find("At most 5 specs in all", 1, true) ~= nil, "...and the page says why")
dr = row("Drakuza")
dr.checks[2]:Click()
H.eq(GG.Prefs.IsTracked("Player-1-ALT2", "MAGE.FIRE"), false, "unticking always works")
GG.API.LIMITS.targets = limit
Win.Refresh()
me = row("Karuzo")
me.checks[1]:Click()
H.eq(GG.Prefs.IsTracked(ME, "PRIEST.DISCIPLINE"), false, "unticking one of your own specs")
H.eq(GG.Prefs.IsTracked(ME, "PRIEST.SHADOW"), true, "...keeps the others tracked")

-- Open AltStable: OpenSheet (only opens), never ToggleSheet (would close an open sheet).
Wd.openAltStable:Click()
H.eq(opened, 1, "Open AltStable opens AltStable's sheet")
H.eq(toggled, 0, "...with OpenSheet, never ToggleSheet")

-- Changes made elsewhere show: a tracked spec set from the settings page.
GG.Prefs.SetTracked("Player-1-ALT1", "PALADIN.HOLY", true, { "PALADIN.HOLY", "PALADIN.PROTECTION", "PALADIN.RETRIBUTION" })
WoW.flush()
H.eq(row("Elegia").checks[1]:GetChecked(), true, "a spec tracked elsewhere shows ticked without reopening")
-- An alt's gear refreshed by a sync.
gear["Player-1-ALT1"] = { capturedAt = NOW - 3600 }
fire("GearChanged", { "Player-1-ALT1" })
WoW.flush()
H.check(row("Elegia").status:GetText():find("Gear 1 h ago", 1, true) ~= nil, "an alt's new gear shows without reopening")

-- Groups: the label never proves an account.
local g2 = Win.Groups({
    { name = "A", current = true, provenance = "self", account = "" },
    { name = "B", provenance = "self", account = "1" },
    { name = "C", provenance = "own-account", account = "1" },
    { name = "D", provenance = "own-account", account = "" },
    { name = "E", provenance = "own-account", account = "3" },
})
H.eq(g2[1].title, "This account (Account 1)", "this account, with its label")
H.eq(g2[2].title, "Your other accounts", "an own account labelled like this one: not shown as this one")
H.eq(#g2[2].chars, 2, "...it shares the honest heading with the unlabelled one")
H.eq(g2[3].title, "Account 3", "a distinct label names its group")

-- A row limit: no empty headings, and the rest counted.
local saved = Win.MAX_ROWS
Win.MAX_ROWS = 2
Win.Refresh()
H.eq(Wd.count, 2, "two rows at a limit of two")
H.check(Wd.hidden > 0 and Wd.more:GetText():find("more character", 1, true) ~= nil, "...the rest counted and said")
local shownHeads = 0
for _, head in ipairs(Wd.heads) do if head.shown ~= false then shownHeads = shownHeads + 1 end end
H.eq(shownHeads, 1, "...and no heading without rows")
Win.MAX_ROWS = saved
Win.Refresh()

-- The page follows the roster.
chars[4].provenance = "own-account"
fire("ProvenanceChanged")
WoW.flush()
H.eq(Wd.count, 5, "a character proven own appears without reopening")

-- The settings page's button.
frame:Hide()
GG.Options._Panel():Show()
GG.Options.charactersButton:Click()
H.eq(frame:IsShown(), true, "the settings page's button opens it")

-- Unavailable.
AS.PUBLIC_API_FEATURES = { provenance = true }
GG.Integrations.RosterProvider._Reset()
GG.Integrations.RosterProvider.Refresh()
Win.Refresh()
H.eq(Wd.status:GetText(), "AltStable unavailable", "AltStable without AS-003: unavailable")
H.check(Wd.unavailable:GetText():find("Current-character comparisons still work", 1, true) ~= nil, "...current-character comparisons still work")
H.check(Wd.unavailable:GetText():find("AS-003", 1, true) ~= nil, "...naming what is missing")
H.eq(Wd.count, 1, "...only you")
H.eq(Wd.openAltStable:IsEnabled(), true, "...Open AltStable stays available (its sheet is where to fix it)")

-- Usable but failing: never "connected".
AS.PUBLIC_API_FEATURES = { provenance = true, gear = true }
AS.GetCharacters = function() error("down") end
GG.Integrations.RosterProvider._Reset()
GG.Integrations.RosterProvider.Refresh()
Win.Refresh()
H.check(Wd.status:GetText():find("GetCharacters failed", 1, true) ~= nil, "GetCharacters failing: the status says so, not 'connected'")
WoW.errors = {}

H.eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
H.done("test_characters")
