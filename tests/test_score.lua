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
H.eq(Score.StripEnchant("19019:2564:1234"), "19019:0:1234", "compact form: enchant zeroed, suffix kept")

local unscored = Stats.UnscoredTokens({ weights = { Speed = 1, Intellect = 1 } })
H.eq(unscored[1], "Speed", "weighted but never scored tokens are listed")

H.done("test_score")
