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
- Bag markers (GG-109): a green arrow on current-spec upgrades in Blizzard's bags; an amber outlined
  arrow on transferable (unbound) items that are upgrades for another of your specs. Soulbound
  off-spec upgrades stay quiet unless you hold the reveal key.
- Reveal (GG-110): hold Ctrl (or Alt; or None) to show amber off-spec upgrades on any bag item.
  Releasing clears it at once, also while typing in chat. Clicks are never taken: Ctrl-click still
  opens the dressing room.
- Loot markers (GG-111): the same arrows on the loot window and the group roll frames. Green for a
  current-spec upgrade; off-spec upgrades show amber only while you hold the reveal key (BoP and
  BoE alike). Marks work in combat (a small pool made beforehand).
- Settings page (GG-112): Esc > Options > AddOns > Glass Gear, or `/gg options`. Tooltips (which
  specs, alts, set-bonus warnings); bag and loot arrows (current spec, + selected specs, or all
  specs; amber for transferable items; the reveal key, Shift shown but not allowed); upgrade rules
  (minimum upgrade, level window and look-ahead, spec armor); disenchant protection (tracked specs,
  specs without weights); appearance (Glass UI's decision) with a live preview; Defaults. Every
  change applies at once.
