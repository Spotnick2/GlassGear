# Glass Gear: product requirements

Glass Gear is a standalone gear comparison and upgrade-advice addon for World of Warcraft: Forever
(Interface 16001). It replaces the owner's Pawn workflow. It's part of the Glass family, and works
on its own.

**The central rule:** tooltips can show all of my character's specs, while ordinary bag arrows stay
on my current spec.

Status: this document is the M0 contract. Everything that touches the game client is unverified until the
in-game checks in [FOREVER-PROBE.md](FOREVER-PROBE.md) pass (the game is offline until 2026-11-04).

## 1. Scope

| In MVP (M1–M3) | Later (M4–M5) | Out of scope |
|---|---|---|
| Per-character, per-spec stat weights | Bag replacements (Baganator, Bagnon) | Combat simulation inside the addon |
| Pawn string import/export (incl. WoWSims "Pawn EP") | Localisation beyond enUS | Recommending items to other players' characters |
| Tooltip rows for my specs (+ eligible alts with AltStable) | Gear Lab planner (Rawr-style) | Automatic disenchanting, casting or item moves |
| Bag and loot markers, Ctrl reveal | External simulations via AltStable Companion | Network requests of any kind |
| Detailed comparison window | Importing simulation results (`sim-result`) | |
| Shatter disenchant protection (Shatter-side integration) | | |
| WoW Forever look (default) and Glass look (via Glass UI) | | |

"Every spec" means **the current character's relevant specs**, not every class in the game. Alt results
are separate rows.

## 2. Vocabulary

- **Spec**: one of the class's talent trees, as a stable key (`PRIEST.SHADOW`). Druid Feral is split
  into `DRUID.FERAL_TANK` / `DRUID.FERAL_CAT`. Forever has no Retail spec IDs ([adr/0002](adr/0002-spec-model.md)).
- **Current spec**: the spec mapped to the active spec group (manual mapping, or automatic once
  probed, GG-101). An unmapped group gives `unknown-spec`, never a guess.
- **Profile**: one set of stat weights for one character and spec, with its provenance ([adr/0005](adr/0005-weight-sources.md)).
- **Baseline**: the equipment a spec is compared against, per slot ([adr/0003](adr/0003-upgrade-metric.md)).
- **Item-score estimate**: Σ weight × stat. It is **not** a DPS or healing percentage, and every surface
  labels it that way.
- **Own character**: provenance `self` (played here) or `own-account` (first-hand from a proven
  own-account peer). Being known to AltStable doesn't make a character mine ([adr/0001](adr/0001-sync-ownership.md)).
- **Transferable**: a bag instance that can still legally move to another of my characters. This is a
  tri-state: `eligible | ineligible | unknown`.

## 3. Context behaviour matrix

The **tooltip**, **marker** and **protection** policies are independent settings
([adr/0006](adr/0006-independent-policies.md)). The marker columns below are defaults.

| Context | Tooltip | Default marker | With reveal held (Ctrl) | Protection (Shatter) |
|---|---|---|---|---|
| Boss loot / loot window / roll frame | My specs, current spec first and emphasised; off-spec rows compact | Green only for a current-spec upgrade | + amber for my off-spec upgrades; BoE loot also amber for eligible alts (**proposal, owner review**) | n/a (not in bags) |
| Soulbound gear in bags | My specs, current first | Green only for a current-spec upgrade | + amber for my off-spec upgrades. **Never alts** | Protects my off-spec upgrades |
| Transferable BoE/BoA in bags | My specs + eligible alt rows | Green for a current-spec upgrade; **otherwise amber** for my other specs or an eligible alt ("Mark transferable upgrades", default on) | Same, green still wins | Protects my specs + eligible alts |
| BoE that becomes soulbound | Re-evaluated as soulbound right away (instance bind state) | Soulbound rules | Soulbound rules | Soulbound rules |
| Hypothetical item (vendor, link, AH) | My specs; transfer `unknown` until it is a bag instance | none | none | n/a |

Rules that apply everywhere:

1. **Green wins.** If an item is a current-spec upgrade, its marker is green, even when it also helps
   another spec or an alt.
2. **Shape and colour both carry meaning.** Green is a filled double chevron; amber is an outlined
   chevron. The tooltip shows a legend line.
3. **Never recommend a soulbound item to an alt.**
4. **Missing weights read "no weights"** (grey). They never read 0, "no upgrade" or "−100%".
5. An upgrade for another spec of the current character does **not** need AltStable.
6. **"Synced" ≠ "transferable".** Transfer eligibility comes from bind state and verified rules, never
   from AltStable knowing a character.
7. Secondary spec rows are compact and quieter than the current-spec row. Alt rows show character,
   spec and the estimated change.
8. Recipients are listed, never ranked by percentage across characters.

## 4. Reveal modifier

- The default is **Ctrl**. Options are Ctrl, Alt or None. Shift is not offered: Forever binds it to
  COMPAREITEMS and EXPANDTOOLTIP (`Bindings_Camelot.xml:1533-1552`).
- **Effective state** = the modifier is down (either side) **and** no edit box has keyboard focus.
  It is recomputed on `MODIFIER_STATE_CHANGED`, whenever a reveal surface is shown, and by a 0.1 s
  poll that runs only while a reveal surface is visible. A release or a focus change while typing
  therefore always reconciles.
- While active: own off-spec upgrades show amber, current-spec stays green, and a soulbound item never
  shows alts. Release restores the normal display at once.
- Reveal never changes saved settings, needs no reload, and never consumes clicks: Ctrl-click
  (DRESSUP) still opens the dressing room.
- **Combat:** reveal works, since it only uses Glass Gear's own textures. A button first seen during combat
  gets its marker after `PLAYER_REGEN_ENABLED`.
- **Tooltips** already show the configured specs without the modifier. An open tooltip refreshes when
  the modifier changes, using Shatter's guards (owner identity, `IsForbidden`). Additional tooltip
  expansion while held is not in MVP. A future option could show alt rows on soulbound tooltips as
  "not transferable" information, which is a separate setting.

## 5. Settings (three independent scopes)

| Setting | Default | Notes |
|---|---|---|
| Tooltip specs | All my specs, current first | Options: current only, all my specs, selected specs |
| Tooltip alts | On when AltStable provides own characters | Eligible own alts on transferable items only |
| Marker scope | Current spec | Options: current spec, + selected own specs, or all my specs |
| Mark transferable upgrades | On | Amber for transferable items (matrix row 3) |
| Reveal modifier | Ctrl | Ctrl / Alt / None |
| Minimum upgrade | 0.5 % | Same threshold as Pawn. It applies to markers and protection, not to the rows themselves |
| Protection scope | All tracked specs (mine + selected alts) | Independent of what the markers show |
| Level-appropriate upgrades only | On, look-ahead 0 levels | Look-ahead N (0–10). Within the window the row reads "+6.2 % at level 42 (in 2 levels)", with no marker by default. Above the window, the item is not presented as an upgrade (the row says "requires level N"). Applies per recipient: an alt uses its own level (GG-117) |
| Spec armor rules | On | Two layers. **Class gate:** a class that can't wear or wield an item never sees it as an upgrade; this is not a setting, and it reads known skills (Forever plate and mail come at 40). **Spec rule:** each spec has its allowed armor types, editable per profile. A Protection Paladin gets plate, while a Holy Paladin gets cloth to plate, so a cloth spell-power item can be a Holy upgrade and is ineligible for Protection (GG-118; defaults in [adr/0003](adr/0003-upgrade-metric.md)) |
| Set-bonus warnings | On | "Breaks 3-piece bonus" / "Completes 2-piece bonus" from the client's ItemSet data. The bonus's value is not scored (GG-119) |
| Appearance | WoW Forever | "Follow Glass UI" when Glass UI lists Glass Gear (GUI-001); a switch needs `/reload` |

**Hiding a tooltip row or a bag marker never disables protection.**

## 6. Data correctness requirements

They are detailed in [adr/0003](adr/0003-upgrade-metric.md). In summary:

- Compare against the **selected spec's baseline**, which has a labelled source. Possible sources are a
  mapped equipment set, the gear seen while that spec was active, or the current gear (labelled
  `fallback-current`).
- Rings and trinkets, two-hand versus main-hand + off-hand, and unique-equipped are handled by
  **enumerating the legal resulting configurations**.
- Class, level and proficiency requirements apply. Above the character's level, the item is scored but
  marked `LATER_LEVEL`.
- Enchants: both items are compared without enchants. Random suffix is kept.
- Equip, use and proc effects and set bonuses are listed as limitations. They never count as a
  modelled zero.
- Stale, incomplete or fallback baselines may drive labelled display estimates, but they can **never**
  give a `clear` protection verdict.
- A generic item link is not a bag instance. Binding and transfer eligibility need the instance.

## 7. Shatter protection (Shatter-side, SH-001/SH-002)

- Normal queue construction leaves out potential upgrades by default and says why.
- **Fail-closed:** `unknown`, `pending`, `unsupported`, an incompatible API or an error all keep the
  item, with the reason "Glass Gear can't confirm yet". Only `clear` lets the item through.
- Glass Gear absent: Shatter behaves exactly as today.
- "Disenchant anyway" is a per-row action. It is scoped to `{item GUID, assessment token}` for the
  session, bypasses only the Glass Gear veto, and expires on any change or at `expiresAt`.
- The secure one-click, one-item flow is unchanged, and nothing is automated.
- Mail Mode: sender-owned items are never assessed for my characters.

## 8. AltStable absent

Glass Gear still evaluates the current character and all its specs. The following are **unavailable**
without AltStable, or with an AltStable that lacks AS-001/AS-003:

- alt rows and alt markers;
- alt protection;
- the characters page;
- baselines of other characters.

Syncing your own weight profiles and baselines across accounts does **not** need AltStable since the
adr/0001 amendment: it goes through the shared entry-sync library (ES-001, GG-202).

`/gg diag` and the API report these as `unavailable`, never as "no upgrade".

## 9. Non-functional

- No network requests, and no full-roster scans on a tooltip redraw. Work per frame is bounded
  ([API.md](API.md)).
- English strings only for now (the family convention). Comparisons use locale-independent tokens
  (`ITEM_MOD_*`, `INVTYPE_*`, class tokens), never tooltip text (GG-403).
- Lua 5.1 and the Forever API only. Every API used is in the newest dump (1.60.1.70532), and runtime
  behaviour is checked in game.

## 10. Acceptance

The owner's acceptance cases and where each one is covered (M0 test or backlog item, automated or in
game) are listed in the traceability table at the end of [BACKLOG.md](BACKLOG.md).
