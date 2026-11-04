------------------------------------------------------------
-- test_alts.lua - GG-203 (this WoW account's alts): tracked alts' specs as
-- rows after the current character's, through a fake AltStable built from
-- its docs/PUBLIC-API.md.
--
--   * only tracked alts, in the roster's order; a bound item costs them nothing;
--   * transfer: same realm and faction (the proposed mail rule, GG-116),
--     account-bound kinds unknown, a third-party character never;
--   * an alt's gear: its observed baseline for the spec, else AltStable's
--     last scan (fallback-current); loading items make a pending row;
--   * the tooltip lists an alt's upgrade ("Wanda · Frost"), the bag arrow
--     goes amber, protection keeps it - and never clears on an untrusted
--     alt baseline or an item that may not reach the alt;
--   * roster and gear changes invalidate; the target limit is never cut.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local INT, SP = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"
local function shoulder(name, stats, extra)
    local t = { name = name, equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = stats, bindType = 2 }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end
WoW.items[50] = shoulder("Old Mantle", { [INT] = 10, [SP] = 10 })     -- the priest wears it
WoW.items[51] = shoulder("Frost Mantle", { [INT] = 10 })               -- Wanda wears it
WoW.items[61] = shoulder("Bright Mantle", { [INT] = 25 })              -- Wanda up, the priest down
WoW.items[62] = shoulder("Heirloom Mantle", { [INT] = 25 }, { bindType = 7 })   -- account-bound
WoW.items[63] = shoulder("Dim Mantle", { [INT] = 5 })                  -- nobody's upgrade
WoW.items[64] = shoulder("Late Mantle", { [INT] = 25 }, { minLevel = 50 })
WoW.items[65] = shoulder("Great Mantle", { [INT] = 30 })
WoW.items[80] = { name = "Dagger", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 15, stats = { [INT] = 1 } }
WoW.items[81] = { name = "Shield", equipLoc = "INVTYPE_SHIELD", classID = 4, subclassID = 6, stats = { [INT] = 1 } }
WoW.equipped[3] = 50
WoW.bags[0] = {
    [1] = { itemID = 61, isBound = false },    -- BoE, not bound: can be mailed
    [2] = { itemID = 61, isBound = true },     -- the same item, bound
    [3] = { itemID = 62, isBound = true },     -- account-bound
    [4] = { itemID = 63, isBound = false },
    [5] = { itemID = 64, isBound = false },
}

local ME = "Player-1-0000AAAA"
local WANDA, DRAK, HORDE, FAR, LOW, BARE = "Player-1-WANDA", "Player-1-DRAK", "Player-1-HORDE", "Player-1-FAR",
    "Player-1-LOW", "Player-1-BARE"
local NOW = 1793500000
WoW.time = NOW
local chars = {
    { guid = ME, name = "Karuzo Elegia", realm = "Forever", faction = "Alliance", class = "PRIEST", level = 60, provenance = "self" },
    { guid = WANDA, name = "Wanda Frostweave", realm = "Forever", faction = "Alliance", class = "MAGE", level = 60, provenance = "self" },
    { guid = DRAK, name = "Drakuza", realm = "Forever", faction = "Alliance", class = "MAGE", level = 60, provenance = "own-account" },
    { guid = HORDE, name = "Hordey", realm = "Forever", faction = "Horde", class = "MAGE", level = 60, provenance = "self" },
    { guid = FAR, name = "Farry", realm = "Elsewhere", faction = "Alliance", class = "MAGE", level = 60, provenance = "self" },
    { guid = LOW, name = "Lowbie", realm = "Forever", faction = "Alliance", class = "MAGE", level = 20, provenance = "self" },
    { guid = BARE, name = "Bare", realm = "Forever", faction = "Alliance", class = "MAGE", level = 60, provenance = "self" },
    { guid = "Player-1-FRIEND", name = "Friendo", realm = "Forever", faction = "Alliance", class = "MAGE", level = 60,
      provenance = "third-party" },
}
-- AltStable's gear shape: every slot, "item:..." strings for occupied ones.
local function gearWith(items, capturedAt)
    local slots = {}
    for _, s in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }) do
        local id = items[s]
        slots[s] = id and { slot = s, state = "occupied", itemID = id, itemString = "item:" .. id .. ":0:0:0:0:0:0:0" }
            or { slot = s, state = "empty" }
    end
    return { capturedAt = capturedAt or NOW - 3600, gearAt = NOW - 7200, slots = slots }
end
local gear = {}
for _, g in ipairs({ WANDA, DRAK, HORDE, FAR, LOW }) do gear[g] = gearWith({ [3] = 51 }) end
local callbacks, gearReads = {}, 0
local AS = {
    PUBLIC_API_VERSION = 1,
    PUBLIC_API_FEATURES = { provenance = true, gear = true },
    GetCharacters = function()
        local out = {}
        for i, c in ipairs(chars) do local t = {} for k, v in pairs(c) do t[k] = v end out[i] = t end
        return out
    end,
    GetCharacterProvenance = function() return nil end,
    GetCharacterGear = function(guid) gearReads = gearReads + 1; return gear[guid] end,
    RegisterCallback = function(event, fn) callbacks[event] = callbacks[event] or {}; table.insert(callbacks[event], fn) end,
}
local function fire(event, ...) for _, fn in ipairs(callbacks[event] or {}) do fn(event, ...) end end
rawset(_G, "AltStable", AS)

local GG = WoW.loadAddon()
local api = GG.API
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=0.1, SpellDamage=1 )')
local MAGE = { "MAGE.ARCANE", "MAGE.FIRE", "MAGE.FROST" }
for _, who in ipairs({ WANDA, HORDE, FAR, LOW, BARE }) do
    assert(GG.Profiles.ImportNew(GG.store, who, "MAGE.FROST", '( Pawn: v1: "Frost": Class=Mage, Intellect=1 )', NOW, "MAGE"))
    GG.Prefs.SetTracked(who, "MAGE.FROST", true, MAGE)
end
GG.Prefs.SetTracked(DRAK, "MAGE.ARCANE", true, MAGE)       -- the other account: no weights here yet (GG-202)
GG.Profiles.Changed(WANDA)
WoW.flush()

local function rows(ref, scope)
    local r = api.Evaluate({ item = ref, scope = scope or "own+tracked" })
    local by = {}
    for _, x in ipairs(r.results) do by[(x.character and x.character.key or "?") .. "/" .. tostring(x.spec)] = x end
    return r, by
end

------------------------------------------------------------
-- Rows: who, in which order, and why.
------------------------------------------------------------
H.eq(api.GetCapabilities().features.alts, true, "features.alts with AltStable AS-001 + AS-003")
H.eq(api.GetCapabilities().features.scopes["own+tracked"], true, "...and the own+tracked scope")
local r, by = rows({ bag = 0, slot = 1 })
local order = {}
for _, x in ipairs(r.results) do order[#order + 1] = x.character.name:match("^%S+") .. ":" .. x.spec:match("%.(.+)") end
H.eq(table.concat(order, ","),
    "Karuzo:SHADOW,Karuzo:DISCIPLINE,Karuzo:HOLY,Wanda:FROST,Drakuza:ARCANE,Hordey:FROST,Farry:FROST,Lowbie:FROST,Bare:FROST",
    "every own spec first (current first), then the tracked alts' specs in the roster's order")
for _, x in ipairs(r.results) do H.check(x.character.key ~= "Player-1-FRIEND", "a third-party character never gets a row") end
local w = by[WANDA .. "/MAGE.FROST"]
H.eq(w.status, "upgrade", "Wanda (Frost) gets an upgrade from the BoE in the bags")
H.eq(w.character.current, false, "...an alt row (character.current false)")
H.eq(by[ME .. "/PRIEST.SHADOW"].character.current, true, "...the current character's rows say current")
H.eq(w.transfer.state, "eligible", "...it can be mailed to her")
H.eq(w.transfer.reasons[1], "MAIL_SAME_REALM_FACTION", "...same realm and faction (proposed until GG-116)")
H.eq(w.baseline.source, "fallback-current", "...compared with what AltStable last saw her wear")
H.check(H.has(w.reasons, "BASELINE_FALLBACK"), "...said so")
H.eq(string.format("%.2f", w.score.pct), "1.50", "...her Intellect weight: 25 against 10")
H.eq(by[ME .. "/PRIEST.SHADOW"].status, "no_upgrade", "the priest's Shadow: no upgrade")
H.eq(by[DRAK .. "/MAGE.ARCANE"].reasons[1], "NO_WEIGHTS", "the other account's alt: no weights here until sync")
local hz = by[HORDE .. "/MAGE.FROST"]
H.eq(hz.status, "ineligible", "another faction: ineligible")
H.eq(hz.reasons[1], "NOT_TRANSFERABLE", "...NOT_TRANSFERABLE")
H.eq(hz.transfer.reasons[1], "OTHER_FACTION", "...because of the faction")
H.eq(by[FAR .. "/MAGE.FROST"].transfer.reasons[1], "OTHER_REALM", "another realm: OTHER_REALM")
H.eq(by[BARE .. "/MAGE.FROST"].reasons[1], "NO_ALT_GEAR", "an alt AltStable has no gear for: unknown, NO_ALT_GEAR")
local _, late = rows({ bag = 0, slot = 5 })
H.eq(late[LOW .. "/MAGE.FROST"].status, "ineligible", "a level 20 alt and a level 50 item: its own level counts")
H.eq(late[WANDA .. "/MAGE.FROST"].status, "upgrade", "...a level 60 one gets it")

-- A bound copy: its alts are ineligible at once, at no cost.
local e0 = GG.API._state.stats.evaluations
local _, bound = rows({ bag = 0, slot = 2 })
H.eq(bound[WANDA .. "/MAGE.FROST"].status, "ineligible", "the same item bound: ineligible for Wanda")
H.eq(bound[WANDA .. "/MAGE.FROST"].transfer.reasons[1], "SOULBOUND", "...SOULBOUND")
H.eq(GG.API._state.stats.evaluations - e0, 3, "...and only the own three specs were evaluated")
local _, boa = rows({ bag = 0, slot = 3 })
H.eq(boa[WANDA .. "/MAGE.FROST"].transfer.state, "unknown", "an account-bound item: transfer unknown (unprobed)")
H.eq(boa[WANDA .. "/MAGE.FROST"].status, "upgrade", "...still evaluated")
local _, link = rows(WoW.link(61))
H.eq(link[WANDA .. "/MAGE.FROST"].transfer.state, "unknown", "a link with no instance (chat, vendor): transfer unknown")

------------------------------------------------------------
-- The tooltip and the bag arrow.
------------------------------------------------------------
local settings = GG.Tooltip.ViewSettings()
local function lines(ref, key)
    local out = {}
    for _, l in ipairs(GG.TooltipView.Build(GG.Results.Get(ref, key), settings, { currentSpec = GG.currentSpec }) or {}) do
        out[#out + 1] = l.left .. (l.right and (" = " .. l.right) or "")
    end
    return table.concat(out, "\n")
end
local t1 = lines({ bag = 0, slot = 1 }, "b1")
H.check(t1:find("Wanda \194\183 Frost = +150.0%", 1, true) ~= nil, "the tooltip lists Wanda's upgrade, first name and spec: " .. t1)
H.check(t1:find("Alts: compared with the gear AltStable last saw them wear", 1, true) ~= nil, "...and says what she is compared with")
for _, who in ipairs({ "Drakuza", "Hordey", "Farry", "Bare" }) do
    H.check(t1:find(who, 1, true) == nil, "...no row for " .. who .. " (not an upgrade it can receive)")
end
H.check(lines({ bag = 0, slot = 2 }, "b2"):find("Wanda", 1, true) == nil, "a bound copy: no alt row")
H.check(lines({ bag = 0, slot = 3 }, "b3"):find("Wanda", 1, true) == nil, "an account-bound item: no alt row (transfer unknown)")
settings.alts = false
H.check(lines({ bag = 0, slot = 1 }, "b1"):find("Wanda", 1, true) == nil, "tooltip.alts off: no alt rows")
settings.alts = true

local bag = ContainerFrameContainer.ContainerFrames[1]
local function mark(i)
    local m = GG.BagMarkers._marks[bag.Items[i]]
    return m and m:IsShown() and m.kind or nil
end
WoW.showBag(bag, { { 0, 1 }, { 0, 2 }, { 0, 3 }, { 0, 4 } })
WoW.flush()
H.eq(mark(1), "amber", "the BoE that is Wanda's upgrade: an amber arrow (transferable upgrades)")
H.eq(mark(2), nil, "...the bound copy: none")
H.eq(mark(3), nil, "...the account-bound one: none (it may not reach her)")
H.eq(mark(4), nil, "...nobody's upgrade: none")
-- Ctrl reveals own off-spec upgrades: an alt's row is never one of those.
WoW.keys.CTRL = true
WoW.fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
WoW.flush()
H.eq(mark(3), nil, "Ctrl held: still no arrow on the account-bound item (an alt row is not an own spec)")
WoW.keys.CTRL = nil
WoW.fire("MODIFIER_STATE_CHANGED", "LCTRL", 0)
WoW.flush()

------------------------------------------------------------
-- Protection (Shatter): tracked alts join, fail-closed.
------------------------------------------------------------
for _, who in ipairs({ HORDE, FAR, LOW, BARE }) do GG.Prefs.SetTracked(who, "MAGE.FROST", false, MAGE) end
GG.Prefs.SetTracked(DRAK, "MAGE.ARCANE", false, MAGE)
SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("alt upgrades: 1 alt specs ticked", 1, true) ~= nil, "/gg counts the ticked alt specs")
local p = api.AssessProtection({ bag = 0, slot = 1 })
H.eq(p.verdict, "protect", "the BoE that is Wanda's upgrade is kept")
H.eq(p.recipients[1] and p.recipients[1].character.key, WANDA, "...for Wanda")
H.eq(api.AssessProtection({ bag = 0, slot = 2 }).verdict, "clear", "the bound copy: Wanda has no say, the priest doesn't want it")
local boaP = api.AssessProtection({ bag = 0, slot = 3 })
H.eq(boaP.verdict, "unknown", "account-bound, Wanda's upgrade: kept, never protect or clear")
H.check(H.has(boaP.reasons, "TRANSFER_UNKNOWN"), "...TRANSFER_UNKNOWN")
local dim = api.AssessProtection({ bag = 0, slot = 4 })
H.eq(dim.verdict, "unknown", "nobody's upgrade, but Wanda compared with AltStable's last scan: never cleared")
H.check(H.has(dim.reasons, "BASELINE_NOT_TRUSTED"), "...BASELINE_NOT_TRUSTED")
local tok = dim.token

-- Wanda played Frost with Glass Gear on this account: that gear is her baseline.
local snap = GG.Baselines.Snapshot({ slots = (function()
    local s = {}
    for _, slot in ipairs(GG.Data.Slots.GEAR) do s[slot] = { state = "empty" } end
    s[3] = { state = "occupied", item = "item:51" }
    return s
end)() }, "MAGE.FROST", "observed", NOW - 600, 1)
assert(GG.store:Create(GG.Capture.ID(WANDA, "MAGE.FROST"), "baseline", snap, "self"))
GG.API._Invalidate("baselines", { WANDA })
local _, obs = rows({ bag = 0, slot = 4 })
H.eq(obs[WANDA .. "/MAGE.FROST"].baseline.source, "observed", "her recorded Frost gear wins over AltStable's scan")
dim = api.AssessProtection({ bag = 0, slot = 4 })
H.eq(dim.verdict, "clear", "...a trusted baseline and no upgrade: clear")
H.check(dim.token ~= tok, "...with a new token")
H.check(lines({ bag = 0, slot = 1 }, "b1x"):find("AltStable last saw", 1, true) == nil, "...and the tooltip no longer says last seen")

-- No weights beside specs that can't use it is still nothing checked.
local PR = GG.Engine.Policy.Protection({
    { status = "unknown", reasons = { "NO_WEIGHTS" }, spec = "A" },
    { status = "unknown", reasons = { "NO_WEIGHTS" }, spec = "B" },
    { status = "ineligible", spec = "C", character = { current = false }, transfer = { state = "ineligible" } },
}, { noWeights = "ignore" })
H.eq(PR.verdict, "unknown", "no weights everywhere but an alt the item can't reach: unknown, never clear")
H.eq(GG.Engine.Policy.Protection({ { status = "ineligible", spec = "A" } }).verdict, "clear",
    "...while an item no tracked spec can use stays clear")

------------------------------------------------------------
-- Loading, changes, limits.
------------------------------------------------------------
-- Wanda's worn item not loaded yet: her row waits for it, the others don't.
GG.store:Delete(GG.Capture.ID(WANDA, "MAGE.FROST"), GG.store:Get(GG.Capture.ID(WANDA, "MAGE.FROST")).version)
WoW.cacheMiss[51] = true
GG.API._Invalidate("test", { WANDA })
local ready
api.RegisterCallback("EvaluationReady", function(_, payload) ready = payload end, "test_alts")
local pr, pby = rows({ bag = 0, slot = 1 })
H.eq(pby[WANDA .. "/MAGE.FROST"].status, "pending", "her gear loading: pending")
H.eq(pby[WANDA .. "/MAGE.FROST"].reasons[1], "BASELINE_ITEM_DATA_PENDING", "...BASELINE_ITEM_DATA_PENDING")
H.eq(pby[ME .. "/PRIEST.SHADOW"].status, "no_upgrade", "...the priest's rows aren't held up")
WoW.cacheMiss[51] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 51, true)
WoW.flush()
H.eq(ready and ready.requestId, pr.requestId, "it arrives: EvaluationReady")
local done
for _, x in ipairs(ready.response.results) do if x.character.key == WANDA then done = x end end
H.eq(done and done.status, "upgrade", "...with her upgrade")

-- AltStable reads stay bounded: once per alt per generation, not per item.
local g0 = gearReads
for slot = 1, 5 do rows({ bag = 0, slot = slot }) end
H.eq(gearReads - g0, 0, "five items in one generation: AltStable's gear read once per alt at most")

-- Her gear changed (AltStable GearChanged): answers are dropped.
gear[WANDA] = gearWith({ [3] = 65 })
fire("GearChanged", { WANDA })
WoW.flush()
H.eq(select(2, rows({ bag = 0, slot = 1 }))[WANDA .. "/MAGE.FROST"].status, "no_upgrade",
    "she now wears better: no upgrade (GearChanged invalidated)")
-- Her level changed (CharactersChanged): rows follow.
chars[2].level = 40
fire("CharactersChanged")
WoW.flush()
H.eq(select(2, rows({ bag = 0, slot = 5 }))[WANDA .. "/MAGE.FROST"].status, "ineligible", "level 40 now: the level 50 item is out")
chars[2].level = 60
fire("CharactersChanged")
WoW.flush()

-- Explicit targets name an alt; an unknown one is refused.
local tr = api.Evaluate({ item = { bag = 0, slot = 1 }, scope = "targets", targets = { { char = WANDA, spec = "MAGE.FROST" } } })
H.eq(#tr.results, 1, "scope targets: an alt's spec")
H.eq(tr.results[1].character.key, WANDA, "...hers")
tr = api.Evaluate({ item = { bag = 0, slot = 1 }, scope = "targets", targets = { { char = WANDA, spec = "MAGE.NOPE" } } })
H.eq(tr.results[1].reasons[1], "UNKNOWN_SPEC", "...an unknown spec: unsupported")
tr = api.Evaluate({ item = { bag = 0, slot = 1 }, scope = "targets", targets = { { char = "Player-1-FRIEND", spec = "MAGE.FROST" } } })
H.eq(tr.results[1].reasons[1], "UNKNOWN_CHARACTER", "...a third-party character: unsupported")

-- The scope over the target limit is refused, never cut.
local limit = api.LIMITS.targets
api.LIMITS.targets = 3
tr = api.Evaluate({ item = { bag = 0, slot = 1 }, scope = "own+tracked" })
H.eq(tr.status, "unsupported", "own+tracked over the limit: unsupported")
H.eq(tr.results[1].reasons[1], "TOO_MANY_TARGETS", "...TOO_MANY_TARGETS")
H.eq(api.AssessProtection({ bag = 0, slot = 1 }).verdict, "unknown", "...protection over the limit keeps the item")
api.LIMITS.targets = limit

-- Dual wield: told by the off-hand an alt wears.
local function dual(oh)
    local b = { slots = { [17] = oh } }
    return GG.Alts.Recipient(chars[2], b).canDualWield
end
H.eq(dual({ state = "occupied", classID = 2 }), true, "a weapon in the off-hand: dual wield")
H.eq(dual({ state = "occupied", classID = 4 }), false, "a shield: no")
H.eq(dual({ state = "empty" }), false, "nothing: no")

-- Without AltStable: own specs only.
rawset(_G, "AltStable", nil)
GG.Integrations.RosterProvider._Reset()
GG.Integrations.RosterProvider.Refresh()
GG.API._Invalidate("test")
H.eq(#api.Evaluate({ item = { bag = 0, slot = 1 }, scope = "own+tracked" }).results, 3, "no AltStable: the own three specs")
H.eq(api.GetCapabilities().features.alts, false, "...features.alts false")

H.eq(#WoW.errors, 0, "no errors" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
H.done("test_alts")
