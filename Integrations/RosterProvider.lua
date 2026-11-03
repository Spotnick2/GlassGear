------------------------------------------------------------
-- Integrations/RosterProvider.lua - who Glass Gear can evaluate (adr/0001).
--
-- The local provider (current character) always exists. The AltStable
-- provider needs AS-001 (provenance + own-account channel, AltStable #282) and
-- AS-003 (gear read API, AltStable #283 @1b35918). Each is detected by its
-- feature flag in AltStable.PUBLIC_API_FEATURES (PUBLIC_API_VERSION stays 1;
-- AltStable docs/PUBLIC-API.md) and its function, and what is missing is
-- reported. Alt rows themselves wait for GG-201/GG-203. Profile/baseline sync is not
-- AltStable's: it goes through the shared entry-sync library (adr/0001).
-- Glass Gear never reads AltStableDB (AltStable docs/PUBLIC-API.md:4-5).
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

-- Characters Glass Gear may evaluate. M0: the current character only.
function RosterProvider.Characters(player)
    return { player }
end

return RosterProvider
