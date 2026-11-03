------------------------------------------------------------
-- Character/Spec.lua - current spec resolution (adr/0002).
--
-- Pure part: Spec.Resolve(classToken, specMap, activeGroup, auto)
--   -> specKey, "manual"|"auto" | nil, "unknown-spec"|"invalid-mapping".
-- Spec.Map(group, specKey|nil) is the one place a mapping is changed (the
-- settings page and /gg spec, GG-104): saved per character, then the current
-- spec is resolved again and every cached answer invalidated.
-- The manual mapping always wins; automatic detection is off until probe
-- GG-101 measures it (Spec.AUTO_ENABLED). A mapping is only ever honoured for
-- a spec of the character's own class and a real spec group.
------------------------------------------------------------

local GG = GlassGear
local Spec = {}
GG.Spec = Spec

Spec.AUTO_ENABLED = false
Spec.MAX_GROUPS = 2   -- primary + dual spec (docs/SCHEMA.md specMap)

-- Is `group` -> `specKey` a mapping this class may hold? -> true | false, reason
function Spec.ValidMapping(classToken, group, specKey)
    if type(group) ~= "number" or group ~= math.floor(group) or group < 1 or group > Spec.MAX_GROUPS then
        return false, "bad-group"
    end
    local s = type(specKey) == "string" and GG.Data.Classes.Spec(specKey)
    if not s or specKey:match("^([%u_]+)%.") ~= classToken then return false, "not-this-class" end
    return true
end

-- auto = { [treeIndex] = pointsSpent } for the active group, or nil.
function Spec.Resolve(classToken, specMap, activeGroup, auto)
    local mapped = specMap and activeGroup and specMap[activeGroup]
    if mapped ~= nil then
        -- A saved mapping that isn't valid for this class (edited or copied
        -- SavedVariables) is reported, never used.
        if not Spec.ValidMapping(classToken, activeGroup, mapped) then return nil, "invalid-mapping" end
        return mapped, "manual"
    end
    if Spec.AUTO_ENABLED and auto then
        local specs = GG.Data.Classes.Specs(classToken)
        local best, bestPoints, tie = nil, 0, false
        for i, s in ipairs(specs) do
            local p = auto[i] or 0
            if p > bestPoints then best, bestPoints, tie = s.key, p, false
            elseif p == bestPoints and p > 0 then tie = true end
        end
        if best and not tie and not best:find("FERAL") then return best, "auto" end
    end
    return nil, "unknown-spec"
end

-- Map a spec group to one of the character's specs, or clear it (nil).
-- Returns true | false, "read-only"|"not-ready"|"bad-group"|"not-this-class".
function Spec.Map(group, specKey)
    if GG.readOnly then return false, "read-only" end
    if not (GG.player and GG.charDB) then return false, "not-ready" end
    if specKey == nil then
        if type(group) ~= "number" or group < 1 or group > Spec.MAX_GROUPS or group ~= math.floor(group) then
            return false, "bad-group"
        end
    else
        local ok, why = Spec.ValidMapping(GG.player.class, group, specKey)
        if not ok then return false, why end
    end
    if GG.charDB.specMap[group] == specKey then return true end
    GG.charDB.specMap[group] = specKey
    GG.ResolveSpec()
    GG.API._Invalidate("spec", { GG.player.key })
    if GG.Capture then GG.Capture.Request() end
    return true
end

return Spec
