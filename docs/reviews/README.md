# Adversarial reviews

Every round used Codex (`gpt-6-astra`, reasoning effort high, read-only sandbox), at the owner's
request, looping until consensus.

| Review | Rounds | Outcome |
|---|---|---|
| [Plan](plan/) | 9 | Consensus at round 9. The main change: ADR-0001 dropped a bespoke snapshot protocol and reused AltStableSync's per-entry sync model, over an AltStable-owned manifest entry-sync service. |
| [Implementation](implementation/) (M0 code and docs) | 4 | Consensus at round 4. Rounds 1–3 found 21 major issues, all fixed with regression tests and mutation checks. |

Each `round-N.md` is Codex's verdict as received. The fixes are in the commits that follow it on the
foundation branch.
