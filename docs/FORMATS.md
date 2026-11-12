# Import and export formats

Which outside formats Glass Gear reads and writes, and which it cannot read. Source labels are
defined in [adr/0005](adr/0005-weight-sources.md), the score itself in
[adr/0003](adr/0003-upgrade-metric.md), and the evidence in
[ECOSYSTEM-FINDINGS.md](ECOSYSTEM-FINDINGS.md).

## Support table

| Format | What it is | Glass Gear | Source label | Backlog |
|---|---|---|---|---|
| Pawn scale string v1 | A stat-weight scale | **Import and export** | `imported-pawn` | GG-003 (parser), GG-105 (UI) |
| WoWSims "Pawn EP" export | A Pawn v1 string of EP weights | **Import**, as a Pawn string, with a warning | `wowsims-pawn-ep` | GG-003, GG-105 |
| WoWSims character JSON / WowSimsExporter addon JSON | A character (gear, talents, professions) | **Unsupported as weights**: it needs a simulation | — | — |
| SimulationCraft addon profile (`/simc`) | A character (gear, talents, `legacy_talents=`) | **Unsupported as weights**: it needs an external simc run | — | GG-502 / ASC-001 (future) |
| simc scale factors, or simc's Pawn output | Weights computed by a simulation | **Future** import | `sim-result` | GG-502 |
| Glass Gear entry codec `GG1\|…` | Glass Gear's own synced entries | Internal | — | [SCHEMA.md](SCHEMA.md) |

When an unsupported format is pasted, import recognises it and says why it can't be used. A
SimC profile, for example, gets: "This is a character, not weights. Run it through SimulationCraft
with scale factors, then import the Pawn string it produces." It never says only "invalid".

## Pawn scale string v1

The reference is Pawn's Forever release, used for behaviour
only (CC BY-NC-ND, so no code is copied).

### From Pawn's own scales

Glass Gear ships none of Pawn's numbers ([research/default-weights.md](research/default-weights.md)),
but a player who has Pawn can bring any of its scales over, built-in ones included:

1. In Pawn, open the **Scale** tab and select the scale (for example the built-in "Classic" one).
2. Click **Export** (it works on read-only built-in scales too) and copy the string.
3. In game: `/gg import <SPEC.KEY> <string>`, for example `/gg import PRIEST.SHADOW ( Pawn: v1: ... )`.

The import replaces that spec's active profile. Built-in scales carry `Class=` and `Spec=`; `Spec=`
is ignored on Forever. Caster scales keep their hit and crit weights: on Forever, Pawn folds
`SpellHitRating` and `SpellCritRating` into `HitRating` and `CritRating` before it exports, and
Glass Gear scores those. A string exported from another game version can still carry the spell
tokens. They aren't on our token list, so they come in as `UNSUPPORTED_TOKEN` warnings. This comes
from reading Pawn's code and hasn't been tried in game.
A one-click "Import from Pawn" is GG-121, later.

### Grammar

  ```
  ( Pawn: v<N>: "<Name>": <Key>=<Value>, <Key>=<Value>, ... )
  ```

- Whitespace is free around every separator. The version must be `1`; a higher one is refused with
  `UNSUPPORTED_VERSION`.
- `Name` is any text without `"`. It is kept as the profile's `origin`.
- `Key` is `[A-Za-z0-9]+`. `Value` is a signed decimal, or `X`.
- Pairs are comma-separated. A trailing comma before `)` is accepted.
- Exporting writes keys in the order of the token table below, values with up to 3 decimals and
  trailing zeros trimmed, and `Class=` first.

### Special keys
- **`Class=`** is a class name or Pawn class id. Glass Gear keeps it as a check: if it doesn't match
  the target character's class, import warns (`CLASS_MISMATCH`). It still allows the import, because
  WoWSims writes friendly class names.
- **`Spec=`** is ignored on Forever, as Pawn does: there are no spec IDs here.
  The target spec is the one the player picks in Glass Gear.
- **`X`** means "never an upgrade for this stat or type". Pawn stores it as `-1000000`
  (as Pawn does). Glass Gear stores `X` as its own marker, never as a large negative number:
  - on a stat, an item with that stat gets the status `ineligible` with reason `IGNORED_STAT`;
  - on an `Is<Type>` token, items of that type are `ineligible` with reason `IGNORED_TYPE`.
- **Other values outside [-999.999, 999.999]** are refused (`VALUE_OUT_OF_RANGE`). The codec bound
  is in [SCHEMA.md](SCHEMA.md).

### Unknown keys
An unknown key is never silently dropped. It is reported as `UNSUPPORTED_TOKEN`, listed in the
import preview, and kept on the profile as `ignoredTokens`, so it round-trips on export.

### Normalisation
Pawn can rescale a total by the sum of positive weights (`NormalizationFactor`). Glass Gear does
not normalise: scores are raw Σ weight × stat. The upgrade percentage cancels any uniform scale,
and the absolute delta is labelled with the profile it came from.

### Validation errors
Each import returns one of these codes:
- `NOT_PAWN` (no header);
- `UNSUPPORTED_VERSION`;
- `NO_WEIGHTS` (no numeric pair, as mockup 05 shows);
- `BAD_PAIR` (with its position);
- `VALUE_OUT_OF_RANGE`;
- `TOO_MANY_TOKENS` (more than 40, the codec limit).

Warnings: `CLASS_MISMATCH`, `UNSUPPORTED_TOKEN`, and `WOWSIMS_DROPPED_STATS` (below).

## Stat tokens and client stat keys

Glass Gear reads an item's stats with `C_Item.GetItemStats(link)`. It returns a table keyed by
global-string names such as `ITEM_MOD_STAMINA_SHORT`, and armor as `RESISTANCE0_NAME` (as the SimC
addon reads them on Forever). It never parses tooltip
text, which keeps it locale-independent.

**Measured on 1.60.1.70425** (Wanderful's probe log, `WanderfulProbe.lua` in the beta
SavedVariables; docs/FOREVER-PROBE.md P4), on wands and one mace:

- "Increases damage and healing done by magical spells by up to N" is **one** key,
  `ITEM_MOD_SPELL_POWER_SHORT`, which feeds both SpellDamage and Healing (items 11287, 11288).
- School damage has its own key: `ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT` (7001) and
  `ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT` (12984). Fire, Frost, Nature and Holy probably follow the same
  pattern but were not sampled, so they stay unscored (with their warning) until a probe sees them.
- Resistance comes back **twice**: `ITEM_MOD_FIRE_RESISTANCE_SHORT=3` and `RESISTANCE2_NAME=3` on
  the same item (279896). It counts once.
- Spirit is `ITEM_MOD_SPIRIT_SHORT`; DPS is `ITEM_MOD_DAMAGE_PER_SECOND_SHORT` (unrounded, 11.333…).
  No weapon-speed key comes back, although the tooltip shows "Speed 1.50".

Not sampled yet (GG-103): healing-only and damage-only items, mana per 5, hit and crit (per cent or
rating), suffix and enchanted links. Those rows stay "expected".

`Data/Stats.lua` implements this table. A test fails if the table and this doc disagree on a
token's status.

Status meanings:
- **supported**: it enters the score.
- **derived**: computed from another key.
- **reported-unsupported**: accepted on import and kept, never scored, and listed in the item's
  limitations as `TOKEN_NOT_SCORED`.

### Primary and secondary stats

| Pawn token | Client key (from `GetItemStats`) | Status |
|---|---|---|
| Strength | `ITEM_MOD_STRENGTH_SHORT` | supported |
| Agility | `ITEM_MOD_AGILITY_SHORT` | supported |
| Stamina | `ITEM_MOD_STAMINA_SHORT` | supported |
| Intellect | `ITEM_MOD_INTELLECT_SHORT` | supported |
| Spirit | `ITEM_MOD_SPIRIT_SHORT` | supported |
| Armor | `RESISTANCE0_NAME` | supported |
| HitRating | `ITEM_MOD_HIT_RATING_SHORT` | supported |
| CritRating | `ITEM_MOD_CRIT_RATING_SHORT` | supported |
| HasteRating | `ITEM_MOD_HASTE_RATING_SHORT` | supported (rare on Forever) |
| ExpertiseRating | `ITEM_MOD_EXPERTISE_RATING_SHORT` | supported |
| SpellPenetration | `ITEM_MOD_SPELL_PENETRATION_SHORT` | supported |
| Ap | `ITEM_MOD_ATTACK_POWER_SHORT` | supported |
| Rap | `ITEM_MOD_RANGED_ATTACK_POWER_SHORT` | supported |
| FeralAp | `ITEM_MOD_FERAL_ATTACK_POWER_SHORT` | supported |
| DefenseRating | `ITEM_MOD_DEFENSE_SKILL_RATING_SHORT` | supported |
| DodgeRating | `ITEM_MOD_DODGE_RATING_SHORT` | supported |
| ParryRating | `ITEM_MOD_PARRY_RATING_SHORT` | supported |
| BlockRating | `ITEM_MOD_BLOCK_RATING_SHORT` | supported |
| BlockValue | `ITEM_MOD_BLOCK_VALUE_SHORT` | supported |
| Hp5 | `ITEM_MOD_HEALTH_REGEN_SHORT` | supported |
| Mp5 | expected `ITEM_MOD_POWER_REGEN0_SHORT` (Pawn's mapping) | supported; key confirmed by GG-103 |
| SpellDamage | `ITEM_MOD_SPELL_POWER_SHORT` (damage and healing, measured 70425); damage-only expected `ITEM_MOD_SPELL_DAMAGE_DONE_SHORT` | supported |
| Healing | `ITEM_MOD_SPELL_POWER_SHORT` (with SpellDamage, measured 70425); healing-only expected `ITEM_MOD_SPELL_HEALING_DONE_SHORT` | supported |
| Fire/Nature/Frost/Shadow/ArcaneResist | `RESISTANCE2_NAME` … `RESISTANCE6_NAME`; the twin `ITEM_MOD_FIRE_RESISTANCE_SHORT` … counts only when the first is absent (both measured 70425) | supported |
| Shadow/ArcaneSpellDamage | `ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT`, `ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT` (measured 70425) | supported |
| Fire/Nature/Frost/HolySpellDamage | expected `ITEM_MOD_<SCHOOL>_DAMAGE_DONE_SHORT` (not sampled) | reported-unsupported until GG-103 sees the key |

### Weapon tokens

| Pawn token | Client key | Status |
|---|---|---|
| Dps | `ITEM_MOD_DAMAGE_PER_SECOND_SHORT` | supported |
| MeleeDps | derived from Dps on a melee weapon (WoWSims exports it, `individual_pawn_ep_exporter.tsx:97`) | derived |
| RangedDps | derived from Dps on a ranged weapon | derived |
| Speed, MinDamage, MaxDamage and the other Melee/Ranged/MainHand/OffHand/OneHand/TwoHand Dps/Min/Max/Speed variants, SpeedBaseline | not returned by `GetItemStats` (speed measured absent, 70425) | reported-unsupported (GG-103 measures what `C_TooltipInfo` offers) |

### Item-type tokens

| Pawn token | How it is read | Status |
|---|---|---|
| IsCloth, IsLeather, IsMail, IsPlate, IsShield | item class/subclass from `C_Item.GetItemInfoInstant` | supported: a number adds a flat amount, `X` makes the item ineligible |
| IsAxe, Is2HAxe, IsBow, IsCrossbow, IsDagger, IsFist, IsGun, IsMace, Is2HMace, IsPolearm, IsStaff, IsSword, Is2HSword, IsThrown, IsWand, IsRelic, IsOffHand, IsFrill | item class/subclass, and equip location for off-hand/frill | supported, same rule |

The `Is<Type>` tokens are honoured as **weights**: a number adds a flat amount to items of that
type, and `X` excludes the type. That is the profile's preference.

**Eligibility is separate:**
- **What the character can wear.** GG-118 decides this from class, level and the armor skill the
  character knows (Mail/Plate at 40 on Forever).
- **Per-spec armor rules** (GG-118, adr/0003): each spec has its own allowed armor types, editable
  per profile. A Holy Paladin may wear cloth while Protection may not.
- **Level.** GG-117's level window is applied separately.

Both GG-117 and GG-118 apply before scoring. An `IsPlate=5` weight never makes plate wearable
for a character who can't wear it.

### Not on Forever
These are accepted on import as `UNSUPPORTED_TOKEN`:
- Pawn tokens without the `PawnStatForever` flag: SpellHitRating,
  SpellCritRating, SpellHasteRating, MasteryRating, Versatility, ResilienceRating, ArmorPenetration,
  SpellPower, MetaSocketEffect and socket tokens;
- WoWSims-only names: `Mana`, `Health`, `Armor2`.

There are no sockets or gems on Forever (`PORTING-TBC-TO-FOREVER.md:2064`).

## WoWSims "Pawn EP" export

- **Recognised by** the scale name `"<Spec> WoWSims Weights"`
  (`exporters/individual_pawn_ep_exporter.tsx:35`). It is imported through the Pawn parser and
  labelled `wowsims-pawn-ep`.
- **Always warns `WOWSIMS_DROPPED_STATS`:** "WoWSims leaves out stats it can't name for Pawn:
  hit, crit, haste, defence, block, school damage, healing and feral AP (`:68-91`). Those weights
  are missing, not zero." These rows show as **no weight** in the profile view. They are not
  scored as 0 against an item that has them; the item gets `limitations: WEIGHT_MISSING`.
- **Never scored:** `Mana`, `Health` and `Armor2` (`:60-67`). They are kept as unsupported tokens.
- **Caveat:** the local WoWSims checkout is the TBC (level 70) sim (`mechanics.ts:1`). Its weights
  are TBC weights. The profile view shows the origin text, so this is visible to the player.

## WoWSims character JSON / WowSimsExporter

This is a character: `version`, `level`, `class`, `race`, `professions`, `talents` and gear
(`importers/individual_addon_importer.tsx:43-79`). It contains no weights.

- Import recognises it by its leading `{` and those keys.
- It is refused with reason `CHARACTER_EXPORT_NOT_WEIGHTS`.
- The message says to load it into WoWSims, run stat weights, and export "Pawn EP".

## SimulationCraft addon profile

A `/simc` profile starts with `<class>="Name"`, then `level=`, `race=`, `spec=`, `talents=`, and
gear lines `slot=,id=…`. On Forever it has some differences:
- `spec=unknown`;
- talents come from `C_Traits`, with an extra `legacy_talents=` line;
- `forever/` adds stats and pet lines.

The profile requires "SimulationCraft 1000-01 or newer". There is no local
simc that understands Forever profiles.

Import recognises a `/simc` profile by a class line plus `spec=` and `talents=`, and refuses it
with `CHARACTER_EXPORT_NOT_WEIGHTS`. Getting weights from it means running simc outside the game
with `calculate_scale_factors=1` on a Forever-capable build, then importing simc's Pawn string.
That string is an ordinary Pawn v1 string; it imports today as `imported-pawn`, and GG-502 labels
it `sim-result`. Orchestrating the run is future work for AltStable Companion (ASC-001).

## Upgrade percentage (summary)

The full definition is [adr/0003](adr/0003-upgrade-metric.md):

```
pct = (candidateScore − baselineScore) / baselineScore
```

This is computed over the slots the best legal configuration affects. The denominator is the score
of the item(s) the candidate replaces for that character and spec, as in Pawn.
It is not the character's total.

- `delta` is always returned with it.
- It counts as an upgrade from 0.5% by default (as Pawn).
- An empty slot has no percentage and reason `EMPTY_SLOT`.
- The result is labelled an **item-score estimate**, never a DPS or healing percentage.
- Results from different characters are never ranked against each other by percentage.
