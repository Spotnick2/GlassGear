------------------------------------------------------------
-- Profiles/Profiles.lua - weight profiles as sync entries (adr/0001, adr/0005).
-- Entry id: <guid>:<specKey>:<uuid>. Up to MAX_PER_SPEC live profiles per
-- spec (GG-105).
--
-- The active profile is the live, non-conflict profile with the latest
-- `activeAt` (ties and profiles never chosen: the first by id). Choosing one
-- edits that entry alone, so two installations choosing at once converge on
-- one answer without any field merge (adr/0001: no field merging, ever).
--
-- Every edit takes the expected version and refuses a stale one
-- (EntrySync "stale"): the caller re-reads and shows what changed.
-- These functions only change the store; GG.Profiles.Changed tells the rest.
------------------------------------------------------------

local GG = GlassGear
local Profiles = {}
GG.Profiles = Profiles

Profiles.MAX_PER_SPEC = 4

local function prefix(guid, specKey) return guid .. ":" .. specKey .. ":" end

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

-- Live profile entries of a spec, by id.
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

-- The active entry of a spec, or nil.
function Profiles.ActiveEntry(store, guid, specKey)
    local best
    for _, e in ipairs(Profiles.ForSpec(store, guid, specKey)) do
        if not best or (e.data.activeAt or 0) > (best.data.activeAt or 0) then best = e end
    end
    return best
end

-- The engine's profile shape of an entry.
function Profiles.Shape(e)
    local d = e.data
    return { id = e.id, version = e.version, specKey = d.specKey, name = d.name, origin = d.origin,
        source = d.source, updatedAt = d.updatedAt, weights = d.weights or {}, ignored = d.ignored or {},
        ignoredTokens = d.ignoredTokens or {}, missing = d.missing or {}, armor = d.armor }
end

-- The engine's profile shape for a spec's active profile, or nil ("no weights").
function Profiles.Active(store, guid, specKey)
    local e = Profiles.ActiveEntry(store, guid, specKey)
    return e and Profiles.Shape(e) or nil
end

-- The activeAt a choice made now gets: later than every profile of the spec
-- already has, so two choices within one second still order (the clock is
-- whole seconds).
local function nextActiveAt(store, idPrefix, now)
    local latest = 0
    for id, e in pairs(store.entries) do
        if e.kind == "profile" and not e.deleted and id:sub(1, #idPrefix) == idPrefix then
            latest = math.max(latest, e.data and e.data.activeAt or 0)
        end
    end
    return math.max(now, latest + 1)
end

local function newId(store, guid, specKey, now, uuid)
    local base = prefix(guid, specKey) .. (uuid or (tostring(now) .. "-" .. store.writer))
    local id, n = base, 1
    while store:Get(id) do n = n + 1; id = base .. "-" .. n end
    return id
end

local function fromParsed(specKey, parsed, now)
    return {
        specKey = specKey, name = parsed.name, origin = parsed.origin, source = parsed.source, updatedAt = now,
        weights = parsed.weights, ignored = parsed.ignored, ignoredTokens = parsed.ignoredTokens,
        missing = (#parsed.missing > 0) and parsed.missing or nil,
    }
end

-- Import a Pawn string as a new profile of the spec, made active.
-- Returns entry, parsed | nil, err ("TOO_MANY_PROFILES" or a parse code).
function Profiles.ImportNew(store, guid, specKey, text, now, classToken, uuid)
    local parsed, err = GG.PawnString.Parse(text, { class = classToken })
    if not parsed then return nil, err end
    if #Profiles.ForSpec(store, guid, specKey) >= Profiles.MAX_PER_SPEC then return nil, "TOO_MANY_PROFILES" end
    local data = fromParsed(specKey, parsed, now)
    data.activeAt = nextActiveAt(store, prefix(guid, specKey), now)
    local entry, cerr = store:Create(newId(store, guid, specKey, now, uuid), "profile", data, "self")
    if not entry then return nil, cerr end
    return entry, parsed
end

-- Replace one profile's weights with a Pawn string. Its name follows the
-- string; whether it is active and its armor types stay.
function Profiles.ImportReplace(store, id, expected, text, now, classToken)
    local e = store:Get(id)
    if not e or e.deleted or e.kind ~= "profile" then return nil, "unknown-id" end
    local parsed, err = GG.PawnString.Parse(text, { class = classToken })
    if not parsed then return nil, err end
    local data = fromParsed(e.data.specKey, parsed, now)
    data.activeAt, data.armor = e.data.activeAt, copy(e.data.armor)
    local entry, eerr = store:Edit(id, expected, data)
    if not entry then return nil, eerr end
    return entry, parsed
end

-- /gg import: replaces the active profile's weights, or creates the first.
-- Returns entry, parsed, replaced | nil, err.
function Profiles.ImportPawn(store, guid, specKey, text, now, uuid, classToken)
    local active = Profiles.ActiveEntry(store, guid, specKey)
    if active then
        local entry, parsed = Profiles.ImportReplace(store, active.id, active.version, text, now, classToken)
        if not entry then return nil, parsed end
        return entry, parsed, true
    end
    local entry, parsed = Profiles.ImportNew(store, guid, specKey, text, now, classToken, uuid)
    if not entry then return nil, parsed end
    return entry, parsed, false
end

-- An edit of one entry's data: fn(data) changes the copy; nil, err to refuse.
local function edit(store, id, expected, fn)
    local e = store:Get(id)
    if not e or e.deleted or e.kind ~= "profile" then return nil, "unknown-id" end
    local data = copy(e.data)
    local ok, why = fn(data)
    if ok == false then return nil, why end
    return store:Edit(id, expected, data)
end

function Profiles.SetActive(store, id, expected, now)
    local at = nextActiveAt(store, (id:match("^([^:]+:[^:]+:)") or id), now)
    return edit(store, id, expected, function(d) d.activeAt = at end)
end

Profiles.MAX_NAME = 24

function Profiles.Rename(store, id, expected, name, now)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then return nil, "EMPTY_NAME" end
    if name:find('"', 1, true) then return nil, "BAD_NAME" end
    if #name > Profiles.MAX_NAME then name = name:sub(1, Profiles.MAX_NAME) end
    return edit(store, id, expected, function(d)
        if d.name == name then return false, "UNCHANGED" end
        d.name, d.source, d.updatedAt = name, "manual", now
    end)
end

-- A weight typed in the editor: "" or 0 removes it, "X" ignores the stat
-- (Pawn's "never an upgrade"), a number in range is rounded to 3 decimals
-- (half away from zero). Any editor change (weight, name, armor) makes the
-- profile "manual" (edited in Glass Gear); the origin (the imported scale's
-- name) stays.
function Profiles.ParseWeight(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return "clear" end
    if text == "X" or text == "x" then return "ignore" end
    text = text:gsub(",", ".")
    if not (text:match("^%-?%d+%.?%d*$") or text:match("^%-?%.%d+$")) then return nil, "NOT_A_NUMBER" end
    local n = tonumber(text)
    if not n or math.abs(n) > GG.PawnString.MAX_ABS then return nil, "VALUE_OUT_OF_RANGE" end
    local sign = n < 0 and -1 or 1
    n = sign * math.floor(math.abs(n) * 1000 + 0.5) / 1000
    if n == 0 then return "clear" end
    return "weight", n
end

function Profiles.SetWeight(store, id, expected, token, text, now)
    if not GG.Data.Stats.TOKENS[token] then return nil, "UNKNOWN_STAT" end
    local what, n = Profiles.ParseWeight(text)
    if not what then return nil, n end
    return edit(store, id, expected, function(d)
        d.weights = d.weights or {}
        d.ignored = d.ignored or {}
        local before = d.ignored[token] and "ignore" or d.weights[token]
        local after = what == "ignore" and "ignore" or (what == "weight" and n or nil)
        if before == after then return false, "UNCHANGED" end
        d.weights[token], d.ignored[token] = nil, nil
        if what == "weight" then d.weights[token] = n elseif what == "ignore" then d.ignored[token] = true end
        if next(d.ignored) == nil then d.ignored = nil end
        if d.missing then
            local keep = {}
            for _, t in ipairs(d.missing) do if t ~= token then keep[#keep + 1] = t end end
            d.missing = #keep > 0 and keep or nil
        end
        local n2 = 0
        for _ in pairs(d.weights) do n2 = n2 + 1 end
        if n2 == 0 then return false, "NO_WEIGHTS" end
        d.source, d.updatedAt = "manual", now
    end)
end

-- Armor types the profile allows (adr/0003, GG-118): a list of armor subclass
-- ids, or nil for the spec's default.
function Profiles.SetArmor(store, id, expected, armor, now)
    if armor ~= nil then
        if type(armor) ~= "table" or #armor == 0 then return nil, "NO_ARMOR" end
        for _, a in ipairs(armor) do
            if not GG.Data.Classes.ARMOR_NAME[a] then return nil, "UNKNOWN_ARMOR" end
        end
        armor = copy(armor)
        table.sort(armor)
    end
    return edit(store, id, expected, function(d)
        d.armor, d.source, d.updatedAt = armor, "manual", now
    end)
end

function Profiles.Delete(store, id, expected)
    local e = store:Get(id)
    if not e or e.deleted or e.kind ~= "profile" then return nil, "unknown-id" end
    return store:Delete(id, expected)
end

-- Tell the rest of Glass Gear: callbacks for API consumers, invalidation for
-- the cached answers (tooltips, arrows).
function Profiles.Changed(charKey)
    GG.Callbacks.Fire("ProfilesChanged", { charKeys = { charKey } })
    GG.API._Invalidate("profiles", { charKey })
end

return Profiles
