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
local L = GG.L
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
View.BADGE = "|cff7fd4ff" .. L["CURRENT"] .. "|r"

-- Short texts for terminal reasons (ineligible / unknown). First match wins.
local REASON_TEXT = {
    NO_WEIGHTS = L["no weights"],
    UNKNOWN_SPEC = L["spec not set"],
    NOT_SPEC_ARMOR = L["not for this spec"],
    PROFICIENCY = L["can't use"],
    NEEDS_TRAINING = L["needs training"],
    NOT_EQUIPPABLE = L["can't use"],
    UNIQUE_EQUIPPED = L["unique, equipped"],
    NEEDS_COMPANION = L["needs an off-hand"],
    COMPANION_DATA_MISSING = L["needs an off-hand"],
    COMPANION_NOT_LEGAL = L["needs an off-hand"],
    NO_LEGAL_SLOT = L["no free slot"],
    NO_SUPPORTED_STATS = L["no scored stats"],
    ITEM_DATA_UNAVAILABLE = L["item data unavailable"],
    ITEM_QUEUE_FULL = L["busy, hover again"],
    OVERLOADED = L["busy, hover again"],
}

local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end end

local function pctText(pct)
    local v = pct * 100
    if v > -0.05 and v < 0.05 then return "0.0%" end
    return string.format("%+.1f%%", v)
end

-- "at level 40 (in 3)"; with `verdict`, "+2.0% at level 40 (in 3)".
local function laterText(row, verdict)
    if not row.atLevel then return verdict end
    local away = row.levelsAway and row.levelsAway > 0 and row.levelsAway
    if verdict then
        if away then return L["%s at level %d (in %d)"]:format(verdict, row.atLevel, away) end
        return L["%s at level %d"]:format(verdict, row.atLevel)
    end
    if away then return L["at level %d (in %d)"]:format(row.atLevel, away) end
    return L["at level %d"]:format(row.atLevel)
end

-- The right-hand text and color of one row.
local function rightOf(row)
    if row.status == "pending" then return L["checking..."], C.muted end
    if row.status == "upgrade" then
        local text = row.pct and pctText(row.pct) or (row.label or L["upgrade"])
        if row.laterLevel then return laterText(row, text), C.later end
        return text, C.good
    end
    if row.status == "no_upgrade" then
        if has(row.reasons, "OWNED_BETTER") then return L["you own better"], C.muted end
        -- An item for a later level keeps saying so, whatever the score.
        local function later(text) return row.laterLevel and laterText(row, text) or text end
        if row.pct and row.pct < 0 then return later(pctText(row.pct)), C.bad end
        if row.pct then return later(pctText(row.pct)), C.muted end
        return later(L["no upgrade"]), C.muted
    end
    if row.status == "ineligible" then
        if has(row.why, "ABOVE_LEVEL_WINDOW") then return laterText(row) or L["later level"], C.muted end
        for _, list in ipairs({ row.why, row.reasons }) do
            for _, r in ipairs(list) do
                if REASON_TEXT[r] then return REASON_TEXT[r], C.muted end
            end
        end
        return L["can't use"], C.muted
    end
    -- unknown (and anything else)
    for _, r in ipairs(row.reasons) do
        if REASON_TEXT[r] then return REASON_TEXT[r], C.muted end
    end
    return L["can't tell yet"], C.muted
end

local function specName(key)
    local s = GG.Data.Classes.Spec(key)
    return s and s.name or tostring(key)
end

-- Stats a profile can't score, per side (the item / the replaced item).
local function statGap(l, side)
    local p = side == "baseline" and "BASELINE_" or ""
    local token = l:match("^" .. p .. "TOKEN_NOT_SCORED:(.+)$") or l:match("^" .. p .. "WEIGHT_MISSING:(.+)$")
    if token then return token end
    if l:match("^" .. p .. "UNSUPPORTED_STAT:") then return L["an unrecognised stat"] end
end

local function joined(set)
    local list = {}
    for k in pairs(set) do list[#list + 1] = k end
    table.sort(list)
    return table.concat(list, ", ")
end

-- Notes shared by the rows, deduplicated, in a fixed order. Anything the
-- score leaves out - on the item or on the gear it replaces - is named, since
-- it can reverse the comparison.
local function notes(rows, setWarnings)
    local gained, lost, setUnscored, effect, baseEffect = {}, {}, false, false, false
    local gaps, baseGaps = {}, {}
    for _, row in ipairs(rows) do
        for _, l in ipairs(row.limitations) do
            local g = l:match("^SET_BONUS_GAINED:[^:]+:(%d+)$")
            local x = l:match("^SET_BONUS_LOST:[^:]+:(%d+)$")
            if g and setWarnings then gained[g] = true end
            if x and setWarnings then lost[x] = true end
            if l == "SET_BONUS_NOT_SCORED" then setUnscored = true end
            if l == "EFFECT_NOT_SCORED" then effect = true end
            if l == "BASELINE_EFFECT_NOT_SCORED" then baseEffect = true end
            local gap, baseGap = statGap(l, "item"), statGap(l, "baseline")
            if gap then gaps[gap] = true end
            if baseGap then baseGaps[baseGap] = true end
        end
    end
    local out = {}
    local function sorted(t)
        local ks = {}
        for k in pairs(t) do ks[#ks + 1] = tonumber(k) end
        table.sort(ks)
        return ks
    end
    for _, n in ipairs(sorted(gained)) do out[#out + 1] = L["Completes a %d-piece set bonus (not scored)"]:format(n) end
    for _, n in ipairs(sorted(lost)) do out[#out + 1] = L["Breaks a %d-piece set bonus (not scored)"]:format(n) end
    if setUnscored and #out == 0 then out[#out + 1] = L["Set item: bonus not scored"] end
    if effect then out[#out + 1] = L["Has an effect that isn't scored"] end
    if baseEffect then out[#out + 1] = L["The replaced item has an effect that isn't scored"] end
    if next(gaps) then out[#out + 1] = L["Not scored: %s"]:format(joined(gaps)) end
    if next(baseGaps) then out[#out + 1] = L["Not scored on the replaced item: %s"]:format(joined(baseGaps)) end
    return out
end

-- One result's short verdict ("+3.1%", "no weights", "can't tell yet"), and
-- the notes for a set of rows: shared with the comparison (GG-113).
function View.ResultText(result)
    local rows = GG.Engine.Policy.TooltipRows({ current = result, own = {} }, { specs = "current" }, false)
    return rows[1] and (rightOf(rows[1])) or ""
end
function View.Notes(rows, setWarnings) return notes(rows, setWarnings) end

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
    for _, n in ipairs(notes(rows, (settings or {}).setBonusWarnings ~= false)) do
        lines[#lines + 1] = { left = n, lc = C.later }
    end
    -- Better gear already owned (GG-122): name it.
    for _, row in ipairs(rows) do
        local o = row.ownedBetter
        local name = o and o.link and o.link:match("%[(.-)%]")
        if name then
            lines[#lines + 1] = { left = L["You own better for %s: %s"]:format(specName(row.spec), name), lc = C.later }
        end
    end
    -- A spec compared with gear recorded too long ago says so (GG-108).
    local stale = {}
    for _, row in ipairs(rows) do
        if has(row.reasons, "BASELINE_STALE") then stale[#stale + 1] = specName(row.spec) end
    end
    if #stale > 0 then
        lines[#lines + 1] = { left = L["Gear recorded over 14 days ago: %s"]:format(table.concat(stale, ", ")), lc = C.later }
    end
    if not ctx.currentSpec then
        lines[#lines + 1] = { left = L["Current spec not set: /gg options"], lc = C.muted }
    end
    local footer = offSpecVsCurrentGear
        and L["Weighted item score \194\183 estimates \194\183 other specs vs current gear"]
        or L["Weighted item score \194\183 estimates"]
    lines[#lines + 1] = { left = footer, lc = C.muted }
    return lines
end

return View
