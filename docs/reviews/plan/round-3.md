**CHANGES NEEDED. No BLOCKER remains; four MAJOR contract issues remain.** The revision closes several round-2 gaps, but reset recovery, aggregate shedding, expiry-token invalidation, and async work bounds still need changes before the foundation contracts are implemented.

| Previous item | Disposition | Assessment |
|---|---|---|
| R1 #2 | **PARTIAL** | Per-character overflow is defined; aggregate shedding still lacks delivery/retry semantics. See F2. |
| R1 #3 | **PARTIAL** | Full snapshots resolve deletion semantics and `(rev, hash)` gives deterministic ordering, but owner recovery remains incomplete. See F1. |
| R1 #7 | **RESOLVED** | Unmodelled effects and zero-supported-stat items cannot establish protection `clear`; **no defect found** in the revised rule ([plan:102](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:102)). |
| R1 #10 | **RESOLVED** | Polling covers every visible reveal surface, with explicit combat deferral; **no defect found** ([plan:129](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:129)). |
| R1 #11 | **PARTIAL** | Synchronous expiry checks close stale cached `clear`; expiry does not necessarily change the override token. See F3. |
| R1 #12 | **PARTIAL** | Placeholders, completion notification, status precedence, and item-load bounds are specified; computation backlog and completion retention remain incomplete. See F4. |
| R1 #14 | **RESOLVED** | Execution now puts contracts before matching implementation; **no defect found** ([plan:281](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:281)). |
| N1 | **PARTIAL** | Clock-based ordering cycles are eliminated; equal-revision recovery and writer authority remain unresolved. See F1. |
| N2 | **PARTIAL** | Numeric bounds, terminal per-character overflow, and target-versus-guarantee wording are fixed; aggregate shedding needs F2. |
| N3 | **PARTIAL** | Verdict freshness is checked synchronously, but expiry-driven token invalidation is still incomplete. See F3. |
| N4 | **PARTIAL** | The display aggregate rule is defined; repeated calls can still create unbounded deferred computation. See F4. |
| N5 | **RESOLVED** | The 0.1 s poll covers bags, loot, and roll frames while visible; **no defect found** ([plan:130](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:130)). |

**F1 — MAJOR: Owner reset recovery does not uphold “the owner’s content always wins.”**

Evidence: [plan:55](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:55) specifies maximum `(rev, hash)`, but recovery at [plan:59](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:59) triggers only for a **higher revision**.

A concrete counterexample:

- A peer retains old content at `(1, "ffff")`.
- The owner resets and publishes current content at `(1, "1000")`.
- The peer keeps the old content by the prescribed comparison.
- Even if the old copy reaches the owner, `remote.rev > local.rev` is false, so recovery never fires.

Thus an old remote copy can permanently beat current owner content at receivers. If the general merge rule also applies locally, it can overwrite the owner’s content there too.

Two related protocol gaps remain:

- “Remote copies … never re-published” does not define how the reset owner learns the higher remote revision required by recovery. An explicit acknowledgement/digest exchange or permitted immutable echo is needed.
- `self = scanned here` is provenance, not exclusive writer authority. AltStable persists `scannedHere` at [Scanner.lua:638](C:/Projects/WoW/AltStable/Scanner.lua:638), and explicitly recognises characters played on another installation at [Core.lua:1316](C:/Projects/WoW/AltStable/Core.lua:1316). Two installations can therefore retain local ownership evidence for one GUID. If both perform “keep my content, bump above remote,” revisions can chase each other indefinitely.

**Concrete fix:** Define writer authority independently of `scannedHere`, for example authoring/recovery only for the currently logged-in `UnitGUID("player")`, with an explicit handoff rule for installation changes. Never replace authoritative local content through replica merging. Reconcile equal-revision/different-hash conflicts as well as higher revisions, and specify how peers report their retained version to the active writer. Add equal-revision reset, stale installation, and recovery-message fixtures.

**No defect found** in maximum `(rev, hash)` as a total order for immutable replica snapshots, or in full-snapshot omissions replacing per-entry tombstones. The defect is the authority/recovery layer.

**F2 — MAJOR: Aggregate shedding can mark undelivered plugin updates as synchronized.**

Evidence: [plan:72](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:72) proposes removing plugin blobs until the compressed message fits, but does not specify receiver-visible omission or retry bookkeeping.

AltStable filters later deltas by character timestamps at [Core.lua:1235](C:/Projects/WoW/AltStable/Core.lua:1235), advances the received timestamp even for skipped records at [Core.lua:1411](C:/Projects/WoW/AltStable/Core.lua:1411), and advances the peer watermark at [Core.lua:2493](C:/Projects/WoW/AltStable/Core.lua:2493). Sending a character record while shedding its GG blob can therefore advance synchronization past an update GG never received. Once capacity becomes available, that unchanged record need not be sent again. The receiver retains its old profiles/baselines without learning that the newer GG snapshot was omitted.

**Concrete fix:** Require per-peer pending-delivery bookkeeping for shed plugin revisions, independent of the core watermark. Send an explicit unavailable/deferred marker for affected GG records, and retry their snapshots when capacity permits. Define a terminal refusal/reporting outcome if the envelope plus non-plugin data still exceeds the ceiling after all plugins are removed.

**No defect found** in the per-character ladder ending in a header-only `overflow=1` snapshot, provided its hash describes the transmitted snapshot. Treating 24 KB as a measured target is also correct.

**F3 — MAJOR: Baseline expiry can leave a destructive-action override token unchanged.**

Evidence: [plan:155](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:155) hashes GUID, generation counters, and an `expiresAt` bucket. [Plan:198](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:198) requires expiry re-reading but does not require an expiry transition to advance a generation or invalidate the token.

For a baseline with deadline `T`, queries immediately before and after `T` have the same GUID, generations, and deadline bucket. The verdict can change from a fresh assessment to `unknown` while the token stays identical. A previously recorded `{guid, token}` override can consequently survive the newly stale assessment.

**Concrete fix:** Detect freshness transitions synchronously before returning or checking a token. Advance an assessment/freshness generation and invalidate existing overrides on that transition; queue `EvaluationInvalidated` for consumers afterward. Alternatively, make token validity explicitly time-bounded and require Shatter to reject the stored override after its deadline before considering a fresh assessment.

**No defect found** in synchronous, bounded, fail-closed `AssessProtection`, or in checking expiry on every query rather than relying on a timer. Those changes fix stale `clear`; token validity needs the additional rule.

**F4 — MAJOR: The async contract bounds item loading, but not deferred computation or reliable completion consumption.**

Evidence: [plan:184](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:184) promises pending placeholders and `EvaluationReady`, while [plan:190](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:190) bounds targets per call, batch size, evaluations per frame, and unique item loads.

Repeated calls using already-loaded items can still enqueue arbitrarily many contextual evaluations/request subscribers. The 256-item loading limit does not constrain that backlog.

Additionally, `EvaluationReady` promises re-query cache hits while explicitly retaining results only in an evictable LRU. Completed entries may be evicted before the consumer re-queries. Re-querying may therefore return fresh pending placeholders despite the completion notification; no retention window or recovery semantics are specified.

**Concrete fix:** Bound outstanding computation jobs and request subscriptions globally, deduplicate identical work, and define terminal overload/cancellation outcomes. Either retain each completed request until consumption or a documented deadline, deliver results with the completion callback, or explicitly redefine the callback as a best-effort re-query hint with bounded restart semantics.

**No defect found** in the stated aggregate precedence for display results: an upgrade may coexist with pending recipients because individual rows remain present. Protection must continue aggregating recipient safety independently; a display aggregate is not a `clear` verdict.

**MINOR — Remaining wording and schema cleanup**

- The API summary omits `Ready` and `EvaluationReady` from its event list, `IsReady()` from its method list, and `expiresAt` from the protection result shape; `profile.epoch` also remains after the protocol abandoned epochs. Reconcile [plan:170](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:170), [plan:177](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:177), and [plan:180](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:180) with the lifecycle contract.
- The review log’s “Fixed” claims for N1–N4 are premature ([plan:302](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:302)). Record them as attempted resolutions pending this round’s corrections.

**No additional material proposal-presented-as-existing defect found.** AltStable extensions, Shatter integration, and runtime probes remain identified as future work. The remaining over-promises are the owner-always-wins guarantee and unconditional completion cache-hit guarantee described above.

Validation used read-only file/range reads, targeted `rg` searches, and small in-memory counterexamples for revision ties, expiry-token inputs, and LRU eviction. No files changed; no client/runtime tests ran.

CHANGES NEEDED