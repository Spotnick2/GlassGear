# Glass Gear public API v1 (contract)

Status: **a proposal, versioned at `API_VERSION = 1`**. In M0 some operations report
`unsupported`; `GetCapabilities()` says exactly which.

Consumers must not read `GlassGearDB` or `GlassGearChar`, and must not parse rendered tooltips. The
callback and readiness idioms follow AltStable (`AltStable/docs/PUBLIC-API.md`,
`PublicAPI.lua:155-194`).

## Discovery, versioning and load order

```lua
-- In the consumer's TOC: ## OptionalDeps: GlassGear
local GG = rawget(_G, "GlassGear")
local api = GG and rawget(GG, "API")
if type(api) ~= "table" or api.API_VERSION ~= 1 then
    -- Absent or an incompatible major version: behave as if Glass Gear is not installed
    return
end
local caps = api.GetCapabilities()        -- deep copy
if not caps.features.assessProtection then -- each operation is feature-detected
    -- treat as "Glass Gear can't confirm" (fail-closed, if you destroy items)
end
```

- **When the table exists.** `GlassGear.API` exists as soon as Glass Gear's files have loaded. That is
  before your `ADDON_LOADED` when you list it in `OptionalDeps`.
- **Data readiness** is separate. Use `api.IsReady()`, or the `Ready` callback, which fires once,
  after `PLAYER_LOGIN` and once the spec and profiles have loaded.
- **Versions.** `API_VERSION` is the **major** version, and it changes only on an incompatible
  change. New fields and new features are additive and are detected through
  `GetCapabilities().features`.
- **Unsupported calls.** An operation or scope that isn't supported returns `status = "unsupported"`
  and is **never silently narrowed** (for example, from `tracked` to `current`).
- **Copies.** Every returned table is a deep copy, so mutating it has no effect.

## Methods

| Method | Returns | M0 |
|---|---|---|
| `GetCapabilities()` | `{apiVersion, build, features = {evaluate, evaluateBatch, assessProtection, alts, sync, frameBudget, resultCache, ...}, limits = {perFrame, jobs, requests, cache, ...}, unavailable = {[feature] = reason}}` | yes |
| `IsReady()` | boolean | yes |
| `GetCharacters()` | list of `{key, guid, name, realm, class, level, provenance, current}`. Current character only without AS-001 | yes (local) |
| `GetSpecs(charKey)` | list of `{key, name, current, hasProfile}` in tree order | yes |
| `GetProfile(charKey, specKey)` | The spec's **active** profile (of up to 4; SCHEMA, latest `activeAt`): `{id, specKey, name, source, origin, version, updatedAt, weights = {[token] = n}}` or `nil, reason` | yes (local) |
| `Evaluate(request)` | response (below) | yes (current character, local baselines) |
| `EvaluateBatch(requests)` | list of responses (at most 64 items) | yes |
| `CancelRequest(requestId)` | `true` / `false` | yes |
| `AssessProtection(itemRef, opts)` | protection result (below) | `unsupported` until GG-301 |
| `RegisterCallback(event, fn, owner)` / `UnregisterCallback(event, owner)` | — | yes |

### Request

```lua
{
  item    = link | ItemLocation | { bag = b, slot = s },
  context = "tooltip" | "bags" | "loot" | "purchase" | "protection",
  scope   = "current" | "own" | "tracked" | "targets",
  targets = { { char = "<charKey>", spec = "PRIEST.HOLY" }, ... }, -- scope == "targets", at most 32
}
```

### Response

```lua
{
  requestId = 17,
  status    = "upgrade",          -- aggregate, display only (precedence below)
  results   = {                   -- one per (character, spec); never ranked by %
    {
      status      = "upgrade" | "no_upgrade" | "ineligible" | "unknown" | "pending" | "unsupported",
      character   = { key, name, realm, provenance = "self" | "own-account" },
      spec        = "PRIEST.HOLY",
      current     = false,
      profile     = { id, source = "imported-pawn", version, updatedAt } | nil,
      candidate   = { itemString, instance = { bag, slot, guid, bound } | nil },
      baseline    = { source = "equipment-set" | "observed" | "fallback-current",
                      capturedAt, complete = true, stale = false, maybeBehind = false,
                      expiresAt },   -- per spec (GG-108): the spec's own gear
                      -- A spec whose own gear is still loading is its own pending row
                      -- (BASELINE_ITEM_DATA_PENDING): a stored or set baseline's items, or,
                      -- for a spec compared with the worn gear (or a candidate pairing with
                      -- a worn hand), a worn item. The others aren't held up.
      replaces    = { slots = { 3 }, items = { "itemString" } },
      score       = { candidate = 108.6, baseline = 100.0, delta = 8.6, pct = 0.086 },
      method      = "weights-linear",
      eligibility = { equipNow = true, reasons = {} },
      transfer    = { state = "eligible" | "ineligible" | "unknown", reasons = {} },
      reasons     = { "EMPTY_SLOT", ... },
      limitations = { "EFFECT_NOT_SCORED", ... },
    },
  },
}
```

- **Order:** current spec, then the character's other specs in tree order, then alts in the owner's
  tracked order.
- **Aggregate `status`** (display only, never a protection verdict), first match wins:
  1. any `upgrade`;
  2. else any `pending`;
  3. else any `unknown`;
  4. else any `no_upgrade`;
  5. else any `ineligible`;
  6. else `unsupported`.

### Async contract

`Evaluate` and `EvaluateBatch` **always return synchronously, with every result present**. A result
that can't be computed yet is a placeholder with `status = "pending"`: its item data is missing, or it
is over the per-frame budget.

- **Completion.** When a request's placeholders resolve, `EvaluationReady` fires **once** with
  `{requestId, response}`. The response is a complete deep copy, so you don't need to call again.
- **Item data.** One load request per itemID (deduplicated), a queue of at most 256 unique ids, and
  each load attempt times out after 5 s.
  - After 3 attempts, the rows that waited for that item are `unknown`, with `ITEM_DATA_UNAVAILABLE`.
    Rows already finished stay, and a row waiting for the frame budget or another item still
    completes.
  - Whether an item is usable is read from the item, never from which rows fit a frame's budget: a
    load event while the budget is spent keeps the item's attempt count, and `ItemDataReady` fires
    only for an item that really loaded.
  - Queue overflow gives `unknown`, with `ITEM_QUEUE_FULL`.
- **Shared work.** Requests for the same item instance (or link), targets and context while one is
  pending share one computation (a *job*). Each request still gets its own `EvaluationReady`, with its
  own `requestId`. A request joining a job gets its rows brought up to date first: never a row from
  before an invalidation, or one whose baseline has since gone stale. `CancelRequest` drops a
  subscription; the job and its item loads go when nobody is subscribed any more.
- **Overload.** At most 512 outstanding pending rows across jobs (deduplicated across requests) and at
  most 64 outstanding requests. Beyond that, the call returns immediately with `unknown`, `OVERLOADED`,
  which is terminal for that call: no callback follows, and nothing is cached.
- **Budget.** At most 200 evaluations (one per (character, spec) row) per frame
  (`features.frameBudget`). A row over the budget is a placeholder, `pending` with `FRAME_BUDGET`,
  computed on a later frame; rows already computed are kept, so a request always progresses.

### Protection

Implemented by GG-301 (`features.assessProtection = true`). The protection scope is the current
character's tracked specs (settings, DISENCHANT PROTECTION); tracked alts join with GG-203.

```lua
local p = api.AssessProtection({ bag = 0, slot = 3 }, { scope = "tracked" })
-- p = { verdict = "protect" | "clear" | "unknown" | "pending" | "unsupported",
--       token = "opaque", expiresAt = 1793500000,
--       recipients = { { character = {...}, spec = "PRIEST.HOLY", pct = 0.086 }, ... },
--       reasons = { "BASELINE_STALE", ... },
--       unchecked = { { character = {...}, spec = "PRIEST.DISCIPLINE" } } }   -- no weights
```

- **Bounded.** It is **synchronous and bounded**: only the protection-scope targets, never deferred.
  It returns a freshly validated verdict, or fail-closed `pending` or `unknown`. Background completion
  only fires `EvaluationInvalidated`.
- **Independent of display.** It uses the **protection scope**, never the marker or tooltip settings
  ([adr/0006](adr/0006-independent-policies.md)).
- **When it is never `clear`.**
  - The baseline is stale, incomplete, `fallback-current` or `maybeBehind`.
  - An item has `EFFECT_NOT_SCORED`, `SET_BONUS_NOT_SCORED` or `NO_SUPPORTED_STATS` and its supported
    score is not already an upgrade.
  - Item data is missing.
- **Specs without weights.** A spec that has no profile cannot be checked. With the default
  `opts.noWeights = "ignore"`, it is listed in `unchecked` and the reasons carry `UNCHECKED_SPECS`,
  so Shatter can say "Discipline unchecked". It does not block the item.
  - With `"keep"`, such a spec makes the verdict `unknown` instead.
  - If no spec in scope has weights, the verdict is `unknown`, never `clear`.

  Without this rule, every item would stay blocked until every tracked spec had weights.
- **Other reasons for `unknown`:** `NOT_READY`, `NO_ITEM` (nothing at that slot),
  `NO_PROTECTION_TARGETS` (no spec tracked), `ITEM_QUEUE_FULL`, `INTERNAL_ERROR` (an error inside:
  reported to the error handler, the item is kept).
- **Pending:** the item data it needs is requested. When it arrives, `EvaluationInvalidated`
  (`itemData`) tells the consumer to ask again; a verdict is never delivered later by itself.
- **`instance`** (`{guid, bound}`) echoes what the verdict was computed for.
- **`token`** hashes the instance GUID, its bind state, the `noWeights` mode, the tracked specs and
  the generation counters, including a **freshness generation**. `expiresAt` is the earliest baseline staleness time. Each call re-checks expiry
  synchronously: when a baseline crosses into staleness, the freshness generation advances before the
  call returns, so the token changes. `EvaluationInvalidated` is queued after that.

### Callbacks

| Event | Payload |
|---|---|
| `Ready` | — |
| `ProfilesChanged` | `{charKeys}` |
| `EquipmentChanged` | `{charKeys}` |
| `RosterChanged` | — |
| `EvaluationInvalidated` | `{reason, charKeys?}`: re-query whatever you cached |
| `EvaluationReady` | `{requestId, response}` |
| `ItemDataReady` | `{itemIDs}`, coalesced per frame |

- **Delivery:** callbacks are batched to the next frame and run under `xpcall`. Dispatch is never
  reentrant, and one failing callback doesn't stop the others.
- **Owner key:** `RegisterCallback(event, fn, owner)` takes an owner key. Registering again with the
  same `(event, owner)` replaces the earlier callback.

## Caching and invalidation (consumer-visible guarantees)

`features.resultCache` (GG-114): complete answers are kept in an LRU cache of 2 000 entries.

- Repeated tooltip redraws don't recompute. Results are cached by (item instance or link, character,
  spec, context). An instance's key includes its GUID, bag and slot and its bind state, so a BoE that
  becomes soulbound, or an item moved to another slot, gets its own answer.
- Every `EvaluationInvalidated` advances a generation **at once** (the event itself follows on the next
  frame), and an answer from an older generation is never served. The reasons cover:
  - profiles;
  - baselines;
  - spec mapping;
  - roster and provenance;
  - policy settings;
  - item data;
  - bind state;
  - freshness.
- **Freshness:** an answer that compared with a stored baseline is dropped once that baseline's
  `expiresAt` passes: the call that notices advances the generation before it returns, computes again
  (`stale = true`), and `EvaluationInvalidated` (`freshness`) follows.
- Answers that may change on their own are never cached: anything `pending`, `OVERLOADED`,
  `ITEM_QUEUE_FULL`, `ITEM_DATA_UNAVAILABLE`, `NOT_READY` or `NO_ITEM`.
- **Nothing scans the roster on a tooltip redraw** (measured: `test_api_runtime`).
- Protection always re-reads the instance's bind state, GUID and expiry.

## Example: Shatter (SH-001)

```lua
-- Shatter/Integrations/GlassGear.lua (proposal; lives in Shatter)
local function GG()
    local g = rawget(_G, "GlassGear"); local api = g and rawget(g, "API")
    if type(api) == "table" and api.API_VERSION == 1 and type(api.AssessProtection) == "function" then
        return api
    end
end

-- Called synchronously from ItemScanner:IsCandidateDisenchantable (Solo only).
function Integration.Verdict(item)
    local api = GG()
    if not api then return "absent" end                      -- behave exactly as today
    local ok, p = pcall(api.AssessProtection, { bag = item.bag, slot = item.slot }, { scope = "tracked" })
    if not ok or type(p) ~= "table" then return "unknown" end -- fail closed
    return p.verdict, p                                       -- "protect"/"unknown"/"pending"/"unsupported" keep the item
end
-- api.RegisterCallback("EvaluationInvalidated", function() Shatter.SoloMode:ScheduleScan("GLASSGEAR", 0.05) end, "Shatter")
```

## Example: a tooltip-reading consumer

```lua
local r = api.Evaluate({ item = link, context = "tooltip", scope = "own" })
for _, row in ipairs(r.results) do
    if row.status == "pending" then -- wait for EvaluationReady(r.requestId)
    elseif row.profile == nil then  -- "no weights": never show 0
    end
end
```
