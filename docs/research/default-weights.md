# Default weights (GG-106)

- Status: recommendation, waiting for the owner's numbers (2026-11-01)
- Issue: [#7](https://github.com/Spotnick2/GlassGear/issues/7)
- Not legal advice. Every licence reading here is the conservative one.

## Summary

1. **Glass Gear does not ship Pawn's built-in numbers.** The conservative reading of Pawn's
   CC BY-NC-ND 3.0 licence rules it out, and the numbers come from a third party with unknown terms.
2. **Ship our own simple defaults instead.** A hand-written table, one row per spec: the primary
   stat, a few obvious secondaries, our own round numbers. The owner asked for exactly this ("a
   simple default stat weight, and use common sense until we have a working wowsim"). The proposed
   table is [below](#proposed-defaults); the owner tunes the numbers before it becomes code.
3. **Defaults are a rough starting point.** As the owner put it, weights "always [depend] on gear",
   so a default "is never going to be awesome". WoWSims-generated weights are the intended
   replacement (GG-502, ASC-001).
4. **Pawn's numbers stay available to the user**, without Glass Gear distributing them: Pawn's own
   Export button works on its built-in scales, and the string imports today with `/gg import`.
5. **Defaults are labelled "default weights", never let protection return `clear`, and any
   imported profile replaces them.**

## The owner's question: can we use Pawn's defaults?

The owner's suggestion was "use the default pawn stat weight until we can replace them with
wowsims". Here is what the licence allows.

### Where Pawn's Forever scales live

| Fact | Source |
|---|---|
| The whole addon is CC BY-NC-ND 3.0 | `References/Addons/BagsInventory/Pawn/Pawn/Readme.md:104`; the header of every Lua file, e.g. `ClassicHawsJon.lua:3` |
| On Forever (`camelot`) Pawn loads `ClassicHawsJon.lua`, not the Ask Mr. Robot file | `Pawn.toc:52-53` |
| Those scales are "sourced from HawsJon" (`http://tbcwowaddons.weebly.com/pawn.html`), a third party | `ClassicHawsJon.lua:6-7` |
| They were "originally designed for Burning Crusade". On Forever every rating multiplier is 1, so they are applied as TBC values | `ClassicHawsJon.lua:21-57` |
| 127 scale-template calls, one per class tree, each a full stat table | `ClassicHawsJon.lua:59…` |
| Caster scales weight `SpellHitRating` / `SpellCritRating`. Pawn's own stat list hides those stats on Forever | `ClassicHawsJon.lua:64`; `UIStrings.lua:44,46` (no `PawnStatForever`) |

The last two rows matter apart from licensing: Pawn's numbers are not tuned for Forever either.

### Can we ship them? No (conservative reading)

- **ND (no derivatives).** CC BY-NC-ND 3.0 lets you reproduce and share the work unchanged, but
  "otherwise you have no rights to make Adaptations" ([legal code](https://creativecommons.org/licenses/by-nc-nd/3.0/legalcode)).
  Shipping the tables means renaming tokens, dropping stats Forever lacks and converting them
  into our data format. That is an adaptation.
- **NC (non-commercial).** Glass Gear is meant for CurseForge and Wago (GG-404), whose author
  reward programmes are arguably commercial advantage.
- **Licence mix.** Glass Gear is MIT (`LICENSE:1`). We can't relicense Pawn material as MIT, and
  shipping an ND/NC file inside an MIT addon makes its terms unclear.
- **Unknown upstream.** The numbers are HawsJon's. Pawn redistributes them, but HawsJon's own
  terms are unknown: the page is not in any local copy, and a web search didn't find it.
- **Bare numbers are an uncertainty, not a way out.** Single numbers may well be uncopyrightable
  facts (in the US, *Feist v. Rural*, 1991), but a selected and arranged table can still be
  protected, and the EU has a separate database right (Directive 96/9/EC). We don't rely on that
  argument.
- **The standing house rule** (`AGENTS.md:37`, `ECOSYSTEM-FINDINGS.md:23`): implement Pawn's
  format and behaviour, never copy its code. Its scale tables are part of that code.

**Answer: no.** Glass Gear never contains Pawn's numbers, in code, data, tests or docs.

### Paths that get the same numbers without shipping them

| Path | What happens | Is it copying by us? | Verdict |
|---|---|---|---|
| **Paste (works today)** | In Pawn: Scale tab → pick the built-in "Classic" scale → **Export** (enabled for read-only scales, `PawnUI.lua:405-406`) → copy → `/gg import <SPEC.KEY> <string>` | No. The user copies from their own installed Pawn for personal use. Glass Gear distributes nothing. | **Document it** (FORMATS.md, the import dialog in GG-105). |
| **"Import from Pawn" at runtime** | While Pawn is loaded, Glass Gear calls Pawn's global `PawnGetScaleTag(name)` (`Pawn.lua:5307`, which Pawn's own Export uses), on a user's click only, and feeds the string to the existing importer | Not distribution: nothing ships, and the values go from the user's Pawn into the user's own SavedVariables, unchanged. The same as the paste path, one click shorter. | **Optional** (GG-121, P3). Explicit action only, never automatic, `pcall`-wrapped, Pawn only as an optional dependency. |
| **Reading Pawn's SavedVariables** | Read `PawnCommon.Scales` | — | **Doesn't work.** Pawn deletes built-in scale values before saving (`Pawn.lua:5661-5668`, `PawnUnitializePlugins`). Only the user's own custom scales are saved. |

Export details that matter for import:

- A built-in scale has a class and a "spec", so its tag carries `Class=` and `Spec=`
  (`Pawn.lua:5326-5331`). Glass Gear ignores `Spec=` on Forever (FORMATS.md:47).
- The tag leaves out entries equal to Pawn's template (`Pawn.lua:5332-5339`). With `NoStats` that
  template holds only the "never usable" `X` markers (`ScaleTemplates.lua:31-32,187-193`), so no
  numeric weight is lost. Glass Gear's class gate covers those markers anyway (`Data/Classes.lua`).
- Tokens outside our list (`SpellHitRating`, `SpellCritRating`, `Mana`, `Health`, `AllResist`,
  `ResilienceRating`, `ArmorPenetration`, `MetaSocketEffect`…) come in as `UNSUPPORTED_TOKEN`
  warnings and are kept in `ignoredTokens` (FORMATS.md). A pasted caster scale therefore loses its
  spell-hit weight. Whether Forever items carry spell hit separately at all is probe GG-103.

A Pawn scale imported either way is an **import** (`source = "imported-pawn"`, `origin` = the scale
name and "Pawn built-in" when it was read-only). The user chose it, so it counts as their weights,
not as a default.

## Other candidates

| Source | Covers | Licence and source | Ship derived numbers? |
|---|---|---|---|
| Pawn 2.14.0 built-in ("Classic", HawsJon) | Every class tree; TBC-designed, ratings ×1 on Forever | CC BY-NC-ND 3.0 (above); HawsJon's terms unknown | **No.** Paste or runtime import only |
| WoWSims `tbc-new` (`C:\Projects\WoW\wowsims\tbc-new`, `8aa378b36`) | TBC, level 70 (`ui/core/constants/mechanics.ts:1`); "Pawn EP" export | MIT (`LICENSE`, "Copyright (c) 2022 wowsims team") | The code is MIT. **Wrong game version**: level 70 weights would mislead at 60. |
| WoWSims `sod` ([github.com/wowsims/sod](https://github.com/wowsims/sod)) | Season of Discovery, level-60 era, same framework | MIT ([pkg.go.dev](https://pkg.go.dev/github.com/wowsims/sod@v0.0.89)); a fork asks for a visible link back | Sims the owner runs produce the owner's own output, so they're clean. SoD runes and mechanics differ from Forever, so those weights would need judgement. **The route to real defaults**, via GG-502 / ASC-001 once a Forever-capable sim exists. A local Classic or Forever WoWSims checkout doesn't exist (ECOSYSTEM-FINDINGS.md "Not present"). |
| SimulationCraft engine | Retail-first; the addon (12.1.5-03) exports Forever profiles with `spec=unknown` | GPL-3.0 ([github.com/simulationcraft/simc](https://github.com/simulationcraft/simc)). GPL covers the program, not the user's output | Scale factors the owner computes would be the owner's own. No local engine understands Forever profiles (ECOSYSTEM-FINDINGS.md). Not now. |
| Community guides (class Discords, guide sites, Wowhead Classic guides) | Varies; often level 60 Classic Era, often per phase | Usually all rights reserved site content. Not fetched (Wowhead only through the shared tool). | **No** without explicit permission. Users can paste such weights themselves as Pawn strings. |
| **Our own table** | What we write | Ours, MIT | **Yes.** The recommended stopgap. |

## Recommendation

**Ship a simple, hand-authored default per spec (`Data/Defaults.lua`), as the owner asked.** It is
licence-clean and good enough to rank obvious upgrades (a clear primary-stat jump) while saying so.

- It stays **few tokens per spec**: the primary stat at 1, the obvious secondaries, Stamina small.
  No attempt to model caps, talents or set bonuses.
- It is **honestly labelled**: "default weights" in every tooltip row it drives, and in `/gg`.
- It is **replaced, not merged**: any profile the user imports for that spec wins, and the default
  is never shown again for it.
- It is **never trusted by protection.**
- It **disappears when WoWSims weights exist**: GG-502 brings in sim results; at that point the
  table can be retuned from the owner's own sims, or retired.

Why this beats shipping nothing: without it, every spec reads "no weights" until the user imports,
and the first-run tooltip is empty. Why it isn't misleading: the result already says "item-score
estimate", and the "default weights" tag says what the estimate rests on.

## Proposed defaults

Our own round numbers, primary stat (or Healing / spell damage) = 1. **The owner tunes these
before they become code.**

Notes for every row:

- **† Unit pending GG-103.** Hit, crit, dodge, parry and block are written **per 1 % item stat**,
  as on Classic-era items ("+1% chance to hit"). If Forever's `GetItemStats` reports them as TBC
  rating points instead (Pawn's multiplier of 1 on Forever hints at that, `ClassicHawsJon.lua:43-57`),
  these numbers must be divided by the rating per 1 % before shipping.
- `MeleeDps` / `RangedDps` are weapon DPS (derived from `Dps`, `Data/Stats.lua:96`). Only specs
  that hit with their weapon get them.
- `Armor` stays small: within one slot and one armor type, base armor barely varies, and armor type
  is already handled by the spec armor rules (`Data/Classes.lua`).
- A token not listed is weight 0, which Glass Gear reports as missing, never as "worth nothing"
  (`WEIGHT_MISSING`, FORMATS.md:172).

| Spec key | Weights | Rationale |
|---|---|---|
| `WARRIOR.ARMS` | Strength 1, Agility 0.6, Ap 0.5, HitRating† 10, CritRating† 10, MeleeDps 3, Stamina 0.1 | Strength gives 2 AP; Agility gives crit; slow two-hander, so weapon DPS matters |
| `WARRIOR.FURY` | Strength 1, Agility 0.6, Ap 0.5, HitRating† 12, CritRating† 10, MeleeDps 3, Stamina 0.1 | As Arms; dual wield misses more, so hit a little higher |
| `WARRIOR.PROTECTION` | Stamina 1, DefenseRating 1, DodgeRating† 12, ParryRating† 12, BlockRating† 6, BlockValue 0.2, Armor 0.02, Strength 0.3, Agility 0.5, HitRating† 4 | Survival first; hit for threat |
| `PALADIN.HOLY` | Healing 1, Intellect 0.9, Mp5 1.5, CritRating† 8, Spirit 0.2, Stamina 0.1 | Intellect carries mana and spell crit; Spirit is weak for paladins |
| `PALADIN.PROTECTION` | Stamina 1, DefenseRating 1, BlockValue 0.3, BlockRating† 6, Armor 0.02, SpellDamage 0.4, HolySpellDamage 0.4, Strength 0.3, Agility 0.4, Intellect 0.3 | Survival; spell damage feeds Holy threat |
| `PALADIN.RETRIBUTION` | Strength 1, Agility 0.5, Ap 0.5, HitRating† 10, CritRating† 10, MeleeDps 3, Intellect 0.2, Stamina 0.1 | Two-hander melee; a little mana |
| `HUNTER.BEAST_MASTERY` | Agility 1, Rap 0.5, HitRating† 12, CritRating† 10, RangedDps 2.5, Intellect 0.2, Stamina 0.1 | Agility gives ranged AP and crit; ranged weapon DPS |
| `HUNTER.MARKSMANSHIP` | same as Beast Mastery | Same stats; tune separately if wanted |
| `HUNTER.SURVIVAL` | same as Beast Mastery | Same stats; tune separately if wanted |
| `ROGUE.ASSASSINATION` | Agility 1, Strength 0.5, Ap 0.5, HitRating† 15, CritRating† 10, MeleeDps 3, Stamina 0.1 | Agility gives AP and crit; dual wield needs hit |
| `ROGUE.COMBAT` | same as Assassination | |
| `ROGUE.SUBTLETY` | same as Assassination | |
| `PRIEST.DISCIPLINE` | Healing 1, Intellect 0.7, Spirit 0.5, Mp5 1.2, CritRating† 6, Stamina 0.1 | Mana pool and regeneration |
| `PRIEST.HOLY` | Healing 1, Intellect 0.6, Spirit 0.7, Mp5 1.2, CritRating† 6, Stamina 0.1 | Spirit matters more for Holy |
| `PRIEST.SHADOW` | SpellDamage 1, ShadowSpellDamage 1, HitRating† 10, Intellect 0.3, Spirit 0.2, Stamina 0.1 | No crit: on Classic-era rules shadow spells don't crit (check on Forever) |
| `SHAMAN.ELEMENTAL` | SpellDamage 1, NatureSpellDamage 1, FireSpellDamage 0.2, HitRating† 10, CritRating† 8, Intellect 0.4, Mp5 1, Stamina 0.1 | Lightning is nature |
| `SHAMAN.ENHANCEMENT` | Strength 1, Agility 0.6, Ap 0.5, HitRating† 10, CritRating† 10, MeleeDps 3, Intellect 0.2, Stamina 0.1 | Two-hander melee |
| `SHAMAN.RESTORATION` | Healing 1, Intellect 0.6, Mp5 1.5, Spirit 0.2, CritRating† 6, Stamina 0.1 | Mp5 over Spirit |
| `MAGE.ARCANE` | SpellDamage 1, ArcaneSpellDamage 1, HitRating† 12, CritRating† 8, Intellect 0.4, Spirit 0.1, Stamina 0.05 | Own school counts like generic spell damage |
| `MAGE.FIRE` | SpellDamage 1, FireSpellDamage 1, HitRating† 12, CritRating† 8, Intellect 0.4, Spirit 0.1, Stamina 0.05 | |
| `MAGE.FROST` | SpellDamage 1, FrostSpellDamage 1, HitRating† 12, CritRating† 8, Intellect 0.4, Spirit 0.1, Stamina 0.05 | |
| `WARLOCK.AFFLICTION` | SpellDamage 1, ShadowSpellDamage 1, HitRating† 12, CritRating† 2, Intellect 0.3, Stamina 0.2 | Damage over time barely crits; Stamina feeds Life Tap |
| `WARLOCK.DEMONOLOGY` | SpellDamage 1, ShadowSpellDamage 1, HitRating† 12, CritRating† 5, Intellect 0.3, Stamina 0.3 | Stamina a little higher (Demonic Embrace) |
| `WARLOCK.DESTRUCTION` | SpellDamage 1, ShadowSpellDamage 1, FireSpellDamage 0.3, HitRating† 12, CritRating† 8, Intellect 0.3, Stamina 0.2 | Shadow Bolt first |
| `DRUID.BALANCE` | SpellDamage 1, ArcaneSpellDamage 0.5, NatureSpellDamage 0.5, HitRating† 10, CritRating† 8, Intellect 0.4, Spirit 0.2, Stamina 0.1 | Starfire is arcane, Wrath is nature |
| `DRUID.FERAL_TANK` | Stamina 1, Armor 0.05, Agility 0.7, DodgeRating† 12, DefenseRating 1, Strength 0.4, FeralAp 0.2, Ap 0.2, HitRating† 4 | Bear form multiplies armor, so it counts more than for plate tanks |
| `DRUID.FERAL_CAT` | Strength 1, Agility 1, Ap 0.5, FeralAp 0.5, HitRating† 12, CritRating† 10, Stamina 0.1 | No weapon DPS: forms ignore it |
| `DRUID.RESTORATION` | Healing 1, Intellect 0.6, Spirit 0.6, Mp5 1.2, Stamina 0.1 | Mostly heals over time, so crit is left out |

Every token above is in Glass Gear's list (`Data/Stats.lua:18-33`).

## Consequences for the code (follow-up GG-120)

**Defaults are not entries.** `Data/Defaults.lua` is read-only data:

- **Lookup.** `Profiles.Active(store, guid, specKey)` returns the live imported profile when there
  is one, and the default for that spec key only when there isn't (and defaults are on). So an
  import always replaces the default, with no migration, no deletion and no field merge.
- **No sync, no store.** Defaults are never written to `GlassGearDB.entries`, so they never sync
  (adr/0001) and every installation sees the same table for its version of the addon.
- **Profile shape.**

  | Field | Value |
  |---|---|
  | `id` | `default:<specKey>` |
  | `version` | `defaults-<N>`, where N is the table's revision |
  | `source` | `default` |
  | `origin` | `"Glass Gear default weights"` |
  | `weights`, `missing`, `ignoredTokens` | `weights` from the table; the other two empty |

- **Setting.** `settings.defaults.enabled`, on by default. Off brings back "no weights" rows.

**Labels**

| Where | Text |
|---|---|
| Tooltip row driven by a default (GG-107 view-model) | the normal row, plus a grey tag **"default weights"** |
| Tooltip footer, when any row uses one | "item-score estimate · default weights: import your own for better advice" |
| `/gg` diagnostics and the profiles UI (GG-105) | `PRIEST.SHADOW: Glass Gear default weights [default]`, with "Import" next to it |
| Detailed comparison (GG-113) | "Source: default weights (not tuned to your gear)" |

Bag and loot markers (GG-109, GG-111) use defaults like any other profile. Without that, the
defaults would add nothing in bags. Every marker's tooltip shows the tag.

**Protection never trusts a default**

- Evaluate adds the limitation `DEFAULT_WEIGHTS` to every result scored with a default profile.
- Policy adds `DEFAULT_WEIGHTS` to its unsafe limitations (`Engine/Policy.lua:135-137`):
  - a default-based `no_upgrade` gives `unknown` (keep), never `clear`;
  - a default-based `upgrade` still gives `protect` (keeping is the safe direction).
- Shatter shows its usual fail-closed reason, "Glass Gear can't confirm yet", plus "default
  weights" in the detail.
- Consequence: until the user imports weights for a spec, Shatter keeps every item that spec can
  use. That is fail-closed by design (adr/0003).

**adr/0005.** `default` changes from "none in MVP" to "Glass Gear's own table (`Data/Defaults.lua`)".
A Pawn built-in scale the user imports is `imported-pawn`, not `default`.

## Follow-up backlog items (proposed, not filed yet)

| ID | P | Class | Outcome |
|---|---|---|---|
| GG-120 | P1 | MVP | Default weights: `Data/Defaults.lua` from the table above (owner-tuned), fallback in `Profiles.Active`, provenance `default`, the "default weights" label, the `DEFAULT_WEIGHTS` unsafe limitation, the setting, tests. The † units are rescaled after GG-103. |
| GG-121 | P3 | MVP | Optional "Import from Pawn": list Pawn's scales (`PawnGetAllScalesEx`) and import one through `PawnGetScaleTag` on a click, `pcall`-wrapped, Pawn as an optional dependency; `origin` notes "Pawn built-in" for read-only scales. |
| (FORMATS) | P2 | docs | Document the paste path from Pawn's Scale tab → Export, with the caster spell-hit caveat. |

The replacement for the defaults is already in the backlog: GG-502 (import sim results) and
ASC-001 (Companion sim orchestration).

## Open questions for the owner

1. **The numbers.** Tune the table, or say "ship as is"; it's meant to be edited.
2. **Protection with defaults.** The recommendation is strict: a default-weighted spec is
   `unknown`, so Shatter keeps everything it can use until weights are imported. The softer
   option treats it like a spec without weights (listed as unchecked, decided by
   `protection.noWeights`, whose default is "ignore"): then other specs with real weights decide.
   Strict or soft?
3. **Markers from defaults.** Should default-weighted upgrades draw the normal green and amber
   markers (recommended), or a dimmer variant?
4. **GG-121.** Is "Import from Pawn" worth building, given the paste path already works?
