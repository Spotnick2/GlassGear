# Changelog

## Unreleased

- Baganator (GG-401): the upgrade arrows show in Baganator too, as an icon-corner widget ("Glass
  Gear upgrades", top left by default; move or remove it in Baganator's corner settings), with the
  same rules and the reveal key; never on another character's bags. `/gg` says where it is, or how
  to bring it back.
- Performance, measured (GG-402): a full bag stays within the per-frame budget and finishes over
  the next frames; tooltip redraws recompute nothing. `/gg stats` shows what the runtime did,
  including the most time spent comparing in one frame.
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
- Your other characters (GG-201): with AltStable, Glass Gear knows your own characters on this and
  your other WoW accounts (AltStable's provenance: never a friend's, never by an account label),
  and `/gg` counts them. Alt upgrades themselves come with GG-203.
- Characters page (GG-204, `/gg characters` or the settings page's button): your characters by
  account, each spec a box for disenchant protection (the one you play is tracked by default; your
  other characters' boxes stay inactive, and the page says so, until protection can assess alts),
  how old each one's recorded gear is (and how to refresh it),
  which specs have no weights, and Open AltStable. Without AltStable it says what still works.
- Spec mapping on the settings page (GG-104): a SPECS section maps each spec group to a spec, or
  Not set, without a slash command; the active group is marked. `/gg spec <group> none` clears one.
- Per-spec gear (GG-108): each spec compares with its own gear. Glass Gear records what you wear
  in each spec (on login, after a gear change, after a spec switch); `/gg set <spec> <set>` uses a
  saved equipment set instead, and a set the client assigned to that spec is used on its own
  (`/gg set <spec> none` turns sets off for that spec, `auto` back on). A
  spec with nothing recorded still compares with your current gear, labelled. Gear recorded more
  than 14 days ago is flagged in the tooltip and `/gg`.
- What you carry counts (GG-122): a one-hander compared with a spec that uses a two-hander pairs with
  the best off-hand in your bags, not only the one you wear; and an item is no longer shown as an
  upgrade when your bags already hold a better one for that spec (the tooltip says "you own better"
  and names it; rings and trinkets need two better ones).
- Disenchant protection for Shatter (GG-301): `GlassGear.API.AssessProtection` says whether a bag
  item is an upgrade for one of your tracked specs (keep it), safe to disenchant, or not certain yet
  (keep it). Recorded gear that is stale, or a spec compared with your current gear, is never called
  safe; specs without weights are listed as unchecked. Shatter's side is SH-001.
- API runtime (GG-114): answers are cached until something they depend on changes, so redrawing a
  tooltip or a bag costs a lookup; at most 200 comparisons run per frame (the rest finish on the
  next frames); requests for the same item share one computation; bounded queues answer OVERLOADED
  instead of growing.
- Bagnon (GG-401): the upgrade arrows also show on Bagnon's bag buttons, with the same rules and the
  reveal key; never on a cached view of another character's bags. `/gg` names the bag addon; on
  AdiBags, ArkInventory, BetterBags and EllesmereUIBags it says the arrows aren't there yet
  (tooltips are).
- Weight profiles window (GG-105, `/gg profiles`, or the settings page's button): up to 4 profiles
  per spec, one active; paste a Pawn string or a WoWSims Pawn EP export and see at once whether it
  is valid, how many weights it has and what it leaves out; add it as a new profile or replace one;
  edit each weight (a number, X to ignore the stat, empty to clear), the name and the armor types;
  export as a Pawn string to copy. Character exports (SimulationCraft, WoWSims JSON) are explained,
  not imported. A change made elsewhere meanwhile is never overwritten. `/gg import` still replaces
  the active profile's weights.
- Set bonuses (GG-119): the client's item-set data (545 sets, build 1.60.1.70753) is built in, so
  tooltips say "Completes a 2-piece set bonus" / "Breaks a 4-piece set bonus" instead of only "Set
  item: bonus not scored". The bonus itself is still never scored.
- Detailed comparison (GG-113, `/gg compare`, with an item link or the item last hovered): one item
  against a spec's gear, with the stats behind the estimate (unweighted ones shown, marked), the
  item score on the profile's scale, the verdict, how it was made (method, profile, source, the gear
  compared with and its age) and what it leaves out. A spec with no recorded gear offers your saved
  equipment sets. Built on the shared window of the profiles page.
