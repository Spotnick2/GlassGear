Reviewed `66f3aa5` against `f40d98f` on `foundation/scaffold`. **No BLOCKER found. Six MAJOR issues remain.** All 11 Lua test files pass: **630 assertions**. I reran the original counterexamples through the regression fixtures and additional Lua scripts supplied through stdin.

The actionable findings are:

1. **MAJOR — Incoming validation still accepts destructive malformed flags and can throw instead of rejecting an entry.**  
   [Engine/EntrySync.lua:72](C:/Projects/WoW/GlassGear/Engine/EntrySync.lua:72) treats any truthy `deleted` value as a deletion. A descendant entry with `deleted = "false"` is accepted with `"replace"` and tombstones the existing live root. Meanwhile, [Engine/Codec.lua:45](C:/Projects/WoW/GlassGear/Engine/Codec.lua:45) calls `pairs`/`ipairs` on optional fields without checking their types: `ignored=true`, `ignoredTokens=true`, and `missing=true` each raise a Lua error through `Store:Receive`.

   The rewritten baseline decoder also accepts `group=garbage`, silently converting it to absent metadata at [Engine/Codec.lua:200](C:/Projects/WoW/GlassGear/Engine/Codec.lua:200).

   **Fix:** validate optional container types, boolean flags, and supplied numeric fields before interpretation. Malformed input must return `bad-entry` without altering the store. The validator exceptions and malformed-group acceptance are new paths in the rewrite; permissive deletion flags remain from round 1.

2. **MAJOR — Baseline and companion scoring uncertainty still disappears before protection.**  
   Missing-weight and unsupported-profile-token checks run only on the candidate at [Engine/Evaluate.lua:137](C:/Projects/WoW/GlassGear/Engine/Evaluate.lua:137). Baseline scoring retains only `.score` at [Engine/Evaluate.lua:170](C:/Projects/WoW/GlassGear/Engine/Evaluate.lua:170), while the new propagation loop handles only `hasSpell` and raw unsupported keys at [Engine/Evaluate.lua:212](C:/Projects/WoW/GlassGear/Engine/Evaluate.lua:212).

   **Reproduced:**
   - WoWSims profile containing only `Intellect=1`; candidate has 9 Intellect; displaced baseline has 10 Intellect and 100 Healing → `no_upgrade`, empty limitations, protection **`clear`**.
   - Profile contains `Speed=X`; a holdable candidate plus main-hand companion replaces a two-handed weapon → unavailable weapon speed is omitted from limitations, and protection returns **`clear`**.

   **Fix:** collect relevant missing-weight and unscored-token limitations from every item participating in the selected comparison, including displaced items and companions. This is an incomplete fix for round-1 findings 4 and 7.

3. **MAJOR — Companions can still bypass profile exclusions and required-level rules.**  
   [Engine/Evaluate.lua:183](C:/Projects/WoW/GlassGear/Engine/Evaluate.lua:183) checks only class usability, then keeps the companion’s numeric score while discarding `ignoredHit`. It never applies the companion’s `reqLevel`.

   **Reproduced:** a level-60 Holy Paladin replaces a score-10 two-hander with a score-5 main-hand mace and score-20 shield. The result is **`upgrade`, `equipNow=true`, candidate score 25** both when:
   - the profile specifies `IsShield=X`; and
   - the shield requires level 70.

   **Fix:** validate companion eligibility, profile exclusions, required level, and necessary item facts before accepting the resulting configuration. Missing eligibility facts must remain unknown. `HandLegal` fixes the original slot-placement errors, but round-1 finding 6 remains partial.

4. **MAJOR — Successful load events with unusable data reset the retry budget indefinitely.**  
   [API/PublicAPI.lua:230](C:/Projects/WoW/GlassGear/API/PublicAPI.lua:230) removes the waiting record before reevaluation. If data remains unavailable, [API/PublicAPI.lua:239](C:/Projects/WoW/GlassGear/API/PublicAPI.lua:239) queues the same item again with a fresh attempt count.

   **Reproduced:** leave item data unavailable and deliver a successful load event after each five-second tick. After 25 seconds: **11 load requests, attempt count reset to 1, one outstanding request, no completion callback**.

   **Fix:** preserve the existing attempt count and deadline until usable data is confirmed or the request exhausts its budget. This is a new retry-reset behavior introduced by the queue rewrite; the original failed-event stranding case is fixed.

5. **MAJOR — Pending requests do not retain their original targets.**  
   [API/PublicAPI.lua:193](C:/Projects/WoW/GlassGear/API/PublicAPI.lua:193) saves `specs`, but completion and timeout reevaluate the original scope against the current spec mapping at [API/PublicAPI.lua:235](C:/Projects/WoW/GlassGear/API/PublicAPI.lua:235) and [API/PublicAPI.lua:257](C:/Projects/WoW/GlassGear/API/PublicAPI.lua:257).

   **Reproduced:** start a pending `scope="current"` request for Holy, then map the current spec to Shadow. Its terminal callback contains **Shadow instead of Holy**. An `own` request similarly changes from Holy/Discipline/Shadow to Shadow/Discipline/Holy.

   **Fix:** evaluate terminal responses against the captured target list, preserving row identities and order. This pre-existing target-drift behavior remains uncorrected by round-1 finding 9’s fix.

6. **MAJOR — An unavailable alternative slot can be ignored when declaring no upgrade.**  
   [Engine/SlotCompare.lua:144](C:/Projects/WoW/GlassGear/Engine/SlotCompare.lua:144) returns a known legal configuration even when another compatible configuration is unknown. Meanwhile, [Engine/Evaluate.lua:160](C:/Projects/WoW/GlassGear/Engine/Evaluate.lua:160) preserves baseline completeness even after unavailable item tokens turn a slot into `unknown`.

   **Reproduced through `Baselines.Choose`:** candidate ring has 9 Intellect; first equipped ring has 10; second ring is occupied but its tokens are unavailable. The baseline remains `complete=true`; evaluation returns **`no_upgrade`**, and protection returns **`clear`**, although the second ring might be worse than the candidate.

   **Fix:** propagate effective data incompleteness and unresolved compatible configurations. A known upgrade can still justify keeping an item; a known non-upgrade cannot establish that every possible replacement is a non-upgrade. This is a remaining M0 defect missed in round 1.

The disposition of each round-1 finding is:

| # | Status | Evidence |
|---|---|---|
| 1 | **RESOLVED** | Deletion conflicts now encode, decode, reach a third peer, and resolve; the exercised forwarding fixture is at [test_entry_sync.lua:83](C:/Projects/WoW/GlassGear/tests/test_entry_sync.lua:83). |
| 2 | **PARTIAL** | Cross-kind copies, malformed weights, and slot 999 are rejected; optional-field exceptions and malformed deletion flags remain, as finding 1 above demonstrates. |
| 3 | **RESOLVED** | Complete profile and baseline payload fixtures pass at [test_entry_sync.lua:180](C:/Projects/WoW/GlassGear/tests/test_entry_sync.lua:180); armor, origin, unknown pairs, missing weights, and baseline group survive serialization. |
| 4 | **PARTIAL** | Original candidate-side Healing and `Speed=X` counterexamples now produce limitations and protection `unknown`; baseline/companion equivalents still return `clear`—finding 2 above. |
| 5 | **RESOLVED** | [Classes.lua:109](C:/Projects/WoW/GlassGear/Data/Classes.lua:109) rejects missing training and foreign relics; [Classes.lua:127](C:/Projects/WoW/GlassGear/Data/Classes.lua:127) makes early mail conditional on plate usability. |
| 6 | **PARTIAL** | Off-hand weapons without dual wield and two-handed off-hand companions are rejected; missing companion tokens yield unknown, but companion exclusions and level requirements remain bypassed—finding 3 above. |
| 7 | **PARTIAL** | Original baseline-effect and same-unmodelled-set cases now make protection unknown; profile-derived baseline limitations still disappear at [Evaluate.lua:170](C:/Projects/WoW/GlassGear/Engine/Evaluate.lua:170). |
| 8 | **PARTIAL** | Original failed-event case finishes after three attempts with zero waiting items and requests; successful events with unusable data reset the budget—finding 4 above. |
| 9 | **PARTIAL** | Timeout and overload retain three identified rows in unchanged conditions; captured targets are unused after a spec change—finding 5 above. |
| 10 | **RESOLVED** | [Main.lua:62](C:/Projects/WoW/GlassGear/Core/Main.lua:62) refreshes player facts; direct checks confirmed level-event payload handling and dual-wield refresh on `SPELLS_CHANGED`. |
| 11 | **RESOLVED** | [Compat.lua:67](C:/Projects/WoW/GlassGear/Core/Compat.lua:67) handles client-shaped bag and equipment ItemLocations; both regression cases pass. |
| 12 | **RESOLVED** | [.github/workflows/package-check.yml:161](C:/Projects/WoW/GlassGear/.github/workflows/package-check.yml:161) skips release-file generation before the first release heading; tag runs retain strict artifact checks. Inspected, not executed in CI. |
| 13 | **RESOLVED** | [PawnString.lua:49](C:/Projects/WoW/GlassGear/Profiles/PawnString.lua:49) rejects out-of-range weights and v0; character-export and class-mismatch fixtures pass with the documented codes. |
| 14 | **RESOLVED** | [Compat.lua:47](C:/Projects/WoW/GlassGear/Core/Compat.lua:47) queries stripped strings; an in-memory API wrapper confirmed normalized inputs for candidate and equipped baseline. |
| 15 | **RESOLVED** | [Diagnostics.lua:48](C:/Projects/WoW/GlassGear/UI/Diagnostics.lua:48) and [Diagnostics.lua:62](C:/Projects/WoW/GlassGear/UI/Diagnostics.lua:62) invalidate assessments; direct checks observed callbacks after both mapping and import. |
| 16 | **PARTIAL — MINOR** | Global replacement detection, documentation assertions, Ready delivery, encoded backfill, and inventory→protection coverage improved; [test_entry_sync.lua:223](C:/Projects/WoW/GlassGear/tests/test_entry_sync.lua:223) still labels the first 40 tokens “worst-case.” Select longest encoded tokens and explicit size-boundary cases, or narrow that claim. |
| 17 | **RESOLVED** | [API.md:117](C:/Projects/WoW/GlassGear/docs/API.md:117) and [API.md:171](C:/Projects/WoW/GlassGear/docs/API.md:171) explicitly defer frame budgeting and caching to GG-114; capability flags report both unavailable. |

**No additional defect found** in the inspected Codec escaping/valid-payload round trips, PawnString rewrite, `Classes.CanUse`/`AllowedArmor`, `SlotCompare.HandLegal` itself, Main player refresh, revised ItemLocation stubs/global replacement detector, or workflow fix beyond the findings above. Changed API names and event payloads match the newest available Forever dump, **70532**; ItemLocation accessors match the local Blizzard implementation.

Validation used read-only `git`, `rg`, `Get-Content`, all 11 Lua test scripts, and additional stdin counterexamples. `git diff --check f40d98f 66f3aa5` passed. **No files changed.** The pre-existing untracked `docs/reviews/implementation/` directory remains. No mutation edits, deployment, packaging execution, or in-game checks ran; client behavior remains subject to the documented probes. Deferred UI, alts, and Shatter work are not findings.

CHANGES NEEDED