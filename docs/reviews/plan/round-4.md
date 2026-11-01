**No BLOCKER remains. One MAJOR remains: F1’s dirty-writer reconciliation can let an older installation overwrite a newer deliberate edit.** The other three round-3 major findings are resolved at the plan-contract level.

| Previous item | Disposition | Assessment |
|---|---|---|
| R1 #2 | **RESOLVED** | Aggregate shedding now requires deferred markers, per-peer delivery bookkeeping independent of core watermarks, retries, and terminal refusal; **no defect found**. [Plan:79](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:79) |
| R1 #3 | **PARTIAL** | Writer authority and separate stores improve recovery, but dirty reconciliation can overwrite newer edits; see F1 below. [Plan:59](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:59) |
| R1 #11 | **RESOLVED** | Synchronous freshness transitions change the token, and Shatter independently rejects expired overrides; **no defect found**. [Plan:168](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:168) |
| R1 #12 | **RESOLVED** | Global job/request bounds, terminal overload, cancellation, and completion carrying a deep-copied response close the outstanding contract gaps; **no defect found**. [Plan:201](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:201) |
| N1 | **PARTIAL** | Immutable replica ordering is deterministic, but cross-installation author reconciliation remains incorrect; see F1. [Plan:55](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:55) |
| N2 | **RESOLVED** | Per-character overflow and aggregate delivery requirements are explicit; 24 KB remains a target rather than a guarantee; **no defect found**. [Plan:74](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:74) |
| N3 | **RESOLVED** | Expiry is checked synchronously and advances freshness generation before returning; **no defect found**. [Plan:169](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:169) |
| N4 | **RESOLVED** | Deferred computation and subscriptions are bounded, and consumers receive completed results without depending on LRU retention; **no defect found**. [Plan:203](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:203) |
| F1 | **PARTIAL** | Logged-in-GUID authority removes the `scannedHere` authority problem; the new dirty rule still permits a stale-installation win. [Plan:65](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:65) |
| F2 | **RESOLVED** | The required AltStable extension now explicitly addresses undelivered revisions advancing past core watermarks; **no defect found**. [Plan:80](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:80) |
| F3 | **RESOLVED** | Both requested safeguards—freshness generation and explicit override expiry rejection—are present; **no defect found**. [Plan:168](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:168) |
| F4 | **RESOLVED** | The 512-job/64-request limits, `OVERLOADED`, `CancelRequest`, and response-bearing completion close the reported issues; **no defect found**. [Plan:205](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:205) |
| R3 MINOR: API/schema summary | **RESOLVED** | `IsReady`, both readiness events, and `expiresAt` are listed; `profile.epoch` is removed; **no defect found**. [Plan:182](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:182) |
| R3 MINOR: premature resolution claims | **RESOLVED** | R2 and R3 now describe their changes as “Attempted”; **no defect found** in that correction. [Plan:325](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:325) |

**F1 — MAJOR: An older unpublished edit can defeat a newer published edit after an installation handoff.**

The rule at [plan:65–69](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:65) preserves dirty authored content and republishes it at `max(rev) + 1`. Being dirty establishes that an edit is unpublished; it does **not** establish that it is the latest deliberate edit.

A counterexample requiring no simultaneous writers:

1. Installation A edits the character’s snapshot to revision 10 while transport is unavailable, then logs out. Its authored snapshot remains dirty.
2. The character is subsequently played on installation B. B makes newer deliberate edits and publishes revision 11.
3. The character later logs into A, without making another edit. A receives B’s revision 11.
4. The prescribed dirty branch republishes A’s older content at revision 12. Replicas converge on A’s old snapshot, replacing B’s newer changes.

Every authoring action satisfies the logged-in-GUID restriction. Separate authored and replica stores prevent direct replica overwrites, but the reconciliation step still promotes stale content. Full-snapshot replacement means this can also resurrect profiles deleted on B.

**Concrete fix:** Persist the base snapshot identity for pending edits and define divergence handling. When dirty edits and an incoming snapshot diverge from that base, preserve both and expose an explicit conflict; do not automatically promote the entire dirty snapshot above the incoming version. Apply pending changes automatically only where their relationship to the incoming snapshot is established. Define exactly when dirty clears and ensure serialization or send scheduling alone does not establish successful reconciliation. Replace “latest deliberate edit wins” with the actual supported conflict policy. Add the sequential A-dirty → B-newer-published → A-login fixture above.

This is the remaining F1 defect, exposed by the revised rule, rather than a separate additional finding.

**Other requested checks: no separate BLOCKER/MAJOR defect found.**

- **Replica ordering and echoes:** Maximum `(rev, hash)` remains a valid deterministic order for immutable snapshots. Separate stores and logged-in-GUID authority address the earlier authority problem. Echo handling needs the minor clarification below.
- **AltStable deferred bookkeeping:** The requirement now correctly separates plugin delivery from core synchronization progress. That matches the actual hazards in [serialization filtering](C:/Projects/WoW/AltStable/Core.lua:1235), [received timestamp advancement](C:/Projects/WoW/AltStable/Core.lua:1411), and [peer watermark advancement](C:/Projects/WoW/AltStable/Core.lua:2493). No defect found at this contract level.
- **Freshness and Shatter:** Expiry cannot retain the old token across a detected freshness transition, and override rejection does not depend on timer delivery. No defect found.
- **Bounded asynchronous evaluation:** Global limits cover the previously unbounded jobs and subscriptions. Terminal overload avoids leaving rejected calls awaiting callbacks, and completed responses no longer depend on cache survival. No defect found in the proposed bounds, cancellation entry point, or completion payload.

**MINOR — Immutable echoes do not, by themselves, prove absence of message loops.**

[Plan:63–64](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:63) says unchanged echoes “cannot loop.” Two peers can repeatedly forward an identical payload without changing its revision. The existing idempotent-merge requirement makes this a clarification rather than another major finding.

**Fix:** State that receiving an equal or older snapshot causes no revision bump, `TouchCharacter`, or receive-triggered retransmission; echoes are sent only through bounded synchronization/request handling. Include duplicate delivery while the writer is dirty in the echo fixture. Say immutable echoes cannot create a **revision escalation by themselves**, rather than claiming immutability prevents all loops.

The remaining material over-promise is **“the latest deliberate edit wins,”** covered by F1. **No additional proposal-presented-as-existing defect found:** AltStable extensions, Shatter integration, and runtime probes remain explicitly future work.

Validation: read-only `Get-Content`/range reads, targeted `rg` searches, repository commit checks, and an in-memory reconciliation counterexample. **No files changed; no client or implementation tests ran.**

CHANGES NEEDED