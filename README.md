# Glass Gear

Gear comparison and upgrade advice for **World of Warcraft: Forever**, in the Glass addon family.
It replaces a Pawn workflow.

> **Tooltips show all of your character's specs. Ordinary bag arrows stay on your current spec.**

**Status:** foundation (M0). The scoring engine, policies, sync model and API contract are built and
tested. Tooltip rows, bag and loot arrows, the reveal key and the settings page (`/gg options`)
are built and wait for the in-game pass; alts and Shatter protection are the next milestones:
see [docs/BACKLOG.md](docs/BACKLOG.md).

## What it will do

- **Weights and scores**
  - Per-character, per-spec stat weights.
  - Pawn string import and export, which also covers WoWSims "Pawn EP" exports.
  - Item-score estimates that are always labelled as estimates. They are never DPS or healing
    percentages.
- **Tooltips:** every spec of the character, current spec first, plus eligible alts for
  transferable items (with AltStable).
- **Markers:**
  - green bag and loot arrows for current-spec upgrades;
  - amber for transferable upgrades for another spec or alt;
  - hold **Ctrl** to reveal off-spec upgrades.
- **Shatter:** protects potential upgrades from disenchanting, through Shatter's own integration.
- **Rules that respect the game:**
  - class and armor-proficiency gates;
  - per-spec armor types (Holy Paladin may wear cloth, Protection may not);
  - a level window ("upgrade in 2 levels");
  - set-bonus warnings.
- **Two looks:** native WoW Forever (default) and Glass (LibGlass, through Glass UI).

## Commands (foundation build)

| Command | Does |
|---|---|
| `/gg` | Diagnostics: build, current spec, profiles per spec, AltStable/Glass UI status |
| `/gg spec <1\|2> <SPEC.KEY>` | Map a spec group to a spec, e.g. `/gg spec 1 PRIEST.SHADOW` |
| `/gg import <SPEC.KEY> ( Pawn: v1: ... )` | Import a Pawn scale string for a spec |
| `/gg options` | Open the settings page (Esc > Options > AddOns > Glass Gear) |
| `/gg set <SPEC.KEY> <set name\|none\|auto>` | Compare a spec with a saved equipment set instead of the gear it last wore. `none`: never a set, not even one assigned in the client; `auto` (default): the set assigned in the client, if any |

## Requirements

- WoW Forever (Interface 16001).
- **Optional:** AltStable for alts across your accounts (its gear and provenance APIs are in;
  Glass Gear's alt rows are GG-201/GG-203); Glass UI for the Glass look; Shatter for disenchant protection. Syncing your own weight
  profiles between accounts uses a shared entry-sync library instead (ES-001), not AltStable
  ([docs/INTEGRATION-GAPS.md](docs/INTEGRATION-GAPS.md)).

## Development

- **Tests:** `pwsh tests/run.ps1` (Lua 5.1 at `C:\Program Files (x86)\Lua\5.1`). It runs
  `luac -p` on every file, then every `tests/test_*.lua`.
- **Deploy:** `pwsh Tools/deploy.ps1`, which copies the TOC's files and LibGlass from `..\LibGlass`
  into `_forever_`.
- **Docs:**
  - [PRD](docs/PRD.md)
  - [Architecture](docs/ARCHITECTURE.md)
  - [ADRs](docs/adr/)
  - [API v1](docs/API.md)
  - [Schema](docs/SCHEMA.md)
  - [Formats](docs/FORMATS.md)
  - [Ecosystem findings](docs/ECOSYSTEM-FINDINGS.md)
  - [In-game checks](docs/FOREVER-PROBE.md)
  - [Mockups](docs/mockups/README.md)

## License

MIT. Glass Gear reads Pawn's documented scale-string format but contains no Pawn code.
