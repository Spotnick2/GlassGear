------------------------------------------------------------
-- Character/Spec.lua - current spec resolution (adr/0002).
--
-- Pure part: Spec.Resolve(specMap, activeGroup, auto) -> specKey | nil, reason.
-- The manual mapping always wins; automatic detection is off until probe
-- GG-101 measures it (Spec.AUTO_ENABLED).
------------------------------------------------------------

local GG = GlassGear
local Spec = {}
GG.Spec = Spec

Spec.AUTO_ENABLED = false

-- auto = { [treeIndex] = pointsSpent } for the active group, or nil.
function Spec.Resolve(classToken, specMap, activeGroup, auto)
    local mapped = specMap and activeGroup and specMap[activeGroup]
    if mapped then return mapped, "manual" end
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

return Spec
