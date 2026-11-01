------------------------------------------------------------
-- Presentation/TooltipView.lua - the tooltip block as plain lines (GG-107,
-- adr/0004). Pure: an API response in, colored text lines out. UI/Tooltip.lua
-- only adds them to the tooltip; it never restyles GameTooltip.
--
--   TooltipView.Build(response, tooltipSettings, ctx) -> lines | nil
--     ctx   = { currentSpec = key|nil }
--     lines = { { left, right|nil, lc = {r,g,b}, rc = {r,g,b}|nil }, ... }
--
-- Layout (mockup 01): "Glass Gear", the current spec first and marked
-- CURRENT, the other specs compact, notes (set bonus, unscored effects, spec
-- not set), then the footer "Weighted item score · estimates".
------------------------------------------------------------

local GG = GlassGear
local View = {}
GG.TooltipView = View

View.COLORS = {
    title = { 1, 0.82, 0 },
    current = { 1, 1, 1 },
    spec = { 0.82, 0.82, 0.82 },
    good = { 0.25, 1, 0.25 },
    bad = { 1, 0.35, 0.35 },
    later = { 1, 0.82, 0 },
    muted = { 0.55, 0.55, 0.55 },
}
local C = View.COLORS
View.BADGE = "|cff7fd4ffCURRENT|r"

-- Short texts for terminal reasons (ineligible / unknown). First match wins.
local REASON_TEXT = {
    NO_WEIGHTS = "no weights",
    UNKNOWN_SPEC = "spec not set",
    NOT_SPEC_ARMOR = "not for this spec",
    PROFICIENCY = "can't use",
    NEEDS_TRAINING = "needs training",
    NOT_EQUIPPABLE = "can't use",
    UNIQUE_EQUIPPED = "unique, equipped",
    NEEDS_COMPANION = "needs an off-hand",
    COMPANION_DATA_MISSING = "needs an off-hand",
    COMPANION_NOT_LEGAL = "needs an off-hand",
    NO_LEGAL_SLOT = "no free slot",
    NO_SUPPORTED_STATS = "no scored stats",
    ITEM_DATA_UNAVAILABLE = "item data unavailable",
    ITEM_QUEUE_FULL = "busy, hover again",
    OVERLOADED = "busy, hover again",
}

local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end end

local function pctText(pct)
    local v = pct * 100
    if v > -0.05 and v < 0.05 then return "0.0%" end
    return string.format("%+.1f%%", v)
end

local function laterText(row)
    if not row.atLevel then return nil end
    if row.levelsAway and row.levelsAway > 0 then
        return string.format("at level %d (in %d)", row.atLevel, row.levelsAway)
    end
    return string.format("at level %d", row.atLevel)
end

-- The right-hand text and color of one row.
local function rightOf(row)
    if row.status == "pending" then return "checking...", C.muted end
    if row.status == "upgrade" then
        local text = row.pct and pctText(row.pct) or (row.label or "upgrade")
        if row.laterLevel then return text .. " " .. laterText(row), C.later end
        return text, C.good
    end
    if row.status == "no_upgrade" then
        if row.pct and row.pct < 0 then return pctText(row.pct), C.bad end
        if row.pct then return pctText(row.pct), C.muted end
        return "no upgrade", C.muted
    end
    if row.status == "ineligible" then
        if has(row.why, "ABOVE_LEVEL_WINDOW") then return laterText(row) or "later level", C.muted end
        for _, list in ipairs({ row.why, row.reasons }) do
            for _, r in ipairs(list) do
                if REASON_TEXT[r] then return REASON_TEXT[r], C.muted end
            end
        end
        return "can't use", C.muted
    end
    -- unknown (and anything else)
    for _, r in ipairs(row.reasons) do
        if REASON_TEXT[r] then return REASON_TEXT[r], C.muted end
    end
    return "can't tell yet", C.muted
end

local function specName(key)
    local s = GG.Data.Classes.Spec(key)
    return s and s.name or tostring(key)
end

-- Notes shared by the rows, deduplicated, in a fixed order.
local function notes(rows)
    local gained, lost, setUnscored, effect = {}, {}, false, false
    for _, row in ipairs(rows) do
        for _, l in ipairs(row.limitations) do
            local g = l:match("^SET_BONUS_GAINED:[^:]+:(%d+)$")
            local x = l:match("^SET_BONUS_LOST:[^:]+:(%d+)$")
            if g then gained[g] = true end
            if x then lost[x] = true end
            if l == "SET_BONUS_NOT_SCORED" then setUnscored = true end
            if l == "EFFECT_NOT_SCORED" then effect = true end
        end
    end
    local out = {}
    local function sorted(t)
        local ks = {}
        for k in pairs(t) do ks[#ks + 1] = tonumber(k) end
        table.sort(ks)
        return ks
    end
    for _, n in ipairs(sorted(gained)) do out[#out + 1] = string.format("Completes a %d-piece set bonus (not scored)", n) end
    for _, n in ipairs(sorted(lost)) do out[#out + 1] = string.format("Breaks a %d-piece set bonus (not scored)", n) end
    if setUnscored and #out == 0 then out[#out + 1] = "Set item: bonus not scored" end
    if effect then out[#out + 1] = "Has an effect that isn't scored" end
    return out
end

function View.Build(response, settings, ctx)
    if type(response) ~= "table" or type(response.results) ~= "table" then return nil end
    ctx = ctx or {}
    local view = { own = {} }
    for _, r in ipairs(response.results) do
        if r.status ~= "unsupported" and r.spec then
            if r.current and not view.current then
                view.current = r
            else
                view.own[#view.own + 1] = r
            end
        end
    end
    local rows = GG.Engine.Policy.TooltipRows(view, settings or {}, false)
    if #rows == 0 then return nil end

    local lines = { { left = "Glass Gear", lc = C.title } }
    local offSpecVsCurrentGear = false
    for _, row in ipairs(rows) do
        local right, rc = rightOf(row)
        local left = specName(row.spec)
        if row.emphasis then left = left .. "  " .. View.BADGE end
        lines[#lines + 1] = { left = left, right = right, lc = row.emphasis and C.current or C.spec, rc = rc }
        if not row.emphasis and has(row.reasons, "BASELINE_FALLBACK")
            and (row.status == "upgrade" or row.status == "no_upgrade") then
            offSpecVsCurrentGear = true
        end
    end
    for _, n in ipairs(notes(rows)) do lines[#lines + 1] = { left = n, lc = C.later } end
    if not ctx.currentSpec then
        lines[#lines + 1] = { left = "Current spec not set: /gg spec", lc = C.muted }
    end
    local footer = "Weighted item score \194\183 estimates"
    if offSpecVsCurrentGear then footer = footer .. " \194\183 other specs vs current gear" end
    lines[#lines + 1] = { left = footer, lc = C.muted }
    return lines
end

return View
