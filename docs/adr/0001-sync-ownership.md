# ADR-0001: Who owns cross-account sync

- Status: accepted (2026-11-01), after nine rounds of adversarial review (Codex gpt-6-astra, high),
  `docs/reviews/plan/`. **Amended 2026-11-01** (#36): spike AS-S1 chose **extraction**, approved by
  the owner in the AltStable session. AS-002 is no longer an AltStable service. Profiles and
  baselines travel through a shared entry-sync library on Glass Gear's own LibAccountSync instance
  (option 4 below). The amendment was checked by a Codex consult (no fatal defect) and by the
  LibAccountSync session against its docs and code.
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
  - Item links are not synced, so random suffixes are lost. (AS-003 fixed this: AltStable #283.)
  - "Own account" is a session-only check, and `account` is a label the player types in.
- **LibAccountSync** reaches the same Battle.net account only, which is the same reach as AltStable's
  route.
- **AltStableSync** (v1.0.0) ships a per-entry catalog sync over LibAccountSync. It has versioned
  entries with ancestry, conflict copies, tombstones, manifest exchange, pull, timers and size checks
  (`AltStableSync/docs/DESIGN.md:850-973`).

## Options

| | 1. AltStable-owned sync | 2. Direct LibAccountSync in Glass Gear | 3. Provider/adapter | 4. AltStable roster + shared entry-sync library |
|---|---|---|---|---|
| Roster/ownership source | AltStable (single truth) | Glass Gear would need its own roster and ownership | Pluggable | AltStable (single truth) |
| Transport for profiles/baselines | AltStable (needs an extension) | Glass Gear's own LAS instance | Whatever the provider gives | The extracted library, on Glass Gear's own LAS instance |
| Duplicate sync services | No | **Yes**: a second own-account roster sync | No, if the provider is AltStable | No second roster; one entry-sync implementation shared with AltStableSync Link |
| Works without AltStable | Current character only | Alts too | Current character; future providers possible | Profile/baseline sync yes; alts no |
| Upstream work | AS-001, AS-002, AS-003 | None upstream, but heavy duplication | As option 1 | AS-001 (done), AS-003 (done), ASS-001 + the library (ES-001) |
| Demonstrated need | Fits "AltStable owns roster/distribution" | No requirement today for alts without AltStable | | AS-S1 found the entry-sync machinery belongs in a library, not in AltStable |

## Decision

**Option 4 (amended 2026-11-01; was option 1), behind the internal `RosterProvider` interface of
option 3.**

- **Glass Gear owns** profile authoring, per-spec baseline capture and evaluation. It **syncs its own
  profiles and baselines** through the shared entry-sync library (ES-001, extracted from AltStableSync
  Link under ASS-001) on **its own LibAccountSync instance**.
- **AltStable owns** the roster, ownership provenance (AS-001, merged in AltStable #282) and gear
  (AS-003, merged in AltStable #283). Alt features (GG-201, GG-203) still go through AltStable.
- **Option 2's rejection still stands for the roster:** Glass Gear never builds a second roster or
  its own ownership model. What it runs itself is entry sync only, with code shared with AltStableSync
  Link, not a second implementation.
- **Consequence:** profile and baseline sync works without AltStable (the owner's own characters,
  across installations and accounts). Evaluating alts still needs AltStable's roster, provenance and
  gear.
- Glass Gear always has a local provider, which covers the current character and its specs. The
  AltStable provider is added when AltStable offers the required capabilities (AS-001, AS-003).

Both are now in AltStable (#282, #283); until GG-201 and GG-203 use them, alt features are
reported **unavailable**; until ES-001
ships, profile sync is. They are not degraded, and Glass Gear never reads `AltStableDB` directly
(AltStable `docs/PUBLIC-API.md:4-5`).

### Refusals and the on/off control (recommended default; the owner's call)

AltStable lets the player "refuse for good" an own account. That refusal is AltStable's own state and
does **not** apply on the library path, which runs on a different LibAccountSync instance.

- **Recommended:** Glass Gear's own sync on/off switch is the control. It is documented as such in the
  settings, and turning it off stops both sending and receiving on Glass Gear's instance.
- **Not recommended:** a policy bridge that mirrors AltStable's refusals into Glass Gear. It would
  couple two stores for a rare case.

## Trust boundary

- **Own accounts only.** Profiles and baselines may only travel to and from the owner's own accounts.
  On the library path, LibAccountSync enforces it:
  - it sends only to its proven own-account peers;
  - it delivers `OnMessage` only from a proven own account, in both snapshot and messages modes
    (`TryDeliver`, `LibAccountSync.lua:1422-1460`), before the library or Glass Gear sees anything.
- **Character provenance comes from AltStable** (AS-001, merged): `GetCharacterProvenance` and the
  provenance fields on `GetCharacters` (AltStable `docs/PUBLIC-API.md`). Glass Gear uses it to decide
  which characters are recipients. An entry arriving from a proven own account says nothing about
  the character it describes beyond that.
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

## Transport: the shared entry-sync library (ES-001, from ASS-001)

AltStable's character-record plugin blob is **not** sufficient. It has no delivery, acknowledgement
or inventory:

- `TouchCharacter` only sets `lastUpdate` (`Core.lua:1204`);
- the 300 s throttle only rejects requests (`Core.lua:2215`);
- replies filter by account (`Core.lua:1915`).

Spike AS-S1 chose **extraction**: AltStableSync Link's entry sync (`DESIGN.md:850-911`) becomes a
small embedded library layered on LibAccountSync. Glass Gear and AltStableSync Link both embed it.
LibAccountSync stays unchanged: transport plus proof, with opaque payloads. Glass Gear registers a
namespace with it (namespace, entry validator, size limits) and depends only on its contract:

- **Manifests.** Each namespace has a manifest `{id → version}`. Manifests are exchanged:
  - on peer sighting;
  - after coalesced local writes;
  - on a bounded timer while a peer is linked;
  - on manual refresh.
- **Pull.** Each side pulls the differing ids from each peer and re-queues on timeout.
- **Size.** Batches shrink until they fit. An oversized single entry is `too-large`: it stays local
  and is reported.
- **Delivery.** "Sent" is never delivery: the layer acknowledges and retries itself.
- **Receipts** never trigger exchanges.
- **The manifest is the inventory.** While a character's relevant entries differ from a peer's
  manifest, that character's targets are `maybeBehind`. They are displayed as stale and never give
  `clear` for protection.
- **Late registration, or no matching consumer on the peer:** pending entries are never counted as
  confirmed and never deleted.

### Transport limits (from the LibAccountSync session)

The original AS-002 numbers (3 outstanding pulls, flat 30 s timeout, 24 KB pages) were too tight
for the transport:

| Fact | Value |
|---|---|
| Planning pace | about **570 B/s**: a 16 KB reply takes about 28 s, a 32 KB one about 57 s |
| Just after login | even 1000 B took 7–14 s to go out |
| Shared receiver limits | every addon on the prefix shares **8 open streams** and **131072 buffered bytes** |
| Escaping | can double the size on the wire |
| A refused stream | is lost silently |

So the library contract uses:

- **batches of at most 16 KB** on the wire, after escaping;
- a **pull timeout computed from the bytes** at the planning pace plus slack, not a flat 30 s;
- **at most 2 outstanding pulls right after login**, more only once the link is settled;
- its own acknowledgement and retry.

At the planning pace the worst-case backfill fixture (about 1.2 MB before compression for 50
characters, `test_entry_sync`) would take over half an hour. Real backfills are far smaller, the
library pages them, and the receiver shows `maybeBehind` until it has caught up.

### Instance model (from the LibAccountSync session)

- **One dedicated LibAccountSync instance** with a tag **derived** for entry sync only, for example
  `GlassGearES`. Tags are 1–16 letters or digits and **permanent**: choose once.
- It uses Glass Gear's own account-wide store getter. The library owns that instance's single
  `OnMessage` handler.
- After `New`, check `inst.messages == true`: an older LibAccountSync copy that wins the LibStub race
  gives snapshots only. Then profile sync reports unavailable.
- The enabled switch lives in the store and is **shared by every tag on that store**: flip them
  together.
- The library's manifests and inventory live in **Glass Gear's own SavedVariables**, never inside
  the accountSync store table, which holds the household key.

## Codec and budget

- Each entry is one line, versioned `GG1|…`, and specified in [SCHEMA.md](../SCHEMA.md).
- **Profiles:**
  - weights are fixed 3-decimal values in [-999.999, 999.999], with Pawn `X` meaning "ignore";
  - a profile name is at most 24 characters;
  - a profile has at most 40 tokens;
  - a spec has at most 4 profiles.
- **Baselines:** at most 17 trimmed item strings (AltStable's `GetCharacterGear` form, at most 64
  characters; on Forever the random suffix is a bonus ID), plus per-slot occupancy and `capturedAt`.
- **Targets** (checked by M0 fixtures, not guarantees):
  - at most 2 KB per encoded entry, including 20 ancestors, ids, conflict metadata and escaping;
  - at most 16 KB per batch or manifest page on the wire (was 24 KB before the amendment; see
    transport limits).
- The full backfill fixture includes tombstones for 50 characters.

## Sync policy by data kind

| Data | Synced | Why |
|---|---|---|
| Weight profiles (imported or manual) | Yes | Needed to evaluate alts from the other account |
| Spec baselines | Yes | Same |
| Spec mapping (group → spec) | Yes, as part of the baseline entry metadata | Needed to label "current" for alts |
| Display, marker and protection settings, reveal modifier | **No** | Per-account preference |
| The sync on/off switch | **No** | It is the control for this account (see refusals) |
| Conflict copies | As entries (per the model) | Resolution must converge |

## Consequences

- M0 implements the receive rules, resolution, the manifest inventory, `maybeBehind` and the codec as
  **pure Lua with simulated transport**, fixture-tested (`tests/test_entry_sync.lua`).
- M2 needs, upstream: AS-001 (merged), AS-003 (merged), and the entry-sync library (ES-001, extracted under
  ASS-001). Glass Gear's adapters (GG-201 for the roster, GG-202 for the library) then only map them
  onto the tested model.
- **New costs (amendment):**
  - Two consumers, Glass Gear and AltStableSync, package and version the library. Each pins a
    release, like LibGlass.
  - AltStableSync Link must stay wire-compatible during the migration (ASS-001's acceptance).
  - Glass Gear owns a LibAccountSync instance with a permanent tag, and its settings need the sync
    on/off switch.
- Accepted edge cases are the ones AltStableSync documents: one extra conflict copy after two
  incomparable tombstones meet, and a conservative copy after 20+ edits of lag.
