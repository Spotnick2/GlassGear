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
H.eq(r.results[1].baseline.source, "observed", "current spec: what it wears now (observed)")
H.eq(r.results[1].candidate.instance.guid, "Item-1-AAA", "instance identity carried")
H.eq(r.results[2].status, "unknown", "Discipline: no weights -> unknown")
H.check(H.has(r.results[2].reasons, "NO_WEIGHTS"), "...with NO_WEIGHTS")
H.eq(r.status, "upgrade", "aggregate (display only)")

-- A client-shaped ItemLocation (bagID/slotIndex + methods) resolves too.
local loc = ItemLocation:CreateFromBagAndSlot(0, 1)
r = api.Evaluate({ item = loc, scope = "current" })
H.eq(r.results[1].status, "upgrade", "ItemLocation bag/slot")
H.eq(r.results[1].candidate.instance.guid, "Item-1-AAA", "...with its instance")
r = api.Evaluate({ item = ItemLocation:CreateFromEquipmentSlot(3), scope = "current" })
H.eq(r.results[1].status, "no_upgrade", "ItemLocation equipment slot: the equipped item vs itself")

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

-- A failed load keeps the item waiting; a later success completes it.
WoW.items[73] = { name = "Flaky", equipLoc = "INVTYPE_WRIST", classID = 4, subclassID = 1,
    stats = { ITEM_MOD_INTELLECT_SHORT = 4 } }
WoW.cacheMiss[73] = true
got = nil
r = api.Evaluate({ item = WoW.link(73), scope = "current" })
local loadsBefore, attemptsBefore = #WoW.itemRequests, GG.API._state.waiting[73].attempts
WoW.fire("ITEM_DATA_LOAD_RESULT", 73, false)
H.eq(#WoW.itemRequests, loadsBefore, "a failed load is not re-requested immediately (the tick owns retries)")
H.eq(GG.API._state.waiting[73].attempts, attemptsBefore, "...and its attempt count is kept")
WoW.flush()
H.eq(got, nil, "failed load: no completion yet")
H.eq(GG.API._state.waiting[73] ~= nil, true, "...the item is still waiting (retries continue)")
WoW.cacheMiss[73] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 73, true)
WoW.flush()
H.eq(got and got.requestId, r.requestId, "completed after the successful load")

-- Timeout: three attempts, then every target row kept, status unknown.
WoW.items[71] = { name = "Never Loads", equipLoc = "INVTYPE_WAIST", classID = 4, subclassID = 1, stats = {} }
WoW.cacheMiss[71] = true
got = nil
local requestsBefore = #WoW.itemRequests
r = api.Evaluate({ item = WoW.link(71), scope = "own" })
H.eq(#r.results, 3, "three pending rows")
for _ = 1, 20 do WoW.time = WoW.time + 1; WoW.flush(1) end
H.eq(#WoW.itemRequests - requestsBefore, 3, "exactly three load attempts (one queue owns them)")
H.eq(got and #got.response.results, 3, "timeout keeps all three target rows")
H.eq(got.response.results[2].spec, r.results[2].spec, "...in the same order, with their identity")
H.eq(got.response.results[1].reasons[1], "ITEM_DATA_UNAVAILABLE", "gives up after the last attempt")

-- Cancel.
WoW.items[72] = { name = "Later", equipLoc = "INVTYPE_FEET", classID = 4, subclassID = 1, stats = {} }
WoW.cacheMiss[72] = true
r = api.Evaluate({ item = WoW.link(72), scope = "current" })
H.eq(api.CancelRequest(r.requestId), true, "cancel a pending request")
H.eq(GG.API._state.waiting[72], nil, "cancelling stops loading an item nobody else waits for")
H.eq(api.CancelRequest(r.requestId), false, "twice: nothing to cancel")

-- Successful load events with still-unusable data never reset the retry budget.
WoW.items[75] = { name = "Stubborn", equipLoc = "INVTYPE_NECK", classID = 4, subclassID = 0, stats = {} }
WoW.cacheMiss[75] = true
got = nil
local before75 = #WoW.itemRequests
r = api.Evaluate({ item = WoW.link(75), scope = "current" })
for _ = 1, 25 do
    WoW.time = WoW.time + 1
    WoW.fire("ITEM_DATA_LOAD_RESULT", 75, true)
    WoW.flush(1)
end
local loads75 = 0
for i = before75 + 1, #WoW.itemRequests do if WoW.itemRequests[i] == 75 then loads75 = loads75 + 1 end end
H.eq(loads75, 3, "still three attempts in all")
H.eq(got and got.requestId, r.requestId, "the request still terminates")

-- A pending request keeps the targets it was made with.
SlashCmdList.GLASSGEAR("spec 1 PRIEST.HOLY")
WoW.items[76] = { name = "Later Cloak", equipLoc = "INVTYPE_CLOAK", classID = 4, subclassID = 1,
    stats = { ITEM_MOD_INTELLECT_SHORT = 3 } }
WoW.cacheMiss[76] = true
got = nil
r = api.Evaluate({ item = WoW.link(76), scope = "own" })
local order = { r.results[1].spec, r.results[2].spec, r.results[3].spec }
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
WoW.cacheMiss[76] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 76, true)
WoW.flush()
H.eq(got and got.response.results[1].spec, order[1], "completion keeps the first target (Holy)")
H.eq(got.response.results[3].spec, order[3], "...and the original order")
WoW.items[77] = { name = "Lost Boots", equipLoc = "INVTYPE_FEET", classID = 4, subclassID = 1, stats = {} }
WoW.cacheMiss[77] = true
got = nil
r = api.Evaluate({ item = WoW.link(77), scope = "own" })
local first = r.results[1].spec
SlashCmdList.GLASSGEAR("spec 1 PRIEST.HOLY")
for _ = 1, 20 do WoW.time = WoW.time + 1; WoW.flush(1) end
H.eq(got and got.response.results[1].spec, first, "a timed-out request keeps its original targets too")

-- A new baseline dependency that can't be queued ends the request (no strand).
GG.API._ResetQueues()
local qsaved = GG.API.LIMITS.itemQueue
GG.API.LIMITS.itemQueue = 1
WoW.items[78] = { name = "Queued Belt", equipLoc = "INVTYPE_WAIST", classID = 4, subclassID = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 2 } }
WoW.items[79] = { name = "New Helm", equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 1, stats = {} }
WoW.items[80] = { name = "New Gloves", equipLoc = "INVTYPE_HAND", classID = 4, subclassID = 1, stats = {} }
WoW.cacheMiss[78], WoW.cacheMiss[79], WoW.cacheMiss[80] = true, true, true
got = nil
r = api.Evaluate({ item = WoW.link(78), scope = "own" })
WoW.equipped[1], WoW.equipped[10] = 79, 80   -- two uncached baseline items appear meanwhile
WoW.cacheMiss[78] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 78, true)
WoW.flush()
H.eq(got and got.requestId, r.requestId, "the request ends instead of waiting forever")
H.eq(got and #got.response.results, 3, "...with every target row")
H.eq(GG.API._state.requestCount, 0, "nothing left outstanding")
H.eq(GG.API._state.waitingCount, 0, "and no orphaned item loads")
WoW.equipped[1], WoW.equipped[10] = nil, nil
WoW.cacheMiss[79], WoW.cacheMiss[80] = nil, nil
GG.API.LIMITS.itemQueue = qsaved
GG.API._ResetQueues()

-- Overload keeps the rows too.
local saved = GG.API.LIMITS.requests
GG.API.LIMITS.requests = 0
WoW.items[74] = { name = "Busy", equipLoc = "INVTYPE_LEGS", classID = 4, subclassID = 1, stats = {} }
WoW.cacheMiss[74] = true
r = api.Evaluate({ item = WoW.link(74), scope = "own" })
H.eq(#r.results, 3, "overload: one row per target")
H.eq(r.results[1].reasons[1], "OVERLOADED", "...each OVERLOADED")
GG.API.LIMITS.requests = saved

-- Level and proficiency changes refresh the player and invalidate.
local inval = 0
api.RegisterCallback("EvaluationInvalidated", function() inval = inval + 1 end, "lvl")
WoW.player.level = 61
WoW.fire("PLAYER_LEVEL_UP", 61)
WoW.flush()
H.eq(api.GetCharacters()[1].level, 61, "level refreshed on PLAYER_LEVEL_UP")
H.eq(inval, 1, "...and consumers told to re-query")

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
