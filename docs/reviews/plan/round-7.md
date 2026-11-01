**The round-6 MAJOR is resolved for both reported counterexamples. No BLOCKER found. Two MAJOR issues remain in ADR-0001: snapshot-wide ancestry can incorrectly fast-forward an omitted section, and bounded receipt history does not uphold the promised duplicate suppression.**

**MAJOR 1 — Ancestry must establish descent separately for each section.**

The [completeness rules](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:72) correctly exclude incomplete sections from reconciliation. However, the [new ancestry rules](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:78) provide one snapshot ID, ancestor list and `integrated` set, then use those identities to authorize adoption **per complete section**.

A snapshot can descend from a packet without having received the content that packet omitted:

1. A and B hold complete snapshot S9, with baseline X.
2. A changes its baseline to Y and publishes A10. Overflow makes `baselinesComplete=false`; A retains Y locally.
3. Later, the character logs into B. B receives A10 and adopts its complete profiles. Correctly, B does **not** adopt the omitted baselines; it retains X.
4. B makes a profile edit that reduces payload size. Its next publication B11 includes complete profiles and baseline X, with A10 in its snapshot ancestry.
5. The character returns to A. A receives B11. Its baseline section is complete, and A10 is an ancestor of B11.
6. The specified fast-forward branch adopts X over Y **without a baseline conflict copy**, although B never received Y.

The incomplete packet itself causes no deletion. The subsequent complete descendant causes the loss. A single snapshot-wide identity cannot express “profiles incorporated; baselines not incorporated.”

**Concrete fix:** Track authoring identity, ancestry, integration and reconciliation base per section, or provide an equivalent explicit rule that prevents snapshot ancestry from proving descent through an omitted section. A partial adoption must not advance the baseline’s authoring identity. In this example, B11’s baseline descends from X’s section identity, while A’s Y is a separate change that must enter baseline reconciliation.

Add the full `complete S9 → baseline-shed A10 → complete B11 → A receipt` fixture. The existing baseline-shedding fixture covers only the first receipt.

AltStableSync does not establish safety for this extension: its [fast-forward rule](C:/Projects/WoW/AltStableSync/docs/DESIGN.md:923) replaces a versioned entry whole. It does not partially adopt sections under one entry identity.

**MAJOR 2 — Evicting integrated IDs makes previously processed snapshots become “unseen” again.**

The plan promises that [duplicate or already-integrated receipts cause no revision bump](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:65), but retains only [32 integrated IDs and eight ancestor IDs](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:79). Once those records expire, the [fallback transition](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:86) treats an old receipt as divergent and assigns another merge revision.

Concrete sequence:

1. A integrates divergent R into merge M.
2. A makes 33 subsequent local publications. R is now outside both bounded histories, and its common-base content need no longer be retained.
3. A receives exactly the same R again.
4. Neither no-op test recognizes it. The no-base fallback runs and allocates another revision, despite no new remote change.

Deduplicating conflict copies by entry ID and source hash does not prevent that revision allocation. With a repeated sequence of enough old IDs to evict earlier receipts, the same mechanism can keep generating merge revisions. An immediate duplicate of one ID is safe; arbitrary late duplicates are not.

This is a meaningful difference from AltStableSync. Its [divergence rule](C:/Projects/WoW/AltStableSync/docs/DESIGN.md:924) leaves the root unchanged and suppresses a repeated conflict ID whether that copy is live **or tombstoned**. Its [resolution rules](C:/Projects/WoW/AltStableSync/docs/DESIGN.md:930) separately define when a new root version is minted.

**Concrete fix:** Make the bounded sets caches rather than the sole correctness mechanism. Either retain durable processed/resolved receipt identities locally, or use a stable conflict-record fallback that does not automatically advance the root and retains resolution markers. Merely increasing 32 postpones the failure. Specify how this survives reload and conflict resolution.

Add “integrate R → exceed both retention windows → replay R,” plus a rotating replay fixture. Assert no new revision, `TouchCharacter`, or repeated recovery record for already processed input.

The requested counterexamples otherwise trace as follows:

| Sequence | Assessment |
|---|---|
| Equal revision, smaller hash, unseen divergent branch | **Round-6 defect resolved; no defect found in routing.** Reconciliation runs before replica selection, regardless of ordering. With the common base held, A’s P edit and B’s Q deletion merge correctly. |
| Lower revision, unseen divergent branch | **Round-6 defect resolved; no defect found in routing.** The same ancestry-based branch applies. |
| A-dirty → B-newer → A-login | **No defect found for complete snapshots with a usable common base.** Remote-only deletions apply; competing local edits survive as conflict copies. Without a held base, this becomes explicit conflict recovery rather than an automatic three-way merge. |
| Dirty or clean writer receives header-only overflow | **No defect found.** Neither section enters adoption or reconciliation. |
| Baseline-only shedding, immediate receipt | **No defect found in immediate preservation.** The later complete-descendant case fails as described in MAJOR 1. |
| Exact current authored echo, repeated | **No defect found.** It acknowledges complete sections without allocating another revision. |
| Recently integrated branch delivered again | **No defect found while its identity remains recognized.** Late replay after eviction fails as described in MAJOR 2. |
| Reset/unseeded writer receives a complete replica | **No defect found.** Explicit seeding avoids the earlier equal-revision rejection. Partial seeding needs the section-specific identity rule from MAJOR 1. |

**The held-common-ancestor rule is implementable with one retained content snapshot.** It is a restricted lookup: use that snapshot only if its ID is demonstrably an ancestor of both branches and its relevant section is complete; otherwise there is no usable held ancestor. “Nearest” does not require retrieving unavailable historical content. **No defect found in keeping only one candidate base**, although this will produce more conflicts than retaining additional bases.

Likewise, **the no-base conflict fallback does not inherently lose data**: it can preserve both alternatives for every differing entry. It must preserve absence as an alternative too, so an edit-versus-deletion conflict remains resolvable. It does not inherently create an immediate echo loop, but the bounded-history/new-revision combination currently prevents an unconditional no-loop or idempotence claim, as described above.

**MINOR — Tighten the remaining recovery wording.**

- [Lines 69–70](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:69) retain the base content from which authored changes derive; [lines 87–88](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:87) describe the retained content as the “last published snapshot.” State exactly when this retained content advances. Publishing a dirty descendant does not make that descendant a common base with an unseen branch.
- Specify the no-base fallback’s active-value choice and conflict-record shape, including an explicit absent/deleted alternative. “Every differing entry becomes a conflict copy” leaves those mechanics implicit.
- State that a merge’s ancestry includes **both parents**, followed by their histories under a defined truncation rule. AltStableSync [states this explicitly for resolutions](C:/Projects/WoW/AltStableSync/docs/DESIGN.md:930).
- Qualify the [“R ≤ base → no rev bump” fixture](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:102) as a **known ancestor or integrated receipt**. Numeric ordering alone is no longer sufficient, correctly.

**Elsewhere in the plan, no additional BLOCKER/MAJOR defect found.** The trust-boundary prerequisite, aggregate shedding/retry bookkeeping, fail-closed protection, synchronous freshness invalidation, bounded async contract and M0 capability boundary remain intact. The two findings above affect the foundation’s sync contract and schema; they do not require implementing M2 transport during M0.

Validation: read the revised plan, verdicts R1–R6 and the cited AltStableSync design; used read-only `Get-Content`, `Get-ChildItem` and `rg`, plus small in-memory transition checks. **No files changed; no implementation or client tests ran.**

CHANGES NEEDED