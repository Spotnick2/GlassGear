Reviewed `0b390d8` against `66f3aa5`. **No BLOCKER found. Two MAJOR defects remain:** one introduced by the async rewrite, and one pre-existing hand-configuration error exposed by missing data.

The requested dispositions, based on rerunning the counterexamples:

| Finding | Disposition |
|---|---|
| Round 2 #1 — malformed flags/optional fields | **RESOLVED** — `"false"` deletion and malformed containers return `bad-entry` without throwing or changing the root; malformed baseline group is rejected. |
| Round 2 #2 — displaced/companion scoring uncertainty | **RESOLVED** — displaced Healing produces `BASELINE_WEIGHT_MISSING:Healing`; companion `Speed=X` produces `BASELINE_TOKEN_NOT_SCORED:Speed`; both prevent protection `clear`. |
| Round 2 #3 — companion exclusions/required level | **RESOLVED** — excluded, level-70, and missing-level companions produce `unknown`; the valid shield still produces the expected score-25 upgrade. |
| Round 2 #4 — successful events resetting retries | **RESOLVED** — repeated successful events with unusable data terminate after exactly three loads, with zero outstanding requests/waits. |
| Round 2 #5 — pending target drift | **RESOLVED** — `current` retains Holy, and `own` retains Holy/Discipline/Shadow order after remapping; timeout coverage also passes. |
| Round 2 #6 — unknown alternative ring slot | **RESOLVED** — the original case returns `unknown`, `ALTERNATIVE_SLOT_UNKNOWN`, `complete=false`, and protection `unknown`. |
| Round 1 #16 — overstated test guarantees | **PARTIAL — MINOR** — longest-token selection is corrected, but the fixture still claims “worst-case” without bounding other fields or asserting the exact size boundary. |

1. **MAJOR — Reevaluation can strand requests when newly discovered dependencies cannot enter the queue.**

   At [API/PublicAPI.lua:243](C:/Projects/WoW/GlassGear/API/PublicAPI.lua:243), reevaluation replaces `entry.itemIDs`, records every new dependency, and ignores a failed `wait(w)`. The arriving item occupies its queue slot until line 252. Dependencies dropped from the previous set also remain in `state.waiting`, even when no request needs them.

   **Reproduced:** with `itemQueue=1`, start a pending candidate request, equip a different uncached baseline item, then deliver the candidate’s successful load. The new baseline dependency cannot enter the full queue. The candidate is subsequently removed, leaving **zero waits, one outstanding request, and no callback after 30 seconds**.

   I also reproduced this with the **unchanged default limits of 256 items/64 requests**: successive equipment changes during one pending request accumulate obsolete waits. After filling the queue and resolving the candidate, its 17 current baseline dependencies are all unqueued. After 30 seconds, the result is again **zero waits, one outstanding request, zero completion callbacks**.

   **Fix:** reconcile dependency subscriptions and release obsolete waits when no other request needs them. Preserve budgets for dependencies that remain missing. Check every `wait()` result; an unqueueable dependency must terminate the request with the documented `unknown`/`ITEM_QUEUE_FULL` response rather than leave an unserviceable pending request.

2. **MAJOR — Unknown main-hand data can make an off-hand falsely qualify as an empty-slot upgrade.**

   [Evaluate.lua:175](C:/Projects/WoW/GlassGear/Engine/Evaluate.lua:175) converts an occupied item without tokens to `state="unknown"`. [SlotCompare.lua:77](C:/Projects/WoW/GlassGear/Engine/SlotCompare.lua:77) handles two-handed displacement only when the main hand remains `occupied`; otherwise the off-hand path checks only slot 17 and can mark it empty.

   **Reproduced:** level-60 Holy Paladin, `Intellect=1`, score-5 shield candidate, slot 17 empty, and slot 16 containing:
   ```lua
   { state = "occupied", itemID = 10,
     equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 5 }
   ```
   With its tokens unavailable and no companion supplied, evaluation returns **`upgrade`, baseline score `0`, `EMPTY_SLOT`, and protection `protect`**. Supplying that same two-hander’s tokens changes the result to `unknown`/`NEEDS_COMPANION`.

   This violates the M0 pure-engine contract: the configuration has not established a legal empty off-hand or scored the displaced two-hander. Runtime pending handling does not correct the pure engine’s result.

   **Fix:** require sufficient main-hand facts before accepting an off-hand configuration. An unknown main hand must propagate `unknown`; a known two-handed equip location must retain the displacement/companion requirement even when its score is unavailable. Add regressions for both missing occupancy and occupied two-hand items with missing tokens.

**No new defect found** in the strict flag/container checks, `scoringGaps` propagation for the selected displaced items and companion, companion `reqLevel`/`ignoredHit` filtering, captured spec targets, or Policy’s `BASELINE_` limitation prefix. **No defect found** in shared-request cancellation: cancelling one subscriber preserves the load for the other, which completes normally. The original alternative-ring case and valid companion configuration also behave correctly.

For **MINOR #16**, the current stress fixture encodes to 1,789 bytes. Changing only its origin from 60 to 200 escaped characters remains valid profile data but returns `too-large`, so “worst-case fits 2 KB” is still too broad. Rename it a bounded stress fixture and add exact boundary assertions. My independent checks confirmed **2,047 and 2,048 bytes accepted; 2,049 rejected**—no encoder boundary defect found.

Validation: all **11 Lua test files passed, 654 assertions**; `luac -p` passed for **40 Lua files**; additional counterexamples ran through stdin. `git diff --check` reports only Markdown trailing spaces in the archived round-2 review. No files changed; working tree clean. No deployment or in-game checks ran. No additional BLOCKER/MAJOR found in the inspected M0 scope.

CHANGES NEEDED