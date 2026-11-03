------------------------------------------------------------
-- Character/Baselines.lua - per-spec baselines (adr/0003, GG-108). Pure.
--
--   Baselines.Choose({ equipmentSet = b|nil, observed = b|nil, current = b|nil })
--     -> baseline (with .source, .complete) | nil
--   Baselines.Freshness(b, now, gearChangedAt) -> stale (bool), expiresAt
--   Baselines.Snapshot(live, specKey, source, now, group, maxItem) -> stored data
--   Baselines.SameGear(a, b) -> bool          (stored data, slot by slot)
--   Baselines.NeedsWrite(stored, snap, now) -> bool
--   Baselines.Hydrate(data, facts) -> baseline, missing itemIDs
--
-- A stored baseline (an entry's data, docs/SCHEMA.md) holds per gear slot
-- only its occupancy and the trimmed item string (Compat.GearItemString, the
-- form AltStable's GetCharacterGear returns). Hydrate turns it back into the
-- shape Evaluate scores, through a `facts(itemString)` function
-- (Compat.ItemFacts); an item whose data isn't loaded yet is listed as
-- missing, never scored as an empty slot.
------------------------------------------------------------

local GG = GlassGear
local Baselines = {}
GG.Baselines = Baselines

Baselines.STALE_AFTER = 14 * 24 * 3600
-- Unchanged gear re-confirms its capture time at most this often, so a
-- login doesn't mint (and later sync) a new version every time.
Baselines.REFRESH_AFTER = 24 * 3600

function Baselines.Choose(sources)
    sources = sources or {}
    local order = {
        { sources.equipmentSet, "equipment-set" },
        { sources.observed, "observed" },
        { sources.current, "fallback-current" },
    }
    for _, o in ipairs(order) do
        local b = o[1]
        if b and b.slots then
            local copy = {}
            for k, v in pairs(b) do copy[k] = v end
            copy.source = o[2]
            local complete = true
            for _, slot in ipairs(GG.Data.Slots.GEAR) do
                local s = b.slots[slot]
                if not s or s.state == "unknown" then complete = false end
            end
            copy.complete = complete
            return copy
        end
    end
end

-- A baseline is stale after STALE_AFTER, or once the character's gear
-- changed after capture (gear-change stamp, never AltStable lastUpdate).
function Baselines.Freshness(b, now, gearChangedAt)
    if not b or not b.capturedAt then return true, now end
    local expiresAt = b.capturedAt + Baselines.STALE_AFTER
    if gearChangedAt and gearChangedAt > b.capturedAt then return true, gearChangedAt end
    return now >= expiresAt, expiresAt
end

-- The stored form of a live (hydrated) baseline. A slot whose item string is
-- missing or longer than maxItem (Codec.MAX_ITEM) is stored as unknown.
function Baselines.Snapshot(live, specKey, source, now, group, maxItem)
    local slots = {}
    for _, slot in ipairs(GG.Data.Slots.GEAR) do
        local s = live and live.slots and live.slots[slot]
        if s and s.state == "empty" then
            slots[slot] = { state = "empty" }
        elseif s and s.state == "occupied" and type(s.item) == "string" and (not maxItem or #s.item <= maxItem) then
            slots[slot] = { state = "occupied", item = s.item }
        else
            slots[slot] = { state = "unknown" }
        end
    end
    return { specKey = specKey, source = source, capturedAt = now, group = group, slots = slots }
end

function Baselines.SameGear(a, b)
    if not (a and b and a.slots and b.slots) then return false end
    for _, slot in ipairs(GG.Data.Slots.GEAR) do
        local x, y = a.slots[slot] or {}, b.slots[slot] or {}
        if x.state ~= y.state or x.item ~= y.item then return false end
    end
    return a.source == b.source and a.group == b.group
end

-- Write when there is nothing yet, the gear differs, or the last capture is
-- older than REFRESH_AFTER (so unchanged gear stays fresh without churn).
function Baselines.NeedsWrite(stored, snap, now)
    if not (stored and stored.slots) then return true end
    if not Baselines.SameGear(stored, snap) then return true end
    return not stored.capturedAt or now - stored.capturedAt >= Baselines.REFRESH_AFTER
end

function Baselines.Hydrate(data, facts)
    local slots, missing = {}, {}
    for _, slot in ipairs(GG.Data.Slots.GEAR) do
        local s = data and data.slots and data.slots[slot]
        if s and s.state == "empty" then
            slots[slot] = { state = "empty" }
        elseif s and s.state == "occupied" then
            local f = facts(s.item)
            if f and f.ready then
                slots[slot] = { state = "occupied", itemID = f.itemID, equipLoc = f.equipLoc,
                    classID = f.classID, subclassID = f.subclassID, itemString = f.itemString,
                    item = s.item, tokens = f.tokens, unique = f.unique, setID = f.setID,
                    hasSpell = f.hasSpell, unsupported = f.unsupported, reqLevel = f.reqLevel }
            else
                slots[slot] = { state = "unknown" }
                if f and f.itemID then missing[#missing + 1] = f.itemID end
            end
        else
            slots[slot] = { state = "unknown" }
        end
    end
    return { slots = slots, capturedAt = data and data.capturedAt, group = data and data.group }, missing
end

return Baselines
