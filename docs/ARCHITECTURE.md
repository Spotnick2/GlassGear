# Architecture

```
            Game client (Forever 1.60.1, Interface 16001)
  tooltips  bags  loot  equipment  talents  C_Item / C_Container
     │       │     │        │          │            │
┌────▼───────▼─────▼────────▼──────────▼────────────▼─────────────┐
│ Core/Compat.lua  (the only module that calls game APIs)        │
└────┬───────────────────────────────────────────────┬───────────┘
     │ item facts, bind state, equipped/set items    │ events
┌────▼─────────────┐  ┌──────────────────┐  ┌────────▼──────────┐
│ Item/ItemContext │  │ Character/Spec   │  │ Character/        │
│ instance vs link │  │ group→spec key   │  │ Baselines         │
│ bind, transfer   │  │ (adr/0002)       │  │ (adr/0003)        │
└────┬─────────────┘  └───────┬──────────┘  └────────┬──────────┘
     │                        │                      │
┌────▼────────────────────────▼──────────────────────▼──────────┐
│ Engine (pure Lua, no game calls; fixture-tested)              │
│  Score · SlotCompare (configurations) · Evaluate (statuses)   │
│  Policy: tooltip rows · marker predicate · reveal · protection│
│  EntrySync (adr/0001 model, transport-agnostic)               │
└────┬───────────────────────────────┬──────────────────────────┘
     │ view-models                    │ results / verdicts
┌────▼────────────────────────┐  ┌───▼─────────────────────────┐
│ Presentation                │  │ API/PublicAPI.lua (v1)      │
│  Theme (forever | glass)    │  │  Evaluate · AssessProtection│
│  TooltipView (pure) · Bag-  │  │  callbacks (Shatter, others)│
│  Markers · LootMarkers (M1) │  └─────────────────────────────┘
└─────────────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│ Integrations: RosterProvider (local | AltStable), GlassUI     │
└──────────────────────────────────────────────────────────────┘
Profiles/ (storage + PawnString)   Core/DB (schema, migrations)   Core/Prefs (settings model)   Character/Capture (per-spec gear)   Presentation/ProfileView (profile texts)   UI/Options (settings page), UI/ProfilesWindow (weights), UI/Diagnostics, UI/Results (shared answers), UI/Tooltip, UI/Reveal, UI/Marks (look), UI/BagMarkers, UI/BagAddons (Bagnon), UI/LootMarkers (hooks)
```

## Module rules

- **`Engine/*` and `Profiles/PawnString.lua` are pure.**
  - They take tables and return tables, and never call a game API.
  - They are tested under plain Lua 5.1 without stubs.
  - They hold every decision the owner's acceptance list cares about.
- **`Core/Compat.lua` is the only file that calls `C_Item`, `C_Container`, `C_SpecializationInfo`,
  `C_Traits` and `C_EquipmentSet`.** It maps the struct and tuple shapes into plain records. A missing
  API returns `nil, "unavailable"`.
- **Presentation never decides.** It renders view-models, and a theme changes only the look.
- **Integrations are optional and feature-detected.**
  - The detection pattern is `rawget(_G, ...)`, an exact major version, every function type-checked,
    and every call under `pcall`. It is the same idiom as Shatter `Suite.lua:43-61` and GlassPearls
    `Theme.lua:73-82`.
  - Absent or incompatible means `unavailable`, with a reason in `/gg diag`.
- **One namespace.** The single global is `GlassGear`. Every file starts with
  `local GG = GlassGear or {}` and its friends. There are no other globals, except `SLASH_GLASSGEAR*`
  and `SlashCmdList` fields.

## Load order

The TOC lists LibGlass first, then the files in this order:

1. Core
2. Data
3. Engine
4. Profiles
5. Item
6. Character
7. Integrations
8. Presentation
9. API
10. UI

Then, in game:

- at `ADDON_LOADED`, the DB loads and migrates, and the Glass UI suite is asked (once, before any glass
  is built);
- at `PLAYER_LOGIN`, the spec is resolved, profiles load, and then `Ready` fires.

## Where each acceptance concern lives

| Concern | Module | Test |
|---|---|---|
| Pawn import/export | `Profiles/PawnString.lua` | `test_pawn_string.lua` |
| Score, enchant stripping, limitations | `Engine/Score.lua` | `test_score.lua` |
| Rings, trinkets, 2H/1H, unique | `Engine/SlotCompare.lua` | `test_slot_compare.lua` |
| Statuses, baselines, no weights | `Engine/Evaluate.lua` | `test_evaluate.lua` |
| Marker predicate, reveal, protection independence | `Engine/Policy.lua` | `test_policy.lua` |
| Transfer tri-state | `Item/ItemContext.lua` (pure part) | `test_item_context.lua` |
| Entry sync model, codec, sizes | `Engine/EntrySync.lua`, `Engine/Codec.lua` | `test_entry_sync.lua` |
| API shape, version gating, unsupported | `API/PublicAPI.lua` | `test_api_contract.lua` |
| Loads under strict Forever stubs, TOC/manifest | all | `test_load.lua`, `test_manifest.lua` |
