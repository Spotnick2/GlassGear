# Forever probes: queued in-game checks

The game is offline until **2026-11-04**. Glass Gear itself has measured nothing yet, but other
addons' probes already answer part of these checks on earlier builds:
[see the sweep](#already-measured-by-other-addons-sweep-of-2026-11-02). Each check says what it
needs to find out, and records the result here with the build once it is run.

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
| P1 | Load and `/gg diag` | GG-001, GG-004 | `/fp steps gg load` | narrowed |
| P2 | Spec group and talent-tree points | GG-101 | `gg spec` | narrowed |
| P3 | Loot window and group roll frames | GG-102 | `gg loot` | narrowed |
| P4 | `GetItemStats` on suffix/enchanted links; item-data timing | GG-103 | `gg stats` | narrowed |
| P5 | Transfer rules | GG-116 | `gg transfer` | narrowed |
| P6 | Tooltip post-call on bag, loot and link tooltips | GG-107, GG-111 | `gg tips` | narrowed |
| P7 | Modifier state and keyboard focus | GG-110 | `gg reveal` | narrowed |
| P8 | `C_Item.IsBound` / `GetItemGUID` on bag `ItemLocation`s | GG-109, GG-301, SH-002 | `gg bind` | narrowed |
| P9 | Armor proficiency known at runtime | GG-118 | `gg armor` | narrowed |
| P10 | `setID` from `C_Item.GetItemInfo`; item-set data source | GG-119 | `gg sets` | queued |
| P11 | Required level and level window inputs | GG-117 | part of `gg armor` | narrowed |
| P12 | Bag and loot marker hooks and look | GG-109, GG-110, GG-111 | `gg marks` | narrowed |
| P13 | Settings page | GG-112 | `gg options` | narrowed |

Status "narrowed": part of the check is already measured elsewhere (sweep below); what remains is
a re-confirm on 70532 plus the open questions.

## Already measured by other addons (sweep of 2026-11-02)

Other repos' probes, the porting guide and the beta probe logs
(`_classic_beta_\WTF\Account\50284074#1|#12\SavedVariables\*Probe.lua`, called SV1 / SV12
below) already answer part of the checks. A fact holds for the build it names: **none of them is
on 70532**, so each check keeps a short re-confirm on the launch build, without the full procedure.
ForeverProbe's cached `facts` table holds nothing on these topics. Shatter and GlassPearls measured
none of them (their rows read "not measured").

| Check | Already measured | Build | Source |
|---|---|---|---|
| P1 | A brand-new addon folder needs only `/reload` (owner); scriptErrors is off by default and error delivery stops after 100 per session; SavedVariables load after a full exit since 70009 (never test persistence with `/reload`) | 70009 / owner 2026-10-09 | `PORTING-TBC-TO-FOREVER.md:430-434`, `:142-180`, `:2276-2286` |
| P2 | `GetNumSpecGroups()` = 1, `GetActiveSpecGroup()` = 1 without dual spec | 70245, 70450 | `AltStableSync/docs/forever-api-notes.md:46`, `:173` |
| P2 | **One trait tree per class, no subtrees**; the three Vanilla trees are posX clusters (1020-2820 / 5020-6820 / 9080-10880). Priest: config 88388, tree 1114, currency 3820, 54 nodes. All at 0 points, so a per-tree split by currency is unproven | 70009 | `GlassRaidFrames/docs/FOREVER-PROBE.md:269-295`, `GlassRaidFrames/Role.lua:13-21` |
| P2 | `ACTIVE_TALENT_GROUP_CHANGED` (1, 0) at login; (1, 1) mid-session with `PLAYER_TALENT_UPDATE` and `PLAYER_SPECIALIZATION_CHANGED`; `TRAIT_CONFIG_UPDATED` | **70532** (raw log) | SV1 `RaidProbe.lua:1307`, `:1519`, `:1622-1624` |
| P3 | Loot rows are children of `LootFrame.ScrollBox.ScrollTarget`, reached with `hooksecurefunc(ScrollBox, "Update")`; loot in combat (first of the session, after a fresh `/reload`) styled every row, 0 blocked | 70450 | `GlassUI/docs/FOREVER-PROBE.md:62`, `:99-105` |
| P4 | Stat keys (see FORMATS.md): `ITEM_MOD_SPELL_POWER_SHORT`, `ITEM_MOD_SHADOW/ARCANE_DAMAGE_DONE_SHORT`, resistance under two names, no speed key | 70425 | SV1 `WanderfulProbe.lua:27`, `:46`, `:77`, `:94`, `:156` |
| P4 | Cache miss: `GetItemInfo` / `GetItemStats` return nothing. Cold IDs load with `ITEM_DATA_LOAD_RESULT success=true` in the same 0.1 s tick; an invalid ID fails 0.4 s later | 70374, 70425 | `AltStable/docs/forever-api-notes.md:1057-1075`; SV1 `WanderfulProbe.lua:37-39` |
| P4 | A random suffix is a bonus ID (205 links); `GetItemStats` on such a link not measured | beta, 2026-10 | `AltStable/Scanner.lua:96-101` |
| P5 | Mail to the other faction fails ("Target is unfriendly."); soulbound items can't be mailed; mail to the other WoW account's character works like an alt (item not recorded); bind types 0/1/2 seen; a "Binds to Account" item exists | 70374, 70450, 70425, 70291 | `GlassMail/docs/FOREVER-PROBE.md:52`, `:54`; SV1 `MailProbe.lua:3009`; SV1 `WanderfulProbe.lua:25`; SV12 `ApothecaProbe.lua:22402` |
| P6 | `HookScript("OnTooltipSetItem")` throws; the Item post-call fired for `SetHyperlink`; `C_TooltipInfo` data carries `guid`, `id`, `lines` | 69913, 70291 | `AltStable/docs/forever-api-notes.md:1194-1216` |
| P7 | An Alt-held overlay (event plus OnUpdate) appeared and cleared | 70450 | `NodeRadar/docs/FOREVER-PROBE.md:568-579` |
| P8 | `GetContainerItemInfo().isBound`: true for soulbound items, false for cloth | 70374 | SV1 `AltStableProbe.lua:32-36` |
| P9 | Armor skills are skill lines (Cloth 415, Leather 414, header 8) via `C_SkillInfo`; a passive "Armor Proficiency" spell 1293712 | ~70334 | SV12 `ApothecaProbe.lua:31118`, `:31173-31174` |
| P11 | `GetItemInfo` 5th return = the tooltip's "Requires Level" (6 items); 0 or 1 when the tooltip has none | 70425 | SV1 `WanderfulProbe.lua:25`, `:60`, `:92` |
| P12 | GlassUI hooks `UpdateItems` on `ContainerFrame1..7` and `ContainerFrameCombinedBags`: 4 windows, 34 slots, child frames per button; bags used in combat with the taint log on, nothing blocked | 70450 | `GlassUI/docs/FOREVER-PROBE.md:209-213`, `GlassUI/docs/BAGS.md:127` |
| P13 | A canvas page created shown is blank on its first visit (hide at creation, build on first show); all 14 templates present, a missing one returns a bare frame; scroll frames work | 70205, 70009 | `PORTING-TBC-TO-FOREVER.md:1953-1960`; `Priestly/docs/FOREVER-PROBE.md:234-250`, `:315-319` |

**What this changed in Glass Gear** (same PR): resistance's twin key is counted once and Shadow
and Arcane damage are scored; the four unsampled schools keep their "not scored" warning (FORMATS.md); bag hooks cover the `ContainerFrame1..N` globals too; the atlas
check prefers `C_Texture.GetAtlasExists` (porting guide :1609); no restart for a new folder.

**Still to measure on 70532:** P2 after buying dual spec, and whether points per tree can be read;
P3 the slot and roll APIs; P4 healing-only, mp5, hit/crit, suffix and enchanted links, trimmed
strings; P5 other realm, account-bound items between accounts; P6 every surface but
`SetHyperlink`, the TooltipData fields, `RefreshData`, the owner; P7 left/right Ctrl, focus while
typing; P8 `IsBound`, `GetItemGUID`, `DoesItemExist`; P9 mail/plate at 40 and `IsSpellKnown`; P10
everything; P12 the atlas and the replacement addons; P13 `OpenToCategory` and this page.

---

## P1: The addon loads cleanly and `/gg diag` reports

- **Question.** Does Glass Gear load on 70532 without Lua errors? Does `/gg diag` show the build,
  `API_VERSION`, the current spec mapping, the dependencies detected (AltStable, GlassUI, LibGlass
  MINOR) and the capabilities reported as unavailable?
- **Why.** M0 claims a loadable scaffold. Only the client proves it.
- **Steps**
  1. `/console scriptErrors 1`, then `/reload` (a new addon folder needs no restart: porting guide :2276-2286).
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

- **From the source (wow-ui-source `forever`, 1.60.1.70532).** Forever (Camelot) loads the
  Mainline loot UI (`Blizzard_UIPanels_Game.toc:127-130`):
  - `LootFrame` is a ScrollBox of pooled elements (`Mainline/LootFrame.lua:74-96`); an item element
    has `GetSlotIndex()` (`:433`) and the icon button `.Item`; Blizzard's `Init` runs on open and on
    `LOOT_SLOT_CHANGED` (`:186-194`). GG-111 hooks `ScrollUtil.AddInitializedFrameCallback`
    (`ScrollUtil.lua:21`), which fires after Blizzard's initializer (`ScrollBoxListView.lua:397-409`).
  - Group rolls: `GroupLootFrame1..4` (`Mainline/GroupLootFrame.xml:641-644`) with `rollID` and the
    `.IconFrame` button, set up on `OnShow` (`GroupLootFrame.lua:371`). The gamepad roll list
    (`GamepadGroupLootRollFrameMixin`) is a different ScrollBox and is not covered.
- **Question.**
  - Is that what the client runs: does `/gg` report "loot window, 4 roll frames"?
  - Do the loot elements get created in combat (mob loot with adds up)?
  - Is `bindType` from `C_Item.GetItemInfo` available on loot links when the window opens?
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
  - Does a random-suffix link return the suffix stats? On Forever the suffix is a **bonus ID**
    (`item:14094::::::::10:1482:::1:12745`, AltStable's measurement), not link field 7.
  - Do `GetItemStats` and `GetItemInfo` read the **trimmed** string baselines store
    (`item:14094::::::::::::1:12745`: level and spec blanked, crafter dropped) the same as the full
    link? Alt baselines from AltStable come only in that form (AS-003).
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
    model), and when `EvaluationReady` arrives for a pending item (GG-107)?
  - Which `TooltipData` fields arrive per surface: `guid` (bags, equipped; `C_Item.GetItemLinkByGUID`
    keeps the suffix?), `hyperlink` (loot, vendor, chat links)? GG-107 falls back to
    `tooltip:GetItem()` when neither is set.
  - Comparison tooltips are named `ShoppingTooltip1/2` (`GameTooltip.xml:239`) and get no rows: is
    that the name on Forever?
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

## P12: Bag and loot marker hooks and look (GG-109, GG-110, GG-111)

- **Question.**
  - Are `ContainerFrameContainer.ContainerFrames[1..6]` and `ContainerFrameCombinedBags` the bag
    frames on Forever, with `UpdateItems` and `EnumerateValidItems` (Mainline
    `ContainerFrame.lua:575`, `:1191`; GlassPearls hooks the same)? `/gg` says how many were hooked.
  - Does atlas `bags-greenarrow` (`EquipmentFlyout.xml:10`) exist and read well at 14 px in a bag
    slot's top-left corner?
  - Does the amber version (the arrow desaturated and tinted, with a dark inner copy) read as an
    **outline**, clearly a different shape from green, also for colour-blind players? If not, pick
    another shape and record it here.
  - Do marks follow Ctrl press and release with the bags open, and after reopening? Is a release
    while typing in chat cleared within 0.1 s?
  - With bags opened in combat, do the marks appear after combat, with no taint message?
  - Do bag replacements (Baganator, Bagnon) hide Blizzard's frames, so no marks show (GG-401)?
  - Loot (GG-111): does the mark sit in the top-left corner of the loot window's icon and the roll
    frame's icon? Does it follow Ctrl with the loot window open? When looting in combat, do marks
    show at once (pooled frames), with no taint message?
- **Why.** The hooks and the visuals are modelled, not measured.
- **Steps.** Screenshots of an open bag with a current-spec upgrade, a BoE off-spec upgrade and a
  soulbound off-spec upgrade: normal, then holding Ctrl. Then the same in combat.

## P13: Settings page (GG-112)

- **Question.**
  - Does Esc > Options > AddOns > Glass Gear show the page **on the first visit** (built on first
    show, hidden at creation: the porting guide's recipe)? Does `/gg options` open it?
  - Do the check and radio buttons (`UICheckButtonTemplate`, `UIRadioButtonTemplate`), the hand-built
    sliders and the scroll frame render and respond? Is Shift visibly disabled, with its tooltip?
  - Does the page fit two columns in the Settings canvas, and does it scroll to Defaults?
  - Do changes apply at once: a minimum-upgrade change or the marker scope redraws open bags, a
    tooltip-scope change shows on the next tooltip?
  - Does the preview's arrow and rows follow the settings?
  - Defaults: everything back, no error. Any `ADDON_ACTION_FORBIDDEN` while the page is open?
- **Why.** The page is built from the porting guide and GlassUnitFrames, but this page is
  unmeasured.
- **Steps.** Open from the AddOns list (first visit), screenshot; change each section once and
  screenshot the bags and a tooltip; Defaults; `/gg options`.
