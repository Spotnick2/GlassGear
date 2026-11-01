# CLAUDE.md: Claude-specific overlay

`AGENTS.md` is the shared baseline (rules, build/test/deploy, workflow). Where the two overlap,
AGENTS.md wins.

## Adversarial review: prefer a different model family

PR code review is done **manually by the owner**. Don't run Codex (or any automated review) on PRs,
and don't post review comments, unless asked.

For a second opinion on a plan or design, when the owner asks for one, use **Codex** through the
`/codex-consult` skill, with `-m gpt-6-astra -c model_reasoning_effort=high` (the owner's choice
for this repo). The foundation plan went through nine rounds until consensus:
`docs/reviews/plan/`.

The loop that works best: Claude drafts, Codex attacks, then Claude reconciles, telling real
objections from context gaps.

Codex's bug-catching is useful here. The sync protocol rounds found real defects. Be sceptical when
it wants to add complexity: reusing an owner-proven model (AltStableSync's) beat inventing one.

## Consulting Codex

Give Codex:

- `AGENTS.md` and `docs/` (ADRs, API, SCHEMA);
- `C:/Projects/WoW/References/Docs/PORTING-TBC-TO-FOREVER.md`;
- the newest API dump.

Good subjects for Codex in this repo:

- the entry-sync receive and resolve rules (`Engine/EntrySync.lua` against AltStableSync's
  `Catalog.lua`);
- configuration enumeration (`Engine/SlotCompare.lua`);
- the protection verdict (`Engine/Policy.lua`);
- the async API contract.

Tell it that the stubs model Forever and that the in-game behaviour is still unprobed: the game is
offline until 2026-11-04.
