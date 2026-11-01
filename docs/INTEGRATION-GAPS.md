# Integration gaps: changes needed in other repositories

Each item below can be filed as an issue in the repo it names. For each repo:
- **"Exists today"** is cited from [ECOSYSTEM-FINDINGS.md](ECOSYSTEM-FINDINGS.md) (commits as listed there).
- **"Needed"** is a proposal and does not exist yet.

The contracts come from [adr/0001](adr/0001-sync-ownership.md), [API.md](API.md) and
[SCHEMA.md](SCHEMA.md). Glass Gear's own items are in [BACKLOG.md](BACKLOG.md).

Without any of these changes, Glass Gear still evaluates the current character and all its specs.
Alt rows, alt protection and two-account data show **unavailable**: a reason in the UI, never a
silent fallback.

| ID | Repo | Kind | Milestone | Blocks |
|---|---|---|---|---|
| AS-001 | AltStable | Required extension: **done** (AltStable #282, `028cdd1`) | M2 | every alt feature |
| AS-002 | — | **Moved** to ES-001 (AS-S1 chose extraction, adr/0001 amendment) | — | — |
| AS-003 | AltStable | Required extension | M2 | GG-201, GG-203 alt baselines |
| ASS-001 | AltStableSync | Required: extract Link's entry sync (AS-S1 chose extraction) | M2 | ES-001 |
| ES-001 | new library (repo and name TBD) | Required: shared entry-sync library | M2 | GG-202 profile/baseline sync |
| SH-001 | Shatter | Required extension | M3 | Disenchant protection |
| SH-002 | Shatter | Required extension | M3 | Manual override |
| GUI-001 | GlassUI | Required extension | M4 | GG-115 Glass look via suite |
| ASC-001 | AltStableCompanion | Future research | M5 | GG-502, GG-501 |
| — | LibGlass | None | — | — |
| — | LibAccountSync | None (used unchanged, own instance) | — | — |

---

## AltStable

**Exists today:**
- Public API v1 (`PublicAPI.lua:32`): `GetCharacters()` returns identity fields only (`:36`, `:51`).
- Callbacks: `CharactersChanged` and `PortraitStatusChanged` only (`:183`).
- Undocumented `RegisterPlugin` (`Core.lua:3749`): needs a sidebar tab (`:3750`). Its
  `OnSerialize`/`OnDeserialize` hooks get no sender or destination (`:849-850`, `:896-897`).
- Gear lives only in the internal `AltStableDB`. Item links are local-only (`Core.lua:871-873`).
- Ownership:
  - `scannedHere` is local (`Scanner.lua:638`);
  - `LibSync.Peer` is session-only (`Core.lua:563`);
  - `account` is a typed label (`docs/PUBLIC-API.md:46`).
- `TouchCharacter` only stamps `lastUpdate` (`Core.lua:1204`).
- Replies filter by account unless `sendAllAccounts` is set (`Core.lua:1916-1918`).

### AS-001: Own-account-only channel and per-character ownership provenance (**done**)

> **Status: merged** in AltStable #282 (main `028cdd1`). The contract is in AltStable
> `docs/PUBLIC-API.md`:
> - per-character provenance `self` / `own-account` / `third-party`: `GetCharacterProvenance`, the
>   `provenance` fields on `GetCharacters`, and the `"ProvenanceChanged"` callback;
> - an own-account channel: `SendToOwnAccounts`, `RegisterOwnAccountHandler`, `GetOwnAccountPeers`,
>   `"OwnAccountPeersChanged"`;
> - feature flags `provenance` and `ownAccountChannel` in `AltStable.PUBLIC_API_FEATURES`.
>   `PUBLIC_API_VERSION` stays 1.
>
> Glass Gear uses the provenance for recipients (GG-201, GG-203). Profile sync does not use the
> own-account channel; it goes through ES-001 (adr/0001). The original request follows.

- **Outcome.** A consumer can tell, for every character AltStable knows, whether it is the
  player's own. Data the consumer exchanges reaches only the player's own accounts.
- **Scope**
  - Expose per-character `provenance` in the public API, one of:
    - `self`: scanned on this client;
    - `own-account`: received first-hand from a LibAccountSync-proven own-account peer;
    - `third-party`: anything else, including whitelisted friends and relayed records.
  - Persist it with the evidence and time it was established.
  - Provide an own-account-only channel for consumers:
    - **outbound** goes only to LibAccountSync-proven own accounts;
    - **inbound** is accepted only from them;
    - both rules are enforced **before** any consumer callback runs;
    - the callback receives the validated sender.
  - The `account` label, a received owner field and roster membership are never treated as
    ownership.
- **Acceptance**
  - A whitelisted third-party peer never receives consumer data and is never reported as `self`
    or `own-account`.
  - A record about a third-party character relayed by an own-account peer is `third-party`.
  - A provenance change fires a public callback.
  - The API version or a feature flag says the channel is available. An older AltStable is detected
    as "unavailable", not crashed into.
- **Dependencies:** none.
- **Validation**
  - AltStable unit tests: own peer, whitelisted peer, relayed record, unknown sender.
  - In game: a two-account check after 2026-11-04 (AltStable's `/fp steps as` style procedure).

### AS-002: moved to ES-001

Spike AS-S1 chose **extraction** (owner-approved in the AltStable session, 2026-11-01). The
entry-sync service is not built in AltStable: it becomes the shared library **ES-001** below,
extracted from AltStableSync Link under ASS-001. AltStable#281's AS-002 section says it moved.

### AS-003: Public gear read API

- **Outcome.** Glass Gear can compare an item against an alt's equipped gear without reading
  `AltStableDB`.
- **Scope**
  - **Getter.** `GetCharacterGear(guid)` (name proposed; to match AltStable's naming) returns a
    deep copy:
    - per slot: `itemString` (keeping the random suffix and enchant), item id, item level and
      occupancy (`occupied` / `empty` / `unknown`);
    - `capturedAt` and a gear-change stamp.

    The gear-change stamp is separate from `lastUpdate`, which plugin touches move
    (`PublicAPI.lua:125`).
  - **Callback.** A `GearChanged(guid)` callback.
  - **Wire change.** Item strings go on the wire. Today only `gearid_` and `gearmod_` travel, and
    `gearlink_` is local (`Core.lua:871`). Records from older peers stay `unknown` for suffix slots.
- **Acceptance**
  - Remote characters return item strings with their suffix.
  - Old records report `unknown` per slot instead of a wrong item.
  - The callback fires on remote and local changes.
  - The feature flag `AltStable.PUBLIC_API_FEATURES.gear` gates it: true once `GetCharacterGear` and
    `GearChanged` ship (`PUBLIC_API_VERSION` stays 1; agreed on AltStable#281).
- **Dependencies:** AS-001 (provenance travels with the record).
- **Validation:** AltStable tests for serialization round-trip and old-record handling.

---

## AltStableSync

**Exists today:** the per-entry model and the Link protocol (`docs/DESIGN.md:850-973`), and
retirement on receipt (`Catalog.lua:89`, `:542`, `:580`). Link is internal to AltStableSync.

### ASS-001: Extract Link's entry sync into a shared library (required: AS-S1 chose extraction)

- **Outcome.** Link's manifest, pull, size and acknowledgement machinery becomes the embedded
  library ES-001, which AltStableSync Link and Glass Gear both use.
- **Scope**
  - Factor it behind a namespace-parameterised library layered on LibAccountSync.
  - AltStableSync keeps working: Link stays **wire-compatible** during the migration.
- **Acceptance**
  - AltStableSync's existing tests pass, and Link interoperates with an unmigrated peer.
  - A second namespace runs side by side in tests without interfering.
- **Dependencies:** none (AS-S1 is decided).
- **Validation:** AltStableSync unit tests.

---

## Entry-sync library (new; repo and name TBD)

### ES-001: Shared entry-sync library (formerly AS-002)

- **Outcome.** Glass Gear's profiles and per-spec baselines reach the player's other accounts
  reliably, with AltStableSync's per-entry rules, and the receiver knows when it is behind. This works
  without AltStable.
- **Where.** A small embedded library layered on LibAccountSync, extracted from AltStableSync Link
  (ASS-001). Glass Gear and AltStableSync Link both embed and pin it. LibAccountSync is unchanged:
  transport plus proof, opaque payloads.
- **Contract.** Modelled on AltStableSync `docs/DESIGN.md:850-911`.
  - **Registration**
    - A consumer registers a `namespace`, an entry validator and size limits.
    - It declares its entries with `{id, version, ancestors, payload}`.
    - Versions are `<writer>:<seq>`, where `writer` is a fresh in-memory token per session
      (DESIGN.md:222). The library stores incoming ids and versions unchanged.
  - **Instance model** (from the LibAccountSync session)
    - The consumer creates **one dedicated LibAccountSync instance** with a **derived, permanent**
      tag just for entry sync (for example `GlassGearES`; tags are 1-16 letters or digits), on its
      own account-wide store getter. The library owns that instance's single `OnMessage` handler.
    - After `New`, `inst.messages == true` must hold. An older winning LibAccountSync copy gives
      snapshots only, and the library then reports unavailable.
    - The enabled switch lives in the store and is shared by every tag on it: flip them together.
    - Manifests and inventory live in the consumer's own SavedVariables, never inside the
      accountSync store table, which holds the household key.
  - **Exchange triggers.** Per-namespace manifests `{id -> version}` are exchanged:
    - on peer sighting;
    - after coalesced local writes;
    - on a bounded timer while a peer is linked;
    - on manual refresh.

    Receipts never trigger an exchange.
  - **Pull and batches** (sized for the transport; see adr/0001, transport limits)
    - Batches of **at most 16 KB on the wire**, after escaping; they shrink until they fit.
    - The pull timeout is **computed from the bytes** at a planning pace of about 570 B/s plus
      slack, not a flat 30 s.
    - **At most 2 outstanding pulls right after login**, more once the link is settled.
    - The library's **own acknowledgement and retry**: "sent" is never delivery. Every addon on the
      prefix shares 8 open streams and 131072 buffered bytes on the receiver, and a refused stream
      is lost silently.
  - **Oversized entries.** A single entry that can't fit is `too-large`: it stays local and is
    reported to the consumer.
  - **Inventory.** Per peer and per id, whether the manifests match. Glass Gear marks a character's
    targets `maybeBehind` while any of that character's profile or baseline entries differs from a
    peer's manifest. Such targets display as stale and **never** give a protection `clear`.
  - **"Confirmed"** means the peer's manifest lists exactly the local `{id, version}`.
  - **Trust.** LibAccountSync delivers `OnMessage` only from proven own accounts, in both modes
    (`TryDeliver`, `LibAccountSync.lua:1422-1460`). AltStable's "refuse for good" does **not**
    apply on this path; the consumer's own on/off switch is the control (adr/0001, refusals).
  - **Late registration and missing consumers.** A consumer enabled late, or a peer without a
    matching consumer: pending entries are never counted as confirmed and never deleted. A late
    consumer gets a full manifest exchange when it registers.
  - **Receive rules stay with the consumer.** The library delivers entries. Glass Gear applies
    AltStableSync's receive rules (`DESIGN.md:913-973`):
    - fast-forward or ignore;
    - divergent: whole-entry conflict copy, suppressed if it exists live or tombstoned;
    - versioned tombstones;
    - the one receive-side mint is retiring covered conflict copies.
- **Acceptance**
  - **Idle catch-up.** A multi-page exchange, then both sides idle: every entry eventually arrives
    and is confirmed.
  - **Recovery.** A lost acknowledgement or a silently refused stream recovers by retry. A receiver
    with nothing pending still exchanges manifests.
  - **No silent loss.** A weight-only change that hasn't arrived shows `maybeBehind` until the
    manifests match. An oversized entry reports `too-large`. Omission never deletes.
  - **Slow link.** Timeouts scale with the bytes, so a 16 KB batch at about 570 B/s (about 28 s)
    is not retried early.
- **Costs.** Two consumers package and version the library. Link stays wire-compatible during the
  migration (ASS-001).
- **Dependencies:** ASS-001.
- **Validation**
  - Library unit tests with a simulated transport. Glass Gear's M0 fixtures run the same scenarios
    against Glass Gear's side.
  - In game: a two-account check.

---

## Shatter

**Exists today:**
- `ItemScanner:IsCandidateDisenchantable` (`ItemScanner.lua:75`) is the one predicate used by the
  queue build (`:190`) and by click-time `Disenchant:ValidateItem` (`Disenchant.lua:183`).
- Possible-upgrade keeping is Solo only (`ItemScanner.lua:86-94`). Equipment sets are protected (`:85`).
- The secure button is armed in `BeginSecureClick` (`Disenchant.lua:190`). "An error in PreClick
  does not cancel the secure action" (`:259`).
- Rescans go through `SoloMode:ScheduleScan` (`Modes/SoloMode.lua:45`). There is no rescan on
  equipment change.
- Integration precedent: `GlassMailSelection()` (`Modes/MailMode.lua:162`).
- There is **no** external veto API.

### SH-001: Glass Gear protection check (Solo)

- **Outcome.** Potential upgrades for any tracked character and spec stay out of the automatic
  disenchant queue, with a reason. This holds even when Glass Gear's bag arrows are hidden.
- **Scope**
  - **Integration file.** Add `Integrations/GlassGear.lua`:
    - detect `_G.GlassGear.API` with `API_VERSION == 1` and `AssessProtection` a function;
    - wrap every call in `pcall`;
    - never depend on Glass Gear internals.
  - **TOC.** Add `GlassGear` to `## OptionalDeps`.
  - **One check** in `IsCandidateDisenchantable`, Solo only. It is synchronous: no async callback
    ever arms the button.
  - **Verdict table** (protection setting on):

    | Glass Gear result | Shatter |
    |---|---|
    | `protect` | keep; reason "Potential upgrade: N specs" |
    | `unknown`, `pending`, `unsupported` | keep; reason "Glass Gear can't confirm yet" |
    | malformed result, error, incompatible `API_VERSION` | keep; reason "Glass Gear can't confirm yet" |
    | `clear` | Shatter's normal rules |
    | Glass Gear not installed | exactly today's behaviour; the settings line says "Glass Gear not installed" |
    | protection disabled in Shatter | skip the check |

  - **Rescans.** Register for `EvaluationInvalidated`; it calls
    `SoloMode:ScheduleScan("GLASSGEAR", …)`.
  - **Mail Mode stays unchanged.** Items there belong to their senders, and Glass Gear assesses none.
  - **Setting.** A setting default and a checkbox under the keep-item-level row.
  - **Other protections unchanged:** equipment set, ignore list, item level, value rules and mail
    ownership.
- **Acceptance**
  - A tracked off-spec upgrade whose bag arrow is hidden is still kept.
  - Each `unknown`, `pending` or `unsupported` result is kept with a reason.
  - Without Glass Gear, the queue is identical to today's.
  - Equipping an item causes a rescan through the invalidation callback.
  - Mail Mode queues are byte-identical with and without Glass Gear.
  - A Glass Gear error leaves the button disarmed.
- **Dependencies:** GG-301 (`AssessProtection` runtime).
- **Validation**
  - Shatter unit tests with a stub `GlassGear.API` covering every row of the verdict table, plus
    the click-time revalidation.
  - In game: ShatterProbe `next` and `guid` procedures.

### SH-002: Excluded rows and the "Disenchant anyway" override

- **Outcome.** The player sees why an item is kept and can deliberately disenchant one specific
  item.
- **Scope**
  - **Row display.** Excluded rows stay listed, greyed, with the reason and the affected
    characters and specs (from `recipients`).
  - **Override action.** A per-row "Disenchant anyway" records `{guid, token}` for the session.
    The GUID comes from the instance's `C_Item.GetItemGUID`; if there is no GUID, no override is
    offered. The override bypasses **only** the Glass Gear veto, never Shatter's other checks.
  - **When it is cleared:**
    - the token or GUID no longer matches at the click-time recheck;
    - the bag slot changes;
    - Glass Gear invalidates;
    - `now ≥ expiresAt` (checked at click time, independent of any timer).
  - The secure one-click, one-cast, one-item flow is unchanged.
- **Acceptance**
  - An override applies to that instance only.
  - Moving the item clears it.
  - A newer assessment (token change) clears it.
  - An expired assessment clears it.
  - A pending item never gets an override.
- **Dependencies:** SH-001.
- **Validation:** Shatter unit tests; in game, the queue and override with mockups 07 / G4.

---

## GlassUI

**Exists today:** the fixed `Suite.ROSTER` (`Suite.lua:31`), with dynamic members such as Shatter
(`:50`, commit `54b84fb`). Non-members get `"unknown"` (`:95`).

### GUI-001: Add GlassGear to the roster (dynamic)

- **Outcome.** Glass Gear can follow the suite's look, and appears on Glass UI's settings page.
- **Scope:** add `{ name = "GlassGear", title = "Glass Gear", dynamic = true }`, as #164 did for
  Shatter.
- **Acceptance**
  - With Glass Gear loaded, its card appears.
  - `Theme("GlassGear")` returns a look.
  - Turning follow off is saved by Glass UI and takes effect after `/reload`.
- **Dependencies:** none. GG-115 consumes it.
- **Validation:** GlassUI `test_suite`-style unit test; in game, the card and the reload.

---

## LibGlass

**None needed.** Glass Gear embeds r11 (`tag: r11`) and makes its own instance with the `pearl`
preset. It never changes shared defaults and never skins GameTooltip; Glass UI #147 owns that. A
future need goes to a LibGlass issue, not an edit from this repo.

## LibAccountSync

**None needed.** Both of the owner's WoW accounts are on one Battle.net account, which
LibAccountSync already covers (`README.md:4`). Since the adr/0001 amendment, Glass Gear uses it
**unchanged**, through the ES-001 library, on its own instance with a derived permanent tag (for
example `GlassGearES`). It still never builds a second roster.

## AltStableCompanion

**Exists today:** a .NET 10 tray app for portrait cutouts. There is no simulation code.

### ASC-001: External simulation orchestration (future research)

- **Outcome.** Gear Lab (GG-501) can queue a simulation outside the game and import its result as
  `sim-result` (GG-502).
- **Scope (research)**
  - Which sim can run Forever: there is no Forever WoWSims locally, and simc needs a
    Forever-capable build.
  - The job contract: request files written by the addon and read on `/reload`; results written
    for import.
  - The job states: queued, running, done, failed.
- **Acceptance:** a written design with a measured proof that one Forever character can be
  simulated outside the game.
- **Dependencies:** GG-502.
- **Validation:** research output only.
