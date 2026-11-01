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

### GG-106: Research, default weights (P2, SPIKE)

- **Outcome.** A licence-clean default weight source per spec, or the decision to ship none.
- **Scope.** Pawn's scales are CC BY-NC-ND and can't be copied. WoWSims tbc-new presets are TBC
  level 70. Evaluate community sources and the owner's own sims.
- **Acceptance.** A recommendation with licence notes, written down.
- **Validation:** n/a.

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
  - Capture on login, `PLAYER_EQUIPMENT_CHANGED` and spec change, storing links so the suffix is
    kept.
  - Equipment-set mapping per spec.
  - Baseline entries in `EntrySync`.
  - Freshness and `expiresAt`.
  - Companion off-hand from baseline or bags.
  - Owned better items in bags as an optional source.
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

## M2: AltStable profiles, roster and the two-account flow

The AltStable items (EXT) are detailed in INTEGRATION-GAPS.md. AS-001 **blocks** M2.

| ID | P | Class | Repo | Outcome |
|---|---|---|---|---|
| AS-001 | P0 | EXT | AltStable | Own-account-only channel; per-character provenance `self` / `own-account` / `third-party`, enforced before callbacks |
| AS-002 | P0 | EXT | AltStable | Namespaced own-account entry-sync service (manifests, pull, timers, size checks, `too-large`). Spike AS-S1: host it in AltStable, or extract AltStableSync Link |
| AS-003 | P0 | EXT | AltStable | Public gear read API (item strings with suffix, per-slot completeness), `GearChanged`, gear-change stamp |
| ASS-001 | P2 | SPIKE | AltStableSync | Extract Link's protocol into a shared module, only if AS-S1 picks extraction |

### GG-201: AltStable roster provider (P0, MVP)

- **Outcome.** Own characters from both accounts are discoverable, with provenance, level, class,
  realm and faction.
- **Scope.** `RosterProvider` adapter; version and feature detection (the existing
  `DetectAltStable`).
- **Deps.** AS-001, AS-003.
- **Acceptance.**
  - Without AltStable, or with an older one: `/gg` and the API say exactly what is missing.
  - A third-party character is never listed as a recipient.
- **Validation:** auto (`DetectAltStable` fixtures), game (two accounts).

### GG-202: Entry sync over AS-002 (P0, MVP)

- **Outcome.** Weight profiles and baselines authored on either account are available on the
  other.
- **Scope.**
  - Map AS-002 onto `Engine/EntrySync` and `Engine/Codec`.
  - `maybeBehind` from manifests.
  - Conflict-copy UI in Profiles ("Keep this / Keep mine").
- **Deps.** AS-002.
- **Acceptance.**
  - The `test_entry_sync` fixtures pass against the real service adapter.
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
