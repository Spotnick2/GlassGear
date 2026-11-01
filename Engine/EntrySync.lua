------------------------------------------------------------
-- Engine/EntrySync.lua - the per-entry sync model of adr/0001. Pure and
-- transport-agnostic: M0 tests it with a simulated transport; M2 maps
-- AltStable's entry-sync service (AS-002) onto it.
--
-- A port of AltStableSync's catalog rules (Catalog.lua Upsert / Retire /
-- RetireCovered / Resolve, docs/DESIGN.md:913-973, MIT, same author), adapted
-- to Glass Gear entries ({ id, kind, version, ancestors, deleted, conflict,
-- provenance, data }).
--
--   local store = EntrySync.New(entriesTable, writerToken)
--   store:Create(id, kind, data)              -> entry
--   store:Edit(id, expectedVersion, data)     -> entry | nil, "stale"|...
--   store:Delete(id, expectedVersion)         -> entry | nil, err
--   store:Receive(incoming, fromLabel)        -> "ignore"|"replace"|"conflict" | nil, "bad-entry"
--   store:Resolve(copyId, choice, expectedRootVersion, newId) -> root, created | nil, err
--   store:Wants(id, version) / store:Manifest(prefix)
--   EntrySync.MaybeBehind(store, peerManifest, prefix) -> bool
------------------------------------------------------------

local GG = GlassGear
local EntrySync = {}
GG.Engine.EntrySync = EntrySync

EntrySync.MAX_ANCESTORS = 20

local function contains(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

-- `firsts` in order, then each list, without duplicates, capped.
local function ancestorList(firsts, ...)
    local out, seen = {}, {}
    local function add(v)
        if type(v) == "string" and not seen[v] and #out < EntrySync.MAX_ANCESTORS then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    for _, v in ipairs(firsts) do add(v) end
    for i = 1, select("#", ...) do
        for _, v in ipairs(select(i, ...) or {}) do add(v) end
    end
    return out
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

local function copyId(id, version) return id .. "~" .. version end

-- Every field checked before anything is stored (adr/0001: a malformed entry
-- is rejected whole). Data validation is Codec.ValidData (per kind).
local function validIncoming(e)
    if type(e) ~= "table" then return false end
    if type(e.id) ~= "string" or e.id == "" or type(e.version) ~= "string" or e.version == "" then return false end
    if e.kind ~= "profile" and e.kind ~= "baseline" then return false end
    if e.deleted ~= nil and e.deleted ~= true then return false end
    if e.ancestors ~= nil then
        if type(e.ancestors) ~= "table" then return false end
        for _, v in ipairs(e.ancestors) do if type(v) ~= "string" then return false end end
    end
    if e.conflict ~= nil then
        if type(e.conflict) ~= "table" or type(e.conflict.of) ~= "string" then return false end
        local c = e.conflict
        if (c.deletion ~= nil and c.deletion ~= true) or (c.retired ~= nil and c.retired ~= true)
            or (c.from ~= nil and type(c.from) ~= "string") then return false end
        -- A copy's id is its root's id + "~" + a version.
        if e.id:sub(1, #e.conflict.of + 1) ~= e.conflict.of .. "~" then return false end
    end
    local contentless = e.deleted or (e.conflict and e.conflict.deletion)
    if contentless then return e.data == nil end
    return (GG.Engine.Codec.ValidData(e.kind, e.data))
end

local function sanitize(e)
    return {
        id = e.id, kind = e.kind, version = e.version, parent = e.parent,
        ancestors = ancestorList({}, e.ancestors),
        deleted = e.deleted and true or nil,
        conflict = e.conflict and copy(e.conflict) or nil,
        provenance = e.provenance,
        data = (not e.deleted) and copy(e.data) or nil,
    }
end

local Store = {}
Store.__index = Store

-- `writer` must be fresh per session (adr/0001): never persisted, so a
-- restored SavedVariables can't reuse a version.
function EntrySync.New(entries, writer)
    assert(type(writer) == "string" and writer ~= "", "writer token required")
    return setmetatable({ entries = entries or {}, writer = writer, seq = 0, wrote = {} }, Store)
end

function Store:mint()
    self.seq = self.seq + 1
    return self.writer .. ":" .. self.seq
end

function Store:advance(e, extra)
    local v = self:mint()
    e.parent = e.version
    e.ancestors = ancestorList({ e.version }, extra, e.ancestors)
    e.version = v
    return e
end

function Store:Get(id) return self.entries[id] end

function Store:Create(id, kind, data, provenance)
    if self.entries[id] then return nil, "exists" end
    local ok, why = GG.Engine.Codec.ValidData(kind, data)
    if not ok then return nil, "bad-data:" .. tostring(why) end
    local e = { id = id, kind = kind, version = self:mint(), ancestors = {}, data = copy(data),
        provenance = provenance or "self" }
    self.entries[id] = e
    self.wrote[#self.wrote + 1] = id
    return e
end

function Store:editable(id, expected)
    local e = self.entries[id]
    if not e then return nil, "unknown-id" end
    if e.deleted then return nil, "deleted" end
    if e.conflict then return nil, "conflict-copy" end
    if e.version ~= expected then return nil, "stale" end
    return e
end

function Store:Edit(id, expected, data)
    local e, err = self:editable(id, expected)
    if not e then return nil, err end
    local ok, why = GG.Engine.Codec.ValidData(e.kind, data)
    if not ok then return nil, "bad-data:" .. tostring(why) end
    self:advance(e)
    e.data = copy(data)
    self.wrote[#self.wrote + 1] = id
    return e
end

function Store:Delete(id, expected)
    local e, err = self:editable(id, expected)
    if not e then return nil, err end
    self:advance(e)
    e.deleted, e.data = true, nil
    self.wrote[#self.wrote + 1] = id
    return e
end

-- Would receiving `id` at `version` change anything here?
function Store:Wants(id, version)
    local e = self.entries[id]
    if not e then return true end
    if e.version == version or contains(e.ancestors, version) then return false end
    if self.entries[copyId(id, version)] then return false end
    return true
end

function Store:retire(cid)
    local c = self.entries[cid]
    if not c or c.deleted then return end
    self:advance(c)
    c.deleted, c.data = true, nil
    c.conflict.retired = true
end

-- The one receive-side mint (adr/0001): retire covered conflict copies.
function Store:retireCovered(rootId)
    local root = self.entries[rootId]
    if not root then return end
    for cid, c in pairs(self.entries) do
        if type(c.conflict) == "table" and c.conflict.of == rootId and not c.deleted
            and (c.version == root.version or contains(root.ancestors, c.version)) then
            self:retire(cid)
        end
    end
end

function Store:Receive(incoming, fromLabel)
    if not validIncoming(incoming) then return nil, "bad-entry" end
    local id = incoming.id
    local mine = self.entries[id]
    if mine and mine.kind ~= incoming.kind then return nil, "bad-entry" end

    if type(incoming.conflict) == "table" then
        local root = self.entries[incoming.conflict.of]
        -- A copy keeps its root's identity (AltStableSync SameIdentity).
        if root and root.kind ~= incoming.kind then return nil, "bad-entry" end
        if root and not incoming.deleted
            and (root.version == incoming.version or contains(root.ancestors, incoming.version)) then
            return "ignore"
        end
    end
    if not mine then
        self.entries[id] = sanitize(incoming)
        return "replace"
    end
    if mine.version == incoming.version then return "ignore" end
    if contains(mine.ancestors, incoming.version) then return "ignore" end
    if contains(incoming.ancestors, mine.version) then
        self.entries[id] = sanitize(incoming)
        self:retireCovered(id)
        return "replace"
    end
    if mine.deleted and incoming.deleted then
        if incoming.version > mine.version then
            self.entries[id] = sanitize(incoming)
            return "replace"
        end
        return "ignore"
    end
    local cid = copyId(id, incoming.version)
    if self.entries[cid] then return "ignore" end
    local c = sanitize(incoming)
    c.id = cid
    c.conflict = { of = id, from = fromLabel, deletion = incoming.deleted and true or nil }
    c.deleted = nil
    if c.conflict.deletion then c.data = nil end
    self.entries[cid] = c
    return "conflict"
end

-- choice: "theirs" | "mine" | "delete" (only when the other side deleted).
-- `newId` names the new entry for "theirs" over a deleted root.
function Store:Resolve(cid, choice, expectedRoot, newId)
    local c = self.entries[cid]
    if not c or not c.conflict or c.deleted then return nil, "not-conflict" end
    local root = self.entries[c.conflict.of]
    if not root then return nil, "unknown-id" end
    if root.version ~= expectedRoot then return nil, "stale" end
    -- A copy of another kind never gives its content to the root; "mine" still settles it.
    if choice ~= "mine" and c.kind ~= root.kind then return nil, "bad-copy" end
    if choice == "theirs" and not c.conflict.deletion and not GG.Engine.Codec.ValidData(root.kind, c.data) then
        return nil, "bad-copy"
    end
    local both = ancestorList({ root.version, c.version }, c.ancestors)
    local deletedThere = c.conflict.deletion
    local created
    if root.deleted then
        if deletedThere then choice = "mine" end
        if choice == "theirs" then
            if type(newId) ~= "string" or self.entries[newId] then return nil, "bad-new-id" end
            created = self:Create(newId, root.kind, c.data, "self")
        elseif choice ~= "mine" then
            return nil, "bad-choice"
        end
        self:advance(root, both)
    elseif deletedThere then
        if choice == "delete" then
            self:advance(root, both)
            root.deleted, root.data = true, nil
        elseif choice == "mine" then
            self:advance(root, both)
        else
            return nil, "bad-choice"
        end
    else
        if choice == "theirs" then
            self:advance(root, both)
            root.data = copy(c.data)
        elseif choice == "mine" then
            self:advance(root, both)
        else
            return nil, "bad-choice"
        end
    end
    self:retireCovered(root.id)
    self.wrote[#self.wrote + 1] = root.id
    return root, created
end

-- { [id] = version } for every entry whose id starts with `prefix` (or all):
-- live entries, tombstones and conflict copies alike.
function Store:Manifest(prefix)
    local m = {}
    for id, e in pairs(self.entries) do
        if not prefix or id:sub(1, #prefix) == prefix then m[id] = e.version end
    end
    return m
end

-- True while the peer lists a version of a matching entry this store would
-- still take: our copy of that character may be behind (adr/0001 inventory).
function EntrySync.MaybeBehind(store, peerManifest, prefix)
    for id, version in pairs(peerManifest or {}) do
        if (not prefix or id:sub(1, #prefix) == prefix) and store:Wants(id, version) then
            return true
        end
    end
    return false
end

-- The ids this store should pull from a peer manifest (deterministic order).
function EntrySync.ToPull(store, peerManifest)
    local out = {}
    for id, version in pairs(peerManifest or {}) do
        if store:Wants(id, version) then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

return EntrySync
