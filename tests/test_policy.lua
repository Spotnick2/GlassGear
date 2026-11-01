------------------------------------------------------------
-- test_policy.lua - marker predicate, reveal, tooltip rows and protection
-- (adr/0006). Covers the owner's acceptance cases: current vs off-spec
-- markers, modifier press/release, green precedence, BoE -> soulbound,
-- protection despite hidden arrows, missing weights.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
local GG = H.loadPure()
local P = GG.Engine.Policy

local function res(status, o)
    o = o or {}
    return { status = status, spec = o.spec or "PRIEST.HOLY",
        character = { key = o.char or "G-Karuzo", provenance = o.prov or "self" },
        eligibility = { equipNow = o.equipNow ~= false, reasons = {} },
        transfer = { state = o.transfer or "eligible" },
        baseline = o.baseline or { source = "observed", complete = true },
        limitations = o.limitations or {}, reasons = o.reasons or {},
        score = { pct = o.pct or 0.05, delta = 1 } }
end

local up, no = res("upgrade"), res("no_upgrade")
local altUp = res("upgrade", { char = "G-Drakuza", prov = "own-account", spec = "MAGE.FROST" })
local defaults = { markTransferable = true }

-- Soulbound bag item, off-spec upgrade only.
local soulbound = { current = no, own = { up }, alts = { altUp }, bound = true, surface = "bags" }
H.eq(P.Marker(soulbound, defaults, false), nil, "soulbound off-spec: no arrow normally")
H.eq(P.Marker(soulbound, defaults, true), "amber", "Ctrl held: amber")
H.eq(P.Marker({ current = no, own = { no }, alts = { altUp }, bound = true, surface = "bags" }, defaults, true), nil,
    "soulbound: never an alt marker, even revealed")

-- Green precedence.
local both = { current = up, own = { up }, alts = { altUp }, bound = false, surface = "bags" }
H.eq(P.Marker(both, defaults, false), "green", "current-spec upgrade is green")
H.eq(P.Marker(both, defaults, true), "green", "green wins over amber while revealed")

-- Transferable BoE in bags: amber by default for own other specs or eligible alts.
local boe = { current = no, own = { no }, alts = { altUp }, bound = false, surface = "bags" }
H.eq(P.Marker(boe, defaults, false), "amber", "transferable + eligible alt: amber by default (matrix row 3)")
H.eq(P.Marker(boe, { markTransferable = false }, false), nil, "setting off: hidden")
H.eq(P.Marker(boe, { markTransferable = false }, true), "amber", "...revealed with Ctrl")
local thirdParty = res("upgrade", { char = "G-Friend", prov = "third-party" })
H.eq(P.Marker({ current = no, own = {}, alts = { thirdParty }, bound = false, surface = "bags" }, defaults, true), nil,
    "a third-party character is never a recipient")
local ineligibleAlt = res("upgrade", { char = "G-Horde", prov = "own-account", transfer = "ineligible" })
H.eq(P.Marker({ current = no, own = {}, alts = { ineligibleAlt }, bound = false, surface = "bags" }, defaults, true), nil,
    "synced is not transferable: ineligible alt gets no marker")

-- BoE becomes soulbound: same results, bound flips -> soulbound rules.
local nowBound = { current = no, own = { no }, alts = { altUp }, bound = true, surface = "bags" }
H.eq(P.Marker(nowBound, defaults, false), nil, "after binding, the alt amber disappears")

-- Later-level upgrades never mark by default.
local later = res("upgrade", { equipNow = false })
H.eq(P.Marker({ current = later, own = {}, alts = {}, bound = true, surface = "bags" }, defaults, true), nil,
    "inside the level window: tooltip row only, no marker")

-- Loot: BoP follows soulbound rules; BoE alts only while revealed.
local lootBoP = { current = no, own = { up }, alts = { altUp }, surface = "loot", bindType = 1 }
H.eq(P.Marker(lootBoP, defaults, false), nil, "loot off-spec hidden")
H.eq(P.Marker(lootBoP, defaults, true), "amber", "loot off-spec revealed")
local lootBoE = { current = no, own = { no }, alts = { altUp }, surface = "loot", bindType = 2 }
H.eq(P.Marker(lootBoE, defaults, false), nil, "BoE loot alt hidden normally")
H.eq(P.Marker(lootBoE, defaults, true), "amber", "BoE loot alt revealed")

-- Reveal: press, release, typing, None.
local rv = P.NewReveal()
local on, changed = rv:Update("CTRL", true, false)
H.eq(on, true, "press")
H.eq(changed, true, "refresh on press")
on, changed = rv:Update("CTRL", true, false)
H.eq(changed, false, "no refresh without change")
on = rv:Update("CTRL", true, true)
H.eq(on, false, "focus moved into an edit box while held: off")
on, changed = rv:Update("CTRL", false, true)
H.eq(on, false, "released while typing: still off (reconciled)")
on = rv:Update("CTRL", false, false)
H.eq(on, false, "released")
H.eq((rv:Update("NONE", true, false)), false, "modifier None: never reveals")

-- Tooltip rows: current first and emphasised, compact others, no-weights row, alts only when transferable.
local noW = res("unknown", { spec = "PRIEST.DISCIPLINE", reasons = { "NO_WEIGHTS" } })
local view = { current = res("no_upgrade", { spec = "PRIEST.SHADOW" }), own = { up, noW }, alts = { altUp } }
local rows = P.TooltipRows(view, { specs = "all", alts = true }, false)
H.eq(#rows, 3, "current + two own specs, no alts on a soulbound item")
H.eq(rows[1].emphasis, true, "current spec emphasised")
H.eq(rows[2].compact, true, "secondary rows compact")
H.eq(rows[3].noWeights, true, "missing weights shown as unavailable")
H.eq(rows[3].label, "no weights", "labelled 'no weights', never 0")
rows = P.TooltipRows(view, { specs = "all", alts = true }, true)
H.eq(rows[4].kind, "alt", "transferable: eligible alt row added")
rows = P.TooltipRows(view, { specs = "current" }, true)
H.eq(#rows, 2, "current spec only (+ alt)")

-- Protection is independent of markers: same results, whatever the arrows show.
local results = { res("no_upgrade", { spec = "PRIEST.SHADOW" }), up }
H.eq(P.Protection(results).verdict, "protect", "off-spec upgrade protects although its arrow is hidden")
H.eq(P.Marker({ current = results[1], own = { up }, bound = true, surface = "bags" }, defaults, false), nil,
    "...and that arrow really is hidden")
H.eq(P.Protection({ no }).verdict, "clear", "trusted no-upgrade: clear")
H.eq(P.Protection({ no, res("pending") }).verdict, "pending", "pending keeps")
H.eq(P.Protection({ res("no_upgrade", { baseline = { source = "fallback-current", complete = true } }) }).verdict,
    "unknown", "fallback baseline can't confirm safety")
H.eq(P.Protection({ res("no_upgrade", { baseline = { source = "observed", stale = true } }) }).verdict,
    "unknown", "stale baseline can't confirm safety")
H.eq(P.Protection({ res("no_upgrade", { limitations = { "EFFECT_NOT_SCORED" } }) }).verdict,
    "unknown", "unscored effect can't confirm safety")
H.eq(P.Protection({ res("no_upgrade", { limitations = { "SET_BONUS_LOST:500:2" } }) }).verdict,
    "unknown", "breaking a set bonus can't confirm safety")
H.eq(P.Protection({ later }).verdict, "protect", "level-window upgrade is kept for later")
H.eq(P.Protection({ res("unsupported") }).verdict, "unsupported", "unsupported keeps (consumer fails closed)")
H.eq(P.Protection({}).verdict, "unknown", "no targets: never clear")
local pv = P.Protection({ no, noW })
H.eq(pv.verdict, "clear", "a spec without weights is reported unchecked, not blocking")
H.check(H.has(pv.reasons, "UNCHECKED_SPECS"), "...and named")
H.eq(P.Protection({ no, noW }, { noWeights = "keep" }).verdict, "unknown", "option: no weights keeps the item")
H.eq(P.Protection({ noW }).verdict, "unknown", "nothing checked at all: never clear")

H.done("test_policy")
