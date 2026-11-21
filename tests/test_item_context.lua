------------------------------------------------------------
-- test_item_context.lua - binding classes and the transfer tri-state.
-- Cross-account ownership vs transfer eligibility (PRD section 3).
------------------------------------------------------------

local H = dofile("tests/harness.lua")
local GG = H.loadPure()
local C = GG.ItemContext

eq(C.Classify({ instance = false }), "hypothetical", "a link is not an instance")
eq(C.Classify({ instance = true, isBound = true }), "bound", "bound instance")
eq(C.Classify({ instance = true, isBound = false }), "unbound", "BoE in bags")
eq(C.Classify({ instance = true, accountBound = true }), "account-bound", "account-bound")
eq(C.Classify({ instance = true }), "unknown", "no bind info")

local from = { realm = "Forever", faction = "Alliance" }
local alt = { provenance = "own-account", realm = "Forever", faction = "Alliance" }

local t = C.Transfer("unbound", 2, from, alt)
eq(t.state, "eligible", "BoE to an own alt on the same realm and faction")
eq(t.proposed, true, "flagged as a proposed rule until GG-116")
eq(C.Transfer("bound", 2, from, alt).state, "ineligible", "soulbound never goes to an alt")
eq(C.Transfer("unbound", 2, from, { provenance = "third-party", realm = "Forever", faction = "Alliance" }).state,
    "ineligible", "known to AltStable is not 'mine'")
eq(C.Transfer("unbound", 2, from, { provenance = "own-account", realm = "Other", faction = "Alliance" }).state,
    "ineligible", "other realm")
eq(C.Transfer("unbound", 2, from, { provenance = "own-account", realm = "Forever", faction = "Horde" }).state,
    "ineligible", "other faction")
eq(C.Transfer("unbound", 2, from, { provenance = "own-account" }).state, "unknown", "missing location -> unknown")
eq(t.reasons[1], "MAIL_SAME_REALM_FACTION", "both realms known: the realm decides")

-- The realm is hidden since the 2026-11-20 hotfix (#88): the ruleset decides.
local me = { ruleset = "Normal", faction = "Alliance" }
local function tr(r) local x = C.Transfer("unbound", 2, me, r); return x.state .. "/" .. x.reasons[1], x.proposed end
local own = function(t) t.provenance = "own-account"; return t end
local got, proposed = tr(own({ ruleset = "Normal", faction = "Alliance" }))
eq(got, "eligible/MAIL_SAME_RULESET_FACTION", "same ruleset and faction, no realm: eligible")
eq(proposed, true, "...proposed until GG-116 (two realms of one ruleset untried)")
eq(tr(own({ ruleset = "Normal", faction = "Alliance", realm = "CAMWOW US2 Realm 1 PvE" })),
    "eligible/MAIL_SAME_RULESET_FACTION", "...the alt's realm known but not ours: the ruleset decides")
eq(tr(own({ ruleset = "PvP", faction = "Alliance" })), "ineligible/OTHER_RULESET", "another ruleset: OTHER_RULESET")
eq(tr(own({ ruleset = "PvP", faction = "Horde" })), "ineligible/OTHER_RULESET", "...first, before the faction")
eq(tr(own({ ruleset = "Normal", faction = "Horde" })), "ineligible/OTHER_FACTION", "same ruleset, other faction")
eq(tr(own({ faction = "Horde" })), "ineligible/OTHER_FACTION", "...the faction alone is enough to say no")
eq(tr(own({ faction = "Alliance" })), "unknown/RECIPIENT_LOCATION_UNKNOWN", "no ruleset and no realm: unknown")
eq(tr(own({ ruleset = "Normal" })), "unknown/RECIPIENT_LOCATION_UNKNOWN", "no faction: unknown")
eq(C.Transfer("unbound", 2, { faction = "Alliance" }, own({ ruleset = "Normal", faction = "Alliance" })).state,
    "unknown", "our ruleset unknown: unknown")
eq(C.Transfer("unbound", 2, { realm = "A", ruleset = "Normal", faction = "Alliance" },
    own({ realm = "B", ruleset = "Normal", faction = "Alliance" })).reasons[1], "OTHER_REALM",
    "both realms known and different (the client tells it again): OTHER_REALM")
eq(C.Transfer("unbound", 2, nil, own({ ruleset = "Normal", faction = "Alliance" })).state, "unknown",
    "no `from` at all: unknown, no error")
eq(C.Transfer("account-bound", 7, from, alt).state, "unknown", "account-bound kinds unknown until probed")
eq(C.Transfer("hypothetical", 1, from, alt).state, "ineligible", "BoP loot link never goes to an alt")
eq(C.Transfer("hypothetical", 2, from, alt).state, "unknown", "BoE link: not an instance yet")
eq(C.Transfer("bound", 1, from, { current = true }).state, "eligible", "the current character itself")

done("test_item_context")
