------------------------------------------------------------
-- Character/Baselines.lua - baseline source precedence and freshness
-- (adr/0003). Pure.
--
--   Baselines.Choose({ equipmentSet = b|nil, observed = b|nil, current = b|nil })
--     -> baseline (with .source) | nil
--   Baselines.Freshness(b, now, gearChangedAt) -> stale (bool), expiresAt
------------------------------------------------------------

local GG = GlassGear
local Baselines = {}
GG.Baselines = Baselines

Baselines.STALE_AFTER = 14 * 24 * 3600

function Baselines.Choose(sources)
    sources = sources or {}
    local order = {
        { sources.equipmentSet, "equipment-set" },
        { sources.observed, "observed" },
        { sources.current, "fallback-current" },
    }
    for _, o in ipairs(order) do
        local b = o[1]
        if b and b.slots then
            local copy = {}
            for k, v in pairs(b) do copy[k] = v end
            copy.source = o[2]
            local complete = true
            for _, slot in ipairs(GG.Data.Slots.GEAR) do
                local s = b.slots[slot]
                if not s or s.state == "unknown" then complete = false end
            end
            copy.complete = complete
            return copy
        end
    end
end

-- A baseline is stale after STALE_AFTER, or once the character's gear
-- changed after capture (gear-change stamp, never AltStable lastUpdate).
function Baselines.Freshness(b, now, gearChangedAt)
    if not b or not b.capturedAt then return true, now end
    local expiresAt = b.capturedAt + Baselines.STALE_AFTER
    if gearChangedAt and gearChangedAt > b.capturedAt then return true, gearChangedAt end
    return now >= expiresAt, expiresAt
end

return Baselines
