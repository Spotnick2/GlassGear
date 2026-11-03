------------------------------------------------------------
-- test_baselines.lua - GG-108: per-spec baselines. Capture of the current
-- spec's gear (login, equipment change, spec change), stored as entries;
-- a Holy result uses Holy gear after one Holy session; unchanged gear mints
-- no new version; staleness after 14 days, reported in the tooltip and /gg;
-- equipment sets (mapped with /gg set, or assigned in the client), with
-- ambiguous or missing items left unknown; the worn off-hand as companion;
-- per-spec pending while a stored baseline's items load; unknown spec.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local INT, HEAL = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT"
local function shoulder(name, stats) return { name = name, equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = stats } end
WoW.items[50] = shoulder("Old Mantle", { [INT] = 10 })
WoW.items[52] = shoulder("Holy Mantle", { [HEAL] = 40 })
WoW.items[54] = shoulder("Healer Spaulders", { [HEAL] = 30 })
WoW.items[55] = shoulder("Set Mantle", { [HEAL] = 20 })
WoW.items[60] = { name = "Staff", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 10, stats = { [INT] = 20 } }
WoW.items[61] = { name = "Dagger", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 15, stats = { [INT] = 5 } }
WoW.items[62] = { name = "Orb", equipLoc = "INVTYPE_HOLDABLE", classID = 4, subclassID = 0, stats = { [INT] = 5 } }
WoW.items[63] = { name = "Mace", equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subclassID = 4, stats = { [HEAL] = 30 } }
WoW.equipped = { [3] = 50, [16] = 61, [17] = 62 }

local GG = WoW.loadAddon()
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR("spec 2 PRIEST.HOLY")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1, SpellDamage=1 )')
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy": Class=Priest, Intellect=1, Healing=1 )')
WoW.flush()

local guid = GG.player.key
local SH, HO = guid .. ":PRIEST.SHADOW:baseline", guid .. ":PRIEST.HOLY:baseline"
local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end return false end
local function result(itemID, spec)
    local r = GG.API.Evaluate({ item = WoW.link(itemID), scope = "own" })
    for _, x in ipairs(r.results) do if x.spec == spec then return x, r end end
end
local function holy(itemID) return result(itemID, "PRIEST.HOLY") end
local function equip(t)
    WoW.equipped = t
    WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
    WoW.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
end
local function switch(group)
    WoW.specGroup = group
    WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", group, 3 - group)
end

------------------------------------------------------------
-- Login: the current spec's gear is captured as an entry.
------------------------------------------------------------
local e = GG.store:Get(SH)
H.check(e ~= nil, "login: the Shadow baseline is captured")
H.eq(e.kind, "baseline", "...as a baseline entry")
H.eq(e.data.source, "observed", "...source observed")
H.eq(e.data.slots[3].item, GG.Compat.GearItemString(WoW.link(50)), "...the trimmed item string")
H.eq(e.data.slots[1].state, "empty", "...empty slots recorded as empty")
H.eq(e.data.group, 1, "...with its spec group")
H.eq(GG.store:Get(HO), nil, "Holy: nothing recorded yet")
local v1 = e.version

local h = holy(54)
H.eq(h.baseline.source, "fallback-current", "no Holy gear recorded: compared with the current gear")
H.check(has(h.reasons, "BASELINE_FALLBACK"), "...and labelled so")
H.eq(h.status, "upgrade", "...30 healing beats the worn 10-intellect mantle")
SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("gear: none recorded", 1, true) ~= nil, "/gg says no Holy gear is recorded and how to fix it")

------------------------------------------------------------
-- One Holy session.
------------------------------------------------------------
switch(2)
equip({ [3] = 52, [16] = 60 })
WoW.flush()
H.eq(GG.currentSpec, "PRIEST.HOLY", "spec group 2 is Holy")
local he = GG.store:Get(HO)
H.check(he ~= nil, "Holy gear captured during the Holy session")
H.eq(he.data.slots[3].item, GG.Compat.GearItemString(WoW.link(52)), "...the Holy mantle")
H.eq(he.data.slots[16].item, GG.Compat.GearItemString(WoW.link(60)), "...the staff")
H.eq(he.data.slots[17].state, "empty", "...no off-hand")
H.eq(he.data.group, 2, "...group 2")
H.eq(GG.store:Get(SH).version, v1, "Shadow's entry untouched while Holy is played")

switch(1)
equip({ [3] = 50, [16] = 61, [17] = 62 })
WoW.flush()
H.eq(GG.store:Get(SH).version, v1, "back in unchanged Shadow gear: no new version")

h = holy(54)
H.eq(h.baseline.source, "observed", "a Holy result uses Holy gear after one Holy session")
H.eq(h.status, "no_upgrade", "...30 healing loses to the recorded 40")
H.eq(h.baseline.stale, false, "...fresh")
H.eq(h.baseline.expiresAt, he.data.capturedAt + GG.Baselines.STALE_AFTER, "...expires 14 days after capture")
local s = result(54, "PRIEST.SHADOW")
H.eq(s.baseline.source, "observed", "the current spec compares with what it wears now")

-- Companion: a main-hand mace for Holy, whose gear has a 2H staff, pairs with the worn orb.
h = holy(63)
H.check(not has(h.reasons, "NEEDS_OFFHAND"), "the worn off-hand completes a 1H against Holy's staff")
H.eq(h.status, "upgrade", "...mace + orb beat the staff for Holy")

------------------------------------------------------------
-- Stale after 14 days.
------------------------------------------------------------
WoW.epoch = WoW.epoch + 15 * 86400
h = holy(54)
H.eq(h.baseline.stale, true, "15 days later: Holy's recorded gear is stale")
H.check(has(h.reasons, "BASELINE_STALE"), "...reason BASELINE_STALE")
local tip = WoW.newTooltip("GameTooltip")
GG.Results.Reset()
WoW.showItem(tip, { type = 0, id = 54, hyperlink = WoW.link(54) })
local found = false
for _, l in ipairs(tip.lines) do if l.left == "Gear recorded over 14 days ago: Holy" then found = true end end
H.check(found, "the tooltip reports the stale baseline")
SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("stale: play it again", 1, true) ~= nil, "/gg reports it too")
equip({ [3] = 50, [16] = 61, [17] = 62 })
WoW.flush()
H.check(GG.store:Get(SH).version ~= v1, "unchanged gear re-confirms its capture time after a day")

------------------------------------------------------------
-- Equipment sets.
------------------------------------------------------------
WoW.bags[0] = { [1] = { itemID = 55, isBound = true }, [2] = { itemID = 60, isBound = true } }
local ignored = {}
for _, slot in ipairs(GG.Data.Slots.GEAR) do if slot ~= 3 and slot ~= 16 then ignored[slot] = true end end
WoW.sets[7] = { name = "Holy Set", items = { [3] = 55, [16] = 60 }, ignored = ignored }
SlashCmdList.GLASSGEAR("set PRIEST.HOLY holy set")
H.check(WoW.chat():find("PRIEST.HOLY -> equipment set 'Holy Set'", 1, true) ~= nil, "/gg set maps a set (any case)")
h = holy(54)
H.eq(h.baseline.source, "equipment-set", "a mapped set wins over recorded gear")
H.eq(h.status, "upgrade", "...30 healing beats the set's 20")
H.eq(h.baseline.complete, true, "...every set item found")
local live = GG.Compat.EquippedBaseline(time())
local setB = GG.Capture.BaselineFor("PRIEST.HOLY", live, time())
H.eq(setB.slots[17].itemID, 62, "an ignored set slot keeps what is worn (the orb)")
H.eq(setB.slots[3].itemID, 55, "...the set's own slots come from the set")
WoW.bags[0][3] = { itemID = 55, enchant = 1883 }
h = holy(54)
H.eq(h.baseline.complete, false, "two different instances of a set item: that slot is unknown, never a guess")
H.eq(h.status, "unknown", "...so the comparison in that slot is unknown, not a verdict")
H.check(has(h.reasons, "BASELINE_SLOT_UNKNOWN"), "...reason BASELINE_SLOT_UNKNOWN")
WoW.bags[0][3] = nil
WoW.bags[0][1] = nil
h = holy(54)
H.eq(h.baseline.complete, false, "a set item no longer worn or in the bags (bank): unknown")
WoW.bags[0][1] = { itemID = 55, isBound = true }
SlashCmdList.GLASSGEAR("set PRIEST.HOLY Nope")
H.check(WoW.chat():find("no equipment set named 'Nope'. Sets: Holy Set", 1, true) ~= nil, "an unknown set name lists the sets")
SlashCmdList.GLASSGEAR("set PRIEST.HOLY none")
h = holy(54)
H.eq(h.baseline.source, "observed", "set unmapped: recorded gear again")
WoW.sets[7].specGroup = 2
h = holy(54)
H.eq(h.baseline.source, "equipment-set", "the set the client assigned to Holy's group is used")
SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("(assigned in the client)", 1, true) ~= nil, "/gg says where the set came from")
WoW.sets[7].specGroup = nil

------------------------------------------------------------
-- A stored baseline whose items aren't loaded: that spec is pending, alone.
------------------------------------------------------------
local ready = {}
GG.API.RegisterCallback("EvaluationReady", function(_, payload) ready[#ready + 1] = payload end, "test_baselines")
GG.Capture._Reset()
WoW.cacheMiss[52] = true
local hp, r = holy(54)
H.eq(hp.status, "pending", "Holy pending while its recorded mantle loads")
H.check(has(hp.reasons, "BASELINE_ITEM_DATA_PENDING"), "...reason BASELINE_ITEM_DATA_PENDING")
H.check(result(54, "PRIEST.SHADOW").status ~= "pending", "...Shadow is not held up")
WoW.cacheMiss[52] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 52, true)
WoW.flush()
local done
for _, p in ipairs(ready) do if p.requestId == r.requestId then done = p.response end end
local doneHoly
for _, x in ipairs(done and done.results or {}) do if x.spec == "PRIEST.HOLY" then doneHoly = x end end
H.eq(doneHoly and doneHoly.baseline.source, "observed", "data arrived: the Holy result completes against Holy gear")
H.eq(doneHoly and doneHoly.status, "no_upgrade", "...a full comparison, not an unknown slot")

------------------------------------------------------------
-- Unknown spec: nothing is captured.
------------------------------------------------------------
GG.charDB.specMap[1] = nil
GG.ResolveSpec()
local before = GG.store:Get(SH).version
equip({ [3] = 54, [16] = 61, [17] = 62 })
WoW.flush()
H.eq(GG.store:Get(SH).version, before, "no spec mapped: the gear is not recorded for any spec")
H.eq(select(2, GG.Capture.Observe(time())), "unknown-spec", "...reason unknown-spec")

------------------------------------------------------------
-- The pure parts.
------------------------------------------------------------
local B = GG.Baselines
local liveT = { slots = { [3] = { state = "occupied", item = "item:1" }, [5] = { state = "occupied", item = string.rep("9", 70) },
    [6] = { state = "empty" } } }
local snap = B.Snapshot(liveT, "PRIEST.HOLY", "observed", 1000, 2, 64)
H.eq(snap.slots[3].item, "item:1", "snapshot keeps the item string")
H.eq(snap.slots[5].state, "unknown", "an item string over MAX_ITEM is stored as unknown")
H.eq(snap.slots[6].state, "empty", "empty stays empty")
H.eq(snap.slots[1].state, "unknown", "a slot the live baseline lacks is unknown")
H.eq(B.NeedsWrite(nil, snap, 1000), true, "nothing stored: write")
H.eq(B.NeedsWrite(snap, snap, 1000 + 3600), false, "same gear an hour later: no write")
H.eq(B.NeedsWrite(snap, snap, 1000 + B.REFRESH_AFTER), true, "same gear a day later: re-confirm")
local other = B.Snapshot(liveT, "PRIEST.HOLY", "observed", 1000, 1, 64)
H.eq(B.SameGear(snap, other), false, "another spec group is a different capture")
local hyd, miss = B.Hydrate(snap, function(item) return { itemID = 1, ready = false } end)
H.eq(miss[1], 1, "hydrate lists items still loading")
H.eq(hyd.slots[3].state, "unknown", "...as unknown slots, never empty")

H.eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
H.done("test_baselines")
