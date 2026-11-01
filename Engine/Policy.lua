------------------------------------------------------------
-- Engine/Policy.lua - the three independent policies (adr/0006) and the
-- reveal state. Pure. Protection never reads marker/tooltip settings or reveal.
------------------------------------------------------------

local GG = GlassGear
local Policy = {}
GG.Engine.Policy = Policy

local function isUpgradeNow(r)
    return r and r.status == "upgrade" and r.eligibility and r.eligibility.equipNow ~= false
end

local function anyUpgrade(list)
    for _, r in ipairs(list or {}) do if isUpgradeNow(r) then return true end end
    return false
end

-- Eligible own alts only: provenance self/own-account and transfer eligible.
local function eligibleAlts(list)
    local out = {}
    for _, r in ipairs(list or {}) do
        local prov = r.character and r.character.provenance
        if (prov == "self" or prov == "own-account") and r.transfer and r.transfer.state == "eligible" then
            out[#out + 1] = r
        end
    end
    return out
end

------------------------------------------------------------
-- Marker predicate.
--   view = { current = result|nil, own = {results for other own specs},
--            alts = {results}, bound = true|false|nil, surface = "bags"|"loot",
--            bindType = number|nil (loot: 1 = BoP, 2 = BoE) }
--   settings = { markTransferable = true, ownSpecs = {specKey=true}|nil }
--   reveal = bool (Policy.Reveal state)
-- Returns "green" | "amber" | nil.
------------------------------------------------------------
function Policy.Marker(view, settings, reveal)
    settings = settings or {}
    if isUpgradeNow(view.current) then return "green" end

    -- Own specs the marker scope always includes (besides current).
    local always = {}
    for _, r in ipairs(view.own or {}) do
        if settings.ownSpecs and settings.ownSpecs[r.spec] then always[#always + 1] = r end
    end
    if anyUpgrade(always) then return "amber" end

    local transferable
    if view.surface == "loot" then
        -- BoP loot follows soulbound rules; BoE loot is transferable, alts only while revealed.
        transferable = view.bindType == 2 and reveal
    else
        transferable = view.bound == false
    end

    if reveal and anyUpgrade(view.own) then return "amber" end
    if transferable then
        local alts = eligibleAlts(view.alts)
        if view.surface ~= "loot" and settings.markTransferable ~= false then
            if anyUpgrade(view.own) or anyUpgrade(alts) then return "amber" end
        end
        if reveal and anyUpgrade(alts) then return "amber" end
    end
    return nil
end

------------------------------------------------------------
-- Tooltip rows: current spec first and emphasised, own specs compact in the
-- given order, then eligible own-alt rows (transferable items only).
--   settings = { specs = "all"|"current"|"selected", selected = {specKey=true},
--                alts = true, showLater = true }
------------------------------------------------------------
local function row(kind, r)
    local x = {
        kind = kind, spec = r.spec, character = r.character, status = r.status,
        pct = r.score and r.score.pct, delta = r.score and r.score.delta,
        emphasis = kind == "current", compact = kind ~= "current",
        noWeights = false, laterLevel = nil, label = nil,
    }
    for _, reason in ipairs(r.reasons or {}) do
        if reason == "NO_WEIGHTS" then x.noWeights = true; x.label = "no weights" end
        if reason == "EMPTY_SLOT" then x.label = "empty slot" end
    end
    if r.eligibility and r.eligibility.equipNow == false and r.eligibility.atLevel then
        x.laterLevel = { atLevel = r.eligibility.atLevel, levelsAway = r.eligibility.levelsAway }
    end
    if r.status == "pending" then x.label = "checking..." end
    return x
end

function Policy.TooltipRows(view, settings, transferable)
    settings = settings or {}
    local rows = {}
    if view.current then rows[#rows + 1] = row("current", view.current) end
    if settings.specs ~= "current" then
        for _, r in ipairs(view.own or {}) do
            if settings.specs ~= "selected" or (settings.selected and settings.selected[r.spec]) then
                rows[#rows + 1] = row("spec", r)
            end
        end
    end
    if transferable and settings.alts ~= false then
        for _, r in ipairs(eligibleAlts(view.alts)) do
            if r.status == "upgrade" then rows[#rows + 1] = row("alt", r) end
        end
    end
    return rows
end

------------------------------------------------------------
-- Reveal: effective = modifier down and no edit box focused. The caller
-- feeds the current inputs on every event/poll; `changed` tells it to refresh.
------------------------------------------------------------
function Policy.NewReveal()
    local state = { active = false }
    function state:Update(modifierSetting, modifierDown, editFocused)
        local now = modifierSetting ~= "NONE" and modifierDown == true and not editFocused
        local changed = now ~= self.active
        self.active = now
        return now, changed
    end
    return state
end

------------------------------------------------------------
-- Protection verdict over the protection-scope results (adr/0003, API.md).
--   opts = { noWeights = "ignore"|"keep" (default "ignore") }
-- Returns { verdict, recipients, reasons, unchecked }.
-- `clear` only when every checked recipient is a trustworthy no_upgrade or
-- a hard ineligible; anything uncertain keeps the item.
------------------------------------------------------------
local UNSAFE_LIMITS = { EFFECT_NOT_SCORED = true, NO_SUPPORTED_STATS = true, SET_BONUS_NOT_SCORED = true }
local UNSAFE_PREFIX = { "SET_BONUS_GAINED", "SET_BONUS_LOST", "TOKEN_NOT_SCORED", "UNSUPPORTED_STAT" }

local function unsafe(r)
    local b = r.baseline
    if not b or b.stale or b.complete == false or b.maybeBehind or b.source == "fallback-current" then
        return "BASELINE_NOT_TRUSTED"
    end
    for _, l in ipairs(r.limitations or {}) do
        if UNSAFE_LIMITS[l] then return l end
        for _, p in ipairs(UNSAFE_PREFIX) do
            if l:sub(1, #p) == p then return p end
        end
    end
end

local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end end

function Policy.Protection(results, opts)
    opts = opts or {}
    local out = { verdict = "clear", recipients = {}, reasons = {}, unchecked = {} }
    local pending, unknown, unsupported, protect = false, false, false, false
    if not results or #results == 0 then
        out.verdict = "unknown"
        out.reasons[1] = "NO_PROTECTION_TARGETS"
        return out
    end
    for _, r in ipairs(results) do
        local who = { character = r.character, spec = r.spec }
        if r.status == "upgrade" then
            -- Inside the level window counts too: keep it for later.
            protect = true
            who.pct = r.score and r.score.pct
            who.laterLevel = r.eligibility and r.eligibility.equipNow == false or nil
            out.recipients[#out.recipients + 1] = who
        elseif r.status == "pending" then
            pending = true
        elseif r.status == "unsupported" then
            unsupported = true
        elseif r.status == "unknown" then
            if has(r.reasons, "NO_WEIGHTS") and opts.noWeights ~= "keep" then
                out.unchecked[#out.unchecked + 1] = who
            else
                unknown = true
                out.reasons[#out.reasons + 1] = (r.reasons and r.reasons[1]) or "UNKNOWN"
            end
        elseif r.status == "no_upgrade" then
            local why = unsafe(r)
            if why then unknown = true; out.reasons[#out.reasons + 1] = why end
        end
        -- ineligible: this recipient cannot use it (class, spec armor, level window).
    end
    if protect then out.verdict = "protect"
    elseif pending then out.verdict = "pending"
    elseif unknown then out.verdict = "unknown"
    elseif unsupported then out.verdict = "unsupported"
    elseif #out.unchecked == #results then
        -- Nothing could be checked at all: never call that safe.
        out.verdict = "unknown"
        out.reasons[#out.reasons + 1] = "NO_WEIGHTS"
    end
    if #out.unchecked > 0 then out.reasons[#out.reasons + 1] = "UNCHECKED_SPECS" end
    return out
end

return Policy
