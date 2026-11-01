**One MAJOR defect remains: overflow snapshots are not safe inputs to writer recovery and three-way reconciliation.** The direct round-4 overwrite counterexample is fixed. The echo clarification still contains a contradictory transition, which I classify as MINOR given the explicit non-escalation and idempotency requirements.

| Previous finding | Disposition | Reason |
|---|---|---|
| F1: older dirty installation overwrites newer edits | **RESOLVED for complete snapshots** | Against the common base, conflicting edits retain R’s version as current and preserve the local version as a conflict copy. Remote deletions are no longer blindly overwritten by the whole dirty snapshot. |
| Echo-loop MINOR | **PARTIAL** | The bounded-cycle and non-escalation wording is correct, but the `dirty and R ≤ base` branch still explicitly requires a revision bump on receipt of an older snapshot. |

**MAJOR — Overflow omissions can become destructive authoring changes during recovery or reconciliation.**

The [full-snapshot contract](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:55) says omission means deletion. The [writer reconciliation rules](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:67) adopt or merge received snapshots without a completeness condition. But the [overflow ladder](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:84) deliberately omits baselines and can publish **no profile content at all**, with `overflow=1`.

A sequential counterexample:

1. Both installations know base revision 9 containing profiles P and Q.
2. A edits P offline, producing dirty revision 10; Q remains unchanged.
3. Later, B edits its profiles and publishes revision 11 through the supported header-only `overflow=1` path. B still has P and Q locally; neither was deliberately deleted.
4. A receives revision 11. Since `R > base`, the prescribed three-way merge runs.
5. P appears deleted remotely and edited locally, so A preserves its P as a conflict copy. **Q appears changed only remotely—from present to absent—so the automatic merge removes Q.** There is no conflict copy for Q.

The clean-writer case is simpler: an older, non-dirty installation adopts the newer header-only R, replacing its usable authored profiles with an unavailable representation.

Calling remote profiles or baselines “unavailable” correctly protects remote evaluation, but the plan does not carry that distinction into authoring, deletion detection, or base selection. This is a newly exposed interaction with recovery; **the overflow ladder itself remains a valid transport policy**.

**Concrete fix:** Distinguish complete authoring snapshots from incomplete transport representations. Overflow omissions must never count as deletions, seed a complete reconciliation base, or replace retained authored content. An incomplete receipt may update remote availability and delivery metadata; writer reconciliation must preserve local content and wait for complete data, or explicitly report recovery unavailable. Define how the transmitted hash and exact-echo acknowledgement relate to this distinction. Add fixtures for dirty and clean writers receiving header-only overflow, plus baseline-only shedding.

**MINOR — The older-echo transition contradicts non-escalation.**

[Lines 64–66](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:64) prohibit revision bumps from equal or older receipts. [Line 72](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:72) nevertheless says:

> dirty and R ≤ base → no divergence: publish authored at `max(rev) + 1`

With base 9 and dirty authored revision 10, receiving echo 9 requires revision 11 under that branch. Receiving it again requires 12 if the branch is followed literally. The explicit idempotency requirement prohibits that result, so this is an inconsistent transition definition rather than evidence that the intended protocol necessarily loops.

**Concrete fix:** For `R ≤ base`, retain the already-versioned dirty authored snapshot and let bounded scheduling resend it unchanged. Specify exact-echo acknowledgement before divergence processing and make stale/duplicate delivery a no-op for reconciliation. Allocate a new revision only for an actual local change or a newly computed merge result requiring publication.

The remaining sequence checks produced these results:

| Sequence/check | Assessment |
|---|---|
| Original A-dirty-10 → B-newer-11 → A-login | **No defect found with complete snapshots.** Conflicting values preserve A’s copy and keep B’s current value; B’s deletions are not blindly resurrected. |
| Reset, then complete replicas arriving in either order | **No defect found** under the specified total-order acceptance rule: unseeded adopts the first, then advances to the greater snapshot. |
| Exact authored echo delivered repeatedly | **No defect found** when exact-echo acknowledgement is processed first: the first clears dirty; later copies do not change content or revision. |
| Older or reordered receipts | Immutable replica maximum selection is sound. The contradictory dirty transition above needs correction; older arrivals must not re-run reconciliation against a superseded remote state. |
| No peer exists | **No defect found in dirty remaining set.** It truthfully represents unacknowledged publication; it need not prevent local editing or evaluation. |
| Keeping base snapshot content | **No BLOCKER/MAJOR defect found.** One retained local base does not inherently consume the wire budget or create unbounded history. |
| Conflict-copy UX and four-profile limit | **No independent BLOCKER/MAJOR defect found.** Clarify as MINOR that unresolved copies are local recovery records, with stable deduplication and explicit resolution, rather than automatically occupying active synchronized profile slots. |

**Elsewhere in the plan, no additional BLOCKER/MAJOR defect found.** The previously resolved trust-boundary, aggregate-delivery bookkeeping, freshness/override, bounded-async, and M0-capability contracts remain intact.

Validation: read the revised plan and all four prior verdicts, performed targeted local source and commit checks, and exercised illustrative transitions in memory. Commands were read-only `Get-Content`, `Get-ChildItem`, `Test-Path`, `rg`, and `git rev-parse`. No files changed; no implementation or client tests ran.

CHANGES NEEDED