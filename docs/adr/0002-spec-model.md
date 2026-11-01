# ADR-0002: The Forever spec model

- Status: accepted (2026-11-01). Automatic detection is pending probe GG-101.

## Context

Forever has no Retail spec IDs:

- the globals `GetSpecialization`, `GetSpecializationInfo`, `GetActiveTalentGroup` and
  `GetPrimaryTalentTree` are absent unless the deprecation fallbacks are on;
- `ChrSpecialization` has one row per class (`References/Forever/db`, build 70532).

What does exist:

- `C_SpecializationInfo.GetActiveSpecGroup`, `GetCombatConfigIDForSpecGroup`, `GetNumSpecGroups`;
- `C_Traits`, which the client's own talent frame uses to show three trees and the points spent in
  each (`wow-ui-source` forever ca8368f2f, `Blizzard_ClassTalentsFrame.lua:107-161, 343-355`).

AltStableSync measured `GetNumSpecGroups() = 1` on a character without dual spec. Pawn turns specs
off on Forever (`VgerCore.lua:49`).

## Decision

1. **Spec keys** are stable and locale-independent: `<CLASS>.<TREE>`. The list is `Data/Classes.lua`:
   three trees per class, plus `DRUID.FERAL_TANK` / `DRUID.FERAL_CAT` in place of a single Feral.
   Display names come from the same table and are never parsed from game text.
2. **Current spec** is resolved in this order:
   1. the **manual mapping** spec group → spec key, kept per character. It is always available and
      always wins when it is set;
   2. **automatic** detection: spec group → `GetCombatConfigIDForSpecGroup` → `C_Traits` group
      currency spent → the tree with the most points. It is **disabled until GG-101 measures it**.
      A tie, no points spent, or the Feral split gives `unknown-spec`;
   3. otherwise `unknown-spec`. The tooltip still shows every spec that has a profile, none of them
      is emphasised as current, and current-spec markers are off; the diagnostics explain why.
3. **Which specs a character has** = every spec key of its class. Specs without a profile show as
   "no weights".
4. **Dual spec:** the mapping is per spec group. `ACTIVE_TALENT_GROUP_CHANGED` and
   `PLAYER_TALENT_UPDATE` invalidate the current spec. Those events are present in the dump; their
   firing still has to be probed.

## Consequences

- Nothing in the engine depends on detection. `Character/Spec.lua` resolves the current spec, and the
  engine takes spec keys as inputs.
- Spec keys are part of entry ids ([adr/0001](0001-sync-ownership.md)), so they must never be
  renamed. Adding keys is allowed.
