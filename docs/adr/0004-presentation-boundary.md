# ADR-0004: Presentation boundary and themes

- Status: accepted (2026-11-01)

## Decision

- **View-models.** The engine and the policies produce plain view-model tables: rows, marker kind and
  labels. Presentation modules only render them. Themes never change what is shown, only how.
- **Two themes.**
  - `forever` is the default. It is the native look: Blizzard tooltip backdrop and fonts, the same
    look as Shatter's WoW Forever skin (`Shatter/Skin.lua:79-91`). It needs no library.
  - `glass` is LibGlass-1.0 **r11** (`preset = "pearl"`), embedded and pinned in `.pkgmeta`. It is
    used **only while Glass UI lists Glass Gear and the player follows the suite** (GUI-001).
    - The pattern is GlassPearls `Theme.lua`: the suite is asked once, before any glass is built, at
      `ADDON_LOADED` with `## OptionalDeps: GlassUI`.
    - Glass Gear reports `declined` when the player opts out, and `live = false` (a switch needs
      `/reload`).
- **Glass UI not following.** While Glass UI is absent, or while the player doesn't follow the suite,
  the `forever` theme is used. Glass Gear's own appearance settings are kept and come back unchanged
  (`GlassUI/docs/SUITE.md:30-33`).
- **Tooltips get lines only.** Glass Gear adds lines through
  `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, …)` and **never restyles
  `GameTooltip`**. Glass UI owns that (issue #147). The same tooltip is never skinned twice. Other
  tooltip extensions coexist, and native item lines are untouched.
- **Bag markers** are child frames on Blizzard item buttons. The pattern is GlassPearls
  `Core/BagMarks.lua`, re-implemented here with no dependency on GlassPearls:
  - Glass Gear hooks `UpdateItems` with `hooksecurefunc`;
  - nothing is written onto the button itself;
  - nothing is created during combat.

  The markers draw above Glass UI's slot wells.
- **Shared defaults stay shared.** LibGlass's shared defaults are never changed to style Glass Gear,
  and every look is per instance.
- **Mockups are not specs for effects.** Real backdrop blur and shaders are not available, and
  LibGlass uses layered textures.

## Consequences

- `Presentation/Theme.lua` is the only module that knows about LibGlass and Glass UI.
- A missing library, or one older than r11, reports `library-too-old` and falls back to `forever`.
