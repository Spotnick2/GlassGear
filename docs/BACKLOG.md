# Glass Gear backlog

Each entry is written so it can be filed as a GitHub issue as is. The repo's workflow is
issue → branch → PR (`Closes #N`) → owner review and merge.

**Fields**

| Field | Values |
|---|---|
| Priority | P0 blocks the milestone, P1 needed for it, P2 nice to have |
| Class | **MVP** · **EXT** (required ecosystem extension, in another repo) · **SPIKE** (research or probe) · **FUT** (future) |
| Validation | **auto** (Lua tests in `tests/`) · **game** (in-game, ForeverProbe procedure in [FOREVER-PROBE.md](FOREVER-PROBE.md)) |

The game is offline until 2026-11-04, so every **game** item waits for it.

Cross-repo items are detailed in [INTEGRATION-GAPS.md](INTEGRATION-GAPS.md). Contracts are in
[API.md](API.md), [SCHEMA.md](SCHEMA.md) and [adr/](adr/), and mockups in [mockups/README.md](mockups/README.md).

## Issue map

M0 is [#1](https://github.com/Spotnick2/GlassGear/issues/1), closed by the foundation PR.

| Backlog | Issue |
|---|---|
| GG-101 | [#2](https://github.com/Spotnick2/GlassGear/issues/2) |
| GG-102 | [#3](https://github.com/Spotnick2/GlassGear/issues/3) |
| GG-103 | [#4](https://github.com/Spotnick2/GlassGear/issues/4) |
| GG-104 | [#5](https://github.com/Spotnick2/GlassGear/issues/5) |
| GG-105 | [#6](https://github.com/Spotnick2/GlassGear/issues/6) |
| GG-106 | [#7](https://github.com/Spotnick2/GlassGear/issues/7) |
| GG-107 | [#8](https://github.com/Spotnick2/GlassGear/issues/8) |
| GG-108 | [#9](https://github.com/Spotnick2/GlassGear/issues/9) |
| GG-109 | [#10](https://github.com/Spotnick2/GlassGear/issues/10) |
| GG-110 | [#11](https://github.com/Spotnick2/GlassGear/issues/11) |
| GG-111 | [#12](https://github.com/Spotnick2/GlassGear/issues/12) |
| GG-112 | [#13](https://github.com/Spotnick2/GlassGear/issues/13) |
| GG-113 | [#14](https://github.com/Spotnick2/GlassGear/issues/14) |
| GG-114 | [#15](https://github.com/Spotnick2/GlassGear/issues/15) |
| GG-115 | [#16](https://github.com/Spotnick2/GlassGear/issues/16) |
| GG-116 | [#17](https://github.com/Spotnick2/GlassGear/issues/17) |
| GG-117 | [#18](https://github.com/Spotnick2/GlassGear/issues/18) |
| GG-118 | [#19](https://github.com/Spotnick2/GlassGear/issues/19) |
| GG-119 | [#20](https://github.com/Spotnick2/GlassGear/issues/20) |
| GG-120 | [#40](https://github.com/Spotnick2/GlassGear/issues/40) |
| GG-121 | [#41](https://github.com/Spotnick2/GlassGear/issues/41) |
| GG-122 | [#46](https://github.com/Spotnick2/GlassGear/issues/46) |
| GG-201 | [#21](https://github.com/Spotnick2/GlassGear/issues/21) |
| GG-202 | [#22](https://github.com/Spotnick2/GlassGear/issues/22) |
| GG-203 | [#23](https://github.com/Spotnick2/GlassGear/issues/23) |
| GG-204 | [#24](https://github.com/Spotnick2/GlassGear/issues/24) |
| GG-301 | [#25](https://github.com/Spotnick2/GlassGear/issues/25) |
| GG-401 | [#26](https://github.com/Spotnick2/GlassGear/issues/26) |
| GG-402 | [#27](https://github.com/Spotnick2/GlassGear/issues/27) |
| GG-403 | [#28](https://github.com/Spotnick2/GlassGear/issues/28) |
| GG-404 | [#29](https://github.com/Spotnick2/GlassGear/issues/29) |
| GG-501 | [#30](https://github.com/Spotnick2/GlassGear/issues/30) |
| GG-502 | [#31](https://github.com/Spotnick2/GlassGear/issues/31) |
| AS-001, AS-003 | [AltStable#281](https://github.com/Spotnick2/AltStable/issues/281), closed: AS-001 in AltStable #282, AS-003 in #283 |
| AS-002 → ES-001 | moved out of AltStable (#36); the library's repo is TBD, extracted under ASS-001 |
| ASS-001 | [AltStableSync#101](https://github.com/Spotnick2/AltStableSync/issues/101) |
| SH-001, SH-002 | [Shatter#52](https://github.com/Spotnick2/Shatter/issues/52) |
| GUI-001 | [GlassUI#167](https://github.com/Spotnick2/GlassUI/issues/167) |
| ASC-001 | [AltStableCompanion#55](https://github.com/Spotnick2/AltStableCompanion/issues/55) |

## M0: Foundation, contracts and design (this PR)

| ID | P | Class | Outcome | Status |
|---|---|---|---|---|
| GG-001 | P0 | MVP | Repo scaffold: TOC (16001), `.pkgmeta` (LibGlass r11), deploy, CI | done: `test_manifest`, `test_load`, deployed |
| GG-002 | P0 | MVP | Contract docs: PRD, ADR 0001–0006, API v1, SCHEMA, FORMATS, findings, gaps, probes | done |
| GG-003 | P0 | MVP | Pure core with fixtures: Pawn I/O, score, configurations, evaluation, policies, transfer, entry sync, codec | done: 11 test files, mutation-checked |
| GG-004 | P1 | MVP | `/gg` diagnostics, manual spec mapping, Pawn import command, Settings category stub | done (auto); game check P1 |
| GG-005 | P1 | MVP | Mockup inventory and gap boards G1–G4 | done; level window, armor and set boards are still a gap |

## M1: Current character (scoring, imports, tooltips, markers)

### GG-101: Spike, spec detection (P0, SPIKE)

- **Outcome.** We know whether spec group → combat config → `C_Traits` tree points identifies the
  current tree on Forever.
- **Scope.** Probe P2. If it works, enable `Spec.AUTO_ENABLED`; ties, unspent points and the Feral
  split stay `unknown-spec`.
- **Deps.** None.
- **Acceptance.**
  - Measured on at least 2 classes with a full talent build and with no points spent.
  - Dual-spec switch fires `ACTIVE_TALENT_GROUP_CHANGED`.
- **Already measured** (FOREVER-PROBE.md sweep): **one trait tree per class, no subtrees** (70009,
  GlassRaidFrames); the three Vanilla trees are posX clusters of its nodes, so "points per tree"
  means summing the spent ranks of each cluster, not a per-tree currency (unproven: measured at 0
  points). `GetNumSpecGroups()` = 1 without dual spec; `ACTIVE_TALENT_GROUP_CHANGED` fires at
  login and mid-session (70532 raw log).
- **Refs.** adr/0002.
- **Validation:** game (P2); auto for the resolver (`test_load` mapping).

### GG-102: Spike, loot surfaces (P0, SPIKE)

- **Outcome.** We know the loot window's and the group roll frame's item buttons, how their
  links are exposed, and the bind type before loot.
- **Scope.** Probe P3.
- **Acceptance.** The frame names and hook points are recorded in FOREVER-PROBE.md.
- **Validation:** game.

### GG-103: Spike, item stats on real links (P0, SPIKE)

- **Outcome.** We have the exact `GetItemStats` keys Forever returns (spell damage, healing, mp5,
  school damage), the behaviour on suffix and enchanted links, and cache-miss timing.
- **Scope.**
  - Probe P4.
  - Turn "expected" keys into measured ones in `Data/Stats.lua` and FORMATS.md (`test_formats_doc`
    keeps them in step).
  - School-specific spell damage: **answered on 70425** (Wanderful's probe log). `GetItemStats`
    returns it as `ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT` / `ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT`, now
    mapped and scored (the four unsampled schools stay unscored, with their warning, until seen); damage-and-healing is `ITEM_MOD_SPELL_POWER_SHORT`; resistance comes under two
    names (counted once). What remains: Fire/Frost/Nature/Holy confirmed, healing-only, damage-only,
    mp5, hit and crit units, suffix and enchanted links, trimmed strings (FORMATS.md).
- **Validation:** game, then auto.

### GG-104: Spec mapping UI (P1, MVP)

- **Outcome.** The owner maps spec groups to specs without a slash command, or confirms automatic
  detection (GG-101).
- **Scope.** A dropdown per spec group in Settings; an `unknown-spec` banner in the tooltip
  footer.
- **Deps.** GG-112 (panel).
- **Acceptance.**
  - The mapping persists per character.
  - Changing it fires `EvaluationInvalidated`.
- **Refs.** mockup 05.
- **Validation:** auto (resolver), game.
- **Done (auto), game P13.** The settings page's SPECS section: one line per spec, a radio column
  per spec group, and Not set (radios, not dropdowns: the porting guide). `Spec.Map` is the one
  setter, also behind `/gg spec` (which now takes `none`). The active group is labelled; group 2
  says "not learned" without dual spec. The tooltip's hint points at `/gg options`.
  `test_spec_mapping.lua`. Automatic detection stays with GG-101.

### GG-105: Profiles UI with Pawn import/export (P0, MVP)

- **Outcome.** Per character and spec, the owner can paste a Pawn or WoWSims "Pawn EP" string,
  see validation, edit weights, and export.
- **Scope.**
  - Profile list per spec, up to 4 profiles.
  - Import dialog with type choice: Pawn; WoWSims Pawn EP; SimC profile or WoWSims JSON, which are
    explained as needing a simulation.
  - Errors and warnings from `PawnString.Parse` (NO_WEIGHTS, UNKNOWN_STAT, WOWSIMS_DROPS).
  - Source and freshness labels; per-spec armor set editor (GG-118).
  - All edits through `EntrySync` with an expected version.
- **Deps.** GG-112.
- **Acceptance.**
  - Every import error in `test_pawn_string` shows a readable message.
  - A spec without a profile shows "no weights".
- **Refs.** mockups 05, G3; adr/0005; FORMATS.md.
- **Validation:** auto (parser, store), game (UI).
- **Done (auto), game P15.** `UI/ProfilesWindow.lua` (own window, WoW Forever look; the owner chose a
  window over a settings sub-page, 2026-11-02), `Presentation/ProfileView.lua` (texts),
  `Profiles/Profiles.lua` (several profiles, `activeAt`), `test_profiles.lua`. Differences from the
  scope above:
  - The import type is **detected**, not chosen: the parser recognises Pawn, WoWSims Pawn EP and
    character exports, and the window names what it read. No dropdown (porting guide: radio
    groups or nothing).
  - Conflict copies (`<id>~<version>`) are not shown: they arrive with sync (GG-202).
  - The Glass look is GG-115.

### GG-106: Research, default weights (P2, SPIKE)

- **Outcome.** A licence-clean default weight source per spec, or the decision to ship none.
- **Scope.** Pawn's scales are CC BY-NC-ND and can't be copied. WoWSims tbc-new presets are TBC
  level 70. Evaluate community sources and the owner's own sims.
- **Acceptance.** A recommendation with licence notes, written down.
- **Validation:** n/a.
- **Result.** [research/default-weights.md](research/default-weights.md): Pawn's numbers are not
  shipped (the user can still export them from Pawn and import them). Recommended: our own simple
  per-spec defaults as a stopgap until WoWSims weights exist, labelled "default weights", never
  trusted by protection, replaced by any import. Follow-ups GG-120 and GG-121 (below).

### GG-120: Default weights (P1, MVP)

- **Outcome.** Every spec without an imported profile scores with Glass Gear's own default weights,
  labelled "default weights", instead of showing "no weights".
- **Scope.**
  - `Data/Defaults.lua` from the draft table in research/default-weights.md, not shipped
    literally: rescaled or revised from GG-103's measurements first.
  - `Profiles.Active` falls back to it; defaults are never stored or synced.
  - Provenance `default`; the tooltip tag and footer.
  - Markers at normal brightness; the qualification is in the tooltip and the profile UI.
  - Limitation `DEFAULT_WEIGHTS`, soft protection: a default-based upgrade protects; a
    default-based `no_upgrade` is unchecked (`protection.noWeights`), never a reason for `clear`;
    only default or no-weight specs relevant → `unknown`. "Relevant" counts eligible specs only
    (`Policy.Protection` counts all results today).
  - Setting `defaults.enabled` (on).
  - Rescale the per-1 % stats after GG-103.
  - Only tokens the scorer reads today. School-specific spell damage weights (the second table in
    research/default-weights.md) wait for GG-103 to map their client keys and for the scorer to
    read them.
- **Deps.** GG-103 for the rating units **and** the school-specific spell damage keys (blocking).
- **Acceptance.** An import replaces the default; a default-based `no_upgrade` never gives `clear`;
  only default or no-weight specs relevant → `unknown`, also beside an ineligible spec; rows carry
  the tag; markers draw normally.
- **Validation:** auto, game (P6).

### GG-121: Import from Pawn (P3, Future: not in the MVP)

- **Outcome.** With Pawn loaded, a click imports one of Pawn's scales (`PawnGetAllScalesEx`,
  `PawnGetScaleTag`) through the normal importer. Nothing from Pawn ships with Glass Gear.
- **Why later.** Pawn's own Export plus `/gg import` already works (FORMATS.md); build the button
  only if users ask for it.
- **Scope.** Explicit action only, `pcall`-wrapped, Pawn as an optional dependency; `origin`
  marks read-only scales "Pawn built-in".
- **Validation:** auto (stubbed Pawn), game.

### GG-107: Tooltip rows for all own specs (FIRST VERTICAL SLICE, P0, MVP)

- **Outcome.** Hovering any equippable item shows a compact "Glass Gear" block:
  - the current spec first and emphasised;
  - the other specs compact;
  - "no weights" rows;
  - a "checking…" row for pending items;
  - "at level N (in k levels)" rows;
  - set-bonus warnings;
  - the footer "item-score estimate".
- **Scope.**
  - `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, …)`, registered once and
    under `pcall`.
  - Owner and instance identity, with the JunkSpot pattern for bag slots.
  - `Policy.TooltipRows` → forever-theme lines; refresh on `EvaluationReady` and modifier changes,
    with Shatter's guards.
  - Baseline: current equipment, labelled `fallback-current` for the other specs until GG-108.
  - Never restyle GameTooltip.
- **Deps.** GG-103 for stat keys; can start with expected keys.
- **Acceptance.**
  - Rows appear on bag, equipped, loot, chat-link and vendor tooltips.
  - No row reads 0 for missing weights.
  - Other tooltip addons' lines stay intact.
  - No error with Glass UI loaded.
- **Refs.** mockups 01, 02, 03, G1; adr/0004, 0006.
- **Validation:** auto (rows), game (P6).

### GG-108: Per-spec baselines (P0, MVP)

- **Outcome.** Each spec compares against its own gear: a mapped equipment set, or gear observed
  while that spec was active.
- **Scope.**
  - Capture on login, `PLAYER_EQUIPMENT_CHANGED` and spec change, storing the trimmed item string
    (`Compat.GearItemString`, AltStable's form: the bonus ID carries the suffix). A string over
    `Codec.MAX_ITEM` is captured as `unknown` for that slot.
  - Equipment-set mapping per spec.
  - Baseline entries in `EntrySync`.
  - Freshness and `expiresAt`.
  - Companion off-hand from the worn gear (from the bags: GG-122).
  - Owned better items in bags as an optional source: moved to GG-122.
- **Acceptance.**
  - A Holy result uses Holy gear after one Holy session.
  - "No Holy equipment recorded" offers "use current gear (estimate)" or "choose a saved set"
    (mockup 08).
  - A stale baseline is reported.
- **Refs.** adr/0003; mockup 08.
- **Validation:** auto (precedence, freshness: `test_evaluate`), game.

### GG-109: Bag markers (P0, MVP)

- **Outcome.**
  - Green filled chevron for current-spec upgrades.
  - Amber outlined chevron for transferable items that are upgrades for another own spec or an
    eligible alt.
  - Soulbound off-spec items are quiet.
- **Scope.**
  - `hooksecurefunc` on container frames' `UpdateItems` (BagMarks pattern).
  - Child frames only, preallocated out of combat.
  - Bind state from the instance; `Policy.Marker`.
- **Acceptance.**
  - Matrix rows 2 and 3 of the PRD.
  - Green precedence.
  - A BoE that binds loses its alt amber on the next update.
  - No taint in combat.
- **Refs.** mockups 02, 03; adr/0006.
- **Validation:** auto (`test_policy`), game (P8).

### GG-110: Reveal modifier (P0, MVP)

- **Outcome.** Holding Ctrl (or Alt) shows amber own off-spec upgrades on bags and loot.
  Releasing restores the normal display at once.
- **Scope.**
  - `Policy.NewReveal` fed by `MODIFIER_STATE_CHANGED`, surface shows, and a 0.1 s focus poll while
    a surface is visible.
  - Never consumes clicks.
  - Combat-safe.
  - No saved change.
- **Acceptance.**
  - Press and release work.
  - A release while typing clears the reveal.
  - Ctrl-click still opens the dressing room.
  - Reopened bags show the current state.
  - Modifier `None` disables it.
- **Refs.** mockups 02, G1.
- **Validation:** auto (`test_policy`), game (P7).

### GG-111: Loot-surface markers (P1, MVP)

- **Outcome.** Loot window and roll frames follow the matrix: current spec green; reveal → amber
  own off-spec; BoE alts only while revealed (proposal, to be confirmed by the owner).
- **Deps.** GG-102.
- **Refs.** mockups 01, G1.
- **Validation:** auto (`test_policy`), game (P3/P6).

### GG-112: Settings panel (P1, MVP)

- **Outcome.** The Settings category holds:
  - the three independent sections: Tooltips, Bag markers, Disenchant protection;
  - the reveal modifier (Ctrl, Alt or None; Shift disabled with its reason);
  - the minimum upgrade;
  - the level window and look-ahead;
  - spec armor rules;
  - set-bonus warnings;
  - tracked specs;
  - Appearance, with a preview.
- **Acceptance.**
  - Defaults as in PRD §5.
  - "Hiding a marker does not disable disenchant protection" is visible.
  - Changing a policy fires `EvaluationInvalidated`.
- **Refs.** mockups 04, G2.
- **Validation:** auto (settings → policy inputs), game.

### GG-113: Detailed comparison window (P2, MVP)

- **Outcome.** Candidate vs the selected spec's baseline:
  - stat deltas, scores, `pct` and the replaced item(s);
  - method, profile, source and baseline;
  - unsupported effects and set-bonus warnings;
  - "no equipment recorded" choices.
- **Refs.** mockup 08; adr/0003.
- **Validation:** game.

### GG-114: Public API v1 runtime (P1, MVP)

- **Outcome.** The async contract, complete:
  - LRU cache;
  - generation counters, including freshness;
  - 512-job and 64-request bounds;
  - `OVERLOADED`;
  - per-frame budget.
- **Acceptance.**
  - `test_api_contract`, extended with overload, budget and invalidation cases.
  - No roster scan on a tooltip redraw: measured with a redraw counter.
- **Refs.** API.md.
- **Validation:** auto.
- **Done.** `API/PublicAPI.lua`: requests subscribe to deduplicated jobs; LRU cache (2 000) keyed by
  instance or link, targets and context, stamped with a generation every invalidation advances;
  freshness checked on every hit; 200 rows per frame with `FRAME_BUDGET` placeholders and a deferred
  runner that keeps finished rows; 512-row and 64-request bounds. `test_api_runtime.lua` (56 checks:
  cache, LRU, invalidation, freshness, budget, dedupe, cancel, bounds, 25 tooltip redraws with no
  recomputation and no roster read). Answers stay correct only if every input change invalidates:
  P14 asks whether assigning a set to a spec fires `EQUIPMENT_SETS_CHANGED`.

### GG-115: Glass theme (P2, MVP)

- **Outcome.** With Glass UI following, Glass Gear's own windows and markers use LibGlass r11
  pearl. The WoW Forever look stays the default.
- **Scope.**
  - Ask once at `ADDON_LOADED`.
  - Report `declined` / `live = false`.
  - Keep the player's own appearance settings unchanged.
- **Deps.** GUI-001.
- **Acceptance.** Opt-in, opt-out and reload behave as Glass UI's SUITE.md says.
- **Refs.** adr/0004.
- **Validation:** auto (Theme decision: extend `test_load`), game.

### GG-116: Spike, transfer rules (P0, SPIKE)

- **Outcome.** We know, measured on Forever:
  - whether a BoE can be mailed to a same-realm, same-faction alt, and to the other WoW account;
  - cross-faction and connected realms;
  - account-bound kinds.
- **Scope.** Probe P5. Update `ItemContext.Transfer` and remove `proposed`.
- **Validation:** game, then auto.

### GG-117: Level window (P1, MVP)

- **Outcome.** "Level-appropriate upgrades only" (default on), with a look-ahead of N levels.
  Within the window: "+x% at level N (in k levels)", with no marker. Above it: not presented.
- **Scope.**
  - The engine is done (`test_evaluate`).
  - UI rows (GG-107, GG-112).
  - Per recipient: an alt uses its own level.
  - Protection keeps in-window items.
- **Validation:** auto (done), game (P11).

### GG-118: Armor eligibility (P0, MVP)

- **Outcome.** A class never sees an item it can't wear or wield as an upgrade. Each spec has its
  own allowed armor types (Protection Paladin plate, Holy Paladin cloth to plate…), editable per
  profile.
- **Scope.**
  - The engine is done (`Data/Classes.lua`, `test_evaluate`).
  - Runtime known skills (`Compat.KnownArmor`) after P9.
  - Armor set editor in GG-105.
  - A single grey "can't use" tooltip line when every spec fails the class gate.
- **Validation:** auto (done), game (P9).

### GG-119: Set-bonus awareness (P1, MVP)

- **Outcome.** Tooltips and the comparison warn "Completes 2-piece bonus" / "Breaks 3-piece
  bonus". The bonus is never silently scored.
- **Scope.**
  - Fetch `ItemSet` / `ItemSetSpell` with the wago-tools skill.
  - Generate `Data/ItemSets.lua`.
  - The engine is done (`Engine/SetBonus.lua`, `test_evaluate`).
- **Validation:** auto, game (P10).
- **Done (auto), game P10.** `Tools/gen_item_sets.py` → `Data/ItemSets.lua` (build 1.60.1.70753,
  545 sets). A set newer than the generated build still reports `SET_BONUS_NOT_SCORED`. For a new
  build: `wago.py get ItemSet ItemSetSpell`, then re-run the generator.

## M2: AltStable profiles, roster and the two-account flow

The upstream items (EXT) are detailed in INTEGRATION-GAPS.md. adr/0001 was amended on 2026-11-01
(#36): spike AS-S1 chose extraction, so profile and baseline sync moved from AltStable to a shared
entry-sync library (ES-001). AltStable keeps the roster, provenance and gear.

| ID | P | Class | Repo | Outcome |
|---|---|---|---|---|
| AS-001 | P0 | EXT | AltStable | **Done** (AltStable #282): per-character provenance `self` / `own-account` / `third-party`, own-account channel, feature flags |
| AS-002 | — | — | — | **Moved** to ES-001 |
| AS-003 | P0 | EXT | AltStable | **Done** (#283): public gear read API (item strings with suffix, per-slot completeness), `GearChanged`, gear-change stamp |
| ASS-001 | P0 | EXT | AltStableSync | Extract Link's entry sync into the shared library; Link stays wire-compatible during the migration |
| ES-001 | P0 | EXT | new library (repo and name TBD) | Shared entry-sync library on LibAccountSync: manifests, pull, own ack/retry, 16 KB batches, byte-sized timeouts, `too-large`, inventory |

### GG-201: AltStable roster provider (P0, MVP)

- **Outcome.** Own characters from both accounts are discoverable, with provenance, level, class,
  realm and faction.
- **Scope.** `RosterProvider` adapter; version and feature detection (the existing
  `DetectAltStable`, which checks `AltStable.PUBLIC_API_FEATURES.provenance` and `.gear` with their
  functions).
- **Deps.** AS-001 (done), AS-003 (done).
- **Acceptance.**
  - Without AltStable, or with an older one: `/gg` and the API say exactly what is missing.
  - A third-party character is never listed as a recipient.
- **Validation:** auto (`DetectAltStable` fixtures), game (two accounts).
- **Done (auto).** `Integrations/RosterProvider.lua`: `Attach` at login follows AltStable's
  `CharactersChanged` / `ProvenanceChanged` (snapshot rebuilt; `RosterChanged` + an invalidation only
  when it changed) and `GearChanged` (→ `EquipmentChanged`). Only `self` / `own-account`; the current
  character from Glass Gear itself. `GetSpecs` answers for an own alt. `/gg` counts them, or says
  exactly what is missing. `test_roster.lua` (34 checks), against a fake built from AltStable's
  docs/PUBLIC-API.md.

### GG-202: Entry sync over the shared library (ES-001) (P0, MVP)

- **Outcome.** Weight profiles and baselines authored on either account are available on the
  other. This works without AltStable; alts still need it (GG-201, GG-203).
- **Scope.**
  - Embed and pin the ES-001 library; map it onto `Engine/EntrySync` and `Engine/Codec`.
  - Glass Gear's own LibAccountSync instance with a derived, permanent tag (for example
    `GlassGearES`) on its own account-wide store getter. Check `inst.messages == true`; otherwise
    sync reports unavailable.
  - Manifests and inventory in `GlassGearDB`, never in the accountSync store table.
  - The sync on/off switch in settings (the control in place of AltStable's refusals; adr/0001,
    refusals). It flips every tag on the store together.
  - `maybeBehind` from manifests.
  - Conflict-copy UI in Profiles ("Keep this / Keep mine").
- **Deps.** ES-001 (not AltStable).
- **Acceptance.**
  - The `test_entry_sync` fixtures pass against the real library adapter.
  - Turning sync off stops sending and receiving on Glass Gear's instance.
  - An edit on account 2 shows on account 1 after exchange.
  - A conflict shows both versions.
- **Validation:** auto, game (two accounts).

### GG-203: Alt rows and transfer eligibility (P0, MVP)

- **Outcome.** A transferable item's tooltip lists eligible alts (character · spec · account ·
  replaced item · estimate); the bag marker is amber.
- **Scope.**
  - `ItemContext.Transfer` (after GG-116).
  - `Policy.TooltipRows` and `Marker` with alts.
  - Protection scope includes tracked alts.
- **Deps.** GG-201, GG-202, GG-116.
- **Acceptance.**
  - Soulbound items never list alts.
  - "Synced" never implies "transferable".
  - Cross-account ownership comes from provenance, never the `account` label.
- **Refs.** mockup 03.
- **Validation:** auto, game.

### GG-204: Characters page (P1, MVP)

- **Outcome.** The owner picks tracked characters and specs across both accounts.
- **Scope.**
  - Freshness: fresh, stale or `maybeBehind`.
  - "No weights".
  - An "AltStable unavailable" state.
  - "Open AltStable", with no duplicate pairing UI.
- **Refs.** mockup 06.
- **Validation:** game.

## M3: Shatter protection

| ID | P | Class | Repo | Outcome |
|---|---|---|---|---|
| SH-001 | P0 | EXT | Shatter | `Integrations/GlassGear.lua` and a check in `IsCandidateDisenchantable` (Solo); verdict table, fail-closed; rescan on `EvaluationInvalidated` |
| SH-002 | P0 | EXT | Shatter | Excluded rows stay listed with their reason. A per-row "Disenchant anyway" uses `{guid, token}`, is session-scoped, and expires at `expiresAt` or on any change. Mail Mode is unchanged |

### GG-301: AssessProtection runtime (P0, MVP)

- **Outcome.** A synchronous, bounded protection verdict over the protection scope.
- **Scope.**
  - `Policy.Protection`.
  - Token: GUID plus generation counters plus the freshness generation.
  - `expiresAt` re-checked on every call.
  - `features.assessProtection = true`.
- **Acceptance.**
  - Protection despite hidden arrows (already pure-tested).
  - Stale or fallback baselines never give `clear`.
  - The token changes when a baseline goes stale without any other event.
- **Refs.** API.md; mockups 07, G4.
- **Validation:** auto, game with Shatter (P8).

## M4: Compatibility, performance, localisation, release

| ID | P | Class | Repo | Outcome / acceptance |
|---|---|---|---|---|
| GUI-001 | P1 | EXT | GlassUI | GlassGear added to `Suite.ROSTER` as `dynamic`. Its card appears only while it is loaded |
| GG-401 | P2 | MVP | GlassGear | Baganator/Bagnon marker adapters; until then `/gg` reports "bag replacement: markers unavailable" |
| GG-402 | P1 | MVP | GlassGear | Performance: tooltip redraw does no recomputation (cache hit). Bag refresh stays within the per-frame budget. Measured |
| GG-403 | P2 | MVP | GlassGear | Localisation: move strings to an `L` table. All comparisons are already locale-independent |
| GG-404 | P1 | MVP | GlassGear | Release: CurseForge and Wago projects; `X-Curse-Project-ID` / `X-Wago-ID` in the TOC (the CI `wago` job needs it); `WAGO_API_TOKEN` secret; first `v0.1.0-alpha1` per RELEASING.md |

## M5: Future (Companion simulations, Gear Lab)

| ID | P | Class | Repo | Outcome |
|---|---|---|---|---|
| GG-501 | P2 | FUT | GlassGear | Gear Lab planner (Rawr-style): plan loadouts across bags and bank; clearly labelled estimates (mockup 09) |
| GG-502 | P2 | FUT | GlassGear | Import external results (`sim-result` provenance; simc scale factors / Pawn output) |
| ASC-001 | P2 | FUT | AltStableCompanion | Research: run external sims (simc-forever / a Forever WoWSims) from SavedVariables requests; results imported on reload |

## Acceptance traceability

| Owner acceptance case | Covered by | Validation |
|---|---|---|
| Current-spec vs off-spec marker behaviour | `test_policy` (soulbound and transferable cases); GG-109 | auto + game |
| Modifier press and release | `test_policy` (reveal state machine incl. typing, None); GG-110 | auto + game (P7) |
| Green precedence | `test_policy` (green over amber, revealed or not) | auto |
| BoE becoming soulbound | `test_policy` (bound flips → alt amber gone); `test_item_context`; GG-109 | auto + game (P8) |
| Cross-account ownership vs transfer eligibility | `test_item_context` (third-party, realm, faction, account-bound unknown); `test_policy` (ineligible or third-party alt → no marker); GG-116, GG-203 | auto + game (P5) |
| Saved off-spec equipment and unavailable baselines | `test_evaluate` (precedence, missing slot data → unknown, stale/fallback reasons); GG-108 | auto + game |
| Unknown or pending item data | `test_evaluate` (pending), `test_api_contract` (pending → `EvaluationReady`, timeout → `ITEM_DATA_UNAVAILABLE`) | auto + game (P4) |
| Dependency absence and incompatible API versions | `test_load` (no AltStable, no Glass UI, newer schema → read-only); `test_api_contract` (capabilities/unavailable); `RosterProvider.DetectAltStable`; GG-201 | auto |
| Default theme and Glass UI opt-in/opt-out | `test_load` (forever without Glass UI); GG-115 + GUI-001 | auto + game |
| Shatter protection despite hidden off-spec arrows | `test_policy` ("off-spec upgrade protects although its arrow is hidden"); GG-301, SH-001 | auto + game |
| Queue changes, stale assessments, manual overrides | `test_policy` (stale/fallback/effects → unknown); API token and `expiresAt` contract; GG-301, SH-001, SH-002 | auto + game |
| Missing weights shown as unavailable | `test_evaluate`, `test_policy` (rows "no weights"; protection unchecked) | auto |
| Level window, armor types, set bonuses (owner, 2026-11-01) | `test_evaluate` (window, class gate, spec armor, set gained/lost); GG-117/118/119 | auto + game (P9–P11) |
| Sync conflicts, replays, resets, `maybeBehind` | `test_entry_sync` | auto |
