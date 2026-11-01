**No BLOCKER remains, but MAJOR issues remain.** Of the 15 round-1 entries, **8 are RESOLVED and 7 are PARTIAL**. The ownership boundary is now an explicit prerequisite, and I withdraw round 1’s objection to the owner’s intended default amber markers on transferable bag items.

I checked the revised plan against the local sources. The Blizzard UI checkout is `forever`, commit `ca8368f2f`, build **70532**, matching the newest local API dump.

**Round-1 disposition**

References below are to the [revised plan](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md).

| R1 # | Disposition | Assessment |
|---:|---|---|
| 1 | **RESOLVED** | Lines 47–54 require sender/destination enforcement before plugin callbacks, validated per-character provenance, and unavailable alt features until the extension ships. This addresses the blocker. |
| 2 | **PARTIAL — MAJOR** | Lines 63–70 resolve single-line encoding, headless registration, backfill, and one-sided installation. The 1200-byte cap and aggregate-size guarantee remain incomplete; see **N2**. |
| 3 | **PARTIAL — MAJOR** | Independent dispatch, immutable remote copies, epochs, tombstones, and scheduling separation are explicit. Epoch ordering is still incomplete and can fail under clock rollback; deletion after tombstone expiry also needs defined snapshot semantics. See **N1**. |
| 4 | **RESOLVED** | Manual mapping remains available and automatic inference remains probe-gated, including unknown results for ties/unspent builds. **No defect found** in the basic spec model. |
| 5 | **RESOLVED** | Lines 79–85 now specify resulting configurations, uniqueness checks after displacement, both weapon transitions, replacement output, and confirmed-empty-slot handling. **No defect found** in the revised comparison contract at this level. |
| 6 | **RESOLVED** | Lines 89–94 define precedence, occupancy, capture information, staleness, and the prohibition on `clear` from incomplete/stale/fallback baselines. Lines 223–224 make the first slice’s baseline explicit. The new time-dependent cache issue is covered under R1 #11 / **N3**. |
| 7 | **PARTIAL — MAJOR** | Symmetric enchant handling, preserved suffix fields, supported-token reporting, limitations, and fixtures are specified. **Still missing:** whether `EFFECT_NOT_SCORED`, `SET_BONUS_NOT_SCORED`, or unmodelled zero-stat items can yield protection `clear`. A limitations array does not prevent that. **Fix:** explicitly return `unknown`/keep whenever an unmodelled contribution could change the relevant comparison, unless a documented supported model resolves it. Evidence: plan:76–87, 135–146. |
| 8 | **RESOLVED** | Lines 127–134 separate binding classification, ownership, and tri-state transfer; distinguish instances from hypothetical links; and leave account-bound eligibility unknown pending probes/trustworthy identity. **No defect found** in that policy. |
| 9 | **RESOLVED** | Lines 135–146 define fail-closed states, current GUID lookup, opaque tokens, override scope, excluded-row UI, synchronous checking, and invalidation. **No separate defect found** in the override token approach or Solo-only placement. Time-dependent invalidation still needs N3. |
| 10 | **PARTIAL — MINOR** | Modifier release reconciliation, combat deferral, tooltip guards, and unavailable replacement-bag adapters are addressed. Focus tracking covers bags but misses other reveal surfaces; see **N5**. |
| 11 | **PARTIAL — MAJOR** | Identity-aware contextual caching, generation counters, and destructive-check GUID/binding reads address the original key problem. The newly introduced age rule can change a verdict without changing any listed generation; see **N3**. |
| 12 | **PARTIAL — MAJOR** | Targets, cardinality, ordering, capabilities, readiness, copies, and item-load retry counts are substantially improved. Aggregate-status precedence and queued-work completion/bounds remain unspecified; see **N4**. |
| 13 | **RESOLVED** | Lines 109–116 explicitly implement the owner’s row-3 default. **No defect found** in persistent amber markers for transferable bag upgrades. The introductory “ordinary bag arrows” shorthand does not override the now-explicit exception. |
| 14 | **PARTIAL — MINOR** | M0’s boundary, separate art status, traceability, fixtures, and first slice are now clear. However, line 239 requires contracts before corresponding code, while execution steps 3–4 put core/tests before docs (256–257). **Fix:** move contract/ADR decisions before matching implementation in the execution order. |
| 15 | **RESOLVED** | Line 179 uses `SavedVariablesPerCharacter`. Proposed GG and cross-repo APIs remain labelled as proposals. **No defect found** in the corrected TOC key or Glass UI dynamic-member terminology. |

**New or newly exposed findings**

1. **N1 — MAJOR: Epoch conflict resolution is not a complete, order-independent merge rule.**

   **Evidence:** [plan:55](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:55) chooses revisions within an epoch, timestamps between epochs, and a hash tie-break only for equal revision **and equal epoch**. Different epochs with equal timestamps have no winner.

   More seriously, without an enforced monotonic timestamp invariant, the rules admit this cycle:

   | Record | Epoch | Revision | `updatedAt` |
   |---|---|---:|---:|
   | A | E | 1 | 300 |
   | B | E | 2 | 100 |
   | C | F | 1 | 200 |

   B beats A by revision; C beats B by timestamp; A beats C by timestamp. Delivery order can therefore change the final result. A reset following clock correction can also lose to the pre-reset epoch. Clock skew is an established concern in this ecosystem, documented in [AltStable/Core.lua:980](C:/Projects/WoW/AltStable/Core.lua:980).

   **Concrete fix:** define an immutable epoch-order/reset-authority mechanism, followed by revision and deterministic content tie-breaking. For example, use a reset generation persisted outside the resettable payload, or an explicit authoritative reset handshake; do not choose epoch precedence from each record’s changing `updatedAt`. Specify equal-time behavior and test reordered delivery, reset, and clock rollback.

   Also define deletion after the 30-day tombstone TTL: a returning peer must receive an authoritative full snapshot whose omissions remove old entries, or deletion information must remain until that peer can safely reconcile. “Tombstones expire after 30 days” alone does not define that recovery.

2. **N2 — MAJOR: The 1200-byte cap does not establish the advertised capacity or the 24 KB aggregate bound.**

   **Evidence:** [plan:63](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:63) allows 160 stat values plus 76 item strings, but specifies neither weight precision/range nor other variable-field bounds. “Drop baselines first” does not say what happens when profiles and headers alone exceed 1200 bytes.

   Fifty capped records permit **60,000 pre-deflate bytes** of GG data. Their compressed size depends on their contents. The existing approximately 9 KB/28-character figure is an observation, not a worst-case bound for 50 characters and other plugin data. AltStable sends the entire compressed payload in one message and explicitly has no BNET fallback for oversized sends: [Core.lua:1826](C:/Projects/WoW/AltStable/Core.lua:1826). LibAccountSync enforces its actual payload ceiling at [LibAccountSync.lua:1154](C:/Projects/WoW/LibAccountSync/LibAccountSync.lua:1154).

   **Concrete fix:** define numeric precision/range, bounded metadata, and the terminal overflow outcome after all baselines have been removed. Then choose either pagination or an **enforced runtime aggregate limit** measured on the final serialized/compressed message, including envelope and other data. Treat 24 KB as a target until demonstrated; a fixture cannot substitute for the runtime check. Explicitly invalidate remote baseline completeness when a newer publication omits baselines due to overflow.

3. **N3 — MAJOR: Time can invalidate a cached protection result without invalidating its token or cache entry.**

   **Evidence:** [plan:92](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:92) makes a baseline stale after 14 days. The cache uses identities and generation counters at [plan:170](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:170), while the override token hashes GUID plus generation counters at [plan:139](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:139). Only GUID and binding are explicitly re-read for protection.

   An assessment cached just before the cutoff can remain `clear` just after it, with unchanged generations. This contradicts the stated prohibition on `clear` from stale baselines. The same omission affects the promise that overrides expire when their assessment inputs change.

   **Concrete fix:** assign contextual results an expiry derived from their baseline timestamps, check freshness synchronously on every protection query, and reject expired cached assessments. Expiry must invalidate the assessment/token and notify consumers; a timer can refresh displays, but correctness must not depend on that timer firing before the click.

   **No defect found in choosing 14 days itself.** It is a conservative product policy. Also, `lastUpdate` is not inherently a gear-change stamp: [AltStable/PublicAPI.lua:125](C:/Projects/WoW/AltStable/PublicAPI.lua:125) documents plugin touches moving it. Implement the second staleness condition using the proposed gear-change information, not every `CharactersChanged` notification.

4. **N4 — MAJOR: “Continue next frame” lacks a completion contract and does not fully bound work.**

   **Evidence:** [plan:157](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:157) promises one result per recipient, while [plan:167](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:167) defines only item-data completion notifications and [plan:170](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:170) defers work after 200 evaluations.

   A 64-item batch across 50 characters × four specs permits 12,800 item/spec evaluations. Even with all item data cached, most work must be deferred. The contract does not specify what the initial call returns, how `requestId` retrieves completed work, or which callback signals computation completion. `ItemDataReady` alone cannot cover this case.

   Batch size also does not bound repeated calls, queued unique item IDs, target-list size, or retained results. “Retry ×3” lacks a timeout for a load request that never completes. Aggregate status is named but its precedence remains undefined.

   **Concrete fix:** specify pending placeholders or a request-handle result, a completion/requery mechanism, aggregate-status rules, queue/target limits, and item-load timeout behavior. Keep `AssessProtection` synchronous: return a freshly validated cached verdict or fail-closed pending/unknown within budget, with background completion only requesting a rescan. **No defect found in the numerical limits 64 or 200 themselves.**

5. **N5 — MINOR: The focus poll stops when bags close, although reveal also applies to loot.**

   **Evidence:** [plan:118](C:/Users/nicol/.claude/plans/magical-floating-giraffe.md:118) polls focus only while bags are open and recomputes once on loot opening.

   With loot open and bags closed, hold Ctrl and then focus or unfocus an edit box without changing Ctrl. Neither a modifier event nor another loot-open event is required to occur, so reveal can remain stale. `OnEditFocusGained/Lost` are scripts on individual edit boxes, as shown in [InputBoxTemplates.xml:8](C:/Projects/WoW/wow-ui-source/Interface/AddOns/Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml:8); they are not a global focus-change subscription.

   **Concrete fix:** poll the current keyboard-focus state while **any reveal-dependent surface** is active, with a specified modest interval and refresh only on state changes. Alternatively, provide complete hook coverage for those surfaces. Clarify that polling observes focus; it does not receive edit-box script callbacks.

   **No defect found** in the revised combat-deferral behavior or preserving Ctrl-click by not consuming clicks.

**Existing versus proposed**

No additional material “already exists” misrepresentation was found in the integration descriptions:

- AltStable’s own-account plugin channel, headless registration, gear API, and `GearChanged` callback are explicitly required extensions. Current callbacks still receive only GUID/blob arguments at [Core.lua:850](C:/Projects/WoW/AltStable/Core.lua:850) and [Core.lua:897](C:/Projects/WoW/AltStable/Core.lua:897).
- Shatter’s GG veto, excluded-row presentation, and override action remain proposed work. Current scanning only adds candidates after the predicate succeeds at [ItemScanner.lua:190](C:/Projects/WoW/Shatter/ItemScanner.lua:190).
- Glass UI supports `dynamic = true` roster entries, but GlassGear still needs an entry; [Suite.lua:31](C:/Projects/WoW/GlassUI/Suite.lua:31) supports the plan’s distinction.
- The `GetItemStats` cache-miss claim has measured backing in [forever-api-notes.md:1070](C:/Projects/WoW/AltStable/docs/forever-api-notes.md:1070). The supplied SimC ZIP declares Interface 16001. **No defect found** in those claims.

The 24 KB result is still an **unproven proposed acceptance target**, and the review-log claim that all R1 issues were folded in is premature given the partial dispositions above.

Commands were read-only file/range reads, targeted `rg` searches, Git identity checks, in-memory ZIP inspection, and a small illustrative merge-order calculation. **No files changed; no client/runtime tests ran.** The next revision should close the partial contracts before implementation.

CHANGES NEEDED