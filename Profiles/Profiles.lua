------------------------------------------------------------
-- Profiles/Profiles.lua - weight profiles as sync entries (adr/0001, adr/0005).
-- Entry id: <guid>:<specKey>:<uuid>. The active profile of a spec is the
-- first live, non-conflict profile entry for it (one per spec in M1; up to
-- four once GG-105 adds the picker).
------------------------------------------------------------

local GG = GlassGear
local Profiles = {}
GG.Profiles = Profiles

local function prefix(guid, specKey) return guid .. ":" .. specKey .. ":" end

function Profiles.ForSpec(store, guid, specKey)
    local p = prefix(guid, specKey)
    local ids = {}
    for id, e in pairs(store.entries) do
        if e.kind == "profile" and not e.deleted and not e.conflict and id:sub(1, #p) == p then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    local out = {}
    for _, id in ipairs(ids) do out[#out + 1] = store.entries[id] end
    return out
end

-- The engine's profile shape for a spec, or nil ("no weights").
function Profiles.Active(store, guid, specKey)
    local e = Profiles.ForSpec(store, guid, specKey)[1]
    if not e then return nil end
    local d = e.data
    return { id = e.id, version = e.version, specKey = specKey, name = d.name, origin = d.origin,
        source = d.source, updatedAt = d.updatedAt, weights = d.weights or {}, ignored = d.ignored or {},
        ignoredTokens = d.ignoredTokens or {}, missing = d.missing or {}, armor = d.armor }
end

-- Import a Pawn string for (guid, specKey). Everything the string carries is
-- kept (origin, unsupported tokens, missing WoWSims weights).
-- Until GG-105 adds the profile picker a spec has one profile, so importing
-- again replaces the active profile's weights (a versioned edit of the same
-- entry: it syncs as a newer version, never as a second profile). Otherwise a
-- new entry is created under a collision-free id: `uuid` when given, else the
-- import time plus this session's writer token, suffixed until unused (a
-- tombstone keeps its id forever, so a deleted id is never reused).
-- Returns entry, parsed, replaced | nil, err.
function Profiles.ImportPawn(store, guid, specKey, text, now, uuid, classToken)
    local parsed, err = GG.PawnString.Parse(text, { class = classToken })
    if not parsed then return nil, err end
    local missing = (#parsed.missing > 0) and parsed.missing or nil
    local data = {
        specKey = specKey, name = parsed.name, origin = parsed.origin, source = parsed.source, updatedAt = now,
        weights = parsed.weights, ignored = parsed.ignored, ignoredTokens = parsed.ignoredTokens, missing = missing,
    }
    local active = Profiles.ForSpec(store, guid, specKey)[1]
    if active then
        local entry, eerr = store:Edit(active.id, active.version, data)
        if not entry then return nil, eerr end
        return entry, parsed, true
    end
    local base = prefix(guid, specKey) .. (uuid or (tostring(now) .. "-" .. store.writer))
    local id, n = base, 1
    while store:Get(id) do n = n + 1; id = base .. "-" .. n end
    local entry, cerr = store:Create(id, "profile", data, "self")
    if not entry then return nil, cerr end
    return entry, parsed, false
end

return Profiles
