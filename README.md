# Glass Gear

Gear upgrade advice for **World of Warcraft: Forever**, for every spec of your character.

> **Tooltips show all of your specs. Bag arrows stay on your current spec.**

Glass Gear scores items with stat weights you import (one set per spec), compares each item with
the gear that spec actually wears, and tells you which items are upgrades: on the tooltip, with
arrows on your bags and the loot window, and in a detailed comparison.

**Status: alpha.** This is the first public build. Everything below works in the addon's own tests;
the in-game pass is under way, so expect rough edges and please report them.

## What it does

- **Tooltip rows for every spec.** Hover an item you can equip: your current spec comes first,
  then your other specs, each with its change in item score (`+3.1%`, `no upgrade`, `no weights`).
  Choose all specs, the current one only, or a selection in the settings.
- **Bag and loot arrows.**
  - A green arrow marks an upgrade for your current spec.
  - An amber arrow marks an item that isn't bound yet and is an upgrade for another of your specs
    or one of your alts (below).
  - Hold **Ctrl** (or Alt, or nothing: your choice) to see your other specs' upgrades as amber
    arrows, bound items included. Release it and the normal arrows come back. The settings can also
    mark chosen specs' upgrades all the time.
  - On Blizzard's bags, the loot window and group loot rolls, and in **Bagnon** and **Baganator**.
    Other bag addons get the tooltip rows only.
- **Each spec against its own gear.** A spec is compared with an equipment set you pick for it
  (`/gg set`), else with the gear it wore the last time you played it, else with what you wear now
  (and then the tooltip says so).
- **Rules that follow the game:**
  - your class's weapons and armor, and per-spec armor (a Holy Paladin may wear cloth, a
    Protection Paladin may not);
  - required levels: by default only items you can use now, with an optional look-ahead;
  - rings, trinkets, two-handers against a main hand and off-hand, unique-equipped items;
  - "you own better": no arrow for an item when a better one is already in your bags.
- **Detailed comparison.** `/gg compare` (or the item you last hovered) shows the stat-by-stat
  change, what it replaces and which profile scored it.
- **Your alts (with AltStable).** Tick an alt's specs on the Characters page (`/gg characters`).
  An unbound item it would use better shows `Name · Spec +x%` on the tooltip and an amber arrow,
  as long as it's on the same realm and faction. This covers the alts of the WoW account you're
  playing; your other account's alts need weight sync, which comes later.
- **Weight profiles.** Up to four profiles per spec, imported as Pawn strings, editable, and
  exportable again as Pawn strings (`/gg profiles`).

## Getting started

1. **Tell Glass Gear which spec you play.** WoW Forever has no spec ID for addons to read, so map
   your talent group once: `/gg spec 1 PRIEST.SHADOW`, or on the settings page (SPECS). With two
   talent groups, map the second too (`/gg spec 2 ...`).
2. **Import weights for each spec you care about.** Paste a Pawn scale string:
   `/gg import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1, SpellDamage=1.1 )`,
   or use the import box in `/gg profiles`.
   - From Pawn: pick a scale, press **Export**, copy, and import it here.
   - From WoWSims: its "Pawn EP" export imports the same way.
3. **Play each spec once** so Glass Gear records what it wears, or give it an equipment set
   (`/gg set PRIEST.HOLY Healing`).

A spec without imported weights shows `no weights`: Glass Gear doesn't ship weights of its own yet.

## Commands

`/gg` and `/glassgear` are the same command.

| Command | Does |
|---|---|
| `/gg` | Status: build, current spec, profiles per spec, bag addon, AltStable |
| `/gg spec <1\|2> <SPEC.KEY\|none>` | Map a talent group to a spec, e.g. `/gg spec 1 PRIEST.SHADOW` |
| `/gg import <SPEC.KEY> ( Pawn: v1: ... )` | Import a Pawn scale string for a spec |
| `/gg profiles [SPEC.KEY]` | The weight profiles window: import, edit, export |
| `/gg compare [item link]` | The detailed comparison for a Shift-clicked item, or the one last hovered |
| `/gg characters` | Your characters (AltStable), the specs protection and alt rows follow, gear freshness |
| `/gg set <SPEC.KEY> <set name\|none\|auto>` | Compare a spec with a saved equipment set. `none`: never a set; `auto` (default): the set assigned to that talent group in the client, if any |
| `/gg options` | The settings page (Esc > Options > AddOns > Glass Gear) |
| `/gg stats [reset]` | What the comparisons cost this session |

Spec keys are `CLASS.TREE` in English: `WARRIOR.ARMS`, `MAGE.FROST`, `DRUID.FERAL_TANK`,
`DRUID.FERAL_CAT`, and so on. `/gg` lists your class's.

## Good to know

- **Scores are estimates.** An item's score is the sum of its stats times your weights. It is not
  a DPS or healing simulation, and the percentages are item-score changes, not damage.
- **Only stats are scored.** Equip, use and proc effects and set bonuses aren't; the tooltip says
  when an item has one ("Has an effect that isn't scored", "Completes a 2-piece set bonus").
- **Enchants are left out** of both sides of a comparison: items are compared as base items.
- **Good weights matter more than anything else.** Weights depend on your gear and talents; import
  ones made for your character when you can.
- **Mailing rule.** Alt rows assume an unbound item can be mailed to an alt on the same realm and
  faction. That is being checked in game.
- **Disenchant protection** (keeping potential upgrades out of Shatter's disenchant list) is ready
  on Glass Gear's side. It works once Shatter adds its part.
- **One look for now:** the WoW Forever look. The Glass look (with Glass UI) comes later.
- **English only for now.** Every text is ready for translation (below).

## Optional companions

- **AltStable:** your characters across your accounts, for the Characters page and alt rows.
- **Shatter:** disenchant protection, once Shatter's side ships.
- **Bagnon** or **Baganator:** arrows in their bag windows.

## Bugs and ideas

Open an issue: https://github.com/Spotnick2/GlassGear/issues. `/gg` prints what helps most:
please include it.

## Translations

Every text Glass Gear shows goes through `GG.L`, keyed by its English text. To translate, copy the
keys you translate from
[Locales/enUS.lua](https://github.com/Spotnick2/GlassGear/blob/main/Locales/enUS.lua) into
`Locales/<locale>.lua`:

```lua
GlassGear.Locale.Register("deDE", {
    ["Not an upgrade for %s"] = "Kein Upgrade f\195\188r %s",
})
```

and list the file in `GlassGear.toc` right after `Core\Locale.lua`. Keep each placeholder (`%s`,
`%d`, ...) in the same order; a translation that changes them is ignored, and so is one with a lone
`%` (write `%%` for a percent sign).

## Development

- **Tests:** `pwsh tests/run.ps1` (Lua 5.1 at `C:\Program Files (x86)\Lua\5.1`). It runs `luac -p`
  on every file, then every `tests/test_*.lua`.
- **Deploy:** `pwsh Tools/deploy.ps1`, which copies the TOC's files and LibGlass from `..\LibGlass`
  into `_forever_`.
- **Public API** for other addons: [docs/API.md](https://github.com/Spotnick2/GlassGear/blob/main/docs/API.md).
- **Design:**
  [PRD](https://github.com/Spotnick2/GlassGear/blob/main/docs/PRD.md),
  [architecture](https://github.com/Spotnick2/GlassGear/blob/main/docs/ARCHITECTURE.md),
  [ADRs](https://github.com/Spotnick2/GlassGear/tree/main/docs/adr),
  [formats](https://github.com/Spotnick2/GlassGear/blob/main/docs/FORMATS.md),
  [backlog](https://github.com/Spotnick2/GlassGear/blob/main/docs/BACKLOG.md),
  [in-game checks](https://github.com/Spotnick2/GlassGear/blob/main/docs/FOREVER-PROBE.md).

## Credits

- **LibGlass** (MIT, by the same author) is embedded.
- The Pawn string format is Pawn's. Glass Gear reads and writes it, and contains no Pawn code.

## License

MIT: [LICENSE](https://github.com/Spotnick2/GlassGear/blob/main/LICENSE).
