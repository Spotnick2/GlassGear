# Glass Gear mockups

Concept boards for Glass Gear's UI. Every board pairs the two presentation styles with the same
content: **WoW Forever** (native, the standalone default) on the left and **Glass / Pearl**
(LibGlass through Glass UI) on the right.

> **Illustrative only.** Item names, levels, scores and percentages are invented. They are not
> simulation results or measured values. A mockup does not prove that any client behaviour or
> integration works. In-game checks are queued in `docs/FOREVER-PROBE.md`.

## Provenance

| Set | Source | Prompts |
|---|---|---|
| `01`–`09`, `icon-source.png`, `superseded/` | The owner generated them before this repo existed (`Downloads\GlassGear`, copied 2026-11-01, unchanged). | Not available: they were generated outside this project. |
| `generated/G1`–`G4` | Codex CLI, built-in `image_gen` tool (imagegen skill, default mode), with an owner board attached as a style reference. G1 was re-run once: the first attempt drew downward chevrons, which read as downgrades, and was discarded. | `prompts/G1.txt`–`G4.txt`, exact text sent; the G1 correction is `prompts/G1-retry.txt` (G1.txt plus a correction paragraph) |

The owner boards are the reference look. They are close to WoW Forever, Glass UI and WoW itself,
but not pixel-exact. Implementation follows the real client templates (`wow-ui-source`) and
LibGlass r11, not the painted textures.

## Screen and state inventory

| # | UI state | Image(s) | Themes | Backlog |
|---|---|---|---|---|
| 01 | Boss loot: tooltip lists all own specs, current spec first and marked CURRENT; an off-spec-only upgrade (Moonwoven Mantle: Holy +8.6%, Shadow −2.4%); a green arrow only on the current-spec upgrade | `01-boss-loot.png` | both | GG-107, GG-111 |
| 01b | Loot window with Ctrl held (amber own off-spec, amber BoE alt); "no weights" tooltip row | `generated/G1-loot-reveal.png` | both | GG-110, GG-111, GG-107 |
| 02 | Soulbound bag items: Normal vs Holding Ctrl, same items; green stays, amber appears only while held | `02-soulbound-bags.png` | both | GG-109, GG-110 |
| 03 | Transferable BoE: own specs plus AltStable recipients (character · spec · account · replaced item); green wins over amber; "Now soulbound" and "No eligible upgrade" compact states | `03-transferable.png` | both | GG-107, GG-109, GG-203 |
| 04 | Settings: three independent controls (tooltip scope, marker scope, protection scope), preview | `04-settings.png` | both | GG-112 |
| 04b | Settings detail: reveal modifier, tracked specs, minimum-upgrade threshold, appearance + Glass UI suite state (not shown: level window, armor preference, see below) | `generated/G2-settings-detail.png` | both | GG-112, GG-115, GG-117, GG-118 |
| 05 | Profiles: per character/spec weights, Pawn import/export, source + freshness, validation error, missing profile | `05-profiles.png` | both | GG-105 |
| 05b | Import formats: Pawn / WoWSims Pawn EP / SimC profile (unsupported as weights), dropped-stat warning, provenance badge | `generated/G3-import-formats.png` | both | GG-105, GG-502 |
| 06 | AltStable characters across two accounts: eligible specs, fresh / stale / no-weights states, "AltStable unavailable" state, sync managed by AltStable | `06-altstable-characters.png` | both | GG-204, GG-201 |
| 07 | Shatter: queue item protected as a potential upgrade, manual warning with recipients and Keep / Disenchant anyway, compact pending state | `07-shatter.png` | both | SH-001, SH-002, GG-301 |
| 07b | Shatter Mail Mode sender ownership; Solo pending "can't confirm yet — kept"; per-row override | `generated/G4-shatter-mail-pending.png` | both | SH-001, SH-002 |
| 08 | Detailed comparison: candidate vs the selected spec's saved baseline, replaced item, method/profile/source/baseline, unsupported effects; "No Frost equipment recorded" fallback choice | `08-comparison.png` | both | GG-113, GG-108, GG-119 |
| 09 | **Future concept** Gear Lab: plan vs current, weight estimate vs simulation "not run", Companion job states (queued / running / results ready) | `09-gear-lab-future.png` | both | GG-501, GG-502, ASC-001 |
| — | Addon icon source art | `icon-source.png` | — | GG-404 |

### Superseded (kept for history, do not implement from these)

| File | Superseded by | Why |
|---|---|---|
| `superseded/03-transferable-v1.png` | `03-transferable.png` | Invents a standalone "Glass Gear" bag window with Bags/Bank/Alts/Settings tabs; its "No eligible upgrade" example shows positive gains |
| `superseded/06-altstable-characters-v1.png` | `06-altstable-characters.png` | Level 80 characters and an extra fifth character; Forever is level 60 |
| `superseded/07-shatter-v1.png` | `07-shatter.png` | Draws Shatter's queue inside a Glass Gear window; Shatter owns its window, and Glass Gear only answers its query |
| `superseded/09-gear-lab-future-v1.png` | `09-gear-lab-future.png` | Earlier status wording ("Weight estimate", account rows instead of export/import status) |

## Implementation notes per board

- **01 / 01b, loot.** The tooltip lists every configured own spec without any modifier, current
  spec first. Loot markers use the same pure marker function as bags: green = current-spec upgrade
  (always wins); amber appears on loot only while reveal is active (own off-spec; BoE alts are a
  proposal for owner review, PRD §Loot). Missing weights render as a grey "no weights" row. Never
  as 0 and never as "no upgrade".
- **02, soulbound bags.** Off-spec amber is reveal-gated. Reveal is recomputed from the live
  modifier and `GetCurrentKeyBoardFocus()` on `MODIFIER_STATE_CHANGED`, on every reveal-surface
  show, and by a 0.1 s poll while a reveal surface is visible. So releasing Ctrl while typing still
  clears it. Glass Gear never consumes clicks: Ctrl-click (dressing room) keeps working. No saved
  setting changes and no reload.
- **03, transferable.** Amber on a transferable bag item is a **default** (the owner's matrix row
  3), not reveal-gated. A BoE that binds is re-read as soulbound from the item instance
  (`C_Item.IsBound`) and loses alt rows. Alt rows need AltStable's ownership provenance (AS-001);
  "synced" never implies "transferable". The transfer state is eligible / ineligible / unknown.
  The real addon overlays Blizzard's own bag buttons and has no bag window of its own.
- **04 / 04b, settings.** Tooltip scope, marker scope and protection scope are three separate
  policy objects. Hiding a marker or a tooltip row never narrows protection (ADR-0006). Shift is
  not offered as the reveal key (COMPAREITEMS). Appearance follows Glass UI's suite rules:
  following needs `/reload`, and the addon's own look settings are kept while it follows.
- **05 / 05b, profiles and imports.** Weights belong to a character and spec and keep their
  provenance (`imported-pawn`, `wowsims-pawn-ep`, `default`, `manual`). Unknown tokens are reported,
  never silently zero. A SimulationCraft profile or WoWSims character JSON is not a weight set and
  is refused with an explanation (`docs/FORMATS.md`). Built (GG-105) as drawn in 05, with the
  import type detected instead of a dropdown and the Active badge on the chosen profile.
- **06, characters.** Built (GG-204): groups by AltStable's account label for display (ownership is
  the provenance); freshness from AltStable's `capturedAt` (stale after 14 days); "maybe behind" waits
  for sync (GG-202). Characters are grouped by account only from AltStable's validated
  provenance, never from the user-typed `account` label. Stale and incomplete data are labelled.
  Pairing and sync stay in AltStable ("Open AltStable"). Without AltStable, current-character
  comparisons still work and alt suggestions are reported unavailable.
- **07 / 07b, Shatter.** Shatter asks `AssessProtection` synchronously inside
  `IsCandidateDisenchantable`, which covers both the queue build and the click-time revalidation.
  `protect`, `unknown`, `pending`, `unsupported` and errors all keep the item (fail-closed).
  "Disenchant anyway" records `{guid, token}` for this one item and this session. It bypasses only
  Glass Gear's veto and expires on any token or GUID change. Mail Mode items belong to their
  senders, so no upgrade check applies to them. The secure one-click button is unchanged.
- **08, comparison.** Built (GG-113): spec tabs replace the character dropdown (one character until
  GG-201; no dropdowns), and "No equipment recorded" offers the saved sets by name. Shows the baseline source (saved set → gear seen in that spec → current gear
  labelled `fallback-current`), the replaced item(s) from the chosen legal configuration, and
  limitations such as `EFFECT_NOT_SCORED`. "Item score" and percentages are item-score estimates,
  never DPS or healing.
- **09, Gear Lab.** Future only (M5). It separates the weight estimate, queued external work and
  imported simulation results. Nothing here is part of the foundation scaffold.

## Known defects in the owner images

- `03-transferable.png`: "+8 Stanlina" (Stamina) on the WoW Forever side.
- `05-profiles.png`: the sample Pawn string reads `Intellec=` (should be `Intellect=`), and the
  file's board number reads "05" while its source file was "-6".
- Several boards draw a standalone "Glass Gear" window with tabs. The settings, profiles,
  characters and comparison windows are real Glass Gear windows. Bag and loot markers are overlays
  on Blizzard's own frames.
- Item levels above 60 (Gear Lab "Item Level 84") and every score are illustrative.

## Known defects in the generated boards

- `G1-loot-reveal.png`: green and amber chevrons are both drawn outlined, so they differ by colour
  only. The spec is a filled green vs an outlined amber chevron (shape matters for colour-blind
  players), and the implementation follows the spec. The footer is clipped at the right edge.
- `G2`, `G3`, `G4`: no text or semantic defect found on inspection.

## Coverage of the required mockup areas

| Required area | Status |
|---|---|
| 1. Boss loot: all specs, current emphasised, off-spec-only example | Covered (01); Ctrl-held loot + "no weights" filled by G1 |
| 2. Soulbound bag item, normal vs modifier-held | Covered (02) |
| 3. Transferable BoE/BoA: own specs + AltStable recipients, green precedence, no eligible recipient, becoming bound | Covered (03) |
| 4. Settings: three scopes, modifier, tracked specs, thresholds, appearance, preview | Covered (04); modifier/tracked specs/threshold/appearance detail filled by G2 |
| 5. Profiles and imports: selection, Pawn I/O, supported formats, source/freshness, errors, missing weights | Covered (05); format list filled by G3 |
| 6. AltStable integration: two accounts, fresh/stale/incomplete, unavailable, no duplicate pairing UI | Covered (06) |
| 7. Shatter: protected queue item, manual warning, pending state | Covered (07); Mail Mode ownership + per-row override filled by G4 |
| 8. Detailed comparison | Covered (08) |
| 9. Future Gear Lab / Companion | Covered (09), labelled FUTURE CONCEPT |
| Later owner requirements (2026-11-01, after G1–G4) | **Remaining gap:** level window, armor preference, set-bonus warning (GG-117 / GG-118 / GG-119). No board shows them yet; G2 predates them. |

## Owner requirements added after the gap boards

These came in after G1–G4 were generated. The boards above do not show them, so implement from
this text and from the PRD, not from the images.

- **Level window (GG-117).** Setting "Only level-appropriate upgrades" (default **on**) with
  "Look ahead: N levels" (default **0**). An item whose required level falls inside the window
  gets a tooltip row such as "Holy +6.2% at level 42 (in 2 levels)", with **no** green or amber
  bag/loot marker by default. Above the window it is not presented as an upgrade at all. Affects
  01, 02, 03, 04 and G2. A future settings board should add both rows under Thresholds.
- **Armor types (GG-118).** Two layers:
  - **A hard class gate.** "Wearable now" comes from class, level and known skill; on Forever,
    mail and plate unlock at level 40 for the classes that get them. A class never sees an item it
    can't wear or wield as an upgrade.
  - **Per-spec armor rules**, default **on** and editable per profile. Protection and
    Retribution Paladins get plate, plus mail before 40; a Holy Paladin gets cloth to plate. So
    a cloth spell-power item can show as a Holy upgrade while it is ineligible for Protection.

  Affects 01–04 and the eligibility reasons in 08.
- **Set bonuses (GG-119).** Detect when a candidate completes or breaks a set-bonus threshold, and
  warn in the tooltip and the comparison window ("Completes 2-piece bonus" / "Breaks 3-piece
  bonus"). The bonus is never silently scored: it stays a `SET_BONUS_NOT_SCORED` limitation plus
  the warning. Needs ItemSet / ItemSetSpell DB2 data through the wago-tools skill. Affects 01, 03
  and 08 (08's "Special effects and set bonuses are not included" line becomes the specific
  warning).
