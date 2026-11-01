Reviewed `f40d98f23cd9e77a8dd1c0dad0964921f9490f35` on `foundation/scaffold`. **No BLOCKER found, but MAJOR defects remain in the M0 implementation.** All 11 existing test files pass under Lua 5.1.5; the counterexamples below expose cases they miss.

1. **MAJOR — Deletion-conflict copies cannot travel through the implemented sync path.**

   [Engine/EntrySync.lua:200](C:/Projects/WoW/GlassGear/Engine/EntrySync.lua:200) creates a deletion conflict with `deleted = nil`, `data = nil`, and `conflict.deletion = true`. However, [the receiver validator](C:/Projects/WoW/GlassGear/Engine/EntrySync.lua:62) rejects a nondeleted entry without data, and [Codec.Encode](C:/Projects/WoW/GlassGear/Engine/Codec.lua:99) tries to encode its nonexistent profile payload. The codec also serializes only `conflict.of`, losing the deletion distinction.

   **Reproduced:** after concurrent delete/edit, encoding the resulting deletion copy returns `nil, "bad-entry"`; delivering it directly to a third store also returns `"bad-entry"`.

   **Fix:** recognize deletion conflicts as valid contentless entries, serialize their deletion metadata, and preserve it on decode. Update [SCHEMA.md:22](C:/Projects/WoW/GlassGear/docs/SCHEMA.md:22), which currently describes `conflict` as a string although the implementation requires a table. Test forwarding and resolving deletion copies through the codec, including a third peer.

2. **MAJOR — Incoming-entry validation permits malformed data and cross-kind conflict resolution.**

   [Engine/EntrySync.lua:57](C:/Projects/WoW/GlassGear/Engine/EntrySync.lua:57) validates little beyond outer types. Unlike AltStableSync’s `SameIdentity` checks, it does not verify a conflict copy against its root, and [Resolve](C:/Projects/WoW/GlassGear/Engine/EntrySync.lua:239) copies the payload into the root without validating its kind.

   **Reproduced:** a `kind = "baseline"` conflict referencing a profile root is accepted; choosing `"theirs"` leaves a profile entry containing baseline data. Separately, [Codec.Decode](C:/Projects/WoW/GlassGear/Engine/Codec.lua:114) accepts `Intellect=1.2.3`—silently dropping the weight—`Intellect=10000`, and baseline slot `999`.

   **Fix:** add per-kind validation before storage and resolution, enforce root/copy identity, and strictly validate numeric values, token counts, slot ranges, flags, and required metadata. Malformed entries must return `bad-entry` without changing local state, as ADR-0001 and SCHEMA require.

3. **MAJOR — Import and wire serialization discard authored profile data while retaining the entry version.**

   [Profiles/Profiles.lua:43](C:/Projects/WoW/GlassGear/Profiles/Profiles.lua:43) drops the parsed origin and unsupported-token metadata. [PawnString.Parse](C:/Projects/WoW/GlassGear/Profiles/PawnString.lua:50) retains only unsupported token names, losing their values, so export cannot round-trip them. [Codec’s profile payload](C:/Projects/WoW/GlassGear/Engine/Codec.lua:72) also omits custom armor rules and origin.

   **Reproduced:** encoding and decoding a profile with `armor = {1, 4}` and `origin = "original"` returns both fields as `nil`. A receiver consequently applies different armor eligibility under the same profile version. Exporting an imported `Mana=7` loses that pair entirely.

   **Fix:** preserve the documented profile fields through parse → entry storage → public profile → wire codec → export. Include the agreed baseline spec-mapping metadata in the schema as required by ADR-0001. Round-trip complete entries, rather than checking selected fields only.

4. **MAJOR — Missing WoWSims weights and unsupported `X` constraints can produce protection `clear`.**

   [Engine/Evaluate.lua:137](C:/Projects/WoW/GlassGear/Engine/Evaluate.lua:137) never emits `WEIGHT_MISSING`. [Stats.UnscoredTokens](C:/Projects/WoW/GlassGear/Data/Stats.lua:126) inspects numeric weights only, ignoring unsupported tokens marked `X`. [Policy’s unsafe limitations](C:/Projects/WoW/GlassGear/Engine/Policy.lua:135) also omit `WEIGHT_MISSING`.

   **Reproduced:** importing `"Holy WoWSims Weights"` with only `Intellect=1`, then comparing a 9-Intellect/100-Healing candidate against 10 Intellect, returns `no_upgrade`, no limitations, and protection `clear`. `Speed=X` likewise produces no uncertainty when speed cannot be evaluated. This contradicts [FORMATS.md:168](C:/Projects/WoW/GlassGear/docs/FORMATS.md:168).

   **Fix:** retain the missing-weight metadata, emit limitations when relevant item stats lack those weights, and make protection fail closed. An exclusion whose underlying stat is unavailable must remain unresolved rather than silently passing.

5. **MAJOR — The class and spec armor gates accept equipment the documented rules exclude.**

   Three concrete failures occur in [Data/Classes.lua:102](C:/Projects/WoW/GlassGear/Data/Classes.lua:102) and [Evaluate’s armor rule](C:/Projects/WoW/GlassGear/Engine/Evaluate.lua:74):

   - A level-60 Paladin whose supplied `knownArmor` excludes plate receives `LATER_LEVEL, 40`; because 40 is already below the character’s level, evaluation returns an immediate plate upgrade.
   - Relic subclasses bypass the class gate entirely. A Mage can receive a Libram upgrade.
   - [Warrior and Protection/Retribution Paladin defaults](C:/Projects/WoW/GlassGear/Data/Classes.lua:20) always include mail, whereas ADR-0003 permits mail only **before plate is learned**.

   **Fix:** distinguish missing training from a future level requirement, enforce class-specific relic restrictions, and resolve conditional spec defaults using proficiency facts. Keep runtime skill discovery probe-gated; these pure decisions can be corrected and tested now.

6. **MAJOR — Weapon configurations are accepted without proving that both hands are legal.**

   [Engine/SlotCompare.lua:115](C:/Projects/WoW/GlassGear/Engine/SlotCompare.lua:115) checks dual wield only for `INVTYPE_WEAPON`, allowing `INVTYPE_WEAPONOFFHAND` with `canDualWield = false`. [Companion placement](C:/Projects/WoW/GlassGear/Engine/SlotCompare.lua:68) accepts any supplied item, without checking its compatible slot or proficiency. [Evaluate.lua:181](C:/Projects/WoW/GlassGear/Engine/Evaluate.lua:181) additionally treats missing companion tokens as score zero.

   **Reproduced:** an off-hand weapon is considered legal without dual wield; replacing a two-handed weapon with a dagger plus another **two-handed weapon in the off-hand** returns an upgrade.

   **Fix:** validate the complete resulting hand configuration, including companion slot compatibility, dual wield, recipient eligibility, and available item data. Missing companion data must produce `unknown`, not zero.

7. **MAJOR — Comparison limitations disappear before protection evaluates them.**

   [Core/Compat.lua:93](C:/Projects/WoW/GlassGear/Core/Compat.lua:93) drops equipped-item `hasSpell` and unsupported-stat information. [Engine/Evaluate.lua:168](C:/Projects/WoW/GlassGear/Engine/Evaluate.lua:168) retains only baseline scores, discarding their scoring limitations. Separately, [SetBonus.lua:35](C:/Projects/WoW/GlassGear/Engine/SetBonus.lua:35) reports an unknown set only when its piece count changes, so replacing an item with another from the same unmodelled set emits no set limitation.

   **Reproduced:** a trusted baseline containing an unscored effect yields `clear` after a lower supported-score comparison. Replacing a set piece with another from the same set, with no threshold data, also yields no limitation and `clear`.

   **Fix:** preserve and propagate limitations from the items participating in the comparison. Implement ADR-0003’s required set-membership warning independently of gained/lost threshold detection, and ensure these uncertainties reach protection.

8. **MAJOR — A failed item-load event strands pending requests permanently.**

   [Core/Main.lua:73](C:/Projects/WoW/GlassGear/Core/Main.lua:73) discards the event’s `success` argument. [API._ItemDataArrived](C:/Projects/WoW/GlassGear/API/PublicAPI.lua:194) removes the waiting item before confirming its data is usable. If reevaluation remains pending, the request survives without a waiting record, so the retry timer stops.

   **Reproduced:** after `ITEM_DATA_LOAD_RESULT(itemID, false)` and 20 seconds of simulated time, `waitingCount = 0`, `requestCount = 1`, and no `EvaluationReady` callback fires.

   Initial loads also bypass deduplication because [Compat.ItemFacts](C:/Projects/WoW/GlassGear/Core/Compat.lua:45) requests data on every cache miss before the API checks its queue.

   **Fix:** give one queue ownership of load attempts, preserve retry state until data resolves or attempts are exhausted, and consume the success flag. Route load requests through Compat while keeping deduplication and attempt accounting centralized.

9. **MAJOR — Terminal async responses lose the request’s target rows.**

   [API/PublicAPI.lua:229](C:/Projects/WoW/GlassGear/API/PublicAPI.lua:229) replaces a timed-out request with one anonymous result. [The overload helper](C:/Projects/WoW/GlassGear/API/PublicAPI.lua:158) does the same. This violates the promise that every target remains present in the complete response.

   **Reproduced:** an `own` request initially returns three priest-spec rows; its timeout callback returns one row without `character` or `spec`.

   **Fix:** retain the resolved target list and update each affected placeholder in place, preserving identity, order, and any completed results. Test multi-target timeout and overload responses, not just their first reason code.

10. **MAJOR — Recipient level and dual-wield capability remain frozen at login.**

    [Core/Main.lua:46](C:/Projects/WoW/GlassGear/Core/Main.lua:46) captures `GG.player` once. No handler refreshes it when the character levels or learns a proficiency. Evaluation continues using that snapshot.

    **Reproduced:** changing the stub player from level 60 to 61 and firing `PLAYER_LEVEL_UP` leaves `GetCharacters()[1].level == 60`. With the default zero-level look-ahead, an item newly usable after leveling remains rejected until reload. Learning dual wield has the equivalent configuration problem.

    **Fix:** refresh relevant player facts on level and proficiency changes and emit `EvaluationInvalidated`. The 70532 dump declares `PLAYER_LEVEL_UP`, `SKILL_LINES_CHANGED`, and `SPELLS_CHANGED`.

11. **MAJOR — Advertised `ItemLocation` requests do not work with the client’s actual object shape.**

    [API/PublicAPI.lua:72](C:/Projects/WoW/GlassGear/API/PublicAPI.lua:72) handles strings and `{bag, slot}` tables only. The client’s [ItemLocation implementation](C:/Projects/WoW/wow-ui-source/Interface/AddOns/Blizzard_ObjectAPI/Mainline/ItemLocation.lua:34) uses `bagID`, `slotIndex`, and accessor methods, with a separate equipment-slot form. [The stub](C:/Projects/WoW/GlassGear/tests/wow_stubs.lua:162) incorrectly models it as `{bag, slot}`.

    **Reproduced:** a client-shaped bag location returns `unknown / NO_ITEM` for an existing item.

    **Fix:** normalize supported ItemLocation objects through their methods in Compat, including equipment locations, and make the stub model those methods and fields.

12. **MAJOR — The PR package-check workflow fails when it builds release metadata.**

    [.github/workflows/package-check.yml:158](C:/Projects/WoW/GlassGear/.github/workflows/package-check.yml:158) derives a fallback tag from a `## v…` changelog heading. [CHANGELOG.md:3](C:/Projects/WoW/GlassGear/CHANGELOG.md:3) contains only `## Unreleased`, so an ordinary PR run supplies an empty tag to [release_files.sh:34](C:/Projects/WoW/GlassGear/tests/release_files.sh:34), which exits with status 2.

    **Fix:** give nonrelease checks an explicit development/prerelease value compatible with the `Unreleased` fallback, or add an explicit nonpublishing `Unreleased` validation mode. Keep actual tag publication strict. This failure is independent of the deliberately deferred Wago project setup.

13. **MAJOR — Pawn import silently changes out-of-range weights instead of rejecting them.**

    [Profiles/PawnString.lua:59](C:/Projects/WoW/GlassGear/Profiles/PawnString.lua:59) clamps imported values, contradicting [FORMATS.md:53](C:/Projects/WoW/GlassGear/docs/FORMATS.md:53), which requires `VALUE_OUT_OF_RANGE`.

    **Reproduced:** `Intellect=1000` imports successfully as `999.999`. Larger out-of-range values can change relative weights substantially while the import reports success.

    **Fix:** reject out-of-range values at the import boundary; retain codec clamping only where explicitly contracted. Complete the other documented validation paths: v0 is currently accepted, character exports receive a generic Pawn error, and class mismatch is never checked. Add exact error-code fixtures.

14. **MINOR — Enchant stripping changes the reported item string but not the stat-query input.**

    [Core/Compat.lua:41](C:/Projects/WoW/GlassGear/Core/Compat.lua:41) constructs a stripped string, then calls `GetItemStats(link)` with the original enchanted link at line 43. [The claimed enchant fixture](C:/Projects/WoW/GlassGear/tests/test_evaluate.lua:146) checks only the string helper, not the adapter or scores.

    **Fix:** query stats using the normalized item string and test the argument passed to the API for both candidate and baseline. This establishes a contract/fixture defect; P4 must still determine whether the client’s returned stats include enchants, so I am not claiming a measured in-game scoring difference.

15. **MINOR — Manual spec changes do not invalidate consumer assessments.**

    [UI/Diagnostics.lua:46](C:/Projects/WoW/GlassGear/UI/Diagnostics.lua:46) changes the mapping and resolves the current spec without firing `EvaluationInvalidated`. Profile import fires `ProfilesChanged` but likewise omits the general invalidation event.

    **Reproduced:** a registered `EvaluationInvalidated` listener receives zero callbacks after `/gg spec 1 PRIEST.HOLY`.

    **Fix:** emit the documented invalidation after mapping and profile changes, with the appropriate reason and character keys. Test delivery after the next-frame callback batch.

16. **MINOR — Several tests overstate the guarantees they establish.**

    - [tests/wow_stubs.lua:202](C:/Projects/WoW/GlassGear/tests/wow_stubs.lua:202) detects only writes to absent global keys. Reassigning an existing Blizzard global bypasses `__newindex`; replacing `SlashCmdList` in memory produced no recorded write. Snapshot protected globals, as Shatter’s harness does.
    - [tests/test_formats_doc.lua:37](C:/Projects/WoW/GlassGear/tests/test_formats_doc.lua:37) skips a documented token if it disappears from `Stats.TOKENS`, and skips a mapping assertion if the mapping disappears. Assert existence before comparing values.
    - [tests/test_entry_sync.lua:170](C:/Projects/WoW/GlassGear/tests/test_entry_sync.lua:170) calls an arbitrary 40-token selection “worst-case,” without conflict metadata or worst-case escaping. Its “including tombstones” backfill contains no tombstones and adds a hard-coded 600 bytes per baseline instead of encoding one.
    - [tests/test_load.lua:16](C:/Projects/WoW/GlassGear/tests/test_load.lua:16) registers its Ready listener after login and never asserts its counter. The inventory fixture also stops at `MaybeBehind`; it does not exercise the promised weight-change → protection-unknown transition.

    **Fix:** make these assertions cover the stated invariants and add the missing end-to-end pure fixtures. The existing green suite does not establish those claims.

17. **MINOR — API.md presents deferred runtime behavior as an unconditional M0 guarantee.**

    [API.md:116](C:/Projects/WoW/GlassGear/docs/API.md:116) promises a 200-evaluation frame budget, and [API.md:170](C:/Projects/WoW/GlassGear/docs/API.md:170) promises cached redraws. The implementation evaluates synchronously and reconstructs the equipped baseline on each call. BACKLOG correctly places the full budget/cache runtime in GG-114.

    **Fix:** explicitly mark those guarantees as pending GG-114, or expose granular capabilities describing what M0 implements. This is a documentation correction within M0; it does not require pulling the deferred runtime milestone forward.

**No defect found** in the inspected API names and principal item return-tuple positions against dump 70532. No additional login-breaking load-order error or Blizzard-global overwrite was found in the addon code. No additional defect found in the TOC’s Interface/SavedVariables/OptionalDeps declarations, LibGlass r11 pin, or TOC-driven deploy paths; deployment and packaging were inspected, not executed.

**No defect found** in the tested ordinary weighted sums, stronger-ring displacement under unique-category restrictions, baseline source precedence/freshness helpers, marker precedence, reveal reconciliation, or independence of protection from marker visibility. Ordinary sync fast-forward, duplicate suppression, recorded-copy replay suppression, and asymmetric resolution retirement match the adopted model apart from the findings above. The deferred tooltips, markers, settings UI, alts, generated ItemSet data, and Shatter integration are not reported as defects.

Validation used read-only `git`, `rg`, `Get-Content`, the 11 Lua test scripts (**481 passing assertions**), and additional Lua counterexamples supplied through stdin. No files changed, no mutation edits were made, and no in-game or deployment checks ran. The working tree remains clean.

CHANGES NEEDED