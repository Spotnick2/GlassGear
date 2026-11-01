**The two round-7 failure mechanisms are resolved by per-entry reconciliation, with a qualification about late replay. No BLOCKER found. Four MAJOR contract defects remain in ADR-0001’s adaptation of the model.** These affect the foundation docs and fixtures; they do not require implementing M2 transport during M0.

**MAJOR 1 — Rotation and echo confirmation lack a delivery mechanism that guarantees progress.**

The [plan’s rotation rule](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:94) relies on `TouchCharacter` and AltStable’s 300-second request throttle. But:

- [`TouchCharacter`](C:/Projects/WoW/AltStable/Core.lua:1204) only sets `lastUpdate`. It schedules no request or send.
- The [300-second throttle](C:/Projects/WoW/AltStable/Core.lua:2215) rejects requests made too soon; it does not schedule subsequent requests.
- Own-account discovery [stops fetching after a request succeeds](C:/Projects/WoW/AltStable/Core.lua:1724).
- Ordinary replies [default to filtering by the sending account](C:/Projects/WoW/AltStable/Core.lua:1915). Consequently, B’s retained copy of A’s character need not be included in B’s reply to A, even when GG needs that copy as an acknowledgement.

Concrete failure: A’s first page delivers P but omits Q. Both accounts remain online without further edits or manual sync. Touching A’s character does not create another exchange, so Q remains undelivered. Independently, B can hold P successfully while its account filter prevents the echo that would confirm P.

AltStableSync explicitly supplies [periodic manifest exchange, repeated requests and timeout recovery](C:/Projects/WoW/AltStableSync/docs/DESIGN.md:857). Those are transport requirements, not consequences of its receive rules.

**Concrete fix:** Require the AltStable extension to provide bounded periodic delivery/acknowledgement exchanges while compatible peers are connected, plus peer-sighting and manual-refresh triggers. Define fair rotation and pending state **per peer**, covering live entries, conflict copies and tombstones. Acknowledgements must be deliverable independently of core account filters and character watermarks. Receipt can update queues without triggering an immediate send.

Add a fixture where several pages are needed, the first exchange succeeds, both sides then remain idle, and every entry eventually arrives and is acknowledged. Include lost acknowledgements and a receiver that has no locally authored pending entries.

**MAJOR 2 — Per-character rotation can leave protection using an obsolete entry without knowing that an update was omitted.**

The plan marks remote data `maybeBehind` when the **aggregate** envelope sheds a whole plugin blob, but provides no corresponding receiver-visible state for [entries omitted inside the 1200-byte blob](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:84). “Pending on the sender” does not invalidate the receiver’s assessment.

Concrete failure:

1. B holds profile P₀ and a complete, fresh baseline. An item evaluates as `no_upgrade`.
2. A changes the weights to P₁, under which that item is an upgrade. A subsequently changes another entry Q.
3. The next blob contains Q; P₁ remains pending because it does not fit.
4. B receives a normal GG blob, without the aggregate `deferred` marker. It retains P₀, and no gear change or baseline-age transition makes that assessment stale.
5. Protection can return `clear` using P₀ despite the received publication being incomplete.

Omission correctly causes **no deletion**, but that alone does not establish that retained content is current enough for protection. AltStableSync’s manifests expose differing entry versions; this transport currently supplies no equivalent information.

**Concrete fix:** Define a receiver-visible inventory or paginated completeness protocol that identifies outstanding entry versions. Until the relevant updates are complete, mark affected targets `maybeBehind` and prevent `clear`. Define precisely what clears that state: receiving one subsequent page is insufficient. Keep delivery/completeness metadata separate from entry ancestry so this does not recreate round 7’s snapshot-wide fast-forward problem.

Add the weight-only change above as a protection fixture.

**MAJOR 3 — Persisting `installId` in the copied/restored database permits version reuse.**

The [plan stores a random identifier per `GlassGearDB`](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:59), with a monotonic sequence. That differs from the source model: AltStableSync explicitly uses a [fresh, in-memory writer token on every successful initialization](C:/Projects/WoW/AltStableSync/docs/DESIGN.md:222), because a stored identifier travels with copied SavedVariables.

Concrete failure:

1. A SavedVariables backup contains writer `I`, sequence 10, and baseline E.
2. A edits E to version `I:11`; a peer retains it.
3. The backup is restored, or copied to another installation. E is edited differently, again producing `I:11`.
4. The two contents now have the same entry ID and version. The first receive rule ignores the incoming value, without a conflict copy.

The counterexample requires no simultaneous logins. A sequence is only monotonic within the surviving database history.

**Concrete fix:** Reuse AltStableSync’s fresh session writer token and session sequence, or specify another mechanism that prevents token reuse after database copying and rollback. Preserve incoming entry IDs and versions unchanged.

A **complete deletion of GlassGearDB followed by a genuinely new random identifier has no defect found** at the reconciliation layer. The failure concerns copied or restored state retaining the old identifier and counter.

**MAJOR 4 — “Receiving never mints a version” contradicts the imported conflict-retirement algorithm.**

The [plan’s absolute prohibition](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:74) is incompatible with the model it incorporates. AltStableSync’s [resolution contract](C:/Projects/WoW/AltStableSync/docs/DESIGN.md:930) requires the receiving account to retire its mirror copies when it fast-forwards to a resolution. The implementation does exactly that:

- [`Upsert` calls `RetireCovered` after fast-forward](C:/Projects/WoW/AltStableSync/Catalog.lua:542).
- [`Retire` calls `Advance`](C:/Projects/WoW/AltStableSync/Catalog.lua:580).
- [`Advance` mints a version](C:/Projects/WoW/AltStableSync/Catalog.lua:89).

Concrete failure:

1. A holds root version a and conflict copy `E~b`; B holds root b and mirror copy `E~a`.
2. A resolves the conflict, producing root m and retiring `E~b`.
3. B receives m. It must retire its own `E~a`.
4. A need not hold `E~a`: its receive rules can ignore that live copy as a copy of its own root content. Therefore A’s retirement tombstones do not necessarily include the one B needs.
5. If B follows the prohibition on minting, it cannot execute the imported retirement algorithm. Its mirror conflict remains unresolved, or the implementation must invent different tombstone semantics.

**Concrete fix:** Permit receive-side minting **only for retirement of existing covered conflict copies**, as the source does. Keep root versions unchanged by receipt, make repeated retirement a no-op, and retain the prohibition on receive-triggered `TouchCharacter` and immediate sends. Deliver the resulting tombstones through the bounded exchange from MAJOR 1. AltStableSync already distinguishes [receipt-side retirements from local-write notifications](C:/Projects/WoW/AltStableSync/Catalog.lua:51).

Add the asymmetric mirror-copy fixture above, followed by duplicate resolution delivery.

The requested counterexamples replay as follows:

| Sequence | Assessment |
|---|---|
| **R7: shed section followed by a complete descendant** | **Resolved; no defect found.** B cannot advance an omitted baseline’s identity by receiving a profile. B’s retained baseline remains the old entry version, which cannot fast-forward over A’s changed baseline. |
| **R7: resolve divergent R, exceed history retention, replay R** | **Resolved for this counterexample; no defect found.** The durable `E~R` live record or tombstone suppresses replay after R leaves root ancestry. No new root revision is allocated. |
| **A-dirty → B-newer → A-login** | **No defect found in per-entry reconciliation.** Independent changes to different entries survive. Divergent changes to the same entry preserve both alternatives for explicit resolution; A’s old dirty content is not automatically promoted above B’s edit. |
| **Immediate duplicate/reordered delivery** | **No defect found in the entry decisions.** Exact versions and known ancestors are ignored; unseen divergence becomes a deterministic conflict copy. Resolution retirement needs MAJOR 4. |
| **Clean reset/reinstall with a new writer identity** | **No defect found in entry adoption.** Unknown IDs can be adopted; independently recreated fixed-ID baselines conflict rather than winning by a reset counter. Delivery still needs MAJOR 1. |
| **Restore/copy of SavedVariables** | Fails through version reuse: MAJOR 3. |
| **Overflow omission** | **No defect found in preservation:** omitted entries are neither deleted nor adopted. Eventual delivery and safe receiver freshness need MAJORs 1–2. |
| **Incomparable tombstones** | **No defect found in the imported tie-break**, including its explicitly accepted possibility of one later conflict from the losing history. |

**MINOR — Narrow the universal late-replay claim.**

[“Late replays never re-create work”](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:66) is stronger than the source model.

If R originally fast-forwarded the root, no `E~R` conflict record was created. After 21 successors evict R from ancestry, replaying R can create its **first** conflict copy. The root does not advance, and subsequent duplicates are durably suppressed. AltStableSync expressly treats [lag beyond 20 saves as divergence](C:/Projects/WoW/AltStableSync/docs/DESIGN.md:924).

**Fix:** Promise indefinite suppression for already-recorded conflict identities, while documenting that history-expired versions without such a record can produce a conservative conflict. This is a qualification of the adopted model, not a return of round 7’s automatic revision escalation.

**MINOR — Complete the size and mutation contracts.**

- **One entry larger than 1200 bytes:** rotation only solves a collection of individually fitting entries. Specify and fixture-test the encoded maximum including 20 ancestors, IDs, conflict metadata and escaping. Define a visible terminal `too-large` outcome or fragmentation if an entry cannot fit alone. AltStableSync [explicitly reports oversized entries and keeps them local](C:/Projects/WoW/AltStableSync/docs/DESIGN.md:856).
- **Tombstone growth:** indefinite retention does not itself break a per-message cap when entries rotate fairly. **No separate defect found.** It does increase storage and backfill time; “tiny” is not an aggregate bound. Include tombstones in the size/backfill fixtures.
- **Expected-version guards:** carry over the source’s [stale-mutation rejection](C:/Projects/WoW/AltStableSync/docs/DESIGN.md:969) explicitly into profile editing and conflict actions, including the relevant versions for resolution. This should be concrete in the foundation API and tests, not merely implicit in “reuse.”

**Elsewhere in the plan, no additional BLOCKER/MAJOR defect found.** The own-account trust prerequisite, configuration enumeration, fail-closed effect/baseline policies, freshness-token invalidation, bounded asynchronous evaluation and explicit unavailable M0 capabilities remain intact.

Validation used read-only `Get-Content`, `Get-ChildItem` and targeted `rg` inspection of the revised plan, R1–R7 verdicts, and AltStable/AltStableSync source, plus small in-memory transition checks. **No files changed; no implementation or in-game tests ran.**

CHANGES NEEDED