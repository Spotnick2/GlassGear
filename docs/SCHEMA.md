# SavedVariables, sync entries and migrations

The layout is internal. Consumers use [API.md](API.md), never these tables.

## `GlassGearDB` (account-wide)

```lua
GlassGearDB = {
  schema   = 1,
  settings = {                     -- per account; never synced; written only through Core/Prefs
    tooltip    = { specs = "all", selected = {}, alts = true },   -- "all" | "current" | "selected"
    markers    = { scope = "current", selected = {}, markTransferable = true, threshold = 0.005 },
                                                 -- scope "current" | "selected" | "own"
    reveal     = { modifier = "CTRL" },          -- "CTRL" | "ALT" | "NONE" (never "SHIFT")
    protection = { scope = "tracked", threshold = 0.005, noWeights = "ignore" },  -- "ignore" | "keep"
    levelWindow = { enabled = true, lookAhead = 0 },              -- look-ahead 0-10 levels
    specArmor  = true,
    setBonusWarnings = true,
    appearance = { theme = "forever" },          -- kept unchanged while Glass UI decides the look
  },
  -- `selected` lists are { [specKey] = true }. The minimum upgrade is one setting: markers.threshold
  -- and protection.threshold always hold the same value (0-5 %).
  tracked  = { ["<charKey>"] = { ["PRIEST.HOLY"] = true } },  -- protection's tracked specs; a
                                   -- character with no entry tracks all of its own specs
  entries  = {                     -- the entry store (adr/0001), local and remote side by side
    ["<entryId>"] = {
      id = "<guid>:PRIEST.SHADOW:<uuid>", kind = "profile" | "baseline",
      version = "<writer>:<seq>", ancestors = { "<v>", ... },  -- at most 20
      deleted = nil | true,
      conflict = nil | { of = "<rootId>", from = "<label>", deletion = true|nil, retired = true|nil },
      provenance = "self" | "own-account",
      data = { ... },              -- per kind, below
    },
  },
  replicaState = { ["<guid>"] = { maybeBehind = false } },  -- from manifest comparison (M2)
}
```

`charKey` is the character's GUID. A display name is never a key, because names are not unique
(AltStable `PUBLIC-API.md:39`).

## `GlassGearChar` (per character)

```lua
GlassGearChar = {
  schema = 1,
  specMap = { [1] = "PRIEST.SHADOW", [2] = "PRIEST.HOLY" },  -- spec group (1-2) -> spec key of this
                                                             -- class (manual); anything else is
                                                             -- ignored as "invalid-mapping"
  equipSetMap = { ["PRIEST.HOLY"] = { id = <equipmentSetID>, name = "Holy Set" },  -- /gg set (GG-108)
                  ["PRIEST.SHADOW"] = { none = true } },  -- /gg set none: no set, not even the client's
                  -- absent (/gg set auto): the set the client assigned to the spec's group, if any
}
```

## Entry data

**Profile** (`kind = "profile"`):

```lua
{ specKey = "PRIEST.SHADOW", name = "Raid", source = "imported-pawn", origin = "Karuzo - Shadow - Raid",
  updatedAt = 1793500000, weights = { Intellect = 0.42, SpellDamage = 1.0, CritRating = 0.68 },
  ignored = { Spirit = true },          -- Pawn "X"
  ignoredTokens = { Mana = "7" },       -- unknown Pawn pairs, kept so they round-trip on export
  missing = { "HitRating", ... },       -- WoWSims-dropped stats: missing, not zero (WEIGHT_MISSING)
  armor = { 1, 4 } | nil }              -- the profile's own allowed armor types (nil = spec default)
```

**Baseline** (`kind = "baseline"`):

```lua
{ specKey = "PRIEST.HOLY", source = "observed" | "equipment-set" | "fallback-current",
  capturedAt = 1793500000, group = 1 | 2 | nil,   -- the spec group it was captured in
  slots = { [1] = { state = "occupied", item = "19019:0:0" }, [2] = { state = "empty" }, [3] = { state = "unknown" }, ... } }
```

## Wire codec `GG1` (one entry per line)

```
GG1|<kind p|b>|<id>|<version>|<ancestors comma-separated>|<flags>|<payload>
```

**Flags** (a comma list):

| Flag | Meaning |
|---|---|
| `d` | deleted |
| `c<rootId>` | conflict copy of that root |
| `x` | deletion conflict: the other side deleted the entry |
| `r` | retired copy |

- A deleted entry or a deletion conflict has an empty payload.
- Any other flag is `bad-entry`.

**Escaping.**

| Character | Written as |
|---|---|
| `\` | `\\` |
| `\|` | `\p` |
| newline | `\n` |
| `;` | `\s` |
| `,` | `\c` |
| `=` | `\e` |

No raw newline is ever emitted.

**Profile payload:**

```
<specKey>;<name>;<origin>;<source>;<updatedAt base36>;<token>=<weight>,...;<X tokens>;<unknown>=<value>,...;<missing tokens>;a<armor ids>
```

- A weight is written with up to 3 decimals.
- A weight outside [-999.999, 999.999], or a malformed number, is `bad-entry`. It is never clamped.

**Baseline payload:**

```
<specKey>;<source>;<capturedAt base36>;<group>;<slot>:<o|e|u>[:<item string>],...
```

- The item string is the **trimmed** form AltStable's `GetCharacterGear` returns
  (`Compat.GearItemString`; AltStable `Scanner.lua:96-129`), so own and alt baselines compare alike:
  - On Forever a random suffix is a **bonus ID**; the classic suffix field is always empty
    (measured by AltStable on 205 links). *Beaded Wraps of the Sorcerer* is
    `item:14094::::::::::::1:12745`. The bonus and modifier block is kept.
  - The link level and spec (the scanning character's) are blanked, and everything after the
    modifiers (a crafter's GUID, relics) is dropped. Trailing empty fields are trimmed: a plain item
    is `item:<id>`.
  - At most 64 characters (`Codec.MAX_ITEM`), so the largest legal baseline still fits one entry
    (fixture: 1837 of 2048 bytes). A longer string is captured as `unknown` for that slot (GG-108).
    Measured by AltStable on the 205 stored beta links (2026-11-01): longest 40 characters
    (`item:15304:::::::::::1:1:12728:1:28:5244`: context, one bonus, one modifier), median 22,
    95th percentile 26. Only an enchant plus gems plus several bonuses could pass 64, and the
    sample has no gemmed item (no sockets on Forever, `PORTING-TBC-TO-FOREVER.md:2064`).

- The occupancy codes are `o` occupied, `e` empty and `u` unknown.
- Slots must be gear slots (1–3, 5–18), each listed once.

**Decoding.**

- Any field that fails validation rejects the whole entry (`bad-entry`). The local entry is left
  untouched.
- An unknown `GG<n>` prefix is rejected as an unknown schema.

**Limits** (enforced by the encoder, fixture-tested in `tests/test_entry_sync.lua`):

| Limit | Value |
|---|---|
| Name | at most 24 characters |
| Tokens per profile | at most 40 |
| Ancestors | at most 20 |
| Encoded entry | at most 2048 bytes |

An entry over the size limit is `too-large`. It stays local and is reported.

## Migrations

- `schema` is an integer in both tables. `Core/DB.lua` runs migrations in order (`MIGRATIONS[n]`
  upgrades n−1 to n) at `ADDON_LOADED`, before anything reads the data.
- A table that is **newer** than the code is not touched. Glass Gear runs read-only for that session
  and says so in `/gg diag`. This is the same "refused schema disables sync" rule as AltStableSync.
- Schema 1 is the first, so there are no migrations yet.
