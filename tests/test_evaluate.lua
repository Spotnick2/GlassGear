------------------------------------------------------------
-- test_evaluate.lua - statuses, upgrade %, eligibility (class gate, spec
-- armor, level window), limitations, set bonuses, baselines (adr/0003).
------------------------------------------------------------

local H = dofile("tests/harness.lua")
local GG = H.loadPure()
local F = dofile("tests/fixtures.lua")
local E = GG.Engine.Evaluate

local function armor(o)
    o.equipLoc = o.equipLoc or "INVTYPE_SHOULDER"
    o.classID = o.classID or 4
    o.subclassID = o.subclassID or 1
    return o
end
local equippedShoulder = F.slot(armor({ itemID = 50,
    stats = { ITEM_MOD_INTELLECT_SHORT = 8, ITEM_MOD_STAMINA_SHORT = 12, ITEM_MOD_SPELL_POWER_SHORT = 12 } }))
local base = F.baseline({ [3] = equippedShoulder })
local mantle = F.item(armor({ itemID = 60,
    stats = { ITEM_MOD_INTELLECT_SHORT = 12, ITEM_MOD_STAMINA_SHORT = 8, ITEM_MOD_SPELL_POWER_SHORT = 18 } }))

local NOBASE = {}
local function eval(o)
    local baseline = o.baseline
    if baseline == nil then baseline = base elseif baseline == NOBASE then baseline = nil end
    return E.One({ item = o.item or mantle, recipient = o.recipient or F.priest, spec = o.spec or "PRIEST.SHADOW",
        current = o.current, profile = o.profile, baseline = baseline, settings = o.settings,
        companion = o.companion, setThresholds = o.setThresholds })
end

-- Upgrade % = (cand - base) / base of the displaced item (Pawn's definition).
local r = eval({ profile = F.shadow, current = true })
local baseScore = 8 * 0.42 + 12 * 1.0 + 12 * 0.1
local candScore = 12 * 0.42 + 18 * 1.0 + 8 * 0.1
H.eq(r.status, "upgrade", "better shoulder is an upgrade")
H.check(math.abs(r.score.pct - (candScore - baseScore) / baseScore) < 1e-9, "pct relative to the replaced item")
H.check(math.abs(r.score.delta - (candScore - baseScore)) < 1e-9, "absolute delta returned too")
H.eq(r.replaces.slots[1], 3, "replaces the shoulder slot")
H.eq(r.method, "weights-linear", "method labelled")
H.eq(r.current, true, "current flag carried")

-- Missing weights: unknown + NO_WEIGHTS, never 0 or no_upgrade.
r = eval({ profile = nil })
H.eq(r.status, "unknown", "no profile -> unknown")
H.check(H.has(r.reasons, "NO_WEIGHTS"), "reason NO_WEIGHTS")
H.eq(r.score, nil, "no score shown")

-- Pending item data; no baseline.
r = eval({ item = F.item(armor({ ready = false })), profile = F.shadow })
H.eq(r.status, "pending", "item data missing -> pending")
r = eval({ profile = F.shadow, baseline = NOBASE })
H.eq(r.status, "unknown", "no baseline -> unknown")
H.check(H.has(r.reasons, "NO_BASELINE"), "reason NO_BASELINE")

-- Baseline item whose data is missing: that slot is unknown, not empty.
local missing = F.baseline({ [3] = { state = "occupied", itemID = 50 } })
r = eval({ profile = F.shadow, baseline = missing })
H.eq(r.status, "unknown", "baseline item without data -> unknown")

-- Threshold: below 0.5% is no_upgrade.
local tiny = F.item(armor({ itemID = 61,
    stats = { ITEM_MOD_INTELLECT_SHORT = 8, ITEM_MOD_STAMINA_SHORT = 13, ITEM_MOD_SPELL_POWER_SHORT = 12 } }))
local lowStam = { weights = { Intellect = 0.42, SpellDamage = 1.0, CritRating = 0.68, Stamina = 0.05 }, ignored = {} }
r = eval({ item = tiny, profile = lowStam })
H.eq(r.status, "no_upgrade", "+1 Stamina at 0.05 (+0.3%) is under the 0.5% threshold")
r = eval({ item = tiny, profile = lowStam, settings = { threshold = 0.001 } })
H.eq(r.status, "upgrade", "...and an upgrade with a 0.1% threshold")

-- Class gate (hard): a priest never sees plate or a sword as an upgrade.
local plate = F.item(armor({ itemID = 62, subclassID = 4, stats = { ITEM_MOD_INTELLECT_SHORT = 40 } }))
r = eval({ item = plate, profile = F.shadow })
H.eq(r.status, "ineligible", "priest + plate")
H.check(H.has(r.eligibility.reasons, "PROFICIENCY"), "PROFICIENCY")
local sword = F.item({ itemID = 63, equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7,
    stats = { ITEM_MOD_INTELLECT_SHORT = 10 } })
r = eval({ item = sword, profile = F.shadow })
H.eq(r.status, "ineligible", "priests can't use swords")

-- Spec armor rule: cloth spell power is fine for Holy Paladin, ineligible for Protection.
local palBase = F.baseline({ [3] = F.slot(armor({ itemID = 70, subclassID = 4,
    stats = { ITEM_MOD_STAMINA_SHORT = 10, ITEM_MOD_STRENGTH_SHORT = 10 } })) })
local clothSP = F.item(armor({ itemID = 71, subclassID = 1,
    stats = { ITEM_MOD_INTELLECT_SHORT = 10, ITEM_MOD_SPELL_POWER_SHORT = 20 } }))
local palHoly = { weights = { Intellect = 0.5, Healing = 1 }, ignored = {} }
local palProt = { weights = { Stamina = 1, Strength = 0.5, DefenseRating = 1 }, ignored = {} }
r = eval({ item = clothSP, recipient = F.paladin, spec = "PALADIN.HOLY", profile = palHoly, baseline = palBase })
H.eq(r.status, "upgrade", "Holy Paladin may wear cloth")
r = eval({ item = clothSP, recipient = F.paladin, spec = "PALADIN.PROTECTION", profile = palProt, baseline = palBase })
H.eq(r.status, "ineligible", "Protection Paladin: cloth is not a spec armor type")
H.check(H.has(r.eligibility.reasons, "NOT_SPEC_ARMOR"), "NOT_SPEC_ARMOR")
r = eval({ item = clothSP, recipient = F.paladin, spec = "PALADIN.PROTECTION", profile = palProt,
    baseline = palBase, settings = { specArmor = false } })
H.check(r.status ~= "ineligible", "spec armor rule can be turned off")
local cloak = F.item(armor({ itemID = 72, equipLoc = "INVTYPE_CLOAK", subclassID = 1, stats = { ITEM_MOD_STAMINA_SHORT = 12 } }))
r = eval({ item = cloak, recipient = F.paladin, spec = "PALADIN.PROTECTION", profile = palProt, baseline = palBase })
H.check(r.status ~= "ineligible", "cloaks are cloth but exempt from the spec armor rule")
local custom = { weights = palProt.weights, ignored = {}, armor = { 1, 4 } }
r = eval({ item = clothSP, recipient = F.paladin, spec = "PALADIN.PROTECTION", profile = custom, baseline = palBase })
H.check(r.status ~= "ineligible", "a profile can edit its spec's armor set")

-- Level window: default on, look-ahead 0.
local lowPal = { key = "G-Low", class = "PALADIN", level = 38, provenance = "self" }
local mail42 = F.item(armor({ itemID = 73, subclassID = 3, reqLevel = 42, stats = { ITEM_MOD_STAMINA_SHORT = 30 } }))
r = eval({ item = mail42, recipient = lowPal, spec = "PALADIN.PROTECTION", profile = palProt, baseline = palBase })
H.eq(r.status, "ineligible", "4 levels away, look-ahead 0 -> not presented")
H.check(H.has(r.eligibility.reasons, "ABOVE_LEVEL_WINDOW"), "ABOVE_LEVEL_WINDOW")
r = eval({ item = mail42, recipient = lowPal, spec = "PALADIN.PROTECTION", profile = palProt, baseline = palBase,
    settings = { levelWindow = { enabled = true, lookAhead = 4 } } })
H.eq(r.status, "upgrade", "inside a 4-level window: scored")
H.eq(r.eligibility.equipNow, false, "not wearable now")
H.eq(r.eligibility.atLevel, 42, "at level 42")
H.eq(r.eligibility.levelsAway, 4, "in 4 levels")
local plate40 = F.item(armor({ itemID = 74, subclassID = 4, reqLevel = 35, stats = { ITEM_MOD_STAMINA_SHORT = 30 } }))
r = eval({ item = plate40, recipient = lowPal, spec = "PALADIN.PROTECTION", profile = palProt, baseline = palBase,
    settings = { levelWindow = { enabled = true, lookAhead = 2 } } })
H.eq(r.eligibility.atLevel, 40, "plate learned at 40: the later of item and skill level")
r = eval({ item = mail42, recipient = lowPal, spec = "PALADIN.PROTECTION", profile = palProt, baseline = palBase,
    settings = { levelWindow = { enabled = false } } })
H.check(H.has(r.eligibility.reasons, "LATER_LEVEL"), "window off: scored as LATER_LEVEL")

-- Pawn X on a stat on the item -> ineligible for that profile.
r = eval({ profile = { weights = F.shadow.weights, ignored = { Stamina = true } } })
H.eq(r.status, "ineligible", "X stat present")

-- Limitations: effects, no supported stats, weighted-but-unscored tokens.
local trinket = F.item({ itemID = 80, equipLoc = "INVTYPE_TRINKET", classID = 4, subclassID = 0, hasSpell = true })
r = eval({ item = trinket, profile = F.shadow, baseline = F.baseline() })
H.check(H.has(r.limitations, "EFFECT_NOT_SCORED"), "proc/use trinket: effect not scored")
H.check(H.has(r.limitations, "NO_SUPPORTED_STATS"), "...and no supported stats: not a modelled zero")
r = eval({ profile = { weights = { Intellect = 1, FireSpellDamage = 2 }, ignored = {} } })
H.check(H.has(r.limitations, "TOKEN_NOT_SCORED:FireSpellDamage"), "weighted token that is never scored is listed")

-- WoWSims missing weights: an item with that stat gets WEIGHT_MISSING.
local wowsims = { weights = { Intellect = 1 }, ignored = {}, missing = { "Healing" } }
local healer = F.item(armor({ itemID = 81, stats = { ITEM_MOD_INTELLECT_SHORT = 9, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 100 } }))
r = eval({ item = healer, profile = wowsims, spec = "PRIEST.HOLY" })
H.check(H.has(r.limitations, "WEIGHT_MISSING:Healing"), "missing weight on a stat the item has")
local intOnly = F.item(armor({ itemID = 91, stats = { ITEM_MOD_INTELLECT_SHORT = 20 } }))
r = eval({ item = intOnly, profile = wowsims })
H.check(not H.has(r.limitations, "WEIGHT_MISSING:Healing"), "...but not when the item lacks that stat")

-- X on a type token: IGNORED_TYPE.
r = eval({ profile = { weights = F.shadow.weights, ignored = { IsCloth = true } } })
H.check(H.has(r.eligibility.reasons, "IGNORED_TYPE:IsCloth"), "X on IsCloth -> IGNORED_TYPE")

-- Class gate details: untrained proficiency, relics, plate-spec mail after 40.
local paladin60 = { key = "G-P", class = "PALADIN", level = 60, provenance = "self", knownArmor = { [1] = true, [2] = true, [3] = true } }
r = eval({ item = plate, recipient = paladin60, spec = "PALADIN.PROTECTION", profile = palProt, baseline = palBase })
H.eq(r.status, "ineligible", "level 60 without plate trained: not an upgrade now")
H.check(H.has(r.eligibility.reasons, "NEEDS_TRAINING"), "NEEDS_TRAINING, not LATER_LEVEL")
local libram = F.item({ itemID = 82, equipLoc = "INVTYPE_RELIC", classID = 4, subclassID = 7, stats = { ITEM_MOD_STAMINA_SHORT = 5 } })
r = eval({ item = libram, recipient = { key = "G-M", class = "MAGE", level = 60, provenance = "self" },
    spec = "MAGE.FROST", profile = F.shadow, baseline = F.baseline() })
H.eq(r.status, "ineligible", "a mage never gets a libram")
H.check(H.has(r.eligibility.reasons, "PROFICIENCY"), "relic class restriction")
local mail = F.item(armor({ itemID = 83, subclassID = 3, stats = { ITEM_MOD_STAMINA_SHORT = 40 } }))
r = eval({ item = mail, recipient = F.paladin, spec = "PALADIN.PROTECTION", profile = palProt, baseline = palBase })
H.check(H.has(r.eligibility.reasons, "NOT_SPEC_ARMOR"), "level-60 Protection Paladin: mail no longer a spec armor type")
local young = { key = "G-Y", class = "PALADIN", level = 30, provenance = "self" }
local mail30 = F.item(armor({ itemID = 84, subclassID = 3, reqLevel = 28, stats = { ITEM_MOD_STAMINA_SHORT = 40 } }))
r = eval({ item = mail30, recipient = young, spec = "PALADIN.PROTECTION", profile = palProt, baseline = palBase })
H.eq(r.status, "upgrade", "before plate, mail is a Protection armor type")

-- Weapons: off-hand weapon without dual wield; companion legality and data.
local ohWeapon = F.item({ itemID = 85, equipLoc = "INVTYPE_WEAPONOFFHAND", classID = 2, subclassID = 15, stats = { ITEM_MOD_AGILITY_SHORT = 10 } })
local rogue = { key = "G-R", class = "ROGUE", level = 60, provenance = "self", canDualWield = false }
local rogueProf = { weights = { Agility = 1 }, ignored = {} }
r = eval({ item = ohWeapon, recipient = rogue, spec = "ROGUE.COMBAT", profile = rogueProf, baseline = F.baseline() })
H.eq(r.status, "ineligible", "off-hand weapon needs dual wield")
local staff = F.slot({ itemID = 86, equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 10, stats = { ITEM_MOD_INTELLECT_SHORT = 30 } })
local wandBase = F.baseline({ [16] = staff })
local dagger = F.item({ itemID = 87, equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subclassID = 15, stats = { ITEM_MOD_INTELLECT_SHORT = 20 } })
local twoHandCompanion = F.slot({ itemID = 88, equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 10, stats = { ITEM_MOD_INTELLECT_SHORT = 30 } })
r = eval({ item = dagger, profile = F.shadow, baseline = wandBase, companion = { [17] = twoHandCompanion } })
H.check(r.status ~= "upgrade", "a two-hander can't be the off-hand companion")
local book = { state = "occupied", itemID = 89, equipLoc = "INVTYPE_HOLDABLE", classID = 4, subclassID = 0 }
r = eval({ item = dagger, profile = F.shadow, baseline = wandBase, companion = { [17] = book } })
H.eq(r.status, "unknown", "companion without item data: unknown, not zero")

-- Scoring gaps of the replaced items count too (WoWSims weight missing on the displaced item).
local healBase = F.baseline({ [3] = F.slot(armor({ itemID = 95,
    stats = { ITEM_MOD_INTELLECT_SHORT = 10, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 100 } })) })
r = eval({ item = F.item(armor({ itemID = 96, stats = { ITEM_MOD_INTELLECT_SHORT = 9 } })), profile = wowsims,
    spec = "PRIEST.HOLY", baseline = healBase })
H.check(H.has(r.limitations, "BASELINE_WEIGHT_MISSING:Healing"), "the displaced item's missing weight is reported")
H.eq(GG.Engine.Policy.Protection({ r }).verdict, "unknown", "...so protection can't say clear")

-- A companion must be wearable now and not excluded by the profile.
local hpal = { key = "G-H", class = "PALADIN", level = 60, provenance = "self" }
local hpalBase = F.baseline({ [16] = F.slot({ itemID = 97, equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 5,
    stats = { ITEM_MOD_INTELLECT_SHORT = 10 } }) })
local mace = F.item({ itemID = 98, equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subclassID = 4, stats = { ITEM_MOD_INTELLECT_SHORT = 5 } })
local function shield(o)
    local x = F.slot({ itemID = 99, equipLoc = "INVTYPE_SHIELD", classID = 4, subclassID = 6, stats = { ITEM_MOD_INTELLECT_SHORT = 20 } })
    x.classID, x.subclassID, x.reqLevel = 4, 6, o.reqLevel
    return x
end
local hprof = { weights = { Intellect = 1 }, ignored = {} }
r = eval({ item = mace, recipient = hpal, spec = "PALADIN.HOLY", profile = hprof, baseline = hpalBase, companion = { [17] = shield({ reqLevel = 50 }) } })
H.eq(r.status, "upgrade", "mace + wearable shield beats the two-hander")
r = eval({ item = mace, recipient = hpal, spec = "PALADIN.HOLY", profile = { weights = { Intellect = 1 }, ignored = { IsShield = true } },
    baseline = hpalBase, companion = { [17] = shield({ reqLevel = 50 }) } })
H.check(r.status ~= "upgrade", "a companion the profile excludes (IsShield=X) doesn't count")
r = eval({ item = mace, recipient = hpal, spec = "PALADIN.HOLY", profile = hprof, baseline = hpalBase, companion = { [17] = shield({ reqLevel = 70 }) } })
H.check(r.status ~= "upgrade", "a companion above the character's level doesn't count")
r = eval({ item = mace, recipient = hpal, spec = "PALADIN.HOLY", profile = hprof, baseline = hpalBase, companion = { [17] = shield({}) } })
H.check(r.status ~= "upgrade", "a companion without a known required level doesn't count")

-- An unevaluable alternative slot blocks "no upgrade" (but not a known upgrade).
local ringBase = F.baseline({ [11] = F.slot({ itemID = 100, equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0,
    stats = { ITEM_MOD_INTELLECT_SHORT = 10 } }), [12] = { state = "occupied", itemID = 101, equipLoc = "INVTYPE_FINGER" } })
local ring9 = F.item({ itemID = 102, equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0, stats = { ITEM_MOD_INTELLECT_SHORT = 9 } })
r = eval({ item = ring9, profile = F.shadow, baseline = ringBase })
H.eq(r.status, "unknown", "the other ring's data is missing: not 'no upgrade'")
H.check(H.has(r.reasons, "ALTERNATIVE_SLOT_UNKNOWN"), "ALTERNATIVE_SLOT_UNKNOWN")
H.eq(r.baseline.complete, false, "and the baseline is reported incomplete")
local ring30 = F.item({ itemID = 103, equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0, stats = { ITEM_MOD_INTELLECT_SHORT = 30 } })
H.eq(eval({ item = ring30, profile = F.shadow, baseline = ringBase }).status, "upgrade", "a known upgrade still stands")

-- Limitations of the items being replaced travel with the result.
local procBase = F.baseline({ [3] = (function() local x = F.slot(armor({ itemID = 90,
    stats = { ITEM_MOD_INTELLECT_SHORT = 8 } })); x.hasSpell = true; return x end)() })
r = eval({ profile = F.shadow, baseline = procBase })
H.check(H.has(r.limitations, "BASELINE_EFFECT_NOT_SCORED"), "replaced item's unscored effect is reported")

-- Enchants are compared symmetrically: Compat strips them from both sides,
-- so an enchanted baseline item scores as its base item.
H.eq(GG.Engine.Score.StripEnchant("item:50:1883:0:0:0:0:0:0"), GG.Engine.Score.StripEnchant("item:50:0:0:0:0:0:0:0"),
    "enchanted and plain links strip to the same item")

-- Set bonuses with known thresholds: completing and breaking.
local setPiece = function(id, setID, slotLoc) return F.slot(armor({ itemID = id, setID = setID, equipLoc = slotLoc,
    stats = { ITEM_MOD_INTELLECT_SHORT = 10 } })) end
local setBase = F.baseline({ [1] = setPiece(90, 500, "INVTYPE_HEAD"), [3] = setPiece(91, 500, "INVTYPE_SHOULDER") })
local nonSet = F.item(armor({ itemID = 92, stats = { ITEM_MOD_INTELLECT_SHORT = 30 } }))
r = eval({ item = nonSet, profile = F.shadow, baseline = setBase, setThresholds = { [500] = { 2 } } })
H.check(H.has(r.limitations, "SET_BONUS_LOST:500:2"), "replacing a set piece breaks the 2-piece bonus")
local third = F.item(armor({ itemID = 93, setID = 500, equipLoc = "INVTYPE_CHEST", stats = { ITEM_MOD_INTELLECT_SHORT = 5 } }))
r = eval({ item = third, profile = F.shadow, baseline = setBase, setThresholds = { [500] = { 2, 3 } } })
H.check(H.has(r.limitations, "SET_BONUS_GAINED:500:3"), "a third piece completes the 3-piece bonus")
r = eval({ item = third, profile = F.shadow, baseline = setBase })
H.check(H.has(r.limitations, "SET_BONUS_NOT_SCORED"), "no threshold data -> SET_BONUS_NOT_SCORED")
local samePiece = F.item(armor({ itemID = 94, setID = 500, stats = { ITEM_MOD_INTELLECT_SHORT = 40 } }))
r = eval({ item = samePiece, profile = F.shadow, baseline = setBase })
H.check(H.has(r.limitations, "SET_BONUS_NOT_SCORED"), "swapping within an unmodelled set still warns")

-- Baseline flags travel into reasons.
r = eval({ profile = F.shadow, baseline = F.baseline({ [3] = equippedShoulder }, { stale = true, source = "fallback-current" }) })
H.check(H.has(r.reasons, "BASELINE_STALE"), "stale baseline reported")
H.check(H.has(r.reasons, "BASELINE_FALLBACK"), "fallback-current reported")

-- Empty slot: upgrade without a percentage.
r = eval({ item = cloak, profile = F.shadow, baseline = F.baseline() })
H.eq(r.status, "upgrade", "anything with value fills an empty slot")
H.check(H.has(r.reasons, "EMPTY_SLOT"), "EMPTY_SLOT")
H.eq(r.score.pct, nil, "no percentage against nothing")

-- Baselines: precedence and freshness.
local B = GG.Baselines
local chosen = B.Choose({ observed = { slots = {}, capturedAt = 1 }, current = { slots = {}, capturedAt = 2 } })
H.eq(chosen.source, "observed", "observed beats fallback-current")
chosen = B.Choose({ equipmentSet = { slots = {} }, observed = { slots = {} } })
H.eq(chosen.source, "equipment-set", "a mapped equipment set wins")
H.eq(chosen.complete, false, "missing slots -> incomplete")
H.eq(B.Choose({ current = { slots = {} } }).source, "fallback-current", "fallback labelled")
local stale, expires = B.Freshness({ capturedAt = 0 }, B.STALE_AFTER - 1)
H.eq(stale, false, "fresh before 14 days")
H.eq(expires, B.STALE_AFTER, "expiresAt = capture + 14 days")
H.eq((B.Freshness({ capturedAt = 0 }, B.STALE_AFTER)), true, "stale at 14 days")
H.eq((B.Freshness({ capturedAt = 100 }, 200, 150)), true, "gear changed after capture -> stale")

-- Aggregate (display only).
H.eq(E.Aggregate({ { status = "no_upgrade" }, { status = "pending" }, { status = "upgrade" } }), "upgrade", "upgrade first")
H.eq(E.Aggregate({ { status = "no_upgrade" }, { status = "unknown" } }), "unknown", "unknown before no_upgrade")
H.eq(E.Aggregate({}), "unsupported", "nothing evaluated")

H.done("test_evaluate")
