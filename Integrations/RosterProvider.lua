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
    out.reason = out.usable and nil or ("AltStable lacks " .. table.concat(out.missing, ", "))
    return out
end

RosterProvider.scans = 0     -- how often Characters was read (GG-114: never on a tooltip redraw)
RosterProvider.rebuilds = 0  -- how often the AltStable snapshot was rebuilt

local alts = {}              -- the player's own other characters, from AltStable
local counts = { self = 0, ownAccount = 0, thirdParty = 0 }
local attached, lastError = false, nil

local function as() return rawget(_G, "AltStable") end

-- A character in Glass Gear's shape, from AltStable's (a copy already).
local function fromAltStable(c)
    return { key = c.guid, guid = c.guid, name = c.name, realm = c.realm, faction = c.faction,
        class = c.class, level = c.level, provenance = c.provenance, provenanceAt = c.provenanceAt,
        provenanceVia = c.provenanceVia, account = c.account, lastUpdate = c.lastUpdate,
        hidden = c.hidden == true, current = false }
end

local function signature(list)
    local parts = {}
    for _, c in ipairs(list) do
        parts[#parts + 1] = table.concat({ c.guid, tostring(c.provenance), tostring(c.level),
            tostring(c.hidden), tostring(c.name), tostring(c.class) }, ",")
    end
    return table.concat(parts, ";")
end
local lastSignature

-- Rebuild the snapshot; returns true when the roster changed.
function RosterProvider.Refresh()
    local d = RosterProvider.DetectAltStable()
    local list, c3 = {}, { self = 0, ownAccount = 0, thirdParty = 0 }
    lastError = nil
    if d.usable then
        RosterProvider.rebuilds = RosterProvider.rebuilds + 1
        local ok, chars = pcall(as().GetCharacters)
        if not ok or type(chars) ~= "table" then
            lastError = "AltStable.GetCharacters failed"
            if not ok then geterrorhandler()("GlassGear roster: " .. tostring(chars)) end
            chars = {}
        end
        local me = GG.player and GG.player.key
        for _, c in ipairs(chars) do
            if type(c) == "table" and type(c.guid) == "string" then
                if c.provenance == "self" then c3.self = c3.self + 1
                elseif c.provenance == "own-account" then c3.ownAccount = c3.ownAccount + 1
                else c3.thirdParty = c3.thirdParty + 1 end
                if RosterProvider.OWN[c.provenance] and c.guid ~= me then list[#list + 1] = fromAltStable(c) end
            end
        end
    end
    alts, counts = list, c3
    local sig = signature(list)
    local changed = lastSignature ~= nil and sig ~= lastSignature
    lastSignature = sig
    if changed and GG.player then
        GG.Callbacks.Fire("RosterChanged")
        GG.API._Invalidate("roster", { GG.player.key })
    end
    return changed
end

-- At login (AltStable is an OptionalDep, so it loaded first): follow its
-- callbacks. Its data right after login may be last session's; a
-- CharactersChanged follows its rescan.
function RosterProvider.Attach()
    local d = RosterProvider.DetectAltStable()
    RosterProvider.Refresh()
    if not d.usable or attached then return d.usable, d.reason end
    local A = as()
    local function onRoster() RosterProvider.Refresh() end
    local ok = pcall(A.RegisterCallback, "CharactersChanged", onRoster)
    ok = pcall(A.RegisterCallback, "ProvenanceChanged", onRoster) and ok
    -- An alt's worn gear changed (its own scan or a sync): consumers re-read.
    ok = pcall(A.RegisterCallback, "GearChanged", function(_, guids)
        if type(guids) == "table" and #guids > 0 then
            GG.Callbacks.Fire("EquipmentChanged", { charKeys = guids })
        end
    end) and ok
    attached = ok
    if not ok then lastError = "AltStable callbacks unavailable" end
    return ok, lastError
end

function RosterProvider.Characters(player)
    RosterProvider.scans = RosterProvider.scans + 1
    local out = { player }
    for _, c in ipairs(alts) do out[#out + 1] = c end
    return out
end

function RosterProvider.Find(guid)
    if GG.player and guid == GG.player.key then return GG.player end
    for _, c in ipairs(alts) do if c.guid == guid then return c end end
end

-- { present, usable, missing, reason, own, self, ownAccount, thirdParty }
function RosterProvider.Status()
    local d = RosterProvider.DetectAltStable()
    d.reason = lastError or d.reason
    d.own = #alts
    d.self, d.ownAccount, d.thirdParty = counts.self, counts.ownAccount, counts.thirdParty
    return d
end

-- Test seam.
function RosterProvider._Reset() alts, counts, attached, lastError, lastSignature = {}, { self = 0, ownAccount = 0, thirdParty = 0 }, false, nil, nil end

return RosterProvider
