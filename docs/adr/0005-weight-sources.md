# ADR-0005: Weight sources and provenance

- Status: accepted (2026-11-01)

Every profile records `source`, `importedAt` / `updatedAt` and, when it is known, `origin` (a free
text label, such as the Pawn scale name).

| `source` | Meaning | Import path |
|---|---|---|
| `imported-pawn` | A Pawn v1 scale string | Pawn string import |
| `wowsims-pawn-ep` | A WoWSims "Pawn EP" export, recognised by its scale name `"<Spec> WoWSims Weights"` | Pawn string import, with a warning about stats WoWSims drops |
| `manual` | Edited in Glass Gear | Profile editor |
| `default` | Shipped defaults | None in MVP. GG-106 researches a licence-clean source; Pawn's defaults are CC BY-NC-ND and are not copied |
| `sim-result` | Results of an external simulation | Future (GG-502), through AltStable Companion (ASC-001) |

These are **not weights**, and cannot be imported as weights:

- a SimulationCraft addon profile;
- a WoWSims character JSON or WowSimsExporter export.

Each is a character description that needs an external simulation. Import shows that explanation
instead of failing silently.

The UI shows the source label and freshness on every profile, and in the detailed comparison
("Source: imported weights"). Imported, default and simulated results are never mixed or relabelled.
