------------------------------------------------------------
-- test_profiles.lua - GG-105: weight profiles. The model (up to four per
-- spec, the active one by activeAt, import new / replace, weight, name and
-- armor edits, delete, stale versions refused), the codec field, every
-- refusal as a readable text, and the profiles window driven like a player
-- (paste, add, edit, make active, export, armor, delete, read-only, combat).
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local GG = WoW.loadAddon()
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
WoW.flush()
local P, V, store = GG.Profiles, GG.ProfileView, GG.store
local guid = GG.player.key
local SHADOW = '( Pawn: v1: "Shadow": Class=Priest, Intellect=1, SpellDamage=0.8 )'
local RAID = '( Pawn: v1: "Raid": Class=Priest, Intellect=0.5, SpellDamage=1, Spirit=X )'
local SIMS = '( Pawn: v1: "Shadow WoWSims Weights": Class=Priest, Intellect=0.4, Spirit=0.2 )'
local now = time()

------------------------------------------------------------
-- The model.
------------------------------------------------------------
local a = assert(P.ImportNew(store, guid, "PRIEST.SHADOW", SHADOW, now, "PRIEST"))
H.eq(P.ActiveEntry(store, guid, "PRIEST.SHADOW").id, a.id, "the first import is the active profile")
local b = assert(P.ImportNew(store, guid, "PRIEST.SHADOW", RAID, now + 10, "PRIEST"))
H.eq(P.ActiveEntry(store, guid, "PRIEST.SHADOW").id, b.id, "a new import becomes the active profile")
H.eq(#P.ForSpec(store, guid, "PRIEST.SHADOW"), 2, "two profiles for Shadow")
H.check(assert(P.SetActive(store, a.id, a.version, now + 20)), "choose the first again")
H.eq(P.Active(store, guid, "PRIEST.SHADOW").name, "Shadow", "...it is active (latest activeAt wins)")
H.eq(P.Active(store, guid, "PRIEST.SHADOW").weights.Intellect, 1, "...and the engine reads its weights")
local _, err = P.SetActive(store, a.id, "stale:1", now + 30)
H.eq(err, "stale", "an edit with an old version is refused")

assert(P.ImportNew(store, guid, "PRIEST.SHADOW", SHADOW, now + 40, "PRIEST"))
assert(P.ImportNew(store, guid, "PRIEST.SHADOW", SHADOW, now + 50, "PRIEST"))
_, err = P.ImportNew(store, guid, "PRIEST.SHADOW", SHADOW, now + 60, "PRIEST")
H.eq(err, "TOO_MANY_PROFILES", "a fifth profile for a spec is refused")
_, err = P.ImportNew(store, guid, "PRIEST.HOLY", "nonsense", now, "PRIEST")
H.eq(err, "NOT_PAWN", "a bad string is refused with the parser's code")

-- Replace keeps whether it is active and its armor.
a = store:Get(a.id)
a = assert(P.SetArmor(store, a.id, a.version, { 4, 1 }, now + 70))
H.eq(table.concat(a.data.armor, ","), "1,4", "armor stored sorted")
local activeAt = a.data.activeAt
a = assert(P.ImportReplace(store, a.id, a.version, RAID, now + 80, "PRIEST"))
H.eq(a.data.name, "Raid", "replace takes the string's name")
H.eq(a.data.activeAt, activeAt, "...keeps activeAt")
H.eq(table.concat(a.data.armor, ","), "1,4", "...keeps the armor types")
H.eq(a.data.ignored.Spirit, true, "...and carries the X")
_, err = P.SetArmor(store, a.id, a.version, {}, now)
H.eq(err, "NO_ARMOR", "no armor type at all is refused")
_, err = P.SetArmor(store, a.id, a.version, { 99 }, now)
H.eq(err, "UNKNOWN_ARMOR", "an unknown armor type is refused")
a = assert(P.SetArmor(store, a.id, a.version, nil, now + 90))
H.eq(a.data.armor, nil, "nil armor: the spec's default again")

-- Weights.
local function w(text)
    local e = store:Get(a.id)
    local r, why = P.SetWeight(store, a.id, e.version, "Intellect", text, now + 100)
    if r then a = r end
    return r, why
end
H.check(w("0,4567"), "a weight with a decimal comma")
H.eq(a.data.weights.Intellect, 0.457, "...rounded to 3 decimals")
H.eq(a.data.source, "manual", "an edited profile is 'manual' (edited in Glass Gear)")
H.eq(a.data.origin, "Raid", "...the imported scale's name stays as origin")
H.check(w("X"), "X ignores the stat")
H.eq(a.data.ignored.Intellect, true, "...ignored")
H.eq(a.data.weights.Intellect, nil, "...no weight")
H.check(w(""), "empty clears it")
H.eq(a.data.ignored.Intellect, nil, "...not ignored any more")
H.eq(select(2, w("abc")), "NOT_A_NUMBER", "text is refused")
H.eq(select(2, w("1000")), "VALUE_OUT_OF_RANGE", "out of range is refused")
H.check(w("-2"), "a negative weight")
H.eq(a.data.weights.Intellect, -2, "...stored exactly (-2, not -2.001)")
H.eq(select(2, w("-2")), "UNCHANGED", "the same value again changes nothing")
H.check(w("-0.4567"), "a negative fraction")
H.eq(a.data.weights.Intellect, -0.457, "...rounded half away from zero")
H.check(w("-1.25"), "an exact negative fraction")
H.eq(a.data.weights.Intellect, -1.25, "...unchanged by rounding")
H.check(w("0.0005"), "a positive half")
H.eq(a.data.weights.Intellect, 0.001, "...rounds up")
local e0 = store:Get(a.id)
H.check(P.SetWeight(store, a.id, e0.version, "Intellect", "", now), "clear Intellect")
e0 = store:Get(a.id)
H.eq(select(2, P.SetWeight(store, a.id, e0.version, "SpellDamage", "0", now)), "NO_WEIGHTS",
    "removing the last weight is refused (a profile has weights)")
H.eq(select(2, P.SetWeight(store, a.id, e0.version, "Mana", "1", now)), "UNKNOWN_STAT", "an unknown stat is refused")

local s = assert(P.ImportNew(store, guid, "PRIEST.HOLY", SIMS, now, "PRIEST"))
H.check(H.has(s.data.missing, "HitRating"), "a WoWSims import lists HitRating as missing")
s = assert(P.SetWeight(store, s.id, s.version, "HitRating", "0.3", now))
H.check(not H.has(s.data.missing or {}, "HitRating"), "setting a missing stat removes it from the missing list")

-- Rename-only and armor-only edits are edits too.
local fresh = assert(P.ImportNew(store, guid, "PRIEST.DISCIPLINE", SHADOW, now, "PRIEST"))
fresh = assert(P.Rename(store, fresh.id, fresh.version, "Renamed", now))
H.eq(fresh.data.source, "manual", "a rename alone makes the profile 'manual'")
H.eq(fresh.data.origin, "Shadow", "...keeping the imported scale's name as origin")
H.eq(select(2, P.Rename(store, fresh.id, fresh.version, "Renamed", now)), "UNCHANGED", "the same name changes nothing")
fresh = assert(P.ImportReplace(store, fresh.id, fresh.version, SHADOW, now, "PRIEST"))
H.eq(fresh.data.source, "imported-pawn", "(replaced: imported again)")
fresh = assert(P.SetArmor(store, fresh.id, fresh.version, { 1 }, now))
H.eq(fresh.data.source, "manual", "an armor change alone makes the profile 'manual'")
assert(P.Delete(store, fresh.id, fresh.version))

-- Names.
local r = assert(P.Rename(store, s.id, s.version, "  Holy raid  ", now))
H.eq(r.data.name, "Holy raid", "names are trimmed")
H.eq(select(2, P.Rename(store, s.id, r.version, 'a"b', now)), "BAD_NAME", "a double quote is refused (Pawn export)")
H.eq(select(2, P.Rename(store, s.id, r.version, "   ", now)), "EMPTY_NAME", "an empty name is refused")
r = assert(P.Rename(store, s.id, r.version, string.rep("n", 40), now))
H.eq(#r.data.name, P.MAX_NAME, "a long name is cut to 24")

-- Delete.
local victim = P.ActiveEntry(store, guid, "PRIEST.HOLY")
assert(P.Delete(store, victim.id, victim.version))
H.eq(store:Get(victim.id).deleted, true, "delete leaves a tombstone (sync)")
H.eq(P.Active(store, guid, "PRIEST.HOLY"), nil, "Holy: no weights again")

-- /gg import replaces the active profile.
local before = #P.ForSpec(store, guid, "PRIEST.SHADOW")
local act0 = P.ActiveEntry(store, guid, "PRIEST.SHADOW")
local _, _, replaced = P.ImportPawn(store, guid, "PRIEST.SHADOW", SHADOW, now + 200, nil, "PRIEST")
H.eq(replaced, true, "/gg import replaces the active profile's weights")
H.eq(#P.ForSpec(store, guid, "PRIEST.SHADOW"), before, "...without a new profile")
H.eq(P.ActiveEntry(store, guid, "PRIEST.SHADOW").id, act0.id, "...the same one stays active")

-- Codec: activeAt round-trips; a line without it still decodes.
local C = GG.Engine.Codec
local line = assert(C.Encode(P.ActiveEntry(store, guid, "PRIEST.SHADOW")))
local back = assert(C.Decode(line))
H.eq(back.data.activeAt, P.ActiveEntry(store, guid, "PRIEST.SHADOW").data.activeAt, "activeAt survives the codec")
local plain = { id = guid .. ":PRIEST.HOLY:x", kind = "profile", version = "w:1", ancestors = {}, provenance = "self",
    data = { specKey = "PRIEST.HOLY", name = "H", source = "manual", updatedAt = 5, weights = { Intellect = 1 } } }
local back2 = assert(C.Decode(assert(C.Encode(plain))))
H.eq(back2.data.activeAt, nil, "a profile never chosen has no activeAt")
H.eq(C.ValidData("profile", { specKey = "PRIEST.HOLY", name = "H", source = "manual", updatedAt = 5,
    weights = { Intellect = 1 }, activeAt = "soon" }), false, "a non-number activeAt is invalid")

------------------------------------------------------------
-- Every refusal reads as a sentence.
------------------------------------------------------------
local codes = {}
for _, text in ipairs({ "", "hello", "{ }", '( Pawn: v2: "x": Intellect=1 )', '( Pawn: v1: "x": Intellect )',
    '( Pawn: v1: "x": Intellect=5000 )', '( Pawn: v1: "x": Intellect=0 )' }) do
    local _, code = GG.PawnString.Parse(text)
    codes[#codes + 1] = code
end
local many = {}
for i = 1, 41 do many[#many + 1] = "Unknown" .. i .. "=1" end
codes[#codes + 1] = select(2, GG.PawnString.Parse('( Pawn: v1: "x": Intellect=1, ' .. table.concat(many, ", ") .. " )"))
for _, c in ipairs({ "TOO_MANY_PROFILES", "NOT_A_NUMBER", "UNKNOWN_STAT", "EMPTY_NAME", "BAD_NAME", "NO_ARMOR",
    "UNKNOWN_ARMOR", "stale", "deleted", "conflict-copy", "unknown-id", "read-only",
    "CHARACTER_EXPORT_NOT_WEIGHTS" }) do codes[#codes + 1] = c end
for _, c in ipairs(codes) do
    local t = V.ErrorText(c)
    H.check(c ~= nil and not t:find("^Can't do that"), "readable text for " .. tostring(c) .. ": " .. t)
end
H.eq(V.ErrorText("BAD_PAIR:3"), "Can't read entry 3: expected Stat=number", "the entry number is named")
H.check(V.WarningText("UNSUPPORTED_TOKEN:Mana"):find("Mana", 1, true) ~= nil, "a kept token is named")
H.check(V.WarningText("WOWSIMS_DROPPED_STATS"):find("missing, not as zero", 1, true) ~= nil, "WoWSims gaps explained")
H.eq(V.Freshness(now - 7200, now), "Updated 2 hours ago", "freshness in hours")
H.eq(V.Freshness(now - 86400, now), "Updated 1 day ago", "...in days, singular")
H.eq(V.Freshness(now - 5, now), "Updated just now", "...just now")
H.eq(V.SourceLabel("imported-pawn"), "Imported Pawn weights", "source label")
for _, t in ipairs(GG.Data.Stats.ORDER) do
    local l = V.StatLabel(t)
    H.check(type(l) == "string" and l ~= "" and not l:match("^Is%u"), "a label for " .. t .. ": " .. tostring(l))
end
H.eq(V.StatLabel("HitRating"), "Hit Rating", "camel case split")
local pv = V.Preview(SIMS, "PRIEST")
H.eq(pv.ok, true, "preview: a WoWSims string is valid")
H.check(pv.lines[1].text:find("WoWSims Pawn EP export", 1, true) ~= nil, "...named as such")
H.eq(pv.lines[2].level, "warn", "...with its warning")
H.eq(V.Preview("( Pawn: v1: \"x\": Class=Priest )").lines[1].text, "No weight values found", "preview: the error")
H.eq(V.Preview("   ").ok, false, "preview: nothing pasted yet")

------------------------------------------------------------
-- The window, as a player uses it.
------------------------------------------------------------
-- A clean character: drop what the model tests made.
for id in pairs(store.entries) do store.entries[id] = nil end
local inval = {}
GG.API.RegisterCallback("EvaluationInvalidated", function(_, p) inval[#inval + 1] = p.reason end, "test_profiles")
local Win = GG.ProfilesWindow
SlashCmdList.GLASSGEAR("profiles")
local frame = Win._Frame()
local Wd = Win._W
H.check(frame and frame:IsShown(), "/gg profiles opens the window")
H.check(H.has(UISpecialFrames, Win.NAME), "Escape closes it (UISpecialFrames)")
H.eq(Win._state.spec, "PRIEST.SHADOW", "the current spec is selected first")
H.eq(Wd.empty.shown ~= false, true, "no profile yet: the empty text shows")
H.check(Wd.empty:GetText():find("Shadow: no profile yet", 1, true) ~= nil, "...naming the spec")
H.eq(Wd.specs[3].sub:GetText():find("no weights", 1, true) ~= nil, true, "the spec list says 'no weights'")

WoW.type(Wd.input, "( Pawn: v1: \"x\": Class=Priest )", false)
H.eq(Wd.preview:GetText(), "No weight values found", "a bad paste: the error, live")
H.eq(Wd.importNew:IsEnabled(), false, "...Add is disabled")
WoW.type(Wd.input, SHADOW, false)
H.check(Wd.preview:GetText():find("Valid Pawn string \"Shadow\": 2 weights", 1, true) ~= nil, "a good paste: valid, 2 weights")
H.eq(Wd.importNew:IsEnabled(), true, "...Add is enabled")
H.eq(Wd.importReplace:IsEnabled(), false, "...Replace needs a profile")
WoW.flush(); inval = {}
Wd.importNew:Click()
WoW.flush()
local active = P.ActiveEntry(store, guid, "PRIEST.SHADOW")
H.check(active ~= nil, "Add as new profile: Shadow has weights")
H.eq(Win._state.id, active.id, "...shown in the window")
H.eq(Wd.input:GetText(), "", "...the import box is cleared")
H.check(H.has(inval, "profiles"), "...cached answers are invalidated")
H.eq(GG.API.GetProfile(guid, "PRIEST.SHADOW").name, "Shadow", "...the API sees it")
H.eq(Wd.empty.shown, false, "...the empty text is gone")
H.eq(Wd.active.shown, true, "...marked Active")
H.eq(Wd.makeActive.shown, false, "...no Make active button")

-- Edit a weight in its row.
local function row(token)
    for _, rw in ipairs(Wd.rows) do if rw.token == token and rw.shown ~= nil and rw:IsShown() then return rw end end
end
H.eq(row("Intellect").box:GetText(), "1", "the Intellect row shows 1")
H.eq(row("Spirit"), nil, "an unweighted stat isn't listed")
WoW.type(row("Intellect").box, "1.25")
H.eq(P.Active(store, guid, "PRIEST.SHADOW").weights.Intellect, 1.25, "typing 1.25 + Enter stores it")
H.check(Wd.source:GetText():find("Edited in Glass Gear", 1, true) ~= nil, "...the source says edited")
WoW.type(row("Intellect").box, "lots")
H.eq(P.Active(store, guid, "PRIEST.SHADOW").weights.Intellect, 1.25, "a bad value isn't stored")
H.check(Wd.message:GetText():find("Not a number", 1, true) ~= nil, "...and says why")
H.eq(row("Intellect").box:GetText(), "1.25", "...the row shows the stored value again")
Wd.showAll:Click()
H.check(row("Spirit") ~= nil, "Show all stats lists every stat")
WoW.type(row("Spirit").box, "x")
H.eq(P.Active(store, guid, "PRIEST.SHADOW").ignored.Spirit, true, "X in a row ignores the stat")
Wd.showAll:Click()

-- Changed elsewhere while shown: the window's version is stale.
local cur = P.ActiveEntry(store, guid, "PRIEST.SHADOW")
assert(P.SetWeight(store, cur.id, cur.version, "SpellDamage", "2", now))
WoW.type(row("Intellect").box, "3")
H.check(Wd.message:GetText():find("Changed elsewhere", 1, true) ~= nil, "a stale edit is refused and reported")
H.eq(P.Active(store, guid, "PRIEST.SHADOW").weights.Intellect, 1.25, "...nothing overwritten")
H.eq(row("SpellDamage").box:GetText(), "2", "...the window shows the other change")
WoW.type(row("Intellect").box, "3")
H.eq(P.Active(store, guid, "PRIEST.SHADOW").weights.Intellect, 3, "...and the next edit goes through")

-- A field being typed in while a change arrives: the draft never overwrites it.
local box = row("Intellect").box
WoW.type(box, "5", false)                   -- typing, no Enter yet
cur = P.ActiveEntry(store, guid, "PRIEST.SHADOW")
assert(P.SetWeight(store, cur.id, cur.version, "Intellect", "4", now))
P.Changed(guid)
WoW.flush()                                 -- the window refreshes while the box has focus
H.eq(box:GetText(), "5", "a refresh leaves the focused draft alone")
box:ClearFocus()
H.eq(P.Active(store, guid, "PRIEST.SHADOW").weights.Intellect, 4, "focus lost: the draft doesn't overwrite the newer 4")
H.check(Wd.message:GetText():find("Changed elsewhere", 1, true) ~= nil, "...it is refused as stale")
H.eq(row("Intellect").box:GetText(), "4", "...and the box shows the newer value")
box = row("Intellect").box
box:SetFocus()                              -- focused, nothing typed
cur = P.ActiveEntry(store, guid, "PRIEST.SHADOW")
assert(P.SetWeight(store, cur.id, cur.version, "Intellect", "3", now))
P.Changed(guid)
WoW.flush()
box:ClearFocus()
H.eq(row("Intellect").box:GetText(), "3", "focused without typing: on focus loss the box shows the newer value")
H.eq(P.Active(store, guid, "PRIEST.SHADOW").weights.Intellect, 3, "...nothing written")

WoW.type(Wd.name, "Draft name", false)
cur = P.ActiveEntry(store, guid, "PRIEST.SHADOW")
assert(P.Rename(store, cur.id, cur.version, "Theirs", now))
P.Changed(guid)
WoW.flush()
Wd.name:ClearFocus()
H.eq(P.Active(store, guid, "PRIEST.SHADOW").name, "Theirs", "a name draft doesn't overwrite a newer rename")

-- Rename.
WoW.type(Wd.name, "Shadow raid")
H.eq(P.Active(store, guid, "PRIEST.SHADOW").name, "Shadow raid", "the name box renames")

-- A second profile, then Make active.
WoW.type(Wd.input, RAID, false)
Wd.importNew:Click()
H.eq(P.Active(store, guid, "PRIEST.SHADOW").name, "Raid", "a second import is active")
H.eq(Wd.tabs[2].shown, true, "two profile tabs")
local first = Wd.tabs[1].id
H.check(store:Get(first).data.name == "Shadow raid", "the first tab is the first profile")
Wd.tabs[1]:Click()
H.eq(Win._state.id, first, "clicking a tab shows that profile")
H.eq(Wd.makeActive.shown, true, "...not active: Make active is offered")
Wd.makeActive:Click()
H.eq(P.Active(store, guid, "PRIEST.SHADOW").id, first, "Make active switches the spec's profile")

-- Replace from the import box.
WoW.type(Wd.input, SHADOW, false)
H.check(Wd.importReplace.label_text:find("Shadow raid", 1, true) ~= nil, "Replace names the shown profile")
Wd.importReplace:Click()
H.eq(store:Get(first).data.name, "Shadow", "Replace takes the string's weights and name")
H.eq(P.Active(store, guid, "PRIEST.SHADOW").id, first, "...and it stays active")

-- Export.
Wd.export:Click()
local out = Wd.input:GetText()
H.check(out:find('^%( Pawn: v1: "Shadow": Class=Priest, ') ~= nil, "Export fills the box with a Pawn string")
H.eq(Wd.input.highlighted, true, "...selected, ready for Ctrl+C")
local reparsed = GG.PawnString.Parse(out, { class = "PRIEST" })
H.eq(reparsed and reparsed.weights.SpellDamage, 0.8, "...and it imports back")
Wd.clear:Click()
H.eq(Wd.input:GetText(), "", "Clear empties the box")

-- Armor types.
H.eq(Wd.armorDefault:GetChecked(), true, "armor: spec default at first")
H.check(Wd.armorDefault.label:GetText():find("Cloth", 1, true) ~= nil, "...naming Cloth")
H.eq(Wd.armor[2].shown, false, "...the type boxes are hidden")
Wd.armorDefault:Click()
H.eq(table.concat(store:Get(first).data.armor, ","), "1", "unchecking starts from the spec's types (cloth)")
H.eq(Wd.armor[2].shown, true, "...the type boxes show")
Wd.armor[2]:Click()
H.eq(table.concat(store:Get(first).data.armor, ","), "1,2", "checking Leather allows it")
Wd.armor[1]:Click()
Wd.armor[2]:Click()
H.check(Wd.message:GetText():find("at least one armor type", 1, true) ~= nil, "unchecking the last type is refused")
H.eq(table.concat(store:Get(first).data.armor, ","), "2", "...leather stays")
Wd.armorDefault:Click()
H.eq(store:Get(first).data.armor, nil, "checking Spec default again: the default")

-- Other specs.
Wd.specs[2]:Click()
H.eq(Win._state.spec, "PRIEST.HOLY", "selecting Holy")
H.eq(Wd.empty.shown, true, "...no Holy profile")
H.eq(Wd.tabs[1].shown, false, "...no tabs")

-- Delete takes two clicks.
Wd.specs[3]:Click()
Wd.tabs[2]:Click()
local victimId = Win._state.id
Wd.delete:Click()
H.eq(store:Get(victimId).deleted, nil, "one click on Delete only asks")
H.eq(Wd.delete.label_text, "Confirm delete", "...the button says so")
WoW.time = WoW.time + 10
Wd.delete:Click()
H.eq(store:Get(victimId).deleted, nil, "a second click too late asks again")
Wd.delete:Click()
H.eq(store:Get(victimId).deleted, true, "two clicks in time delete it")
H.eq(Wd.tabs[2].shown, false, "...one tab left")

-- Read-only session.
GG.readOnly = true
local cnt = #P.ForSpec(store, guid, "PRIEST.SHADOW")
WoW.type(Wd.input, RAID, false)
H.eq(Wd.importNew:IsEnabled(), false, "read-only: Add is disabled")
Win.ImportNew()
H.eq(#P.ForSpec(store, guid, "PRIEST.SHADOW"), cnt, "...nothing is stored")
H.check(Wd.message:GetText():find("Read-only", 1, true) ~= nil, "...and says why")
GG.readOnly = false
Wd.clear:Click()

-- A /gg import while the window is open shows at once.
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ' .. RAID)
WoW.flush()
H.eq(Wd.tabs[1].text:GetText():find("Raid", 1, true) ~= nil, true, "/gg import while open: the window follows")

-- Combat: Escape's list is left for the fight.
WoW.fire("PLAYER_REGEN_DISABLED")
H.eq(H.has(UISpecialFrames, Win.NAME), false, "in combat the window leaves UISpecialFrames")
WoW.fire("PLAYER_REGEN_ENABLED")
H.eq(#(function() local n = {} for _, x in ipairs(UISpecialFrames) do if x == Win.NAME then n[#n + 1] = x end end return n end)(),
    1, "...and comes back once after it")

-- Dragging saves the position; closing hides it.
frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -50)
local bar
for _, f in ipairs(WoW.frames) do if f.parent == frame and f._scripts.OnDragStop then bar = f end end
bar._scripts.OnDragStop(bar)
H.eq(GG.db.ui.windows.profiles.x, 100, "the window position is saved")
SlashCmdList.GLASSGEAR("profiles PRIEST.HOLY")
H.eq(Win._state.spec, "PRIEST.HOLY", "/gg profiles <spec> opens on that spec")
SlashCmdList.GLASSGEAR("profiles WARRIOR.ARMS")
H.check(WoW.chat():find("usage: /gg profiles", 1, true) ~= nil, "another class's spec: usage")
frame:Hide()
H.eq(frame:IsShown(), false, "closed")

-- The settings page opens it too.
GG.Options._Panel():Show()
GG.Options.profilesButton:Click()
H.eq(frame:IsShown(), true, "the settings page's Weight profiles button opens the window")
frame:Hide()

-- Opened for the first time during a fight: no Escape entry until it ends.
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
Win._Reset()
SlashCmdList.GLASSGEAR("profiles")
H.eq(Win._Frame():IsShown(), true, "first opened in combat: the window opens")
H.eq(H.has(UISpecialFrames, Win.NAME), false, "...without an Escape entry during the fight")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
H.eq(H.has(UISpecialFrames, Win.NAME), true, "...the entry comes after it")

H.eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
for name in pairs(WoW.globalWrites) do H.check(false, "undeclared global written: " .. name) end
H.done("test_profiles")
