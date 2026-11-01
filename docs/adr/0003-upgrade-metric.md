# ADR-0003: Upgrade metric, configurations and baselines

- Status: accepted (2026-11-01)

## Score

`score(item, profile) = Σ weight[token] × stat[token]`, over **supported tokens** only.

- Stats come from `C_Item.GetItemStats(link)`. Its keys are locale-independent `ITEM_MOD_*` names,
  mapped to Pawn tokens in `Data/Stats.lua` ([FORMATS.md](../FORMATS.md)).
  - If it returns nothing (a cache miss), the result is `pending`, not zero.
- A stat with no supported token is listed in `limitations` as `UNSUPPORTED_STAT:<key>`. It is never
  silently zero.
- **Enchants** are handled symmetrically: the enchant is stripped from both the candidate and the
  baseline item, and the random suffix and the other item-string fields are kept. Pawn does the same
  (`Pawn.lua:3024-3045, 3598, 3687`).
  - Enchants that would carry over are a future option, off by default.
- **Effects:**
  - An item with an equip, use or proc spell (`C_Item.GetItemSpell`) gets `EFFECT_NOT_SCORED`.
  - An item that belongs to a set gets `SET_BONUS_NOT_SCORED`.
  - "Zero supported stats" is not the same as "a modelled zero": an item whose supported score is 0 is
    flagged `NO_SUPPORTED_STATS`.

## Upgrade percentage (the exact definition)

```
pct = (candidateScore − baselineScore) / baselineScore
```

- `baselineScore` is the score of the item or items the candidate **displaces** in the chosen
  configuration (below). This is the Pawn definition (`Pawn.lua:3770`): it is relative to the
  replaced items, **not** to the character's total.
- `delta = candidateScore − baselineScore` is always returned alongside `pct`.
- If `baselineScore ≤ 0`, then `pct = nil`, and the delta and the reason `BASELINE_NONPOSITIVE` are
  shown instead.
- If the displaced position is a confirmed, legal **empty** slot, the status is `upgrade`,
  `pct = nil`, and the reason is `EMPTY_SLOT`.
- Unknown occupancy is `unknown`, never `EMPTY_SLOT`.
- An item is an upgrade when `pct ≥ threshold` (default 0.005, as Pawn `Pawn.lua:3760`), or when it is
  `EMPTY_SLOT`.
- The label everywhere is **"item-score estimate"**. Results are never ranked across characters by
  `pct`.

## Configurations (rings, trinkets, weapons, unique)

The comparison **enumerates the legal resulting configurations** instead of picking a slot by rule:

1. The candidate goes into each compatible slot (`INVTYPE_*` → slots, in `Data/Slots.lua`). Rings and
   trinkets have two slots each.
2. **Weapons.**
   - A 1H, MH or OH candidate with a 2H equipped is only legal with an identified companion: an
     off-hand or main-hand from the baseline, or from bags once bags are a source (GG-108). Without
     one, the result is `unknown` with `NEEDS_COMPANION`.
   - A 2H candidate displaces MH and OH together, and is compared against their **sum**.
   - Shields and held-in-off-hand items count as off-hands.
3. **Unique.** The displaced items are removed, then the unique limits are re-checked on the
   **resulting** set. Limits come from `C_Item.GetItemUniqueness`, as a limit category and a maximum.
   - A candidate that is legal only when it displaces the stronger ring is compared against that
     ring.
   - Duplicates of an already-equipped unique item are `ineligible` with `UNIQUE_EQUIPPED` unless they
     displace the equipped copy.
4. The **best legal configuration** wins. It is returned as `replaces = {slots, items}`.
5. **Proficiency.**
   - Armor and weapon classes come from `Data/Classes.lua`, **gated by level and known skill**. A
     Forever Warrior or Paladin gets plate at 40, a Hunter or Shaman mail at 40. At runtime this is
     read from the character's skills, and the table is only the fallback.
   - A failure is `ineligible` with `PROFICIENCY`.
   - An armor type the character can wear only after a later level is treated like a level
     requirement (rule 6).
   - **Class gate (hard, never a setting):** an item the class can't wear or wield (yet) is never
     presented as an upgrade, for any spec. When every own spec fails on proficiency, the tooltip
     shows a single grey line ("Paladin can't use Wands"), or nothing, depending on a display setting.
   - **Spec armor rule (per spec, editable per profile):** each spec has its own set of allowed
     armor types. The defaults are in `Data/Classes.lua`:

     | Spec | Allowed |
     |---|---|
     | Protection or Retribution Paladin, any Warrior spec | plate, plus mail before plate is learned |
     | Holy Paladin | cloth to plate |
     | Feral Druid (tank and cat) | leather |
     | Balance or Restoration Druid | cloth and leather |
     | Enhancement Shaman | leather and mail |
     | Elemental or Restoration Shaman | cloth, leather and mail |
     | Hunter | leather and mail |
     | Rogue | leather |
     | Priest, Mage, Warlock | cloth |

     An armor type outside the spec's set is `ineligible` with `NOT_SPEC_ARMOR` for **that spec
     only**. A Holy Paladin may still see a cloth upgrade while the same item is ineligible for
     Protection. Each profile can change its set, and the "preferred armor type only" setting turns
     the rule off globally. Shields, off-hands and weapons follow class proficiency only.
   - Pawn-style `IsCloth`, `IsPlate`… weights in a profile are honoured as ordinary tokens (a Pawn `X`
     on `IsCloth` is equivalent to excluding cloth).
6. **Level window** (setting "level-appropriate only", default on, look-ahead `L` = 0..10, default 0).
   For a recipient at level `c`, an item requiring level `r`:
   - `r ≤ c`: evaluated normally.
   - `c < r ≤ c + L`: scored, `eligibility.equipNow = false`, `LATER_LEVEL` and `levelsAway = r − c`.
     It is shown as "at level r (in r − c levels)". There is no marker by default.
   - `r > c + L`: `ineligible`, with `ABOVE_LEVEL_WINDOW`, and is not presented as an upgrade. With
     the setting off, it is scored as `LATER_LEVEL`.
   - Protection counts `LATER_LEVEL` upgrades inside the window as `protect`: keep it for later.
7. **Set bonuses.** The set id comes from `C_Item.GetItemInfo` (`setID`). The thresholds and bonus
   spells come from the client's `ItemSet` / `ItemSetSpell` tables, through `wago-tools`, as a
   generated `Data/ItemSets.lua` (GG-119). For the configuration that results from the candidate:
   - **completes** a threshold the baseline lacks: `SET_BONUS_GAINED`, with the piece count;
   - **breaks** a threshold the baseline had: `SET_BONUS_LOST`, with the piece count.

   The bonus's value is not scored, and the warning always shows. For protection, `SET_BONUS_LOST`
   and `SET_BONUS_GAINED` count like `SET_BONUS_NOT_SCORED`: the result is never `clear` on its own.
   Until the data lands, a set item only gets `SET_BONUS_NOT_SCORED`.

## Baselines

Baselines are kept per character × spec, with sources in this precedence:

1. the **equipment set** the owner mapped to the spec (`C_EquipmentSet`);
2. the **gear observed while that spec was active** (captured by Glass Gear, with links, so the suffix
   is kept);
3. the **current equipment** scored with that spec's profile, labelled `fallback-current`.

Each slot records:

- its occupancy: `occupied`, `empty` or `unknown`;
- its `itemString`;
- `capturedAt`;
- its source.

**Staleness.** A baseline is `stale` when:

- `capturedAt` is more than 14 days ago; or
- the character's gear changed after capture. The signal is the AltStable gear-change stamp (AS-003),
  or Glass Gear's own `PLAYER_EQUIPMENT_CHANGED`, and **not** AltStable's `lastUpdate`, which plugin
  touches move (`AltStable/PublicAPI.lua:125`).

A remote baseline whose manifest differs is `maybeBehind` ([adr/0001](0001-sync-ownership.md)).

**Display versus protection.** Incomplete, stale, `fallback-current` or `maybeBehind` baselines may
drive **labelled display estimates**. They can **never** make protection return `clear`. The same
holds for `EFFECT_NOT_SCORED`, `SET_BONUS_NOT_SCORED` and `NO_SUPPORTED_STATS`: that recipient's
protection result is `unknown` (keep) unless the supported score alone is already an upgrade, which
gives `protect`.

## Owned items (later)

"Better gear already owned or already allocated" (an item in bags that beats the candidate) is a
GG-108 extension, using bags as a baseline source. M0 compares only against baselines.
