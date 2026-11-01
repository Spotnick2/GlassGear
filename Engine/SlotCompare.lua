------------------------------------------------------------
-- Engine/SlotCompare.lua - legal resulting configurations (adr/0003). Pure.
--
--   SlotCompare.Best(candidate, baseline, ctx) -> best, all
--
-- candidate = { itemID, equipLoc, score, unique = { key, max } | nil, setID }
-- baseline  = { [slot] = { state = "occupied"|"empty"|"unknown",
--                          itemID, equipLoc, score, unique, setID, itemString } }
--             Missing slots count as "unknown".
-- ctx       = { canDualWield = bool, companion = { [16|17] = item } | nil }
--
-- best = { state = "legal"|"unknown"|"illegal", slots = {..}, displaced = {items},
--          candScore, baseScore, delta, emptySlot = bool, reason }
-- The best legal configuration is the one with the largest delta (ties: the
-- lower slot). With no legal one: unknown if any was unknown, else illegal.
------------------------------------------------------------

local GG = GlassGear
local Slots = GG.Data.Slots
local SlotCompare = {}
GG.Engine.SlotCompare = SlotCompare

local MH, OH = Slots.MAIN_HAND, Slots.OFF_HAND

local function slotOf(baseline, s)
    return baseline[s] or { state = "unknown" }
end

local function isTwoHand(item)
    return item and Slots.TWO_HAND[item.equipLoc or ""] == true
end

-- May `item` go in hand slot `s`? Off-hand weapons need dual wield.
local MH_OK = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local OH_OK = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }
local OH_WEAPON = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }
function SlotCompare.HandLegal(item, s, canDualWield)
    local loc = item and item.equipLoc or ""
    if s == MH then return MH_OK[loc] == true end
    if s == OH then return OH_OK[loc] == true or (OH_WEAPON[loc] == true and canDualWield == true) end
    return false
end

-- Count unique keys over the resulting set of items; true when within limits.
local function uniqueOk(items)
    local counts, limits = {}, {}
    for _, it in ipairs(items) do
        local u = it.unique
        if u and u.key then
            counts[u.key] = (counts[u.key] or 0) + 1
            limits[u.key] = math.min(limits[u.key] or math.huge, u.max or 1)
        end
    end
    for key, n in pairs(counts) do
        if n > limits[key] then return false, key end
    end
    return true
end

-- Build one configuration: the candidate in slot `s`.
local function configure(candidate, baseline, s, ctx)
    local cfg = { slots = { s }, displaced = {}, candScore = candidate.score or 0 }
    local placed = { [s] = candidate }
    local mh = slotOf(baseline, MH)

    if isTwoHand(candidate) then
        -- A 2H displaces main hand and off hand together.
        cfg.slots = { MH, OH }
        for _, hs in ipairs({ MH, OH }) do
            local cur = slotOf(baseline, hs)
            if cur.state == "unknown" then return nil, "unknown", "BASELINE_SLOT_UNKNOWN" end
            if cur.state == "occupied" and not (hs == OH and isTwoHand(mh)) then
                cfg.displaced[#cfg.displaced + 1] = cur
            end
        end
        placed[OH] = false
    elseif (s == MH or s == OH) and mh.state == "occupied" and isTwoHand(mh) then
        -- 1H/MH/OH while a 2H is equipped: legal only with an identified companion.
        local other = (s == MH) and OH or MH
        local comp = ctx.companion and ctx.companion[other]
        if not comp then return nil, "unknown", "NEEDS_COMPANION" end
        if not SlotCompare.HandLegal(comp, other, ctx.canDualWield) then
            return nil, "illegal", "COMPANION_NOT_LEGAL"
        end
        if type(comp.score) ~= "number" then return nil, "unknown", "COMPANION_DATA_MISSING" end
        cfg.slots = { MH, OH }
        cfg.displaced[1] = mh
        cfg.candScore = cfg.candScore + (comp.score or 0)
        cfg.companion = comp
        placed[other] = comp
    else
        local cur = slotOf(baseline, s)
        if cur.state == "unknown" then return nil, "unknown", "BASELINE_SLOT_UNKNOWN" end
        if cur.state == "occupied" then cfg.displaced[1] = cur else cfg.emptySlot = true end
    end

    -- The resulting item set: every baseline item not displaced, plus placed ones.
    local result = {}
    for _, gs in ipairs(Slots.GEAR) do
        local p = placed[gs]
        if p then
            result[#result + 1] = p
        elseif p == nil then
            local cur = baseline[gs]
            local displaced = false
            for _, d in ipairs(cfg.displaced) do if d == cur then displaced = true end end
            if cur and cur.state == "occupied" and not displaced then result[#result + 1] = cur end
        end
    end
    local ok, key = uniqueOk(result)
    if not ok then return nil, "illegal", "UNIQUE_EQUIPPED", key end

    cfg.baseScore = 0
    for _, d in ipairs(cfg.displaced) do cfg.baseScore = cfg.baseScore + (d.score or 0) end
    cfg.delta = cfg.candScore - cfg.baseScore
    cfg.result = result
    cfg.state = "legal"
    return cfg
end

function SlotCompare.Best(candidate, baseline, ctx)
    ctx = ctx or {}
    baseline = baseline or {}
    local slots = Slots.FOR_EQUIP_LOC[candidate.equipLoc or ""]
    if not slots then
        return { state = "illegal", reason = "NOT_EQUIPPABLE" }, {}
    end
    local all, best, sawUnknown, unknownReason, illegalReason = {}, nil, false, nil, nil
    for _, s in ipairs(slots) do
        local allowed = (s ~= MH and s ~= OH) or isTwoHand(candidate)
            or SlotCompare.HandLegal(candidate, s, ctx.canDualWield)
        if allowed then
            local cfg, state, reason = configure(candidate, baseline, s, ctx)
            if cfg then
                all[#all + 1] = cfg
                if not best or cfg.delta > best.delta then best = cfg end
            elseif state == "unknown" then
                sawUnknown, unknownReason = true, unknownReason or reason
            else
                illegalReason = illegalReason or reason
            end
        end
    end
    if best then return best, all end
    if sawUnknown then return { state = "unknown", reason = unknownReason }, all end
    return { state = "illegal", reason = illegalReason or "NO_LEGAL_SLOT" }, all
end

return SlotCompare
