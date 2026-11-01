# ADR-0006: Tooltip, marker and protection policies are independent

- Status: accepted (2026-11-01)

## Decision

There are three policy objects. Each is evaluated by its own pure function in `Engine/Policy.lua`:

| Policy | Input | Output |
|---|---|---|
| Tooltip | evaluation results, tooltip settings | ordered rows (current spec first and emphasised; compact secondary rows; alt rows; "no weights" rows) |
| Marker | evaluation results, item context, marker settings, reveal state | `green`, `amber` or none (+ label) |
| Protection | evaluation results for the **protection scope**, freshness, limitations | `protect`, `clear`, `unknown`, `pending` or `unsupported` (+ recipients, reasons) |

- **Protection never reads marker or tooltip settings, or the reveal state.** A test asserts it:
  hiding every arrow leaves the protection verdict unchanged.
- **The marker predicate**, in order:
  1. green, if it is a current-spec upgrade;
  2. else amber, if the reveal is active and it is an own off-spec upgrade;
  3. else amber, if the item is a transferable bag instance, "mark transferable" is on, and it is an
     own off-spec or eligible own-alt upgrade;
  4. else amber, if the reveal is active, the item is transferable, and it is an eligible own-alt
     upgrade;
  5. else none.

  A soulbound instance never gets an alt-based marker.
- **Loot surfaces** use the same predicate. The item counts as soulbound for BoP, and as transferable
  only for BoE when the reveal is active (proposal for owner review).

## Consequences

The owner's acceptance case "Shatter protection despite hidden off-spec arrows" is a pure unit test
(`tests/test_policy.lua`).
