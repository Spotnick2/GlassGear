# Ecosystem findings

What Glass Gear can build on today, and what it can't. Every line below was read on 2026-11-01 at
the commit listed. **Verified** means the code or measured note exists at that line. **Not present
/ proposed** means it doesn't exist yet; the proposals are tracked in
[INTEGRATION-GAPS.md](INTEGRATION-GAPS.md) and [BACKLOG.md](BACKLOG.md). A function being in the
API dump doesn't prove it works (`References/Docs/PORTING-TBC-TO-FOREVER.md:1064`).

## Inspected state

| Source | Commit (date) | Tag / version |
|---|---|---|
| AltStable | `c89cf44` (2026-11-01) | v0.17.0-beta1 |
| AltStableCompanion | `0f0718a` (2026-10-24) | v0.1.1 |
| AltStableSync | `e5b1b75` (2026-11-01) | v1.0.0 |
| LibAccountSync | `ea0c0e8` (2026-10-29) | r5 (MINOR 6 on `main`, untagged) |
| LibGlass | `e2b9062` (2026-10-24) | r11 |
| GlassUI | `b78b244` (2026-10-29) | no tag |
| Shatter | `0ce809d` (2026-11-01) | v1.0.0-beta1 |
| GlassPearls | `250a17e` (2026-11-01) | v0.1.0-alpha1 |
| wow-ui-source (branch `forever`) | `ca8368f2f` (2026-10-22) | 1.60.1, build 70532 |
| API dump | `References/Forever/api/forever-api-1.60.1.70532.md` (the newest) | Interface 16001, `WOW_PROJECT_ID` 18 (line 4) |
| Pawn | the Forever release | 2.14.0, Interface 16001; CC BY-NC-ND: behaviour reference only, no code copied |
| WoWSims | `wowsims/tbc-new` `8aa378b36` (2026-07-25) | v0.0.101 |
| SimulationCraft addon | the current release | 12.1.5-03, `## Interface: 120100, 120105, 16001` |

Glass Gear records `MEASURED_ON_BUILD = "70532"`.

## Client: WoW Forever, build 70532

### Verified
- **Target:** Interface 16001, Lua 5.1. The TOC has no suffix. Forever is Vanilla content on the
  Mainline API (porting guide).
- **Item APIs in the dump** (line numbers in `forever-api-1.60.1.70532.md`):

  | API | Line |
  |---|---|
  | `C_Item.GetItemStats(itemLink)` | 2266 |
  | `C_Item.GetItemInfo` | 2243 |
  | `C_Item.GetItemSpell` | 2264 |
  | `C_Item.GetItemUniqueness(itemInfo) -> limitCategory, limitMax` | 2268 |
  | `C_Item.GetItemGUID(itemLocation)` | 2235 |
  | `C_Item.IsBound` (takes an `ItemLocation`) | 2277 |
  | `C_Item.IsBoundToAccountUntilEquip` | 2278 |
  | `C_Item.IsEquippableItem` | 2286 |
  | `C_Item.IsItemBindToAccount` | 2291 |
  | `C_Item.RequestLoadItemDataByID` | 2315 |
  | `C_Item.GetItemNumSockets` | 2258 |
  | `C_Container.GetContainerItemInfo` | 1170 |
  | `C_TooltipInfo.GetBagItem` | 3776 |
  | `C_EquipmentSet.GetItemLocations` | 1573 |
  | `TooltipDataProcessor` | 33780 |
  | `GetCurrentKeyBoardFocus` | 18891 |
  | `IsControlKeyDown` | 5446 |

  Events: `GET_ITEM_INFO_RECEIVED` 7332, `ITEM_DATA_LOAD_RESULT` 7538, `MODIFIER_STATE_CHANGED`
  7677, `PLAYER_EQUIPMENT_CHANGED` 7840, `ACTIVE_TALENT_GROUP_CHANGED` 6681.
- **`GetItemStats` on a cache miss returns nothing at all**, measured: `AltStable/docs/forever-api-notes.md:1070`.
- **No sockets or gems** on Forever: `PORTING-TBC-TO-FOREVER.md:2064`.
- **Tooltip hook.** `GameTooltip:HookScript("OnTooltipSetItem", …)` raises an error
  (`PORTING-TBC-TO-FOREVER.md:979-990`). The working hook is
  `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)` (`Shatter/Tooltip.lua:144-148`).
- **Bank:** bank tabs are ordinary containers (`PORTING-TBC-TO-FOREVER.md:960`). The account bank
  is plumbed but not enabled (`:973`).

### Specs
**Verified:**
- There is no global `GetSpecialization`, `GetActiveTalentGroup` or `GetPrimaryTalentTree` in the
  dump. `C_SpecializationInfo.GetSpecialization` (3504), `GetActiveSpecGroup` (3490),
  `GetCombatConfigIDForSpecGroup` (3494), `GetNumSpecGroups` (19269) and
  `C_Traits.GetGroupCurrencyInfo` (3970) exist.
- The porting guide says "There is no spec: the talent-tab API is gone" (`PORTING-TBC-TO-FOREVER.md:1052-1057`).
- Blizzard's Forever talent UI works this way:
  - it keys its tabs on `C_SpecializationInfo.GetActiveSpecGroup()`
    (`Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua:124`);
  - it resolves a group's config with `GetCombatConfigIDForSpecGroup` (`:132`, `:195`);
  - it reads points per tree with `C_Traits.GetGroupCurrencyInfo` (`:112`).
- AltStableSync measured `GetNumSpecGroups() = 1` and `GetActiveSpecGroup() = 1` on the owner's
  characters, so no dual spec had been bought (`AltStableSync/docs/forever-api-notes.md:46`).

**Not present:** a client spec ID per talent tree. `ChrSpecialization` has one row per class.
Glass Gear therefore defines its own spec keys ([adr/0002](adr/0002-spec-model.md)). Automatic
detection is unprobed (GG-101, [FOREVER-PROBE.md](FOREVER-PROBE.md)).

### Modifier keys
**Verified:** the default `ModifiedClick` bindings
(`Blizzard_FrameXML/Bindings_Camelot.xml:1533-1551`):

| Action | Default | Line |
|---|---|---|
| SELFCAST | ALT | 1533 |
| EXPANDTOOLTIP | SHIFT | 1534 |
| STICKYCAMERA | CTRL | 1539 |
| CHATLINK | SHIFT-BUTTON1 | 1540 |
| DRESSUP | CTRL-BUTTON1 | 1541 |
| SPLITSTACK | SHIFT | 1543 |
| PICKUPITEM | SHIFT | 1545 |
| COMPAREITEMS | SHIFT | 1546 |
| OPENALLBAGS | SHIFT | 1547 |
| SHOWITEMFLYOUT | ALT | 1551 |

Holding **Ctrl** over a bag item without clicking is not bound to anything that consumes it.
Ctrl-*click* is the dressing room. Glass Gear's reveal only reads the key state and never handles
clicks, so both coexist. Shift belongs to item comparison, so it is not offered as a default.

### Armor proficiency, level and item sets (GG-117, GG-118, GG-119)
**Verified in the dump** (`forever-api-1.60.1.70532.md`):

| API | Line |
|---|---|
| `C_SpellBook.IsSpellKnown(spellID, spellBank)` | 3634 |
| `C_SpellBook.IsSpellInSpellBook` | 3633 |
| `IsSpellKnown` (global) | 20044 |
| `IsPlayerSpell` | 20014 |
| `C_SkillInfo.GetNumSkillLines` | 3414 |
| `C_SkillInfo.GetSkillLineInfo` | 3416 |
| `C_SkillInfo.GetSkillLineInfoByID` | 3417 |
| `C_SpellBook.GetSkillLineIndexByID` | 3600 |
| `C_Item.GetItemSetInfo(setID) -> name` | 2262 |
| `C_LootJournal.GetItemSetItems(setID)` | 2497 |

- Events: `SKILL_LINES_CHANGED` (8067) and `SPELLS_CHANGED` (8102).
- There is no global `GetSkillLineInfo`.
- `C_Item.GetItemInfo` returns `bindType` as its 14th value and `setID` as its 16th (optional),
  both at line 2243.

**Verified in the client tables** (`References/Forever/db`, build 70532):
- `forever-skillline` has the armor skill lines:
  - Plate Mail 293 (line 89)
  - Mail 413 (100)
  - Leather 414 (101)
  - Cloth 415 (102)
  - Shield 433 (103)
- `forever-skilllineability` maps them to the proficiency spells. Read with awk:

  | Skill line | Spell |
  |---|---|
  | 293 | 750 |
  | 413 | 8737 |
  | 414 | 9077 |
  | 415 | 9078 |
  | 433 | 9116 |

  Skill line 415 also maps to spell 1293712.
- `forever-itemsparse` has `ItemSet` (column 78), `RequiredSkill` (84), `AllowableClass` (86) and
  `RequiredLevel` (101).
- `forever-spelllevels` has **no** rows for those five spells, so the level a class learns
  Mail/Plate is not in the saved tables. Trainer-taught at 40 is the owner's statement, not
  measured here.

**Not present locally:**
- **`ItemSet` and `ItemSetSpell` tables** are not saved in `References/Forever/db`. GG-119 must
  fetch them through the `wago-tools` skill (`References/Tools/Wago/wago.py get ItemSet` and
  `ItemSetSpell`). They were not fetched for this doc.
- **Which runtime call reports a known armor proficiency** is unmeasured: `IsSpellKnown(8737)`,
  `IsPlayerSpell`, or the `C_SkillInfo` skill list. That is a probe in [FOREVER-PROBE.md](FOREVER-PROBE.md).

### Item transfer
**Verified:**
- Item and instance binding *queries* exist (`IsBound`, `IsBoundToAccountUntilEquip`,
  `IsItemBindToAccount*`, above).
- AltStable syncs your own game accounts across rulesets and factions
  (`AltStable/docs/SYNC-DISCOVERY.md:295`). This proves **data** can cross. It says nothing about items.

**Not verified (unprobed on Forever):**
- whether a BoE can be mailed cross-faction or cross-realm;
- whether connected realms exist;
- which account-bound kinds (`ToWoWAccount`, `ToBnetAccount`) occur on Forever, and how they move
  between two WoW accounts on one Battle.net account.

All of these are proposals until GG-116 measures them.

## AltStable

### Verified
- **Public API**
  - `AltStable.PUBLIC_API_VERSION = 1` (`PublicAPI.lua:32`).
  - `GetCharacters()` (`:51`) returns copies of identity fields only (`FIELDS`, `:36`): `guid,
    name, realm, faction, class, level, money, account, lastUpdate` plus `hidden` and `current`.
    It returns **no gear, no spec, no stats**.
  - Callbacks are limited to `CharactersChanged` and `PortraitStatusChanged` (`:183`), through
    `RegisterCallback` (`:185`). Dispatch is batched to the next frame and run under `xpcall`.
  - Consumers declare `## OptionalDeps: AltStable` (`docs/PUBLIC-API.md:8`). `account` is "the
    number the player gave that WoW account", `""` when unset (`docs/PUBLIC-API.md:46`).
- **Plugins**
  - `AltStable.RegisterPlugin` (`Core.lua:3749`) requires `id`, `label` and `OnActivate` (`:3750`),
    and so a sidebar tab.
  - Sync hooks: `OnSerialize(guid, sinceTS)` (`Core.lua:896-897`) and `OnDeserialize(guid, blob)`
    (`:849-850`), plus the `independentStamp` opt-in (`:838`).
  - Neither hook receives a sender or a destination.
  - `TouchCharacter` (`Core.lua:1204`) only stamps `lastUpdate`.
  - First-party plugins are listed in `LOD_PLUGINS` (`Core.lua:3674`).
- **Gear snapshot (internal)**
  - It is `AltStableDB[guid]`, a flat record over `GEAR_SLOTS` (`Scanner.lua:66`) holding item
    level, quality, item id, name and enchant/socket mods.
  - `gearlink_*` and `gearsubtype_*` are **local-only** and never synced (`Core.lua:871-873`), so a
    remote random suffix survives only as name text. *(Before AS-003; AltStable #283 now syncs a
    trimmed item string per slot, see INTEGRATION-GAPS.md.)*
  - `lastUpdate` is stamped only when the data is complete (`Scanner.lua:974-978`).
- **Spec:** retired. "No spec: GetNumTalentTabs / GetTalentTabInfo are gone on Forever" (`Scanner.lua:718`).
- **Ownership signals**
  - `scannedHere = true` is set by the client that scans the character (`Scanner.lua:638`). It is
    local-only (`Core.lua:875`).
  - `LibSync.Peer(name)` is a session-only own-account check (`Core.lua:563`).
  - `account` is typed by the player.
  - `sendAllAccounts` (default off) decides whether characters tagged with another account are
    relayed (`Core.lua:1916-1918`).
- **Merge**
  - `ValidateIncoming` (`Core.lua:407`), `ShouldMerge` (`:1327`).
  - A locally scanned character wins over remote copies (`:1316-1330`).
  - `ClearSyncedStateFields` (`:1279`).
- **Transport**
  - `PROTOCOL_VERSION = "8"` (`Core.lua:88`), `CHUNK_VERSION = "5"` (`:94`).
  - Own accounts use LibAccountSync with `maxPayload = 32768` (`:3251`). The whole payload goes as
    one message (`ChunkAndSendPayload`, `:1824-1830`).
- **Forget:** `ForgetCharacter` (`Core.lua:1052`). `STALE_DAYS = 90` (`:1095`).

### Not present / proposed
- ~~A public gear read API, per-slot completeness, item strings with suffix, and a gear-change
  stamp (AS-003).~~ Shipped in AltStable #283 (`1b35918`).
- Per-spec gear, equipment sets, stat weights, BiS.
- An own-account-only channel with sender/destination enforcement, and persistent per-character
  ownership provenance (AS-001).
- A namespaced entry-sync service with manifests, acknowledgements and inventory (AS-002). Since
  2026-11-01 this is no longer asked of AltStable: it moved to the shared library ES-001
  (adr/0001 amendment). AS-001 (provenance, own-account channel) has since merged in AltStable
  #282 (`028cdd1`); the findings above describe the commit listed at the top.
- Headless plugin registration (no sidebar tab).

## AltStableSync

### Verified
- **What it is:** an addon that catalogs UI setups and class loadouts. It syncs over LibAccountSync
  through its Link plugin.
- **Writer identity:** the writer token is "a fresh random 12-hex string generated on every"
  initialisation, never stored (`docs/DESIGN.md:222`). Versions are `writer:seq` (`:153`).
- **Messages and exchange** (`docs/DESIGN.md:850-911`):
  - manifests, one-id pulls (at most 3 outstanding), 30 s re-queue, bounded timer;
  - batches shrink until they fit; oversized entries stay local;
  - wire schema 3 (`:875`).
- **Receive rules per entry, idempotent** (`docs/DESIGN.md:913-928`):
  - 20 ancestors;
  - fast-forward / ignore / divergent → whole-entry conflict copy, suppressed if it already
    exists live or tombstoned.
- **Resolution and deletion** (`docs/DESIGN.md:930-973`):
  - resolution with both parents (`:930`);
  - versioned tombstones kept indefinitely (`:965`);
  - expected-version guards (`:969`);
  - no field merging.
- **Receipt-side retirement of covered conflict copies:** `Catalog.lua:542` (Upsert → RetireCovered),
  `:580` (Retire), `:89` (Advance mints).

### Not present
- No gear, stat weights or simulation.
- The Link protocol isn't a library other addons can call. AS-S1 chose extraction (2026-11-01):
  ASS-001 turns it into the shared library ES-001.

## AltStableCompanion

### Verified
- A Windows tray app: .NET `net10.0` (`Directory.Build.props:3`) with Avalonia (`src/AltStableCompanion.App/AltStableCompanion.App.csproj`).
- It reads AltStable SavedVariables files to make portrait cutouts.

### Not present
No WoWSims or SimC orchestration and no job queue. Nothing in AltStable, AltStableCompanion,
AltStableSync or LibAccountSync mentions simc or wowsims. Simulation work is ASC-001 (future).

## LibAccountSync

### Verified
- `LibAccountSync-1.0`, MINOR 6 (`LibAccountSync.lua:31`). The latest tag is r5 (`CLAUDE.md:12`);
  MINOR 6 is untagged (`CLAUDE.md:7`).
- Scope is "your own other WoW accounts on the same Battle.net account" (`README.md:4`).
- Transport: `BNSendGameData` (`LibAccountSync.lua:890`) with prefix `LibAcctSync` (`:50`).
- Limits: `MAX_PAYLOAD = 32768` (`:54`), `MAX_CHUNKS = 365` (`:56`). An oversized send returns
  `"too-large"` (`:1154`).
- It has a messages mode (`README.md:56`).

### Not present
Sync across separate Battle.net accounts (AltStable #143, deferred). Glass Gear doesn't need it:
both of the owner's WoW accounts are on one Battle.net account.

## LibGlass

### Verified
- `LibGlass-1.0`, MINOR 11 (`LibGlass.lua:41`). `lib.ready = MINOR` is the last line (`:1168`).
- The pearl preset is at `:1124`.
- Consumers pin `tag: r11` (`Shatter/.pkgmeta`, `AltStable/.pkgmeta:20`).

### Not present
LibGlass has no tooltip skin. Glass Gear needs no LibGlass change. It must not change the shared
defaults.

## Glass UI

### Verified
- `Suite = { API = 1 }` (`Suite.lua:21`).
- `Suite.ROSTER` (`:31`) is a fixed list:
  - dynamic members include AltStable and Shatter (`:47`, `:50`);
  - a non-member gets `"unknown"` (`:95`);
  - Shatter joined in commit `54b84fb` ("Suite: Shatter as a dynamic member (#164)").
- Following:
  - follow is on unless the player opted out (`:90`), set through `Suite.SetFollow` (`:186-190`);
  - a following addon's own look settings are "suspended but kept" (`docs/SUITE.md:31`);
  - `live = false` members show "/reload to apply" (`:179`);
  - an addon may report `declined` (`:184`).
- A tooltip skin is planned as #147 and is not built (`docs/SKINS.md:102`).

### Not present
GlassGear on the roster (GUI-001).

## Shatter

### Verified
- **Queue and click-time checks**
  - `ItemScanner:IsCandidateDisenchantable` (`ItemScanner.lua:75`) is called by the queue build
    (`ScanBags`, `:178`, call at `:190`) and at click time (`Disenchant:ValidateItem`,
    `Disenchant.lua:154`, call at `:183`).
  - The Solo-only "possible upgrades" block reads: "Mail items belong to their senders" (`:86-94`).
  - Equipment sets are excluded (`:85`).
- **Secure button:** a `SecureActionButtonTemplate` (`UI/MainFrame.lua:40`), armed in
  `BeginSecureClick` (`Disenchant.lua:190`). "An error in PreClick does not cancel the secure
  action" (`:259`).
- **Rescans:** `SoloMode:ScheduleScan` (`Modes/SoloMode.lua:45`). Shatter does not rescan on
  `PLAYER_EQUIPMENT_CHANGED`.
- **Integration precedent:** `GlassMailSelection()` (`Modes/MailMode.lua:162`).
  `## OptionalDeps: GlassMail` (`Shatter.toc:8`).
- **Item GUID:** Mail items carry an `itemGUID`, re-read at click time (`Disenchant.lua:170-173`).
- **Tooltip:** `AddTooltipPostCall` with an `IsForbidden` guard, and a modifier-driven
  `RefreshData` (`Tooltip.lua:108`, `:127-138`, `:148`).

### Not present
- No external veto or filter API (SH-001).
- No per-row "Disenchant anyway" override (SH-002).
- Solo items don't carry an `itemGUID`.

## GlassPearls

### Verified
- **Bag overlay pattern:** `hooksecurefunc(cf, "UpdateItems", …)` on each bag frame
  (`Core/BagMarks.lua:126-127`), iterated with `EnumerateValidItems` (`:106`), with combat
  deferral via `PLAYER_REGEN_ENABLED` (`:88`, `:163`).
- **Bag-slot tooltip identity check:** `GetOwner` → `GetBagID` → `GetContainerItemID`
  (`Pearls/JunkSpot.lua:72-78`).
- **Look switch:**
  - the Glass look is optional via `useGlassUI` (`Options.lua:301`), reported as declined (`Theme.lua:13`);
  - `## Category: |cff7fd4ffGlass|r` (`GlassPearls.toc:4`).

## Pawn (behaviour reference)

### Verified
- **Forever flags**
  - `VgerCore.IsForever`.
  - `SpecsExist` is false on Forever, `EquipmentSetsExist` is false and
    `RangedSlotExists` is true.
- **Scale string**
  - parsed by Pawn's `PawnParseScaleTag`: a header pattern, then a pair pattern;
  - `PawnIgnoreStatValue = -1000000` for `X`;
  - written by `PawnGetScaleTag`, imported by `PawnImportScale`.
- **Upgrade %:** `PercentUpgrade = Difference / (BestValue + PawnEpsilon)`.
  - Only upgrades more than 0.5% better count (`ThisValue > BestValue * 1.005`).
  - An empty second slot shows as `PawnBigUpgradeThreshold = 100`.
- **Trinkets** are skipped for score-based upgrades.
- **Enchants:** the candidate is unenchanted before comparison.
- **Unique-equipped:** not handled ("Pawn currently can't determine that").
- **2H / 1H:** handled with `DoNotShow1HUpgrades` and `PawnAssignOneHandedBestItems`.
- **Stat tokens flagged for Forever:** Pawn's `PawnStatForever` flags.
- **Gems:** `PawnMinimumItemLevelToConsiderGems = 10000`, so gems are off.
- **Spec code:** `GetSpecialization and GetSpecialization() or GetPrimaryTalentTree()`.
  Both functions are absent on Forever.

## WoWSims (`tbc-new`)

### Verified
- `CHARACTER_LEVEL = 70` (`ui/core/constants/mechanics.ts:1`). It is a TBC sim, not a Forever one.
- **Imports:** "Addon" importer (`individual_sim_ui.tsx:469`) reading a WowSimsExporter JSON
  (`importers/individual_addon_importer.tsx:43-79`: `version`, `professions`, `talents`, `gear`).
- **Exports:** "Pawn EP" (`individual_sim_ui.tsx:475`).
  - Format: `( Pawn: v1: "<Spec> WoWSims Weights": Class=<Class>,Stat=w.www,... )`
    (`exporters/individual_pawn_ep_exporter.tsx:35-37`).
  - Zero-weight and unmapped stats are dropped (`:22`).
  - Names include `Mana`, `Health`, `Armor2` (`:60-67`), and many stats map to `''` (`:68-91`).

### Not present
A Forever (Vanilla, level 60) sim in the local checkout.

## SimulationCraft addon

### Verified
- **Forever detection:** `IS_FOREVER = WOW_PROJECT_ID == (WOW_PROJECT_CAMELOT or 18)`.
  Forever-only exports; a `forever/` folder (`stats.lua`, `legacytalents.lua`, `pet.lua`).
- **Profile header:** "Requires SimulationCraft 1000-01 or newer".
- **Spec and talents**
  - `spec=unknown` on Forever;
  - `legacy_talents=`;
  - talents from `GenerateImportString`.
- **Stats:** its `forever/stats.lua` sums gear stats with `GetItemStats` ("does not include enchants").

### Not present
- Stat weights. A profile is a character.
- A local simc engine that understands Forever profiles.

## Doc drift found

- **AltStable pins.** `AGENTS.md:252` says LibGlass is pinned at `tag: r5` and `:266` says
  LibShowcase is at `tag: r3`. `.pkgmeta:20,23` pins `r11` and `r4`. Trust `.pkgmeta`.
- **Shatter build.** `Constants.lua:13` records `MEASURED_ON_BUILD = "1.60.1.70334"`, but the
  newest dump is 70532. AltStable records `"70450"` (`Config.lua:1723`).
