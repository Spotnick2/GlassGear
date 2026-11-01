# Forever probes: queued in-game checks

The game is offline until **2026-11-04**. Nothing on this page has been measured yet. Each check
says what it needs to find out, and records the result here with the build once it is run.

- **How:** one ForeverProbe module, `Tools/GlassGearProbe` (`/fp gg`), with one `Probe:Steps`
  procedure per check. This follows `References/Docs/PROBES.md` and
  `ForeverProbe/docs/GUIDE.md` §3 (steps) and §4 (facts). Deploy with
  `pwsh Tools/deploy.ps1 -Probe`.
- **Reading results:** after the owner's `/reload`, read `GlassGearProbe.lua` and
  `ForeverProbe.lua` (`steps.records`) from SavedVariables. Never ask for a paste.
- **Screenshots:** take them freely for anything visual, then remove them with
  `ForeverProbe/Tools/screenshots.ps1 -Remove`.
- **Before measuring:** check `PORTING-TBC-TO-FOREVER.md`, the 70532 dump and `/fp facts`.
  Per-client measurements are facts (`ForeverProbe:DefineFact`). Anything that depends on the
  character or its gear is a log line.
- **What isn't here yet:** the probe module itself. It is written with the first M1 spike (GG-101).

| # | Check | Backlog | Procedure | Status |
|---|---|---|---|---|
| P1 | Load and `/gg diag` | GG-001, GG-004 | `/fp steps gg load` | queued |
| P2 | Spec group and talent-tree points | GG-101 | `gg spec` | queued |
| P3 | Loot window and group roll frames | GG-102 | `gg loot` | queued |
| P4 | `GetItemStats` on suffix/enchanted links; item-data timing | GG-103 | `gg stats` | queued |
| P5 | Transfer rules | GG-116 | `gg transfer` | queued |
| P6 | Tooltip post-call on bag, loot and link tooltips | GG-107, GG-111 | `gg tips` | queued |
| P7 | Modifier state and keyboard focus | GG-110 | `gg reveal` | queued |
| P8 | `C_Item.IsBound` / `GetItemGUID` on bag `ItemLocation`s | GG-109, GG-301, SH-002 | `gg bind` | queued |
| P9 | Armor proficiency known at runtime | GG-118 | `gg armor` | queued |
| P10 | `setID` from `C_Item.GetItemInfo`; item-set data source | GG-119 | `gg sets` | queued |
| P11 | Required level and level window inputs | GG-117 | part of `gg armor` | queued |

---

## P1: The addon loads cleanly and `/gg diag` reports

- **Question.** Does Glass Gear load on 70532 without Lua errors? Does `/gg diag` show the build,
  `API_VERSION`, the current spec mapping, the dependencies detected (AltStable, GlassUI, LibGlass
  MINOR) and the capabilities reported as unavailable?
- **Why.** M0 claims a loadable scaffold. Only the client proves it.
- **Steps**
  1. `/console scriptErrors 1`, then `/reload` (a brand-new folder needs one full client restart first).
  2. `run`: call the diag function and log its lines.
  3. `ask`: "Any Lua error on load?"
  4. `screenshot` of `/gg diag`.
  5. Repeat with AltStable disabled and with GlassUI disabled: the capabilities must show as
     unavailable, with no errors.

## P2: Spec group and talent-tree points (GG-101)

- **Question.** Can the current spec be inferred? The candidate path, verified only in Blizzard's
  UI source, is `C_SpecializationInfo.GetActiveSpecGroup()` →
  `GetCombatConfigIDForSpecGroup(group)` → `C_Traits.GetGroupCurrencyInfo(configID, groupIDs)` →
  points spent per tree (`Blizzard_ClassTalentsFrame.lua:112`, `:124`, `:132`). Questions:
  - Are the tree group IDs stable per class?
  - Does `ACTIVE_TALENT_GROUP_CHANGED` or `TRAIT_CONFIG_UPDATED` fire on respec?
  - Is a talent preview distinguishable from committed talents?
  - What do `GetNumSpecGroups()` and `GetActiveSpecGroup()` return after buying dual spec? Today
    they are `1` and `1`: `AltStableSync/docs/forever-api-notes.md:46`.
- **Why.** Automatic current-spec detection. Until this is measured, manual mapping is the only
  source ([adr/0002](adr/0002-spec-model.md)).
- **Steps**
  1. `auto run`: log the group, config ID, tree group IDs and spent points.
  2. Ask the owner to spend one point in a different tree without committing, then log again:
     does preview change the result?
  3. Commit, using the `event = "TRAIT_CONFIG_UPDATED"` step, then log.
  4. If dual spec is available: swap specs (`event = "ACTIVE_TALENT_GROUP_CHANGED"`), then log.
  5. Try a tie and an unspent character: the result must be "unknown".
- **Fact candidates.** Tree group IDs per class (inputs: class).

## P3: Loot window and group roll frames (GG-102)

- **Question.**
  - Which frames show boss loot on Forever: `LootFrame` buttons, or a ScrollBox of elements?
  - Which frames show group rolls?
  - How does a probe get each slot's link and its button?
  - Do frames get created in combat?
- **Why.** Loot-surface markers (GG-111) and the reveal surface list (P7).
- **Steps**
  1. Loot a mob (`event = "LOOT_OPENED"`), then `run`: walk `LootFrame` children and log their
     names, types and `GetLootSlotLink(i)`.
  2. `screenshot`.
  3. In a group, at a roll: `event = "START_LOOT_ROLL"`, then log the roll frame names and
     `GetLootRollItemLink`.
  4. `screenshot`.
- **Check first.** Use the wow-ui-source `forever` branch to find the loot templates before writing
  the probe.

## P4: `GetItemStats` on real links, and item-data timing (GG-103)

- **Question.**
  - Which keys does `C_Item.GetItemStats` return for spell damage, healing, mana per 5, school
    damage and weapon speed? [FORMATS.md](FORMATS.md) lists them as "expected".
  - Is a school-specific bonus ("+20 Shadow Spell Damage") returned at all? If not, what in
    `C_TooltipInfo` carries it? An omitted bonus is scored as missing with no warning (GG-103).
  - Does a random-suffix link return the suffix stats?
  - Does an enchanted link include the enchant? SimC's Forever code says it doesn't:
    `forever/stats.lua:70`.
  - How long after `C_Item.RequestLoadItemDataByID` does `ITEM_DATA_LOAD_RESULT` or
    `GET_ITEM_INFO_RECEIVED` fire for an uncached item?
  - Does `GetItemStats` then return data? It returns nothing on a miss:
    `AltStable/docs/forever-api-notes.md:1070`.
- **Why.** The score inputs and the pending state. A wrong key silently zeroes a stat.
- **Steps**
  1. `run` over the owner's equipped and bag items: log every key `GetItemStats` returns, per link.
  2. Repeat with a known suffix item, an enchanted item, a wand, a caster item with spell damage,
     and a healing item.
  3. `run`: request an uncached item ID (from a list the probe carries), then use a `wait` step on
     the load event with a 10 s timeout; log the delay.
- **Fact candidates.** The key per Pawn token (inputs: none). The suffix behaviour.

## P5: Transfer rules (GG-116)

- **Question.**
  - Can an unbound BoE be mailed to a same-realm character of the **other faction**?
  - Can it be mailed to another realm?
  - Do connected realms exist?
  - Which bind types occur: `C_Item.GetItemInfo` `bindType`, `Enum.ItemBind`?
  - Does any account-bound item exist? If so, does it move between the owner's two WoW accounts
    on the same Battle.net account?
  - What do `C_Item.IsItemBindToAccount` and `IsItemBindToAccountUntilEquip` return for ordinary BoE items?
- **Why.** Transfer eligibility is tri-state and stays `unknown` until measured
  ([PRD.md](PRD.md); [ECOSYSTEM-FINDINGS.md](ECOSYSTEM-FINDINGS.md) "Item transfer"). Synced data is
  not proof that an item can be transferred.
- **Steps.** Everything is owner actions with `ask` steps and screenshots. The probe never sends
  mail itself.
  1. Address a mail to an other-faction alt and attach a cheap BoE: was it refused? Take a screenshot.
  2. Address one to an alt on another realm.
  3. `run`: log the bind values for a sample of bag items.

## P6: Tooltip post-call coverage (GG-107, GG-111)

- **Question.** Does `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, …)` fire
  for bag items, loot slots, roll frames, chat links (`ItemRefTooltip`), the character sheet and
  comparison tooltips?
  - Is the owner a bag button with `GetBagID` and `GetID` (the `GlassPearls/Pearls/JunkSpot.lua:72-78`
    model)?
  - Does `RefreshData` rebuild an open tooltip when a modifier changes (the `Shatter/Tooltip.lua:127-138`
    model)?
- **Why.** Where the spec rows appear, and whether rows can identify the bag instance.
- **Steps.** `run` installs a logging post-call. For each surface, the owner hovers it
  (`ask`: "rows shown?") and a screenshot is taken.

## P7: Modifier state and keyboard focus (GG-110)

- **Question.**
  - Does `MODIFIER_STATE_CHANGED` fire for left and right Ctrl, and for Alt, with bags open, in
    combat, and while an edit box (chat) has focus?
  - Does `GetCurrentKeyBoardFocus()` return the chat edit box while typing?
  - Does Ctrl-click on a bag item still open the dressing room with Glass Gear loaded?
- **Why.** The reveal state machine is computed from the modifier state and the focus state.
- **Steps**
  1. `run` starts a logger for the event and a 0.1 s focus sampler, active while bags are open.
  2. The owner presses and releases Ctrl, then the right Ctrl.
  3. The owner opens chat, holds Ctrl, closes chat, releases Ctrl. The state must clear.
  4. The same in combat, at a training dummy.
  5. `ask`: "Ctrl-click opened the dressing room?"

## P8: Bind state and GUID on bag `ItemLocation`s (GG-109, GG-301, SH-002)

- **Question.**
  - Does `C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(b, s))` match the tooltip's
    "Soulbound" line, before and after equipping a BoE? `ItemLocation` is a Lua object:
    `Blizzard_ObjectAPI/Mainline/ItemLocation.lua:9`, dump line 31333.
  - Does `C_Item.GetItemGUID` stay the same across a drag to another slot, a bag sort and a `/reload`?
    ShatterProbe's `guid` procedure measures the same thing; reuse its result if it has run.
- **Why.** BoE → soulbound re-evaluation, and the override's `{guid, token}`.
- **Steps**
  1. `run` logs `IsBound` and the GUID for a chosen slot.
  2. The owner equips and unequips the BoE, then logs again.
  3. The owner drags the item, then logs.
  4. `reload`, then log.

## P9: Armor proficiency known at runtime (GG-118)

- **Question.**
  - Which call reports that the character can wear Mail, Plate or Shield?
  - Are proficiency spells learned at level 40 (from a trainer) visible to the call before and
    after training?
  - Does `SKILL_LINES_CHANGED` or `SPELLS_CHANGED` fire on training?
- **Candidates**, all present in the 70532 dump. None is measured.
  - `C_SpellBook.IsSpellKnown(spellID)` (line 3634) or `IsPlayerSpell` (20014) with the
    proficiency spells from `forever-skilllineability`:

    | Armor | Spell | Skill line |
    |---|---|---|
    | Plate Mail | 750 | 293 |
    | Mail | 8737 | 413 |
    | Leather | 9077 | 414 |
    | Cloth | 9078 | 415 |
    | Shield | 9116 | 433 |

  - `C_SkillInfo.GetSkillLineInfoByID(413)` (3417), or walking `C_SkillInfo.GetNumSkillLines`
    (3414) and `GetSkillLineInfo` (3416).
  - `C_SpellBook.GetSkillLineIndexByID` (3600).
- **Why.** The hard class gate by class, level and **known** skill (per-spec armor rules apply on top). A
  level-39 warrior must not see plate as an upgrade. A level-40 warrior who hasn't trained it is
  `LATER_LEVEL`-like ("needs training").
- **Steps**
  1. `run` on a pre-40 hunter or warrior: log every candidate for spells 750, 8737 and 9116, and
     skill lines 293, 413 and 433.
  2. Repeat on a character that trained the skill.
  3. If possible, train during the probe (`event = "SKILL_LINES_CHANGED"`), then log again.
- **Fact candidates.** None: this is per character, so the results are log lines.

## P10: Item sets (GG-119)

- **Question.**
  - Does `C_Item.GetItemInfo` return `setID` (16th return, dump line 2243) for set pieces on Forever?
  - Does `C_Item.GetItemSetInfo(setID)` (2262) return the name?
  - Does `C_LootJournal.GetItemSetItems(setID)` (2497) work on Forever?
  - Do these agree with the `ItemSet` column in `forever-itemsparse` (column 78)?
- **Table status.** `ItemSet` and `ItemSetSpell` are **not** in `References/Forever/db`. GG-119
  fetches them with the `wago-tools` skill to generate `Data/ItemSets.lua` (pieces, bonus
  thresholds, bonus spells). Not fetched yet.
- **Why.** Set-bonus awareness: an item that completes or breaks a bonus threshold is flagged with
  its limitation instead of being scored as if the bonus didn't exist.
- **Steps.** `run` over the owner's equipped and bag set pieces: log `setID`, the set name and
  `GetItemSetItems`. Cross-check against `forever-itemsparse` offline.

## P11: Level window inputs (GG-117)

- **Question.**
  - Does `C_Item.GetItemInfo`'s `itemMinLevel` (5th return) match the tooltip's "Requires Level"
    for gear?
  - What does `RequiredLevel` in `forever-itemsparse` (column 101) say for the same items?
  - Do suffix items differ?
- **Why.** The "level-appropriate only, look ahead N levels" window needs a reliable required
  level for links that come from loot and other characters.
- **Steps.** Logged as part of `gg armor`, for the same item sample.
