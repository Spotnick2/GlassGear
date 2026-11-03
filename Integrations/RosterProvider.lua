------------------------------------------------------------
-- Integrations/RosterProvider.lua - who Glass Gear can evaluate (adr/0001).
--
-- The local provider (current character) always exists. The AltStable
-- provider (GG-201) needs AS-001 (provenance + own-account channel, AltStable
-- #282) and AS-003 (gear read API, AltStable #283 @1b35918). Each is detected
-- by its feature flag in AltStable.PUBLIC_API_FEATURES (PUBLIC_API_VERSION
-- stays 1; AltStable docs/PUBLIC-API.md) and its function, and what is
-- missing is reported. Profile/baseline sync is not AltStable's: it goes
-- through the shared entry-sync library (adr/0001). Glass Gear never reads
-- AltStableDB (AltStable docs/PUBLIC-API.md:4-5).
--
--   RosterProvider.Attach()        at login: follow AltStable's callbacks
--   RosterProvider.Characters(p)   the current character, then the player's
--                                  own other characters (a cached snapshot)
--   RosterProvider.Find(guid)      one of them, or nil
--   RosterProvider.Status()        what /gg and the API report
--
-- Ownership is AltStable's provenance, never the `account` label: only
-- "self" (scanned on this WoW account) and "own-account" (a proven own
-- account said so first-hand) are listed. "third-party" never is.
-- The snapshot is rebuilt on CharactersChanged / ProvenanceChanged, never
-- on a tooltip redraw.
------------------------------------------------------------

local GG = GlassGear
local RosterProvider = {}
GG.Integrations.RosterProvider = RosterProvider

-- Each extension: its feature flag and a function it adds; both must be there.
-- An older AltStable has no flags table, or no flag: "not available".
RosterProvider.ALTSTABLE_NEEDS = {
    { id = "AS-001", flag = "provenance", fn = "GetCharacterProvenance" },
    { id = "AS-003", flag = "gear", fn = "GetCharacterGear" },
}
RosterProvider.OWN = { self = true, ["own-account"] = true }

-- Returns { present, apiVersion, usable, missing = {ids}, reason }.
function RosterProvider.DetectAltStable(env)
    env = env or _G
    local as = rawget(env, "AltStable")
    if type(as) ~= "table" then
        return { present = false, usable = false, missing = {}, reason = "AltStable not loaded" }
    end
    local version = rawget(as, "PUBLIC_API_VERSION")
    local out = { present = true, apiVersion = version, missing = {}, usable = false }
    if type(version) ~= "number" or version < 1 then
        out.reason = "AltStable public API not found"
        return out
    end
    local flags = rawget(as, "PUBLIC_API_FEATURES")
    for _, need in ipairs(RosterProvider.ALTSTABLE_NEEDS) do
        local flagged = type(flags) == "table" and flags[need.flag] == true
        if not flagged or type(rawget(as, need.fn)) ~= "function" then out.missing[#out.missing + 1] = need.id end
    end
    out.usable = #out.missing == 0
    -- (not `usable and nil or ...`: that always yields the second branch)
    if not out.usable then out.reason = "AltStable lacks " .. table.concat(out.missing, ", ") end
    return out
end

RosterProvider.scans = 0     -- how often Characters was read (GG-114: never on a tooltip redraw)
RosterProvider.rebuilds = 0  -- how often the AltStable snapshot was rebuilt

local alts = {}              -- the player's own other characters, from AltStable
local counts = { self = 0, ownAccount = 0, thirdParty = 0 }   -- never counting the current one
local registered = {}        -- [event] = true once AltStable took our handler
local attachError, fetchError = nil, nil

local function as() return rawget(_G, "AltStable") end

-- A character in Glass Gear's shape, from AltStable's (a copy already).
local function fromAltStable(c)
    return { key = c.guid, guid = c.guid, name = c.name, realm = c.realm, faction = c.faction,
        class = c.class, level = c.level, provenance = c.provenance, provenanceAt = c.provenanceAt,
        provenanceVia = c.provenanceVia, account = c.account, lastUpdate = c.lastUpdate,
        hidden = c.hidden == true, current = false }
end

-- Every field GetCharacters returns that a page shows: a change in any of
-- them is a roster change.
local function signature(list)
    local parts = {}
    for _, c in ipairs(list) do
        parts[#parts + 1] = table.concat({ c.guid, tostring(c.provenance), tostring(c.provenanceVia),
            tostring(c.level), tostring(c.hidden), tostring(c.name), tostring(c.class), tostring(c.realm),
            tostring(c.faction), tostring(c.account) }, ",")
    end
    return table.concat(parts, ";")
end
local lastSignature

-- Rebuild the snapshot; returns true when the roster changed.
function RosterProvider.Refresh()
    local d = RosterProvider.DetectAltStable()
    local list, c3 = {}, { self = 0, ownAccount = 0, thirdParty = 0 }
    fetchError = nil
    if d.usable then
        RosterProvider.rebuilds = RosterProvider.rebuilds + 1
        local ok, chars = pcall(as().GetCharacters)
        if not ok or type(chars) ~= "table" then
            fetchError = "AltStable.GetCharacters failed"
            if not ok then geterrorhandler()("GlassGear roster: " .. tostring(chars)) end
            chars = {}
        end
        local me = GG.player and GG.player.key
        for _, c in ipairs(chars) do
            if type(c) == "table" and type(c.guid) == "string" and c.guid ~= me then
                if c.provenance == "self" then c3.self = c3.self + 1
                elseif c.provenance == "own-account" then c3.ownAccount = c3.ownAccount + 1
                else c3.thirdParty = c3.thirdParty + 1 end
                if RosterProvider.OWN[c.provenance] then list[#list + 1] = fromAltStable(c) end
            end
        end
    end
    alts, counts = list, c3
    local sig = signature(list)
    local changed = lastSignature ~= nil and sig ~= lastSignature
    lastSignature = sig
    -- No invalidation: no answer depends on the alts yet (features.alts is
    -- false; alt rows are GG-203, which invalidates for its own charKeys).
    if changed and GG.player then GG.Callbacks.Fire("RosterChanged") end
    return changed
end

-- At login (AltStable is an OptionalDep, so it loaded first): follow its
-- callbacks. Its data right after login may be last session's; a
-- CharactersChanged follows its rescan.
local function onRoster() RosterProvider.Refresh() end

-- An own alt's worn gear changed (its own scan or a sync): consumers re-read.
-- Only own alts are named: never a third-party character, and never the
-- current one (Glass Gear reports its own gear changes).
local function onGear(_, guids)
    if type(guids) ~= "table" then return end
    local me = GG.player and GG.player.key
    local keys = {}
    for _, guid in ipairs(guids) do
        if guid ~= me and RosterProvider.Find(guid) then keys[#keys + 1] = guid end
    end
    if #keys > 0 then GG.Callbacks.Fire("EquipmentChanged", { charKeys = keys }) end
end

local HANDLERS = { CharactersChanged = onRoster, ProvenanceChanged = onRoster, GearChanged = onGear }
local EVENTS = { "CharactersChanged", "ProvenanceChanged", "GearChanged" }

function RosterProvider.Attach()
    local d = RosterProvider.DetectAltStable()
    RosterProvider.Refresh()
    if not d.usable then return false, d.reason end
    local A = as()
    attachError = nil
    -- Each handler once: a retry registers only what is missing.
    for _, event in ipairs(EVENTS) do
        if not registered[event] then
            if pcall(A.RegisterCallback, event, HANDLERS[event]) then
                registered[event] = true
            else
                attachError = "AltStable callbacks unavailable (" .. event .. ")"
            end
        end
    end
    return attachError == nil, attachError
end

function RosterProvider.Characters(player)
    RosterProvider.scans = RosterProvider.scans + 1
    local out = { player }
    for _, c in ipairs(alts) do out[#out + 1] = c end
    return out
end

-- An own character's recorded gear from AltStable (AS-003): { capturedAt,
-- gearAt, slots } or nil. Never a third-party character's.
function RosterProvider.Gear(guid, usable)
    local c = RosterProvider.Find(guid)
    if not c or c == GG.player then return nil end
    local A = as()
    -- `usable`: the caller already checked once for many characters.
    if usable == nil then usable = RosterProvider.DetectAltStable().usable end
    if not (A and usable) then return nil end
    local ok, gear = pcall(A.GetCharacterGear, guid)
    if ok and type(gear) == "table" then return gear end
end

-- AltStable's own window (pairing and sync stay there, GG-204). OpenSheet
-- only ever opens; ToggleSheet would close a sheet already open.
-- Returns true | false, reason.
function RosterProvider.OpenAltStable()
    local A = as()
    local fn = A and (rawget(A, "OpenSheet") or rawget(A, "ToggleSheet"))
    if type(fn) ~= "function" then return false, "AltStable has no sheet to open" end
    local ok, err = pcall(fn)
    if not ok then
        geterrorhandler()("GlassGear: opening AltStable: " .. tostring(err))
        return false, "AltStable failed to open"
    end
    return true
end

function RosterProvider.CanOpenAltStable()
    local A = as()
    return A ~= nil and type(rawget(A, "OpenSheet") or rawget(A, "ToggleSheet")) == "function"
end

function RosterProvider.Find(guid)
    if GG.player and guid == GG.player.key then return GG.player end
    for _, c in ipairs(alts) do if c.guid == guid then return c end end
end

-- { present, usable, missing, reason, own, self, ownAccount, thirdParty }
function RosterProvider.Status()
    local d = RosterProvider.DetectAltStable()
    d.reason = fetchError or attachError or d.reason
    d.own = #alts
    d.self, d.ownAccount, d.thirdParty = counts.self, counts.ownAccount, counts.thirdParty
    return d
end

-- Test seam.
function RosterProvider._Reset()
    alts, counts, lastSignature = {}, { self = 0, ownAccount = 0, thirdParty = 0 }, nil
    registered, attachError, fetchError = {}, nil, nil
end

return RosterProvider
