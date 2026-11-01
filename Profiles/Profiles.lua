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
    return { id = e.id, version = e.version, specKey = specKey, name = d.name, source = d.source,
        updatedAt = d.updatedAt, weights = d.weights or {}, ignored = d.ignored or {}, armor = d.armor }
end

-- Import a Pawn string as a new profile for (guid, specKey).
-- Returns entry, parsed | nil, err.
function Profiles.ImportPawn(store, guid, specKey, text, now, uuid)
    local parsed, err = GG.PawnString.Parse(text)
    if not parsed then return nil, err end
    local id = prefix(guid, specKey) .. (uuid or tostring(now))
    local entry, cerr = store:Create(id, "profile", {
        specKey = specKey, name = parsed.name, source = parsed.source, updatedAt = now,
        weights = parsed.weights, ignored = parsed.ignored,
    }, "self")
    if not entry then return nil, cerr end
    return entry, parsed
end

return Profiles
