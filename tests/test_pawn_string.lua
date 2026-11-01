------------------------------------------------------------
-- test_pawn_string.lua - Pawn v1 import/export, WoWSims Pawn EP (GG-003).
------------------------------------------------------------

local H = dofile("tests/harness.lua")
local GG = H.loadPure()
local P = GG.PawnString

local p = assert(P.Parse('( Pawn: v1: "Karuzo - Shadow - Raid": Class=Priest, Intellect=0.42, SpellDamage=1.00, CritRating=0.68, Spirit=X )'))
H.eq(p.name, "Karuzo - Shadow - Raid", "scale name")
H.eq(p.class, "Priest", "Class= is metadata, not a weight")
H.eq(p.weights.Intellect, 0.42, "weight parsed")
H.eq(p.weights.SpellDamage, 1.0, "weight parsed")
H.eq(p.ignored.Spirit, true, "X = ignored stat")
H.eq(p.weights.Spirit, nil, "X is not a weight")
H.eq(p.source, "imported-pawn", "provenance")

-- Round trip.
local again = assert(P.Parse(P.Export(p, "Priest")))
H.eq(again.weights.CritRating, 0.68, "export/import keeps weights")
H.eq(again.ignored.Spirit, true, "export/import keeps X")

-- Unknown tokens are reported, not silently dropped or scored.
local w = assert(P.Parse('( Pawn: v1: "Frost WoWSims Weights": Class=Mage,Intellect=1.234,Mana=0.050,Stamina=0.010 )'))
H.eq(w.source, "wowsims-pawn-ep", "WoWSims Pawn EP recognised by its scale name")
H.check(H.has(w.warnings, "UNKNOWN_STAT:Mana"), "Mana is not a Pawn stat: warned")
H.check(H.has(w.warnings, "WOWSIMS_DROPS:HitRating"), "WoWSims EP drops hit: warned")
H.eq(w.weights.Mana, nil, "unknown token not kept as weight")

-- Errors.
local _, e1 = P.Parse("( Pawn: v2: \"x\": Stamina=1 )")
H.eq(e1, "UNSUPPORTED_VERSION", "future version refused")
local _, e2 = P.Parse("hello")
H.eq(e2, "NOT_A_PAWN_STRING", "garbage refused")
local _, e3 = P.Parse('( Pawn: v1: "x": Class=Priest )')
H.eq(e3, "NO_WEIGHTS", "no weight values found (mockup 05 error)")
local _, e4 = P.Parse('( Pawn: v1: "x": Stamina=abc )')
H.eq(e4, "BAD_VALUE:Stamina", "non-numeric value refused")
local long = assert(P.Parse('( Pawn: v1: "A very long scale name beyond the cap": Stamina=1 )'))
H.eq(#long.name, P.MAX_NAME, "name capped at 24 (codec limit)")

H.done("test_pawn_string")
