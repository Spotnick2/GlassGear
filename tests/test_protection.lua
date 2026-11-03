------------------------------------------------------------
-- test_protection.lua - GG-301: GlassGear.API.AssessProtection, the runtime
-- around Policy.Protection (pure-tested in test_policy). The protection scope
-- (tracked specs, independent of markers), specs without weights, untrusted
-- baselines never clear, the token (instance, bind state, generation,
-- freshness without any other event), expiresAt, pending item data then
-- EvaluationInvalidated, never deferred, never cached, fail-closed errors.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local INT, HEAL = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT"
local function shoulder(name, stats, bindType)
    return { name = name, equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = stats, bindType = bindType }
end
WoW.items[50] = shoulder("Old Mantle", { [INT] = 10 })
WoW.items[51] = shoulder("Shadow Mantle", { [INT] = 20 }, 2)
WoW.items[52] = shoulder("Holy Mantle", { [HEAL] = 40 })
WoW.items[53] = shoulder("Weak Mantle", { [INT] = 5 }, 2)
WoW.items[54] = shoulder("Healer Spaulders", { [HEAL] = 60, [INT] = 2 }, 2)
WoW.equipped = { [3] = 50 }
WoW.bags[0] = {
    [1] = { itemID = 51, isBound = false, guid = "Item-1-SHADOW" },
    [2] = { itemID = 53, isBound = false, guid = "Item-1-WEAK" },
    [3] = { itemID = 54, isBound = false, guid = "Item-1-HEAL" },
}

local GG = WoW.loadAddon()
local api, S = GG.API, GG.API._state
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR("spec 2 PRIEST.HOLY")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1 )')
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy": Class=Priest, Healing=1, Intellect=0.5 )')
WoW.flush()
local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end return false end
local function bag(slot) return { bag = 0, slot = slot } end
local inval = {}
api.RegisterCallback("EvaluationInvalidated", function(_, p) inval[#inval + 1] = p.reason end, "test_protection")

H.eq(api.GetCapabilities().features.assessProtection, true, "features.assessProtection")

------------------------------------------------------------
-- Verdicts over the protection scope.
------------------------------------------------------------
local p = api.AssessProtection(bag(1))
H.eq(p.verdict, "protect", "a Shadow upgrade is kept")
H.eq(p.recipients[1].spec, "PRIEST.SHADOW", "...Shadow named as recipient")
H.check(type(p.token) == "string" and #p.token > 0, "...with an opaque token")
H.eq(p.instance and p.instance.guid, "Item-1-SHADOW", "...for that instance")
H.check(has(p.reasons, "UNCHECKED_SPECS"), "Discipline has no weights: unchecked, reported")
H.eq(p.unchecked[1].spec, "PRIEST.DISCIPLINE", "...named")

-- Holy has no recorded gear yet: its row compares with the current gear.
local h = api.AssessProtection(bag(3))
H.eq(h.verdict, "protect", "a big Holy upgrade is kept even against the current gear")
local w = api.AssessProtection(bag(2))
H.eq(w.verdict, "unknown", "a weak mantle: Shadow says no, but Holy's baseline is a fallback -> unknown, never clear")
H.check(has(w.reasons, "BASELINE_NOT_TRUSTED"), "...reason BASELINE_NOT_TRUSTED")

-- One Holy session: Holy gets its own recorded gear.
WoW.specGroup = 2
WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
WoW.equipped = { [3] = 52 }
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
WoW.flush()
WoW.specGroup = 1
WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", 1, 2)
WoW.equipped = { [3] = 50 }
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
WoW.flush()
w = api.AssessProtection(bag(2))
H.eq(w.verdict, "clear", "with Holy's gear recorded, the weak mantle is safe to disenchant")
H.eq(type(w.expiresAt), "number", "...expiresAt: when Holy's recorded gear goes stale")

-- Tracked specs, never the marker or tooltip scopes.
GG.Prefs.Set("markers.scope", "current")
GG.Prefs.Set("tooltip.specs", "current")
h = api.AssessProtection(bag(3))
H.eq(h.verdict, "protect", "a Holy upgrade is kept although arrows and tooltips show Shadow only")
local all = { "PRIEST.DISCIPLINE", "PRIEST.HOLY", "PRIEST.SHADOW" }
GG.Prefs.SetTracked(GG.player.key, "PRIEST.HOLY", false, all)
h = api.AssessProtection(bag(3))
H.eq(h.verdict, "clear", "Holy not tracked: its upgrade doesn't keep the item")
GG.Prefs.SetTracked(GG.player.key, "PRIEST.HOLY", true, all)

-- Protection's own threshold (adr/0006). Prefs keeps the two equal today;
-- set apart here, protection reads its own.
GG.db.settings.protection.threshold = 2.0      -- +200 %
api._Invalidate("settings")
H.check(api.AssessProtection(bag(1)).verdict ~= "protect", "a +100 % upgrade under a 200 % protection threshold isn't kept")
H.eq(api.Evaluate({ item = bag(1), scope = "current" }).results[1].status, "upgrade", "...while the marker threshold still calls it an upgrade")
GG.db.settings.protection.threshold = GG.db.settings.markers.threshold
api._Invalidate("settings")

-- Specs without weights.
local keep = api.AssessProtection(bag(2), { noWeights = "keep" })
H.eq(keep.verdict, "unknown", "noWeights = keep: Discipline's missing weights keep the item")
GG.Prefs.Set("protection.noWeights", "keep")
H.eq(api.AssessProtection(bag(2)).verdict, "unknown", "...the setting does the same")
GG.Prefs.Set("protection.noWeights", "ignore")
for _, s in ipairs(all) do GG.Prefs.SetTracked(GG.player.key, s, s == "PRIEST.DISCIPLINE", all) end
local none = api.AssessProtection(bag(2))
H.eq(none.verdict, "unknown", "only a spec without weights tracked: unknown, never clear")
for _, s in ipairs(all) do GG.Prefs.SetTracked(GG.player.key, s, false, all) end
H.eq(api.AssessProtection(bag(2)).reasons[1], "NO_PROTECTION_TARGETS", "nothing tracked: unknown, NO_PROTECTION_TARGETS")
for _, s in ipairs(all) do GG.Prefs.SetTracked(GG.player.key, s, true, all) end

------------------------------------------------------------
-- The token.
------------------------------------------------------------
local t1 = api.AssessProtection(bag(2)).token
H.eq(api.AssessProtection(bag(2)).token, t1, "the same item, nothing changed: the same token")
H.check(api.AssessProtection(bag(1)).token ~= t1, "another instance: another token")
WoW.bags[0][2].isBound = true
local tb = api.AssessProtection(bag(2)).token
H.check(tb ~= t1, "the instance became soulbound: the token changes")
WoW.bags[0][2].isBound = false
H.eq(api.AssessProtection(bag(2)).token, t1, "...and back")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow2": Class=Priest, Intellect=1.1 )')
local t2 = api.AssessProtection(bag(2)).token
H.check(t2 ~= t1, "a weight change (any invalidation): the token changes")

-- Freshness, without any other event.
local before = api.AssessProtection(bag(2))
WoW.flush(); inval = {}
local gen = S.generation
WoW.epoch = before.expiresAt + 1
local after = api.AssessProtection(bag(2))
H.check(S.generation > gen, "past expiresAt: the freshness generation advanced before the call returned")
H.check(after.token ~= before.token, "...so the token changes with no other event")
H.eq(after.verdict, "unknown", "...and stale recorded gear never clears")
WoW.flush()
H.check(has(inval, "freshness"), "...then EvaluationInvalidated(freshness) is delivered")

------------------------------------------------------------
-- Fresh every time; never deferred.
------------------------------------------------------------
local e0 = S.stats.evaluations
api.AssessProtection(bag(2)); api.AssessProtection(bag(2))
H.eq(S.stats.evaluations - e0, 6, "every call computes its three rows (never the result cache)")
local saved = api.LIMITS.perFrame
api.LIMITS.perFrame = 0
H.check(api.AssessProtection(bag(1)).verdict ~= "pending", "the frame budget spent: still a verdict now (never deferred)")
api.LIMITS.perFrame = saved

------------------------------------------------------------
-- Pending item data.
------------------------------------------------------------
WoW.items[60] = shoulder("Unloaded Mantle", { [INT] = 50 }, 2)
WoW.bags[0][4] = { itemID = 60, isBound = false, guid = "Item-1-LATE" }
WoW.cacheMiss[60] = true
local pend = api.AssessProtection(bag(4))
H.eq(pend.verdict, "pending", "item data missing: pending (the consumer keeps it)")
H.check(S.waiting[60] ~= nil, "...the item is loading")
WoW.flush(); inval = {}
WoW.cacheMiss[60] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 60, true)
WoW.flush()
H.check(has(inval, "itemData"), "data arrived: EvaluationInvalidated tells the consumer to ask again")
H.eq(S.waiting[60], nil, "...the load record released")
H.eq(api.AssessProtection(bag(4)).verdict, "protect", "...and the next call has the verdict")

WoW.items[61] = shoulder("Lost Mantle", { [INT] = 50 }, 2)
WoW.bags[0][5] = { itemID = 61, isBound = false, guid = "Item-1-LOST" }
WoW.cacheMiss[61] = true
api.AssessProtection(bag(5))
for _ = 1, 20 do WoW.time = WoW.time + 1; WoW.flush(1) end
H.eq(S.protectionWaits[61], nil, "a load that gives up releases the protection wait")
H.eq(api.AssessProtection(bag(5)).verdict, "pending", "...the next call asks again (still pending, kept)")
WoW.cacheMiss[61] = nil

------------------------------------------------------------
-- Fail-closed.
------------------------------------------------------------
local real = GG.Engine.Policy.Protection
GG.Engine.Policy.Protection = function() error("boom") end
local err = api.AssessProtection(bag(1))
GG.Engine.Policy.Protection = real
H.eq(err.verdict, "unknown", "an error inside: unknown (kept)")
H.eq(err.reasons[1], "INTERNAL_ERROR", "...INTERNAL_ERROR")
H.eq(#WoW.errors, 1, "...and it reaches the error handler")
H.eq(api.AssessProtection({ bag = 3, slot = 9 }).reasons[1], "NO_ITEM", "an empty slot: unknown, NO_ITEM")
local copy = api.AssessProtection(bag(1))
copy.recipients[1].spec = "mangled"
H.eq(api.AssessProtection(bag(1)).recipients[1].spec, "PRIEST.SHADOW", "answers are copies")

H.done("test_protection")
