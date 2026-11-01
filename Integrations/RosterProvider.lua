------------------------------------------------------------
-- Integrations/RosterProvider.lua - who Glass Gear can evaluate (adr/0001).
--
-- The local provider (current character) always exists. The AltStable
-- provider needs AltStable extensions that do not exist yet (AS-001 own-account
-- channel + provenance, AS-002 entry-sync service, AS-003 gear read API), so
-- it reports exactly what is missing and alt features stay unavailable.
-- Glass Gear never reads AltStableDB (AltStable docs/PUBLIC-API.md:4-5).
------------------------------------------------------------

local GG = GlassGear
local RosterProvider = {}
GG.Integrations.RosterProvider = RosterProvider

-- The AltStable functions each extension would add (proposed names, see
-- docs/INTEGRATION-GAPS.md); detection is by type, under rawget.
RosterProvider.ALTSTABLE_NEEDS = {
    { id = "AS-001", fn = "GetCharacterProvenance" },
    { id = "AS-002", fn = "RegisterEntrySync" },
    { id = "AS-003", fn = "GetCharacterGear" },
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
    for _, need in ipairs(RosterProvider.ALTSTABLE_NEEDS) do
        if type(rawget(as, need.fn)) ~= "function" then out.missing[#out.missing + 1] = need.id end
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
