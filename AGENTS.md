# AGENTS.md: Glass Gear

This is the shared baseline for any coding agent. `CLAUDE.md` adds Claude-specific notes; where the
two overlap, this file wins. The workspace-wide rules are in `C:\Projects\WoW\CLAUDE.md`: the API
dump, References, probes, deploy target and secrets.

## What this is

Glass Gear is a WoW **Forever** addon (Interface 16001, Lua 5.1, Vanilla content on the Retail
codebase) for gear comparison and upgrade advice.

The single global is `GlassGear`, and `GlassGear.API` is the public v1 contract
([docs/API.md](docs/API.md)).

## Rules

- **Pure engine.** `Engine/*`, `Profiles/PawnString.lua`, `Item/ItemContext.lua` (decisions),
  `Character/Spec.lua` and `Character/Baselines.lua` never call game APIs. Every decision lives
  there and is tested under plain Lua.
- **`Core/Compat.lua` is the only file that calls item and character game APIs.** Every name it
  uses is in the newest dump (`References/Forever/api`, highest build). Behaviour is trusted only
  after a probe ([docs/FOREVER-PROBE.md](docs/FOREVER-PROBE.md)).
- **The three policies are independent.** Tooltip, marker and protection never share settings, and
  protection never reads marker visibility ([adr/0006](docs/adr/0006-independent-policies.md)).
- **Missing data is never zero.**
  - No weights reads "no weights".
  - Missing item data is `pending`.
  - A missing baseline slot is `unknown`.
  - Untrusted baselines never give a `clear` protection verdict.
- **Ownership comes from provenance** (`self` / `own-account`), never from AltStable's `account`
  label or roster membership. "Synced" never means "transferable".
- **Sync** follows AltStableSync's per-entry model ([adr/0001](docs/adr/0001-sync-ownership.md)).
  - Never field-merge.
  - Never mint a version on receipt, except when retiring conflict copies.
  - The writer token is fresh every session.
- **Spec keys and entry ids are stable.** Add to them; never rename them.
- **Pawn is CC BY-NC-ND.** Implement its documented format and behaviour; never copy its code.
- **Reference copies stay private.** Never cite a third-party reference copy (its path, version or
  `file.lua:line`) in code, docs, tests or issues; the citations live in the private project
  memory, which the reference index reads. Naming an addon we integrate with is fine.
- **No `## Dependencies`**, only `OptionalDeps`. No GameTooltip restyling, no writes to Blizzard
  globals (`SlashCmdList` fields only).
- **Player text goes through `GG.L`** (GG-403, `Core/Locale.lua`): `L["English text"]`, a literal
  key, one format string per sentence (`L["Not an upgrade for %s"]:format(spec)`). Never branch on
  displayed text: return a kind or a flag beside it. Codes, keys, Pawn syntax, API data for other
  addons and `geterrorhandler()` messages stay English. After adding keys, run
  `python -I Tools/locale_catalogue.py` (tests/test_locale.lua checks `Locales/enUS.lua`).
- **Tests.** Every new test is mutation-checked once: break the code and watch the test fail.
  Stubs (`tests/wow_stubs.lua`) model Forever, and every stubbed name must exist in the dump.

## Build, test, deploy

```
pwsh tests/run.ps1          # luac -p on every file + tests/test_*.lua (Lua 5.1)
pwsh Tools/deploy.ps1       # -> _forever_\Interface\AddOns\GlassGear (+ LibGlass from ..\LibGlass)
```

After deploying, the owner does `/reload` in game; a brand-new addon folder needs one full client
restart. Deploy yourself after a change.

## Workflow

- The backlog is [docs/BACKLOG.md](docs/BACKLOG.md), mirrored as GitHub issues.
- Work goes issue → branch off `main` → PR with `Closes #N`. The owner reviews and merges, except
  docs-only PRs that aren't worth a review.
- Cross-repo work goes as issues in the other repos ([docs/INTEGRATION-GAPS.md](docs/INTEGRATION-GAPS.md)).
  Never edit a sibling repo from this one.
- Releases follow `References\Docs\RELEASING.md` (GG-404 first).
