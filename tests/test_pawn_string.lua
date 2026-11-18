------------------------------------------------------------
-- test_pawn_string.lua - Pawn v1 import/export and WoWSims Pawn EP, with the
-- exact codes of docs/FORMATS.md (GG-003, GG-105).
------------------------------------------------------------

local H = dofile("tests/harness.lua")
local GG = H.loadPure()
local P = GG.PawnString

local p = assert(P.Parse('( Pawn: v1: "Karuzo - Shadow - Raid": Class=Priest, Intellect=0.42, SpellDamage=1.00, CritRating=0.68, Spirit=X )',
    { class = "PRIEST" }))
eq(p.name, "Karuzo - Shadow - Raid", "scale name")
eq(p.origin, "Karuzo - Shadow - Raid", "kept as origin")
eq(p.class, "Priest", "Class= is metadata, not a weight")
eq(p.weights.Intellect, 0.42, "weight parsed")
eq(p.ignored.Spirit, true, "X = ignored stat")
eq(p.weights.Spirit, nil, "X is not a weight")
eq(p.source, "imported-pawn", "provenance")
eq(#p.warnings, 0, "matching class: no warning")

-- Round trip, in the token table's order, Class first.
local text = P.Export(p, "Priest")
check(text:find('^%( Pawn: v1: "Karuzo %- Shadow %- Raid": Class=Priest, Intellect=0.42') ~= nil, "export order: Class, then token order")
local again = assert(P.Parse(text))
eq(again.weights.CritRating, 0.68, "export/import keeps weights")
eq(again.ignored.Spirit, true, "export/import keeps X")

-- Unknown tokens are kept (ignoredTokens) and round-trip; WoWSims EP warnings.
local w = assert(P.Parse('( Pawn: v1: "Frost WoWSims Weights": Class=Mage,Intellect=1.234,Mana=7,Stamina=0.010, )', { class = "MAGE" }))
eq(w.source, "wowsims-pawn-ep", "WoWSims Pawn EP recognised by its scale name")
check(H.has(w.warnings, "UNSUPPORTED_TOKEN:Mana"), "Mana is not a Pawn stat: UNSUPPORTED_TOKEN")
check(H.has(w.warnings, "WOWSIMS_DROPPED_STATS"), "WoWSims EP: dropped-stats warning")
eq(w.ignoredTokens.Mana, "7", "unknown pair kept")
check(H.has(w.missing, "HitRating") and H.has(w.missing, "Healing"), "dropped stats recorded as missing, not zero")
eq(w.weights.Mana, nil, "unknown token is not a weight")
check(P.Export(w):find("Mana=7", 1, true) ~= nil, "unknown pair round-trips on export")

-- Class mismatch warns but imports.
local m = assert(P.Parse('( Pawn: v1: "x": Class=Warrior, Strength=1 )', { class = "PRIEST" }))
check(H.has(m.warnings, "CLASS_MISMATCH"), "class mismatch warned")
check(not H.has(assert(P.Parse('( Pawn: v1: "x": Class=5, Intellect=1 )', { class = "PRIEST" })).warnings, "CLASS_MISMATCH"),
    "Pawn class id 5 is Priest")

-- Errors (exact codes).
local function err(t) return select(2, P.Parse(t)) end
eq(err('( Pawn: v2: "x": Stamina=1 )'), "UNSUPPORTED_VERSION", "future version refused")
eq(err('( Pawn: v0: "x": Stamina=1 )'), "UNSUPPORTED_VERSION", "v0 refused: the version must be 1")
eq(err("hello"), "NOT_PAWN", "garbage refused")
eq(err('( Pawn: v1: "x": Class=Priest )'), "NO_WEIGHTS", "no weight values found (mockup 05)")
eq(err('( Pawn: v1: "x": Spirit=X )'), "NO_WEIGHTS", "X only: no numeric weight")
eq(err('( Pawn: v1: "x": Stamina=abc )'), "BAD_PAIR:1", "non-numeric value")
eq(err('( Pawn: v1: "x": Stamina=1, Intellect=1.2.3 )'), "BAD_PAIR:2", "malformed number, with position")
eq(err('( Pawn: v1: "x": Intellect=1000 )'), "VALUE_OUT_OF_RANGE:Intellect", "out of range refused, never clamped")
local many = {}
for t in pairs(GG.Data.Stats.TOKENS) do if #many < 41 then many[#many + 1] = t .. "=1" end end
eq(err('( Pawn: v1: "x": ' .. table.concat(many, ", ") .. " )"), "TOO_MANY_TOKENS", "more than 40 tokens")
eq(err('{ "class": "mage", "gear": { "items": [] } }'), "CHARACTER_EXPORT_NOT_WEIGHTS", "WoWSims character JSON")
eq(err('priest="Karuzo"\nlevel=60\nspec=unknown\ntalents=ABC'), "CHARACTER_EXPORT_NOT_WEIGHTS", "SimC profile")
local long = assert(P.Parse('( Pawn: v1: "A very long scale name beyond the cap": Stamina=1 )'))
eq(#long.name, P.MAX_NAME, "name capped at 24 (codec limit); origin keeps the full text")

done("test_pawn_string")
