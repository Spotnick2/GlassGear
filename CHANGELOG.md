# Changelog

## Unreleased

- Foundation (M0):
  - **Addon scaffold:** TOC for Forever 16001, optional AltStable and Glass UI, LibGlass r11
    pinned.
  - **Pure engine:**
    - weighted item score;
    - legal equipment configurations (rings, trinkets, 2H/1H, unique);
    - eligibility: class gate, per-spec armor, level window;
    - set-bonus detection;
    - marker, tooltip and protection policies;
    - Ctrl reveal state;
    - transfer tri-state;
    - per-entry sync model and the GG1 codec.
  - **Pawn v1 scale strings:** import and export, including WoWSims "Pawn EP".
  - **Public API v1** (current character): capabilities, specs, profiles, Evaluate with pending
    item data.
  - **`/gg` commands:** diagnostics, spec mapping (own class, groups 1–2) and Pawn import
    (importing again for a spec replaces its weights).
- Tooltip rows (GG-107): every equippable item's tooltip lists all your specs, the current spec
  first and marked CURRENT, with the upgrade estimate, "no weights", "checking..." while item data
  loads, "at level N (in k)" for later items, set-bonus and unscored-effect notes, and the
  "Weighted item score · estimates" footer. Off-specs compare with your current gear until GG-108.
  No markers yet.
