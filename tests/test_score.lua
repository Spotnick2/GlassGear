------------------------------------------------------------
-- test_score.lua - stat mapping, weighted score, enchant stripping (adr/0003).
------------------------------------------------------------

local H = dofile("tests/harness.lua")
local GG = H.loadPure()
local Stats, Score = GG.Data.Stats, GG.Engine.Score

local tokens, unsupported = Stats.FromItemStats({
    ITEM_MOD_INTELLECT_SHORT = 12, ITEM_MOD_STAMINA_SHORT = 8, ITEM_MOD_SPELL_POWER_SHORT = 18,
    ITEM_MOD_SOMETHING_NEW = 5, RESISTANCE0_NAME = 40,
}, { classID = 4, subclassID = 1, equipLoc = "INVTYPE_SHOULDER" })
H.eq(tokens.Intellect, 12, "intellect")
H.eq(tokens.SpellDamage, 18, "spell power feeds SpellDamage")
H.eq(tokens.Healing, 18, "...and Healing")
H.eq(tokens.Armor, 40, "armor from RESISTANCE0_NAME")
H.eq(tokens.IsCloth, 1, "type token from the subclass")
H.eq(unsupported[1], "ITEM_MOD_SOMETHING_NEW", "unknown key reported, not dropped")

local weapon = Stats.FromItemStats({ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40.5 },
    { classID = 2, subclassID = 19, equipLoc = "INVTYPE_RANGEDRIGHT" })
H.eq(weapon.IsWand, 1, "wand type token")
H.eq(weapon.RangedDps, 40.5, "derived RangedDps")

local s = Score.Compute(tokens, { weights = { Intellect = 0.5, SpellDamage = 1, Stamina = 0.1 } })
H.eq(s.score, 12 * 0.5 + 18 + 0.8, "weighted sum")
H.eq(s.noSupported, false, "has supported stats")
local none = Score.Compute({ Armor = 50 }, { weights = { Intellect = 1 } })
H.eq(none.score, 0, "zero score")
H.eq(none.noSupported, true, "...flagged as no supported stats, not a modelled zero")
local ign = Score.Compute(tokens, { weights = { Intellect = 1 }, ignored = { Stamina = true } })
H.eq(ign.ignoredHit, "Stamina", "an X stat on the item is reported")

H.eq(Score.StripEnchant("item:19019:2564:0:0:0:0:1234:0"), "item:19019::0:0:0:0:1234:0",
    "enchant removed, suffix 1234 kept")
H.eq(Score.StripEnchant("item:14094:1883:::::::::::1:12745"), "item:14094::::::::::::1:12745",
    "Forever: enchant removed, the bonus ID that carries the random suffix kept")
H.eq(Score.StripEnchant("item:288919"), "item:288919", "a plain trimmed string is unchanged")

local unscored = Stats.UnscoredTokens({ weights = { Speed = 1, Intellect = 1 } }, { classID = 2 })
H.eq(unscored[1], "Speed", "weighted but never scored tokens are listed for weapons")
H.eq(#Stats.UnscoredTokens({ weights = { Speed = 1 } }, { classID = 4 }), 0, "weapon-only token is irrelevant to armor")
H.eq(Stats.UnscoredTokens({ weights = {}, ignored = { Speed = true } }, { classID = 2 })[1], "Speed",
    "an X on an unsupported token is also unscored (unresolvable)")
H.eq(#Stats.UnscoredTokens({ weights = { ShadowSpellDamage = 1 } }, { classID = 4 }), 0,
    "measured school damage (Shadow) is read from its own key: not listed as unscored")
H.eq(Stats.UnscoredTokens({ weights = { FireSpellDamage = 1 } }, { classID = 4 })[1], "FireSpellDamage",
    "an unsampled school (Fire) keeps its not-scored warning (Codex, PR #45)")
local _, fireUns = Stats.FromItemStats({ ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = 6 })
H.eq(fireUns[1], "ITEM_MOD_FIRE_DAMAGE_DONE_SHORT", "...and a guessed Fire key on an item stays unrecognised")

-- Forever's keys as measured on 70425 (docs/FOREVER-PROBE.md P4).
local t, uns = Stats.FromItemStats({ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 29, ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = 6,
    ITEM_MOD_SPIRIT_SHORT = 3 })
H.eq(t.ShadowSpellDamage, 6, "Shadow damage key -> ShadowSpellDamage")
H.eq(#uns, 0, "...nothing left unrecognised")
t, uns = Stats.FromItemStats({ ITEM_MOD_FIRE_RESISTANCE_SHORT = 3, RESISTANCE2_NAME = 3 })
H.eq(t.FireResist, 3, "resistance reported under both names counts once")
H.eq(#uns, 0, "...and neither name is unrecognised")
t = Stats.FromItemStats({ ITEM_MOD_FROST_RESISTANCE_SHORT = 4 })
H.eq(t.FrostResist, 4, "the ITEM_MOD_ form alone still counts")
t = Stats.FromItemStats({ ITEM_MOD_SPELL_POWER_SHORT = 2 })
H.eq(t.SpellDamage, 2, "spell power -> SpellDamage")
H.eq(t.Healing, 2, "...and Healing")

H.done("test_score")
