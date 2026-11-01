------------------------------------------------------------
-- test_api_contract.lua - GlassGear.API v1 shape, version gating, unsupported
-- operations, pending -> EvaluationReady, timeouts, copies (docs/API.md).
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

-- Items: an equipped shoulder and a better one in the bags.
WoW.items[50] = { name = "Old Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    stats = { ITEM_MOD_INTELLECT_SHORT = 8, ITEM_MOD_SPELL_POWER_SHORT = 12 } }
WoW.items[60] = { name = "Moonwoven Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    bindType = 2, stats = { ITEM_MOD_INTELLECT_SHORT = 12, ITEM_MOD_SPELL_POWER_SHORT = 18 } }
WoW.equipped[3] = 50
WoW.bags[0] = { [1] = { itemID = 60, isBound = false, guid = "Item-1-AAA" } }

local GG = WoW.loadAddon()
local api = GG.API

-- Discovery the way a consumer does it.
local found = rawget(rawget(_G, "GlassGear"), "API")
H.eq(found.API_VERSION, 1, "major version 1")
local caps = api.GetCapabilities()
H.eq(caps.features.evaluate, true, "evaluate supported")
H.eq(caps.features.assessProtection, false, "protection not yet (GG-301)")
H.eq(caps.features.alts, false, "alts unavailable without AltStable extensions")
H.check(caps.unavailable.alts:find("AltStable", 1, true) ~= nil, "reason names AltStable")
caps.features.evaluate = false
H.eq(api.GetCapabilities().features.evaluate, true, "returns are copies")

-- Characters and specs.
local chars = api.GetCharacters()
H.eq(#chars, 1, "current character only")
H.eq(chars[1].provenance, "self", "provenance self")
local specs = api.GetSpecs(chars[1].key)
H.eq(#specs, 3, "three priest specs")
H.eq(specs[1].hasProfile, false, "no weights yet")
local _, why = api.GetProfile(chars[1].key, "PRIEST.SHADOW")
H.eq(why, "NO_WEIGHTS", "missing profile is reported, not empty")

-- Map spec, import weights.
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Intellect=0.42, SpellDamage=1 )')
H.check(WoW.chat():find("imported Shadow for PRIEST.SHADOW", 1, true) ~= nil, "slash import works")
H.eq(api.GetProfile(chars[1].key, "PRIEST.SHADOW").source, "imported-pawn", "profile provenance")

-- Evaluate a bag instance across own specs.
local r = api.Evaluate({ item = { bag = 0, slot = 1 }, context = "bags", scope = "own" })
H.eq(#r.results, 3, "one result per own spec")
H.eq(r.results[1].spec, "PRIEST.SHADOW", "current spec first")
H.eq(r.results[1].current, true, "flagged current")
H.eq(r.results[1].status, "upgrade", "better mantle is an upgrade")
H.eq(r.results[1].baseline.source, "fallback-current", "M0 baseline labelled fallback-current")
H.eq(r.results[1].candidate.instance.guid, "Item-1-AAA", "instance identity carried")
H.eq(r.results[2].status, "unknown", "Discipline: no weights -> unknown")
H.check(H.has(r.results[2].reasons, "NO_WEIGHTS"), "...with NO_WEIGHTS")
H.eq(r.status, "upgrade", "aggregate (display only)")

-- Unsupported scopes are reported, never narrowed.
r = api.Evaluate({ item = WoW.link(60), scope = "tracked" })
H.eq(r.results[1].status, "unsupported", "tracked scope needs alts")
r = api.Evaluate({ item = WoW.link(60), scope = "targets", targets = { { char = "Player-2-OTHER", spec = "MAGE.FROST" } } })
H.eq(r.results[1].status, "unsupported", "alt targets unsupported in M0")
H.eq(api.AssessProtection({ bag = 0, slot = 1 }).verdict, "unsupported", "protection unsupported -> consumers fail closed")

-- Pending item data, then EvaluationReady with the full response.
WoW.items[70] = { name = "Sage's Gloves", equipLoc = "INVTYPE_HAND", classID = 4, subclassID = 1,
    stats = { ITEM_MOD_INTELLECT_SHORT = 9 } }
WoW.cacheMiss[70] = true
local got
api.RegisterCallback("EvaluationReady", function(_, payload) got = payload end, "test")
r = api.Evaluate({ item = WoW.link(70), scope = "current" })
H.eq(r.results[1].status, "pending", "cache miss -> pending placeholder")
H.check(H.has(WoW.itemRequests, 70), "item load requested")
WoW.cacheMiss[70] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 70, true)
WoW.flush()
H.eq(got and got.requestId, r.requestId, "EvaluationReady for that request")
H.eq(got.response.results[1].status, "upgrade", "...carrying the complete response (empty hands slot)")

-- Timeout: three attempts, then unknown ITEM_DATA_UNAVAILABLE.
WoW.items[71] = { name = "Never Loads", equipLoc = "INVTYPE_WAIST", classID = 4, subclassID = 1, stats = {} }
WoW.cacheMiss[71] = true
got = nil
r = api.Evaluate({ item = WoW.link(71), scope = "current" })
for _ = 1, 20 do WoW.time = WoW.time + 1; WoW.flush(1) end
H.eq(got and got.response.results[1].reasons[1], "ITEM_DATA_UNAVAILABLE", "gives up after the last attempt")

-- Cancel.
WoW.items[72] = { name = "Later", equipLoc = "INVTYPE_FEET", classID = 4, subclassID = 1, stats = {} }
WoW.cacheMiss[72] = true
r = api.Evaluate({ item = WoW.link(72), scope = "current" })
H.eq(api.CancelRequest(r.requestId), true, "cancel a pending request")
H.eq(api.CancelRequest(r.requestId), false, "twice: nothing to cancel")

-- Batch bound.
local many = {}
for i = 1, 65 do many[i] = { item = WoW.link(60), scope = "current" } end
H.eq(api.EvaluateBatch(many)[1].results[1].reasons[1], "BATCH_TOO_LARGE", "batch > 64 refused")

-- Callback errors don't stop others; unknown events are refused.
local second = false
api.RegisterCallback("ProfilesChanged", function() error("boom") end, "bad")
api.RegisterCallback("ProfilesChanged", function() second = true end, "good")
GG.Callbacks.Fire("ProfilesChanged", { charKeys = {} })
WoW.flush()
H.eq(second, true, "a failing callback doesn't stop the others")
H.eq(#WoW.errors, 1, "the failure reaches the error handler")
H.raises(function() api.RegisterCallback("Nope", function() end, "x") end, "unknown event refused")

H.done("test_api_contract")
