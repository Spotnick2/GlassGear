------------------------------------------------------------
-- Engine/SetBonus.lua - set-bonus thresholds gained or lost (adr/0003 rule 7,
-- GG-119). Pure. Thresholds come from Data.ItemSets (generated from the
-- client's ItemSet/ItemSetSpell tables); a set without data is "unknown".
--
--   SetBonus.Diff(baselineItems, resultItems, thresholds)
--     -> { gained = { {setID, pieces} }, lost = { {setID, pieces} }, unknownSets = {setID} }
------------------------------------------------------------

local GG = GlassGear
local SetBonus = {}
GG.Engine.SetBonus = SetBonus

local function counts(items)
    local c = {}
    for _, it in ipairs(items or {}) do
        if it.setID then c[it.setID] = (c[it.setID] or 0) + 1 end
    end
    return c
end

function SetBonus.Diff(baselineItems, resultItems, thresholds)
    thresholds = thresholds or {}
    local before, after = counts(baselineItems), counts(resultItems)
    local out = { gained = {}, lost = {}, unknownSets = {} }
    local seen = {}
    for setID in pairs(before) do seen[setID] = true end
    for setID in pairs(after) do seen[setID] = true end
    local ids = {}
    for setID in pairs(seen) do ids[#ids + 1] = setID end
    table.sort(ids)
    for _, setID in ipairs(ids) do
        local t = thresholds[setID]
        local b, a = before[setID] or 0, after[setID] or 0
        if not t then
            if a ~= b then out.unknownSets[#out.unknownSets + 1] = setID end
        else
            for _, pieces in ipairs(t) do
                if b < pieces and a >= pieces then out.gained[#out.gained + 1] = { setID = setID, pieces = pieces } end
                if b >= pieces and a < pieces then out.lost[#out.lost + 1] = { setID = setID, pieces = pieces } end
            end
        end
    end
    return out
end

return SetBonus
