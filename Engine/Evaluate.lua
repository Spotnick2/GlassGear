------------------------------------------------------------
-- Engine/Evaluate.lua - one (item, character, spec) evaluation (adr/0003). Pure.
--
--   Evaluate.One(input) -> result   (the per-result shape of docs/API.md)
--
-- input = {
--   item      = { ready, itemID, itemString, equipLoc, classID, subclassID,
--                 reqLevel, setID, hasSpell, unique = {key,max}, tokens, unsupported },
--   recipient = { key, name, realm, provenance, class, level, knownArmor, canDualWield },
--   spec      = "PRIEST.HOLY", current = bool,
--   profile   = { id, weights, ignored, source, version, updatedAt, armor = {subclass,...} } | nil,
--   baseline  = { source, capturedAt, complete, stale, maybeBehind,
--                 slots = { [slot] = { state, itemID, itemString, equipLoc, tokens, unique, setID } } } | nil,
--   settings  = { threshold = 0.005, levelWindow = { enabled = true, lookAhead = 0 }, specArmor = true },
--   companion = { [16|17] = baseline-shaped item } | nil,
--   setThresholds = Data.ItemSets,
-- }
------------------------------------------------------------

local GG = GlassGear
local Score = GG.Engine.Score
local SlotCompare = GG.Engine.SlotCompare
local SetBonus = GG.Engine.SetBonus
local Classes = GG.Data.Classes
local Stats = GG.Data.Stats
local Evaluate = {}
GG.Engine.Evaluate = Evaluate

Evaluate.DEFAULT_SETTINGS = {
    threshold = 0.005,
    levelWindow = { enabled = true, lookAhead = 0 },
    specArmor = true,
}

-- Body-armor types the spec rule applies to (not cloaks, jewellery, shields, relics).
local BODY_ARMOR = { [1] = true, [2] = true, [3] = true, [4] = true }

local function newResult(input)
    local r = input.recipient or {}
    local p = input.profile
    return {
        status = "unknown",
        character = { key = r.key, name = r.name, realm = r.realm, provenance = r.provenance },
        spec = input.spec,
        current = input.current == true,
        profile = p and { id = p.id, source = p.source, version = p.version, updatedAt = p.updatedAt } or nil,
        candidate = { itemString = input.item and input.item.itemString, instance = input.instance },
        baseline = nil,
        replaces = nil,
        score = nil,
        method = "weights-linear",
        eligibility = { equipNow = true, reasons = {} },
        transfer = input.transfer or { state = "unknown", reasons = {} },
        reasons = {},
        limitations = {},
    }
end

local function add(list, v) list[#list + 1] = v end

-- Class gate, spec armor rule and level window. Returns a terminal status or nil.
local function eligibility(input, res)
    local item, r, s = input.item, input.recipient or {}, input.settings
    local ok, why, learnAt = Classes.CanUse(r.class, r.level, item, r.knownArmor)
    if not ok then
        add(res.eligibility.reasons, why)
        return "ineligible"
    end
    -- The level at which the character could equip it: item level requirement,
    -- or the level the armor type is learned.
    local needLevel = item.reqLevel or 0
    if why == "LATER_LEVEL" and learnAt and learnAt > needLevel then needLevel = learnAt end

    if s.specArmor and item.classID == 4 and BODY_ARMOR[item.subclassID]
        and item.equipLoc ~= "INVTYPE_CLOAK" then
        local allowed = (input.profile and input.profile.armor)
        if not allowed then
            local spec = Classes.Spec(input.spec)
            allowed = spec and spec.armor
        end
        if allowed then
            local found = false
            for _, a in ipairs(allowed) do if a == item.subclassID then found = true end end
            if not found then
                add(res.eligibility.reasons, "NOT_SPEC_ARMOR")
                return "ineligible"
            end
        end
    end

    local level = r.level or 0
    if needLevel > level then
        local window = s.levelWindow or {}
        local away = needLevel - level
        if window.enabled ~= false and away > (window.lookAhead or 0) then
            add(res.eligibility.reasons, "ABOVE_LEVEL_WINDOW")
            res.eligibility.levelsAway = away
            return "ineligible"
        end
        res.eligibility.equipNow = false
        res.eligibility.levelsAway = away
        res.eligibility.atLevel = needLevel
        add(res.eligibility.reasons, "LATER_LEVEL")
    end
    return nil
end

function Evaluate.One(input)
    local settings = {}
    for k, v in pairs(Evaluate.DEFAULT_SETTINGS) do settings[k] = v end
    for k, v in pairs(input.settings or {}) do settings[k] = v end
    input.settings = settings

    local res = newResult(input)
    local item = input.item

    if not item or not item.ready then
        res.status = "pending"
        add(res.reasons, "ITEM_DATA_PENDING")
        return res
    end
    if not GG.Data.Slots.IsEquippable(item.equipLoc) then
        res.status = "ineligible"
        add(res.eligibility.reasons, "NOT_EQUIPPABLE")
        return res
    end
    local terminal = eligibility(input, res)
    if terminal then res.status = terminal return res end

    local profile = input.profile
    if not profile then
        res.status = "unknown"
        add(res.reasons, "NO_WEIGHTS")
        return res
    end

    -- Limitations that do not stop scoring.
    for _, key in ipairs(item.unsupported or {}) do add(res.limitations, "UNSUPPORTED_STAT:" .. key) end
    for _, token in ipairs(Stats.UnscoredTokens(profile)) do add(res.limitations, "TOKEN_NOT_SCORED:" .. token) end
    if item.hasSpell then add(res.limitations, "EFFECT_NOT_SCORED") end

    local cand = Score.Compute(item.tokens, profile)
    if cand.ignoredHit then
        res.status = "ineligible"
        add(res.eligibility.reasons, "IGNORED_STAT:" .. cand.ignoredHit)
        return res
    end
    if cand.noSupported then add(res.limitations, "NO_SUPPORTED_STATS") end

    local baseline = input.baseline
    if not baseline then
        res.status = "unknown"
        add(res.reasons, "NO_BASELINE")
        return res
    end
    res.baseline = {
        source = baseline.source, capturedAt = baseline.capturedAt,
        complete = baseline.complete ~= false, stale = baseline.stale == true,
        maybeBehind = baseline.maybeBehind == true,
    }

    -- Score every baseline item with this profile (enchants already stripped).
    local slots = {}
    for slot, b in pairs(baseline.slots or {}) do
        local copy = {}
        for k, v in pairs(b) do copy[k] = v end
        if b.state == "occupied" then
            if b.tokens then copy.score = Score.Compute(b.tokens, profile).score
            else copy.state = "unknown" end   -- item data missing: unknown, not empty
        end
        slots[slot] = copy
    end
    local candidate = { itemID = item.itemID, equipLoc = item.equipLoc, score = cand.score,
        unique = item.unique, setID = item.setID, itemString = item.itemString }
    local companion
    if input.companion then
        companion = {}
        for s, c in pairs(input.companion) do
            local copy = {}
            for k, v in pairs(c) do copy[k] = v end
            copy.score = c.tokens and Score.Compute(c.tokens, profile).score or 0
            companion[s] = copy
        end
    end
    local best = SlotCompare.Best(candidate, slots, {
        canDualWield = (input.recipient or {}).canDualWield, companion = companion })

    if best.state == "illegal" then
        res.status = "ineligible"
        add(res.eligibility.reasons, best.reason)
        return res
    elseif best.state == "unknown" then
        res.status = "unknown"
        add(res.reasons, best.reason)
        return res
    end

    res.replaces = { slots = best.slots, items = {} }
    for _, d in ipairs(best.displaced) do add(res.replaces.items, d.itemString) end

    -- Set bonuses on the resulting configuration.
    if item.setID or #best.displaced > 0 then
        local before = {}
        for _, b in pairs(slots) do if b.state == "occupied" then add(before, b) end end
        local diff = SetBonus.Diff(before, best.result, input.setThresholds or GG.Data.ItemSets)
        for _, g in ipairs(diff.gained) do add(res.limitations, "SET_BONUS_GAINED:" .. g.setID .. ":" .. g.pieces) end
        for _, l in ipairs(diff.lost) do add(res.limitations, "SET_BONUS_LOST:" .. l.setID .. ":" .. l.pieces) end
        if #diff.unknownSets > 0 then add(res.limitations, "SET_BONUS_NOT_SCORED") end
    end

    local pct
    if best.emptySlot then
        add(res.reasons, "EMPTY_SLOT")
    elseif best.baseScore > 0 then
        pct = best.delta / best.baseScore
    else
        add(res.reasons, "BASELINE_NONPOSITIVE")
    end
    res.score = { candidate = best.candScore, baseline = best.baseScore, delta = best.delta, pct = pct }

    local upgrade
    if best.emptySlot then upgrade = best.candScore > 0
    elseif pct then upgrade = pct >= settings.threshold
    else upgrade = best.delta > 0 end
    res.status = upgrade and "upgrade" or "no_upgrade"
    if res.baseline.stale then add(res.reasons, "BASELINE_STALE") end
    if not res.baseline.complete then add(res.reasons, "BASELINE_INCOMPLETE") end
    if res.baseline.source == "fallback-current" then add(res.reasons, "BASELINE_FALLBACK") end
    if res.baseline.maybeBehind then add(res.reasons, "MAYBE_BEHIND") end
    return res
end

-- Aggregate display status (API.md precedence). Never a protection verdict.
local ORDER = { "upgrade", "pending", "unknown", "no_upgrade", "ineligible" }
function Evaluate.Aggregate(results)
    local seen = {}
    for _, r in ipairs(results or {}) do seen[r.status] = true end
    for _, s in ipairs(ORDER) do if seen[s] then return s end end
    return "unsupported"
end

return Evaluate
