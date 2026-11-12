------------------------------------------------------------
-- Init.lua - the one global namespace and build facts.
-- Every other file starts with `local GG = GlassGear`.
------------------------------------------------------------

GlassGear = GlassGear or {}
local GG = GlassGear

GG.NAME = "GlassGear"
-- The client build these files were checked against (API dump
-- References/Forever/api/forever-api-1.60.1.70888.md). Runtime behaviour is
-- unverified until docs/FOREVER-PROBE.md's checks pass.
GG.MEASURED_ON_BUILD = "70888"
GG.SCHEMA = 1

-- Sub-namespaces, filled by later files in TOC order.
GG.Data = GG.Data or {}
GG.Engine = GG.Engine or {}
GG.Integrations = GG.Integrations or {}

-- Small shared helpers (pure).
GG.Util = GG.Util or {}
local U = GG.Util

function U.deepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, x in pairs(v) do out[U.deepCopy(k, seen)] = U.deepCopy(x, seen) end
    return out
end

function U.contains(list, value)
    for _, x in ipairs(list) do if x == value then return true end end
    return false
end

return GG
