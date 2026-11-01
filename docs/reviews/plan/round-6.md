**The round-5 MAJOR and MINOR are resolved for their reported counterexamples. One MAJOR remains: the new `R ≤ authored` early return can discard an unseen divergent edit. No BLOCKER found.**

The remaining defect is in ADR-0001’s reconciliation contract and should be corrected before that contract is carried into the foundation docs and tests.

| Sequence rechecked | Result |
|---|---|
| Dirty A at revision 10 receives header-only overflow revision 11 | **No defect found.** Both sections are incomplete, so neither enters reconciliation. P and Q remain authored content; Q is not interpreted as deleted. |
| Clean A receives newer header-only overflow | **No defect found.** Incomplete sections cannot be adopted or replace authored content. |
| Baselines are partially or wholly shed, but profiles remain complete | **No defect found in the completeness rule.** Profiles can reconcile or be adopted; the incomplete baseline section only changes remote availability. Retained baselines are not deleted, adopted from the packet, or replaced by it as a reconciliation base. |
| Dirty authored revision 10 repeatedly receives base revision 9 | **No defect found.** Content and revision remain unchanged; bounded scheduling can resend revision 10. The round-5 MINOR is resolved. |
| Exact authored echo, including an incomplete section | **No defect found in the acknowledgement rule.** Only complete sections can clear their dirty state; repeated acknowledgements do not allocate revisions. |
| Original A-dirty-10 → B-complete-11 → A-login | **No defect found for this sequence.** It reaches three-way reconciliation; conflicting local content is preserved in local recovery records, and remote-only deletions apply. |

These results follow from the revised [completeness and acknowledgement rules](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:70) and [unchanged-revision branch](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:78). The local-only, deduplicated conflict-copy policy also resolves the previous clarification: **no defect found** there.

**MAJOR — Total-order precedence is being mistaken for proof that a received branch is already obsolete.**

**Evidence:** [Plan:76](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:76) returns immediately for every `R ≤ authored`, before the [divergence check at plan:80](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:80). Consequently, the intended merge never runs when:

```text
base < R < authored
```

That interval can contain independent, previously unseen changes. A lower revision or lexical hash does not establish that the authored snapshot contains those changes.

Concrete counterexample, with complete snapshots and no simultaneous writers:

1. A and B both retain base revision 9, containing profiles P and Q.
2. While logged into the character on A, the owner edits P without synchronization. A produces dirty snapshot `(10, hA)`, retaining Q, then logs out.
3. Later, the owner plays the same character on B, which still has base 9, and deliberately deletes Q. B publishes `(10, hB)`, where `hB < hA`. Neither installation has seen the other’s edit.
4. The character returns to A. A receives B’s complete snapshot.
5. B’s snapshot is greater than A’s base but less than A’s authored snapshot. Line 76 therefore discards it without reconciliation.
6. A retains Q and creates no conflict or recovery record for B’s deletion. Its snapshot wins replica ordering, so synchronization can restore Q on peers.

The specified three-way rule would instead retain A’s P edit and apply B’s Q deletion: they changed different entries. The early return prevents that result. The same failure occurs without a hash tie when A made enough local edits to reach revision 12 while B’s independent edit reached revision 10.

**Concrete fix:** Separate immutable replica winner selection from writer divergence detection.

- Preserve `(rev, hash)` maximum selection for the replica store.
- For a dirty writer, do not discard an unseen complete snapshot solely because it sorts below `authored`. Reconcile applicable `R > base` branches before that shortcut.
- Make duplicate suppression depend on the persisted reconciliation base and already-integrated snapshot identities. An exact echo, an already-integrated receipt, or a genuinely stale receipt must remain a no-op; an unseen divergent branch may produce one merge revision.
- Ensure incoming branches reach writer reconciliation before replica maximum selection discards them. Add both the equal-revision/different-hash and unequal-revision examples above, followed by duplicate delivery to verify idempotence.

The blanket non-escalation wording at [plan:64](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:64) should be narrowed accordingly: processing duplicates must not bump revisions, but integrating previously unseen divergent changes is a substantive merge.

**MINOR — Qualify the introductory omission rule.**

[Plan:55](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:55) still says every publication is full and “omission = deletion,” while the later completeness rule correctly establishes exceptions.

**Fix:** Say that omission means deletion **within a section marked complete**; an incomplete section conveys availability only. This is wording cleanup because the operative completeness rule is explicit.

**Elsewhere in the plan, no additional BLOCKER/MAJOR defect found.** The own-account trust prerequisite, aggregate shedding and retry bookkeeping, fail-closed protection, synchronous freshness/token invalidation, bounded asynchronous evaluation, and M0 capability boundary remain intact. Runtime probes and ecosystem extensions remain identified as future work.

Validation consisted of read-only `Get-Content`, `Get-ChildItem`, and `rg` inspection of the plan, prior verdicts, and workspace instructions, plus an in-memory exercise of the written transition rules. **No files changed; no implementation or client tests ran.** At this final safety-cap round, the unresolved item is the divergent-branch rejection above.

CHANGES NEEDED