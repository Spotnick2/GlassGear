# Changelog

## Unreleased

- **Fire, Frost, Nature and Holy spell damage count**: items with "+N Fire Spell Damage" and the
  like now score for the specs that weigh them, measured in game (they were left out, with a
  warning, until then).
- **A shorter tooltip**: your current spec, then one line for the others ("+ 2 other specs (hold
  Ctrl)") that names the best upgrade among them. Hold the reveal key to see them all. "All my
  specs" in the settings shows them all the time. The "default weights" tag is gone from the
  tooltip; `/gg` and the profiles window still say which specs use them.
- **The Glass look with Glass UI**: with Glass UI loaded, Glass Gear's windows follow its look
  (Pearl glass, Glass UI's tint and accent), and Glass UI's settings show Glass Gear's state. Prefer
  the WoW Forever look? Pick it under Appearance in Glass Gear's settings and `/reload`.

## v0.1.0

The first public build, an alpha: everything here works in the addon's own tests, and the in-game
pass is under way.

- **Tooltip rows for every spec**: your current spec first, then the others, each with its change
  in item score, "no upgrade" or "no weights". All specs, the current one, or a selection.
- **Bag and loot arrows**: green for a current-spec upgrade; amber for an unbound item another of
  your specs or alts would use better. Hold Ctrl (or Alt, or none) to see your other specs'
  upgrades. On Blizzard's bags, the loot window, group loot rolls, Bagnon and Baganator.
- **Each spec against its own gear**: an equipment set you pick (`/gg set`), the gear it wore last
  time you played it, or what you wear now (said on the tooltip).
- **Rules that follow the game**: class weapons and armor, per-spec armor, required levels with an
  optional look-ahead, rings and trinkets, two-handers against main hand and off-hand, unique items,
  and no arrow when you already own better.
- **Weight profiles**: up to four per spec, imported from Pawn strings (Pawn's own Export, WoWSims
  "Pawn EP"), editable and exportable (`/gg profiles`).
- **Detailed comparison** (`/gg compare`): stat by stat, what the item replaces, which profile scored
  it.
- **Alts with AltStable**: tick an alt's specs on the Characters page (`/gg characters`); an unbound
  item it would use better shows on the tooltip and as an amber arrow (same realm and faction). This
  WoW account's alts for now.
- **Disenchant protection** for Shatter, ready on Glass Gear's side; it works once Shatter adds its
  part.
- **Settings page** (`/gg options`), **status** (`/gg`), and a runtime cost report (`/gg stats`).
- **Ready for translation**: English only for now.

Not in this build: Glass Gear's own default weights (import yours), the Glass look, weight sync
between your accounts, and automatic spec detection (map your talent group with `/gg spec`).
