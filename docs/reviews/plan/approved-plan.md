# Glass Gear — foundation, contracts & design (plan)

## Context

The owner wants a standalone Pawn replacement for WoW Forever (Interface 16001, newest dump
`forever-api-1.60.1.70532`) whose central UX rule is: **tooltips show all of my character's specs,
ordinary bag arrows stay on my current spec**, with alt upgrades (via AltStable, across two WoW
accounts), disenchant protection (via Shatter), and two looks (native WoW Forever / Glass via
LibGlass + Glass UI). This session delivers the **foundation**: a new repo with a working scaffold,
the implemented pure-Lua core (weights, Pawn strings, scoring, policies, API skeleton) with tests,
the full design/contract docs, the imported mockups (+ imagegen for the gaps only), an issue-ready
backlog, and cross-repo issues. Product features beyond that become backlog items.

`C:\Projects\WoW\GlassGear` is an empty folder inside the root `wow-dev-tools` repo. Game is offline
until 2026-11-04 (memory), so all client behaviour is queued for in-game validation, never claimed.

Owner decisions (asked this session): local git + **private** GitHub `Spotnick2/GlassGear`, work via
issue + PR; mockups = owner's images in `Downloads\GlassGear` (do **not** regenerate); generate
**only gap** images with Codex imagegen.

## Verified ecosystem facts that drive the design (sources go into docs/ECOSYSTEM-FINDINGS.md)

| Area | Verified (repo @ commit) | Consequence |
|---|---|---|
| Specs on Forever | No `GetSpecialization`; `C_SpecializationInfo.GetActiveSpecGroup`, `GetNumSpecGroups` exist; talent trees via `C_Traits` (`Blizzard_ClassTalentsFrame.lua:107-161`, wow-ui-source forever ca8368f2f). `ChrSpecialization` = one row per class. AltStableSync measured `GetNumSpecGroups()=1` (no dual spec bought). PORTING:1052 "unprobed". | Glass Gear owns a **spec model**: stable keys per class tree (`PRIEST.SHADOW`…, plus Feral tank/cat). "Current spec" = active spec group → mapped tree (auto by most points **once probed**, else manual mapping). |
| Item APIs | `C_Item.GetItemStats/GetItemInfo/GetItemInfoInstant/IsBound(ItemLocation)/IsItemBindToAccount*/GetItemUniqueness/GetItemSpell/IsEquippableItem`, `C_TooltipInfo`, `ITEM_DATA_LOAD_RESULT`, `MODIFIER_STATE_CHANGED`, `C_EquipmentSet` in 70532 dump. `GetItemStats` returns nothing on cache miss. No gems/sockets on Forever. | Locale-independent stat read via `GetItemStats` (ITEM_MOD_* keys), no tooltip-text parsing. Pending state is first-class. |
| Tooltip hook | `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, …)`; `HookScript("OnTooltipSetItem")` throws (PORTING:979-990). Models: `Shatter/Tooltip.lua:107-158`, `GlassPearls/Pearls/JunkSpot.lua:67-101`. | Lines only; never restyle GameTooltip (Glass UI #147 owns that). |
| Bag overlays | `GlassPearls/Core/BagMarks.lua` (hooksecurefunc `UpdateItems`, child frames, combat deferral). Glass UI bag skin draws wells at level−1. | Re-implement same pattern in Glass Gear (no dependency on GlassPearls). |
| Modifiers | Bindings_Camelot.xml:1533-1552: Ctrl = DRESSUP click, STICKYCAMERA; Shift = COMPAREITEMS/EXPANDTOOLTIP; Alt = SELFCAST/flyout. Ctrl-hover only changes cursor. | **Ctrl-hold** default is safe (we never consume clicks); Shift not offered as default. |
| AltStable (c89cf44, v0.17.0-beta1) | Public API v1: `GetCharacters()` identity only (guid,name,realm,faction,class,level,account,lastUpdate,…), callbacks `CharactersChanged`/`PortraitStatusChanged`. Gear snapshot is internal (`AltStableDB`, 17 slots id/enchant, **no link → no random suffix** synced). No spec, no equipment sets, no weights. Plugin `RegisterPlugin` (undocumented, needs sidebar tab; `OnSerialize/OnDeserialize`, `independentStamp`, `TouchCharacter`; peer drops blobs of unknown plugins). Ownership: user-typed `account`, local `scannedHere`, session-only `LibSync.Peer`. | Alt features need **AltStable extensions** (public gear read, ownership, headless plugin channel). Glass Gear owns per-spec baselines + profiles and ships them through the plugin channel. |
| LibAccountSync (ea0c0e8, tag r5; MINOR 6 untagged) | Same Battle.net account only, 32 KB max payload, snapshot/messages modes, BNSendGameData. | Two WoW accounts on one Battle.net are covered by AltStable's existing route. |
| AltStableCompanion (0f0718a, v0.1.1) / AltStableSync (e5b1b75, v1.0.0) | Companion = .NET tray app (portraits via SavedVariables). No simulation anywhere. | Gear Lab / sims = **future**, needs new Companion work. |
| Shatter (0ce809d, v1.0.0-beta1) | No external veto API. `ItemScanner:IsCandidateDisenchantable` (`ItemScanner.lua:75-97`) is used by queue build **and** click-time `Disenchant:ValidateItem` (`:183`). No rescan on `PLAYER_EQUIPMENT_CHANGED`. Mail items sender-owned, `PrepareDisenchantQueue` uses only `CanBeDisenchanted`. Integration precedent: `Integrations/*`, `GlassMailSelection()`. | Shatter-side `Integrations/GlassGear.lua` + one check in `IsCandidateDisenchantable` (Solo only), fail-closed. Mail Mode untouched. |
| LibGlass (e2b9062, **r11**) / Glass UI (b78b244) | `New{preset="pearl"}`; consumers pin `tag: r11`; no tooltip skin. Glass UI `Suite.ROSTER` fixed — unknown addons get `"unknown"`; follow opt-out saved by Glass UI; reload to switch. | Pin LibGlass r11. Glass UI PR to add GlassGear as dynamic member. Default look = WoW Forever. |
| Pawn 2.14.0 Forever (Downloads zip; CC BY-NC-ND → behaviour only) | Scale tag grammar; % = (new−best)/best for the slot, >0.5% threshold; rings vs weaker; trinkets skipped; 2H vs 1H skip; no unique handling. | Pawn-compatible string I/O + Pawn-compatible upgrade % definition (documented, labelled estimate). |
| WoWSims (local `wowsims/tbc-new` 8aa378b3, level 70) | "Pawn EP" export is a Pawn string (drops hit/crit/haste etc.). Importer JSON = WowSimsExporter. No Forever sim locally. | Pawn EP strings importable (provenance `wowsims-pawn-ep`, warn on dropped stats); character JSON unsupported (not weights). |
| SimulationCraft addon 12.1.5-03 zip | `## Interface: 120100, 120105, 16001` — **does** target Forever; exports simc profile (`spec=unknown` on Forever, `legacy_talents=`, gear lines). | Profile ≠ weights; needs external simc `calculate_scale_factors`. Only simc **scale-factor/Pawn output** importable later. |

## Key decisions (become ADRs in docs/adr/)

1. **ADR-0001 Sync ownership → AltStable-owned sync behind a provider interface.** Glass Gear owns
   profile authoring, per-spec baselines and evaluation; AltStable owns roster, snapshots and
   cross-account transport. Glass Gear defines an internal `RosterProvider` interface (local-only
   provider always present; AltStable provider when AltStable ≥ required API). No second roster
   sync; direct LibAccountSync rejected for MVP (no demonstrated need: LAS is same-Battle.net only,
   identical to AltStable's route). Revisit trigger: "alts without AltStable" becomes a requirement.
   **Trust boundary (Codex R1 blocker):** AltStable's plugin hooks carry no destination/sender
   (`Core.lua:843,888`) and ordinary replies go to whitelisted third parties too. So the required
   AltStable extension is an **own-account-only plugin channel**: outbound restricted to
   LibAccountSync-proven own accounts, inbound accepted only from them, enforced *before* plugin
   callbacks, with validated per-character ownership provenance (`self` = scanned here, `own-account`
   = first-hand from a proven own-account peer, else `third-party`) handed to consumers. Glass Gear
   never infers ownership from `account` labels, a received `ownerGuid`, or roster membership; until
   the extension ships, alt features are reported unavailable (not degraded).
   **Protocol = AltStableSync's per-entry model, reused** (`AltStableSync/docs/DESIGN.md:913-973`,
   measured and shipped in v1.0.0), not a bespoke snapshot protocol (rounds R2–R7 showed whole-
   snapshot/section schemes keep leaking edge cases). Units of sync are **entries**, each with a
   stable id: one per weight profile (`<guid>:<specKey>:<uuid>`) and one per spec baseline
   (`<guid>:<specKey>:baseline`). Each entry version is `<writer>:<seq>` where `writer` is a **fresh
   in-memory token minted at every successful initialisation** and `seq` a session counter
   (AltStableSync `DESIGN.md:222`), so a copied or restored SavedVariables can never reuse a version;
   incoming ids/versions are stored unchanged. Each version carries its last 20 `ancestors`. Only a client logged in as that
   GUID edits that character's entries (UI rule); several installations may, and conflicts are
   handled per entry. **Receive rules per entry, idempotent** (copied from DESIGN.md:918-928): same
   version → ignore; live conflict copy whose version the root holds or passed → ignore; incoming in
   local ancestors → ignore; local in incoming ancestors or unknown id → replace (fast-forward);
   otherwise divergent → keep local, store incoming **whole** as conflict copy `<id>~<version>`,
   ignored if that copy id already exists **live or tombstoned** (durable: an already-recorded copy
   never comes back; a version that aged out of 20-deep ancestry without a recorded copy can produce
   **one** conservative conflict copy, as DESIGN.md:924 accepts — never a root change); wrong
   type/validator failure → reject; unknown/newer schema →
   reject. **No field merging, ever.** Resolution (Keep this / Keep mine) mints a version whose
   ancestors hold **both** competing versions first, then both histories, and retires matching
   copies with tombstones (DESIGN.md:930-939). **Delete = versioned tombstone kept indefinitely**
   (tiny); deletion conflicts and the incomparable-tombstone lexical tie-break follow DESIGN.md:
   940-951,960-964. **Omission never means deletion** — an entry not sent (overflow, shedding, peer
   without GG) is simply not yet delivered and stays "pending" on the sender. "Confirmed" = a peer's
   manifest lists exactly our `{id, version}`. Root versions are minted only by local edits and
   explicit resolutions; the **one receive-side mint** is retiring covered conflict copies after a
   fast-forward to a resolution (as AltStableSync `Catalog.lua:542,580,89` does; repeated retirement
   is a no-op; no receive-triggered `TouchCharacter` or immediate send). All edits and conflict
   actions take an **expected version** and refuse when stale (DESIGN.md:969-971). Remote entries
   live in `GlassGearDB.entries` beside local ones (provenance recorded); AltStable forget → drop
   that GUID's entries locally; unforget → normal fast-forward.
   **Transport = a manifest-based entry-sync service, not the character-record plugin blob** (R8:
   the blob path has no delivery, acknowledgement or inventory — `TouchCharacter` only sets
   `lastUpdate` `Core.lua:1204`, the 300 s throttle only rejects `Core.lua:2215`, replies filter by
   account `Core.lua:1915`). Required AltStable extension (keeps the owner's "AltStable owns
   distribution" preference): a **namespaced own-account entry-sync service** that a consumer
   registers headlessly (`namespace`, validator, size limits), modelled on and ideally extracted from
   AltStableSync Link (`DESIGN.md:850-911`): per-namespace manifests `{id → version}` exchanged on
   peer sighting, after coalesced local writes, on a bounded timer while a peer is linked and on
   manual refresh; per-peer pull of differing ids (≤ 3 outstanding, 30 s timeout, re-queue);
   batches shrink until they fit; oversized single entry → `too-large`, stays local, reported;
   receipts never trigger exchanges; own-account trust enforced before delivery. The manifest is the
   **inventory**: a receiver knows exactly which of a GUID's entry versions it lacks, so targets
   whose relevant entries (that character's profiles/baselines) differ from the peer's manifest are
   `maybeBehind` (displayed stale, never `clear` for protection) until the manifests match.
   Whether AltStable hosts this itself or delegates to an extracted shared module is an AltStable
   design decision (spike AS-S1); Glass Gear depends only on the service contract.
   **Codec & budget:** each entry single-line, versioned (`GG1|…`); weights fixed 3-decimal in
   [-999.999, 999.999] (+ Pawn `X` = ignore); profile name ≤ 24 chars, ≤ 40 tokens per profile, ≤ 4
   profiles per spec; baseline = ≤ 19 compact item strings (`id:enchant:suffix`) + per-slot
   occupancy + capturedAt. M0 fixtures compute the encoded maximum of one entry **including 20
   ancestors, ids, conflict metadata and escaping** and of full backfill **including tombstones** for
   50 characters; targets (≤ 2 KB per entry, < 24 KB per manifest exchange page) are design targets
   checked by fixtures, not guarantees.
   **M0 fixtures** (pure Lua, transport simulated): lag fast-forward; divergent → copy; copy replay
   after any delay (no-op); aged-out ancestry → at most one conservative copy; resolution
   convergence in both delivery orders incl. the asymmetric mirror-copy case + duplicate resolution
   delivery; tombstone vs edit both ways; incomparable tombstones; restored-SavedVariables writer
   (no version reuse); stale expected-version refused; multi-page manifest exchange where both
   sides then stay idle and every entry still arrives and confirms (lost ack, receiver with nothing
   pending); weight-only change pending → protection `unknown` (never `clear`) until manifests match;
   oversized entry → `too-large`.
   Imported weights sync; UI/display/policy settings never sync.
2. **ADR-0002 Spec model**: stable locale-independent keys per class tree (+ `DRUID.FERAL_TANK/CAT`);
   current spec = active spec group → manual mapping (always available) or, once probed, automatic
   via spec group → `GetCombatConfigIDForSpecGroup` → `C_Traits` group currency spent (wow-ui-source
   `Blizzard_ClassTalentsFrame.lua:107-161`); ties/unspent → `unknown-spec` state, never a guess.
3. **ADR-0003 Upgrade metric & configurations**: score = Σ weight × stat over **supported tokens**
   (published list; unknown tokens reported, not silently zero). Enchants: symmetric base-item
   comparison (strip enchant from candidate and baseline, keep suffix/unique fields, as Pawn
   as Pawn does). Comparison = **enumerate legal resulting configurations**
   (candidate into each compatible slot; displaced items removed; unique category limits from
   `GetItemUniqueness` re-checked on the result; 2H→1H needs an identified companion off-hand from the
   baseline/bags else `status=unknown, reason=NEEDS_OFFHAND`; 1H/OH→2H compares against MH+OH
   combined); best legal configuration wins and is returned (`replaces = {slots,items}`).
   `pct = (cand − base)/base` over the affected slots (Pawn-compatible); `EMPTY_SLOT` only for a
   confirmed, legal empty position (unknown occupancy → unknown); base ≤ 0 → pct nil. Items with
   equip/use/proc effects or set membership get `limitations` (`EFFECT_NOT_SCORED`, `SET_BONUS_NOT_SCORED`);
   "zero supported stats" ≠ "modelled zero". Labelled "item-score estimate"; absolute delta returned;
   recipients listed, never ranked across characters by %.
   **Baselines** (per character × spec): sources in precedence: (1) equipment set the owner mapped
   to the spec, (2) gear observed while that spec was active (captured by GG, with links), (3) current
   equipment scored with that spec's profile, labelled `fallback-current`. Per slot: `occupied/empty/
   unknown`, `itemString`, `capturedAt`, source. Staleness: `capturedAt` > 14 days ago, or the
   character's gear changed after capture (from the proposed AltStable gear-change stamp / GG's own
   `PLAYER_EQUIPMENT_CHANGED` — **not** `lastUpdate`, which plugin touches move, `PublicAPI.lua:125`).
   Incomplete/stale/fallback baselines may drive labelled display estimates, but can never make
   protection return `clear`. Likewise any `EFFECT_NOT_SCORED`/`SET_BONUS_NOT_SCORED` limitation, or
   a zero-supported-stat item, makes that recipient's protection result `unknown` (keep) unless the
   supported score alone is already an upgrade (→ `protect`).
4. **ADR-0004 Presentation boundary**: engine/policy emit view-models; `Theme` renders
   `forever` (default, Blizzard tooltip backdrop like Shatter `Skin.lua:79-91`) or `glass`
   (LibGlass r11 pearl, only via Glass UI follow, GlassPearls `Theme.lua` model). Tooltip = lines only.
5. **ADR-0005 Weight sources & provenance**: `imported-pawn`, `wowsims-pawn-ep`, `default`,
   `manual`, future `sim-result` (Companion). SimC profile / WoWSims JSON = unsupported as weights.
6. **ADR-0006 Policies are independent**: tooltip scope, marker scope, protection scope are three
   settings objects evaluated separately; protection never reads marker visibility.

## Behaviour spec highlights (docs/PRD.md + context matrix)

- Context matrix exactly as requested (loot / soulbound / transferable), plus: BoE that becomes
  bound re-evaluates as soulbound (instance `C_Item.IsBound`); loot surfaces use bindType (BoP →
  soulbound rules). Loot-marker policy: green current-spec only; Ctrl reveals amber own-spec; alts
  shown only for BoE loot (proposal, flagged for owner review).
- Marker predicate (one pure function, fully tested): **green** = current-spec upgrade (always wins).
  Otherwise **amber** when (a) reveal active and own off-spec upgrade, or (b) item is a
  **transferable bag instance** with an own off-spec or eligible-own-alt upgrade and "Mark
  transferable upgrades" is on (**default on — this is the owner's matrix row 3**, not a
  reveal-gated case), or (c) reveal active and eligible-own-alt upgrade on a transferable item.
  Soulbound off-spec is amber **only** while revealed; soulbound never shows alts. Loot surfaces:
  green current spec; reveal → amber own off-spec; BoE loot alts only while revealed (proposal for
  owner review). Modifier `None` → no reveal. Symbols: green filled double chevron vs amber outlined
  chevron (shape differs, not colour only) + tooltip legend line.
- Reveal: effective state = `modifier down (either side) and GetCurrentKeyBoardFocus() == nil`,
  **recomputed** on `MODIFIER_STATE_CHANGED`, on every reveal-surface show (bags, loot, roll frames),
  and by a 0.1 s `OnUpdate` poll that runs **only while any reveal surface is visible** and refreshes
  only when the computed state changes (the poll observes focus; it does not rely on edit-box
  scripts) — so a release or focus change while typing always reconciles. Never
  consumes clicks (Ctrl-click DRESSUP keeps working — coexistence, not "conflict-free"). Overlays are
  preallocated for visible buttons out of combat; a button first seen in combat gets its marker after
  `PLAYER_REGEN_ENABLED` (documented). No saved-setting change, no reload. Open tooltips refresh with
  Shatter's guards (`Tooltip.lua:120-139`: identity, `IsForbidden`, owner). Bag replacements
  (Baganator/Bagnon): reported unavailable until an adapter exists (M4).
- Missing weights → row "no weights" (grey), never 0 / "no upgrade".
- Eligibility: class proficiency table, required level (scored + `LATER_LEVEL`), unique (configuration
  enumeration above). **Binding classification first** (bag instance: `C_Item.IsBound(loc)` +
  `IsBoundToAccountUntilEquip`; hypothetical link from loot/purchase: bindType only, instance state
  `unknown`), then **transfer = tri-state** `eligible | ineligible | unknown` with reasons: character-
  bound → ineligible; unbound BoE → eligible only to `self`/`own-account` provenance characters on same
  realm + faction (**proposed until probed**: mail rules, cross-faction, connected realms); account-
  bound kinds → `unknown` until probed and until a trustworthy WoW-account identity exists (the
  `account` label is not one). "Synced" ≠ "transferable".
- Shatter verdict table (protection on): `protect` → keep, reason "Potential upgrade: N specs";
  `unknown`/`pending`/`unsupported`/malformed/exception/incompatible API version → **keep**, reason
  "Glass Gear can't confirm yet" (fail-closed); `clear` → normal rules; Glass Gear absent → Shatter
  behaves exactly as today (settings line says "Glass Gear not installed"); protection disabled in
  Shatter → skip. `AssessProtection` is **synchronous and bounded** (only the tracked protection
  targets; never deferred): it returns a freshly validated verdict or fail-closed `pending`/`unknown`,
  and background completion only fires `EvaluationInvalidated` → Shatter rescans. It returns an opaque
  `token` (hash of instance GUID + generation counters, including a **freshness generation**) and
  `expiresAt` = earliest baseline staleness time. Every query re-checks expiry synchronously; a
  freshness transition bumps the freshness generation **before** returning (so the token changes)
  and then queues `EvaluationInvalidated`. Shatter additionally rejects a stored override once
  `now ≥ expiresAt`, independent of any timer. Shatter resolves the current instance GUID (`C_Item.GetItemGUID`) —
  no GUID → no override. "Disenchant anyway" = per-row action in Shatter's list (excluded rows stay
  listed, greyed) recording `{guid, token}` for the session; it bypasses **only** the Glass Gear veto;
  any token/GUID mismatch, bag move, or GG invalidation clears it. Check is synchronous, `pcall`-
  wrapped, inside `IsCandidateDisenchantable` (covers `ScanBags:190` and click-time `ValidateItem:183`);
  failure leaves the button disarmed; nothing arms from async callbacks. GG invalidation →
  `SoloMode:ScheduleScan`. Mail Mode unchanged (sender-owned items, no GG assessment).

## Public API v1 (docs/API.md; proposals, AltStable callback idiom)

`GlassGear.API` (`API_VERSION = 1`, additive minors via `GetCapabilities().features`):
`GetCapabilities()`, `IsReady()`, `GetCharacters()`, `GetSpecs(charKey)`, `GetProfile(charKey,
specKey)`, `Evaluate(request)`, `EvaluateBatch(requests)`, `CancelRequest(requestId)`,
`AssessProtection(itemRef, opts)`, `RegisterCallback(event, fn, owner)` / `UnregisterCallback` —
events `Ready`, `ProfilesChanged`, `EquipmentChanged`, `RosterChanged`, `EvaluationInvalidated`,
`EvaluationReady`, `ItemDataReady`. Request:
`{item = link|ItemLocation|{bag,slot}, context = "tooltip"|"bags"|"loot"|"purchase"|"protection",
scope = "current"|"own"|"tracked"|"targets", targets = {{char=key, spec=key},…}}`.
Response = `{requestId, status (aggregate), results = {…}}` with **one result per (character, spec)**,
ordered current spec → own specs (tree order) → alts (owner's tracked order); never ranked by %.
Per result: `{status = upgrade|no_upgrade|ineligible|unknown|pending|unsupported, character{key,
name,realm,provenance}, spec, profile{id,source,rev,updatedAt}, candidate{itemString,instance},
baseline{source,slots,capturedAt,complete,stale}, replaces, score{candidate,baseline,delta,pct},
method="weights-linear", eligibility{equipNow,reasons}, transfer{state,reasons}, reasons[],
limitations[]}`. `AssessProtection` → separate shape `{verdict, token, expiresAt, recipients[],
reasons[]}`.
Lifecycle: the table exists after file load (`API_VERSION` major check + `GetCapabilities().features`
for each operation; unsupported scopes/ops return `status=unsupported`, never silently narrowed);
data readiness via `IsReady()` + `Ready` callback (fires once after `PLAYER_LOGIN` + spec/profile
load). **Async contract:** `Evaluate`/`EvaluateBatch` always return synchronously with every
result present — computed ones, or placeholders `status=pending` (item data missing or over the
per-frame budget). When a request's placeholders resolve, `EvaluationReady{requestId, response}`
fires once with the **complete response (deep copy)**, so nothing depends on cache retention;
re-calling is optional. Global bounds on deferred work: ≤ 512 outstanding computation jobs
(deduplicated by contextual cache key across requests) and ≤ 64 outstanding requests; beyond that
the call returns immediately with placeholders `status=unknown, reason=OVERLOADED` (terminal for
that call, no callback). `CancelRequest(requestId)` drops a subscription. LRU cache 2,000 entries is
an optimisation only. Aggregate status precedence (display only — protection aggregates its own
verdict, a display aggregate is never a `clear`): any `upgrade` →
upgrade; else any `pending` → pending; else any `unknown` → unknown; else any `no_upgrade` →
no_upgrade; else any `ineligible` → ineligible; else unsupported. Bounds: ≤ 32 targets per request,
≤ 64 items per batch, ≤ 200 evaluations/frame, item-load queue ≤ 256 unique itemIDs (overflow →
`unknown, ITEM_QUEUE_FULL`), one load per itemID (deduped), 5 s timeout × 3 attempts then
`unknown, ITEM_DATA_UNAVAILABLE`; `ItemDataReady{itemIDs}` coalesced per frame. Callbacks:
next-frame batched, `xpcall`, no reentrant dispatch (AltStable `PublicAPI.lua:155-194` idiom). All
returns deep copies. Caching: immutable layer (itemString → stats, keyed with suffix, enchant
stripped) separate from contextual results keyed by (item instance identity or link, character,
spec, context) + generation counters {profiles, baselines, spec mapping, roster/provenance, policy
settings, item-data, bind-state} + `expiresAt` (baseline staleness); protection always re-reads
instance binding, GUID and expiry. Nothing scans the roster on tooltip redraw.

## Files to create (repo `C:\Projects\WoW\GlassGear`, mirroring Shatter/GlassPearls conventions)

- Root: `GlassGear.toc` (Interface 16001, `@project-version@`, `## Category: |cff7fd4ffGlass|r`,
  `OptionalDeps: AltStable, GlassUI`, `SavedVariables: GlassGearDB`, `SavedVariablesPerCharacter: GlassGearChar`,
  LibGlass xml first), `.pkgmeta` (LibGlass `tag: r11` + repeated ignores), `.gitignore` (`Libs/`),
  `README.md`, `CLAUDE.md` (+ "Consulting Codex"), `AGENTS.md`, `CHANGELOG.md`, `LICENSE` (MIT).
- `Core/` Init (namespace, `MEASURED_ON_BUILD="70532"`), Callbacks, Compat (API adapter), DB (schema v1 + migration hook).
- `Data/` Stats (ITEM_MOD ↔ Pawn names), Classes (trees, proficiencies), Slots (INVTYPE → slots).
- `Engine/` Score (pure), SlotCompare (rings/trinkets/2H/unique), Evaluate (status/reason codes), Policy (marker/tooltip/protection, reveal).
- `Profiles/` Profiles (per char/spec, provenance), PawnString (parse/export, WoWSims EP detection).
- `Item/ItemContext.lua` (instance vs link, bind state, transfer rules), `Character/Spec.lua`, `Character/Baselines.lua`.
- `Integrations/` RosterProvider (local + AltStable capability detection, gaps stubbed as "unavailable"), GlassUI (suite ask/report).
- `Presentation/Theme.lua` (forever + glass), `UI/Diagnostics.lua` (`/glassgear` + `/gg diag`: build, API version, current spec mapping, deps detected, profile counts) + Blizzard Settings category stub page.
- `API/PublicAPI.lua` (v1 skeleton: capabilities, specs, profiles, Evaluate for current character with pending handling, AssessProtection returning `unsupported` until GG items land).
- `tests/` run.ps1 (Shatter pattern, Lua 5.1), wow_stubs.lua (only dump-verified names), harness.lua, fixtures, tests: pawn_string, score, slot_compare, policy (green precedence, reveal, soulbound-never-alt, protection independent of markers), evaluate statuses (pending/unknown/no-weights), api_contract (shape, version gating).
- `Tools/deploy.ps1` (Shatter/GlassPearls pattern, `_forever_` default, LibGlass from `..\LibGlass`), `Tools/LibGlassPin.ps1`.
- `.github/workflows/package-check.yml` from `References/Docs/release/` template.
- `docs/` PRD.md, ARCHITECTURE.md, adr/0001–0006, API.md (+ consumer examples incl. Shatter), SCHEMA.md
  (SavedVariables + sync record + migrations), FORMATS.md (Pawn/WoWSims/SimC support table),
  ECOSYSTEM-FINDINGS.md (paths, commits, verified vs proposed), INTEGRATION-GAPS.md, BACKLOG.md,
  FOREVER-PROBE.md (queued in-game checks), mockups/.

## Mockups (docs/mockups/)

Copy the 14 owner images (renamed `NN-<state>.png`, superseded ones under `superseded/`), plus the
logo as `icon-source.png`. `docs/mockups/README.md` = screen/state inventory → image, theme, backlog
IDs, implementation notes, known defects (03 "Stanlina", 05 "Intellec=", 06/old Level 80, 07-old
Shatter inside Glass Gear window, 03-old invented bag window). Prompts: "owner-generated outside this
session; prompts not available".

Gap images via Codex built-in `image_gen` (`codex exec -s workspace-write`, existing boards attached as
style references, one call per board, prompts saved to `docs/mockups/prompts/*.txt`, inspect each and
re-run once on text errors): G1 loot window Ctrl-held + "no weights" row; G2 settings detail
(modifier, tracked specs, thresholds, appearance/suite state); G3 import formats (Pawn / WoWSims Pawn
EP / SimC profile "needs external sim" / validation error); G4 Shatter Mail Mode sender-owned
advisory + pending policy. If imagegen fails: keep prompts, report blocker, no HTML substitutes.

## Backlog (docs/BACKLOG.md → GitHub issues)

IDs `GG-###` (GlassGear), `AS-###` (AltStable), `SH-###` (Shatter), `GUI-###` (GlassUI), `ASC-###`
(Companion); each with priority, repo, outcome, scope, deps, acceptance, mockups/API refs,
validation (automated vs in-game). Classes: MVP / ecosystem extension / spike / future. Milestones:
M0 foundation (this session) · M1 current-character scoring, imports, tooltip, bag+loot markers,
reveal · M2 AltStable profiles/roster/two-account flow · M3 Shatter protection · M4 compat (Baganator/
Bagnon), perf, localisation, release · M5 Companion sims + Gear Lab. Spikes first in M1: spec detection
probe, loot-frame structure, transfer rules (cross-faction mail, BoA kinds), `GetItemStats` on
suffix links. **First vertical slice**: manual spec mapping + Pawn import + current-character tooltip
rows for all own specs (+ "no weights"); baseline = current equipment for the active spec, other
specs labelled `fallback-current` until per-spec capture (GG M1) lands — no markers, no alts.

Cross-repo issues filed after approval (one per repo, wow-propagate style): **AltStable** — own-
account-only plugin channel with sender/destination enforcement and per-character ownership
provenance (blocker for M2); **namespaced own-account entry-sync service** (manifest exchange,
pull, timers, size checks, inventory; spike AS-S1: host in AltStable vs extract AltStableSync Link
into a shared module); public gear read API with item strings (suffix) + per-slot completeness +
`GearChanged` callback + gear-change stamp. **AltStableSync** — only if AS-S1 chooses extraction:
factor Link's protocol into a reusable module (issue filed as research). **Shatter** — `Integrations/GlassGear.lua`, check in
`IsCandidateDisenchantable` (Solo), verdict table, per-row override with `{guid, token}`, rescan on
GG invalidation. **GlassUI** — roster member (dynamic). **AltStableCompanion** — future sim
orchestration research.

**M0 done means** (this session): loadable scaffold; fixture-tested pure decisions (Pawn I/O,
score, configuration enumeration incl. unique/2H/rings, baseline precedence/completeness, marker
predicate, reveal state machine, transfer tri-state, protection verdicts, cache keys, sync codec +
size budget, API contract shapes); runtime capabilities that aren't built report "unavailable" in
`/gg diag` and the API; contracts/ADRs written **before** the matching core code; mockup inventory;
issue-ready backlog. Generated gap art is reported separately (may fail without blocking M0).
`docs/BACKLOG.md` ends with a **traceability table**: each owner acceptance case (current vs
off-spec markers, modifier press/release, green precedence, BoE→soulbound, cross-account ownership
vs transfer, saved off-spec/unavailable baselines, unknown/pending, dependency absence/incompatible
versions, default theme + Glass UI opt-in/out/reload, Shatter protection with hidden arrows, queue
changes/stale assessments/manual overrides) → M0 test file or backlog ID + validation type.
Fixtures include: enchanted baseline, suffix preservation, proc-only trinket, identical links with
different bind state, BoE→bound without other changes, saved off-spec set, missing baseline slot.

## Execution order

1. `git init` GlassGear; create private `Spotnick2/GlassGear`; initial commit (README stub) on main;
   branch `foundation/scaffold`. (Root repo: GlassGear is a separate repo; check root `.gitignore`.)
2. References: add Pawn (`-Add -CurseForge pawn`, confirm category) and SimC zip (`-Add -Zip …
   -Category DataExport`) via `wow-references`; leave the owner's existing uncommitted References
   edits untouched and uncommitted.
3. Contract docs first: PRD + context matrix, ADRs 0001–0006, API.md, SCHEMA.md, FORMATS.md,
   ECOSYSTEM-FINDINGS.md.
4. Scaffold + core Lua implementing those contracts + tests; run `pwsh tests/run.ps1` + `luac -p`;
   mutation-spot-check key tests. Then INTEGRATION-GAPS.md, FOREVER-PROBE.md, BACKLOG.md
   (+ traceability table).
5. Mockups import + index; gap images via Codex imagegen; inspect.
6. `Tools/deploy.ps1` run (memory: deploy myself) → `_forever_` AddOns; in-game checks queued (game offline).
7. **Codex adversarial loop** (gpt-6-astra, `model_reasoning_effort=high`, read-only, owner asked):
   review docs + code; fix; re-run until a round returns CONSENSUS (no BLOCKER/MAJOR); safety cap
   6 rounds, then report the open disagreements to the owner instead of looping; record each
   round's verdict in `docs/reviews/`.
8. PR "Foundation" (`Closes` foundation issues); file GG backlog issues + cross-repo issues; no merge
   without owner approval.

## Plan review log (Codex gpt-6-astra, high, read-only)

- R1: CHANGES NEEDED — 1 blocker (AltStable plugin channel has no own-account trust boundary),
  10 major, 4 minor. All folded in above (trust boundary + provenance, codec/budget/backfill,
  epochs/tombstones, configuration enumeration, baseline precedence, enchant/effect policy,
  tri-state transfer, Shatter verdict table + token/GUID override, reveal recompute, cache split,
  API cardinality/lifecycle, M0 boundary + traceability, TOC key). Marker finding answered by
  making the owner's row-3 default explicit rather than reveal-gating transferable items.
- R2: CHANGES NEEDED — blocker cleared; 8/15 resolved, 7 partial; new N1–N5. Attempted: clock-free
  `(rev, hash)` ordering with full snapshots + owner reset recovery (N1); codec precision, overflow
  ladder, aggregate limit moved to AltStable runtime check, 24 KB = target (N2); `expiresAt` checked
  synchronously + token bucket, gear-change staleness not `lastUpdate` (N3); async contract,
  aggregate precedence, queue/target/timeout bounds, synchronous `AssessProtection` (N4); focus poll
  on any reveal surface (N5); unmodelled effects → protection `unknown` (R1#7); contracts before
  code in execution order (R1#14).
- R3: CHANGES NEEDED — R1#7, #10, #14, N5 resolved; 4 major left (F1 writer authority/recovery,
  F2 aggregate shedding bookkeeping, F3 expiry vs override token, F4 deferred-work bounds and
  completion retention) + API-summary wording. Attempted: logged-in-GUID writer authority with
  separate authored/replica stores, unchanged-echo replicas and dirty-based reconciliation (F1);
  deferred marker + per-peer pending-delivery bookkeeping + terminal refusal in the AltStable
  extension (F2); freshness generation bumped synchronously + Shatter rejects override after
  `expiresAt` (F3); global job/request bounds, `OVERLOADED`, `CancelRequest`, completion callback
  carries the response (F4); API lists reconciled, `epoch` removed.
- R4: CHANGES NEEDED — all resolved except F1 (an older dirty edit on another installation could
  overwrite a newer published one) + echo-loop wording. Attempted: base-tracked three-way
  reconciliation with conflict copies, `dirty` cleared only by an exact echo, echo non-escalation
  wording.
- R5: CHANGES NEEDED — F1 resolved for complete snapshots; new MAJOR: overflow (incomplete)
  snapshots could act as deletions/adoption sources; MINOR: `R ≤ base` branch bumped rev. Attempted:
  per-section completeness flags in the hash, incomplete sections never authoring inputs, ack only
  for complete sections, no rev bump on stale receipts, conflict copies local-only.
- R6: CHANGES NEEDED — round-5 items resolved; one MAJOR: `R ≤ authored` early return dropped an
  unseen divergent branch (ordering mistaken for ancestry); MINOR omission wording. Attempted:
  ancestry-based reconciliation (8 ancestor ids, `integrated` set, fast-forward / no-op / three-way
  with conflict copies), `(rev, hash)` kept for replica display only — the AltStableSync model.
- R7: CHANGES NEEDED — R6 resolved; two MAJOR: snapshot-wide ancestry fast-forwarded a shed
  section; bounded `integrated` history let late replays mint revisions. Decision: drop the bespoke
  snapshot protocol and **reuse AltStableSync's per-entry model verbatim** (entry versions +
  20 ancestors, whole-entry conflict copies with durable live-or-tombstoned suppression, versioned
  tombstones, no field merging, omission ≠ deletion).
- R8: CHANGES NEEDED — R7 resolved; four MAJOR, all from carrying the model over AltStable's
  record-plugin blob (no delivery/ack/inventory; persisted installId reuse; retirement needs a
  receive-side mint). Attempted: transport becomes an AltStable-owned namespaced manifest entry-sync
  service modelled on AltStableSync Link (manifest = inventory → `maybeBehind`), fresh per-session
  writer token, receive-side mint only for copy retirement, expected-version guards, size fixtures
  incl. ancestors/tombstones, `too-large`, narrowed replay claim.
- **R9: CONSENSUS** — all R8 majors/minors resolved; no BLOCKER/MAJOR left in the M0 scope; the
  M0/M2 boundary judged coherent (M0 fixture-tests consumer contracts + reconciliation with simulated
  transport; AS-S1 chooses the upstream host/wire). Verdict files R1–R9 are copied into
  `docs/reviews/plan/` during execution step 3.

## Verification

- `pwsh tests/run.ps1` green (all `tests/test_*.lua` under Lua 5.1, `luac -p` on every file); each
  new test mutation-checked once (break the code, see it fail).
- `Tools/deploy.ps1` succeeds; TOC lists only existing files (script check); LibGlass pin matches
  checkout (`LibGlassPin.ps1`).
- BigWigs packager dry-run via the package-check workflow locally where possible (`release_files.sh`).
- Mockup index: every image file referenced, every required state mapped or listed as gap.
- In-game (after 2026-11-04, queued in FOREVER-PROBE.md): addon loads without errors, `/gg diag`
  output, spec-group detection, tooltip post-call fires.
- Codex final round: consensus recorded.
