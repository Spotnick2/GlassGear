# ADR-0001: Who owns cross-account sync

- Status: accepted (2026-11-01), after nine rounds of adversarial review (Codex gpt-6-astra, high),
  `docs/reviews/plan/`
- Scope: weight profiles and per-spec baselines across the owner's two WoW accounts (one Battle.net
  account)

## Context

The owner plays on two WoW accounts. Evaluating an item for an alt needs that alt's **weights** and
**baseline gear**, authored on the account that plays the alt.

What exists today (verified, see [ECOSYSTEM-FINDINGS.md](../ECOSYSTEM-FINDINGS.md)):

- **AltStable** already syncs the roster and a 17-slot gear snapshot across own accounts through
  LibAccountSync (Battle.net game data, 32 KB max), and to whitelisted third parties through whispers.
  - Its public API v1 exposes identity only.
  - Its plugin hooks `OnSerialize(guid)` / `OnDeserialize(guid, blob)` carry **no sender or
    destination**.
  - Item links are not synced, so random suffixes are lost.
  - "Own account" is a session-only check, and `account` is a label the player types in.
- **LibAccountSync** reaches the same Battle.net account only, which is the same reach as AltStable's
  route.
- **AltStableSync** (v1.0.0) ships a per-entry catalog sync over LibAccountSync. It has versioned
  entries with ancestry, conflict copies, tombstones, manifest exchange, pull, timers and size checks
  (`AltStableSync/docs/DESIGN.md:850-973`).

## Options

| | 1. AltStable-owned sync | 2. Direct LibAccountSync in Glass Gear | 3. Provider/adapter |
|---|---|---|---|
| Roster/ownership source | AltStable (single truth) | Glass Gear would need its own roster and ownership | Pluggable |
| Transport | AltStable (needs an extension) | Glass Gear's own LAS instance | Whatever the provider gives |
| Duplicate sync services | No | **Yes**: a second own-account roster sync | No, if the provider is AltStable |
| Works without AltStable | Current character only | Alts too | Current character; future providers possible |
| Upstream work | AS-001, AS-002, AS-003 | None upstream, but heavy duplication | As option 1 |
| Demonstrated need | Fits "AltStable owns roster/distribution" | No requirement today for alts without AltStable | |

## Decision

**Option 1, behind the internal `RosterProvider` interface of option 3.**

- **Glass Gear owns** profile authoring, per-spec baseline capture and evaluation.
- **AltStable owns** the roster, ownership provenance and cross-account distribution.
- Glass Gear always has a local provider, which covers the current character and its specs. The
  AltStable provider is added when AltStable offers the required capabilities.
- Direct LibAccountSync is rejected for the MVP: it would solve no demonstrated requirement and would
  duplicate AltStable's own-account route.
- **Revisit trigger:** "alts without AltStable" becomes a requirement.

Until AS-001 and AS-002 ship, alt features are reported **unavailable**. They are not degraded, and
Glass Gear never reads `AltStableDB` directly (AltStable `docs/PUBLIC-API.md:4-5`).

## Trust boundary (required: AS-001)

- **Own accounts only.** Profiles and baselines may only travel to and from the owner's own accounts.
  The AltStable extension provides an own-account-only channel:
  - outbound goes only to LibAccountSync-proven own accounts;
  - inbound is accepted only from them;
  - both are enforced before any consumer callback.
- **Provenance per character.**
  - `self`: scanned on this client.
  - `own-account`: first-hand from a proven own-account peer.
  - `third-party`: anything else.
- **What Glass Gear never infers ownership from:** the `account` label, a received owner field, or
  roster membership. Third-party characters are never recipients.

## Data model: AltStable Sync's per-entry model, reused

Earlier drafts used whole-character snapshots. They kept leaking edge cases: shed sections that got
fast-forwarded, late replays after history eviction, and stale installations winning. Glass Gear
therefore reuses AltStableSync's shipped model (`DESIGN.md:913-973`).

**Entries.** Each entry has a stable id:

- a weight profile is `<guid>:<specKey>:<uuid>`;
- a spec baseline is `<guid>:<specKey>:baseline`.

**Versions.**

- A version is `<writer>:<seq>`. `writer` is a fresh in-memory token minted at every successful
  initialisation, and `seq` is a session counter (`DESIGN.md:222`). A copied or restored
  SavedVariables can therefore never reuse a version.
- Each version carries its last 20 `ancestors`.
- Incoming ids and versions are stored unchanged.

**Who edits.** Only a client logged in as that GUID edits that character's entries. Several
installations may do so, and conflicts are handled per entry.

**Receive rules** (per entry, idempotent, from `DESIGN.md:918-928`):

| Incoming | Action |
|---|---|
| Same version as local | ignore |
| Live conflict copy whose version the root already holds or passed | ignore |
| Incoming version is in local ancestors | ignore |
| Local version is in incoming ancestors, or unknown id | replace (fast-forward) |
| Anything else | divergent: keep local, and store the incoming one **whole** as conflict copy `<id>~<version>`. Ignored if that copy id exists **live or tombstoned** |
| Validator failure / wrong type | reject; local untouched |
| Unknown or newer schema | reject; local untouched |

- **No field merging, ever.**
- **Conflict copies.** A copy that was already recorded never comes back. A version that aged out of
  the 20-deep ancestry without a recorded copy can produce **one** conservative conflict copy
  (`DESIGN.md:924`). It never changes the root.
- **Resolution.** "Keep this version" and "Keep mine" each mint a version whose ancestors hold **both**
  competing versions first, then both histories. Covered copies are retired with tombstones
  (`DESIGN.md:930-939`).
- **Receive-side minting.** The only version minted on receipt is the one that retires covered
  conflict copies after a fast-forward to a resolution (AltStableSync `Catalog.lua:542,580,89`).
  Repeating it is a no-op.
- **Deletion** is a versioned tombstone kept indefinitely. Deletion conflicts and the lexical
  tie-break between two incomparable tombstones follow `DESIGN.md:940-964`.
- **Omission never means deletion.** An entry that wasn't sent is not delivered yet.
- **Stale edits.** Every edit and conflict action takes an **expected version** and refuses when that
  version is stale (`DESIGN.md:969-971`).
- **Receiving is passive.** Receiving never triggers a send, and never calls `TouchCharacter`.
- **AltStable forget** drops that GUID's entries locally. **Unforget** is a normal fast-forward.

## Transport (required: AS-002, spike AS-S1)

AltStable's character-record plugin blob is **not** sufficient. It has no delivery, acknowledgement
or inventory:

- `TouchCharacter` only sets `lastUpdate` (`Core.lua:1204`);
- the 300 s throttle only rejects requests (`Core.lua:2215`);
- replies filter by account (`Core.lua:1915`).

The required extension is a **namespaced, own-account entry-sync service**. A consumer registers with
it headlessly (namespace, validator, size limits). It is modelled on, and ideally extracted from,
AltStableSync Link (`DESIGN.md:850-911`):

- **Manifests.** Each namespace has a manifest `{id → version}`. Manifests are exchanged:
  - on peer sighting;
  - after coalesced local writes;
  - on a bounded timer while a peer is linked;
  - on manual refresh.
- **Pull.** Each side pulls the differing ids from each peer, with at most 3 outstanding, a 30 s
  timeout and re-queueing.
- **Size.** Batches shrink until they fit. An oversized single entry is `too-large`: it stays local
  and is reported.
- **Receipts** never trigger exchanges.
- **The manifest is the inventory.** While a character's relevant entries differ from a peer's
  manifest, that character's targets are `maybeBehind`. They are displayed as stale and never give
  `clear` for protection.

Whether AltStable hosts the service itself or delegates to a module extracted from AltStableSync is
an AltStable decision (AS-S1). Glass Gear depends only on this contract.

## Codec and budget

- Each entry is one line, versioned `GG1|…`, and specified in [SCHEMA.md](../SCHEMA.md).
- **Profiles:**
  - weights are fixed 3-decimal values in [-999.999, 999.999], with Pawn `X` meaning "ignore";
  - a profile name is at most 24 characters;
  - a profile has at most 40 tokens;
  - a spec has at most 4 profiles.
- **Baselines:** at most 19 compact item strings `id:enchant:suffix`, plus per-slot occupancy and
  `capturedAt`.
- **Targets** (checked by M0 fixtures, not guarantees):
  - at most 2 KB per encoded entry, including 20 ancestors, ids, conflict metadata and escaping;
  - under 24 KB per manifest exchange page.
- The full backfill fixture includes tombstones for 50 characters.

## Sync policy by data kind

| Data | Synced | Why |
|---|---|---|
| Weight profiles (imported or manual) | Yes | Needed to evaluate alts from the other account |
| Spec baselines | Yes | Same |
| Spec mapping (group → spec) | Yes, as part of the baseline entry metadata | Needed to label "current" for alts |
| Display, marker and protection settings, reveal modifier | **No** | Per-account preference |
| Conflict copies | As entries (per the model) | Resolution must converge |

## Consequences

- M0 implements the receive rules, resolution, the manifest inventory, `maybeBehind` and the codec as
  **pure Lua with simulated transport**, fixture-tested (`tests/test_entry_sync.lua`).
- M2 needs AS-001, AS-002 and AS-003 upstream. Glass Gear's adapter (GG-201, GG-202) then only maps
  the service onto the tested model.
- Accepted edge cases are the ones AltStableSync documents: one extra conflict copy after two
  incomparable tombstones meet, and a conservative copy after 20+ edits of lag.
