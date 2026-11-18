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
eq(C.Transfer("account-bound", 7, from, alt).state, "unknown", "account-bound kinds unknown until probed")
eq(C.Transfer("hypothetical", 1, from, alt).state, "ineligible", "BoP loot link never goes to an alt")
eq(C.Transfer("hypothetical", 2, from, alt).state, "unknown", "BoE link: not an instance yet")
eq(C.Transfer("bound", 1, from, { current = true }).state, "eligible", "the current character itself")

done("test_item_context")
