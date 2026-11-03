------------------------------------------------------------
-- Presentation/CompareView.lua - the detailed comparison (GG-113, mockup 08,
-- adr/0003) as plain text. Pure: one API result and the items' stats in, a
-- view out. UI/CompareWindow.lua only lays it out.
--
--   CompareView.Build(result, data) -> view
--     data = { specKey, specName, current, candidate = { name, tokens },
--              companion = { name, tokens } | nil, replaced = { { name, tokens }, ... },
--              profile = profile shape | nil, setWarnings = bool }
--     an item whose data is still loading has tokens = nil: the view says
--     "loading", never zeros (view.loading)
--     view = { equipped, candidate, rows = { { label, equipped, candidate, change, level } },
--              score = { equipped, candidate, change, level } | nil,
--              status = { text, level }, info = { { label, text } }, warnings = { text },
--              noBaseline = bool }
------------------------------------------------------------

local GG = GlassGear
local View = {}
GG.CompareView = View

View.MAX_ROWS = 12

local function num(v)
    if v == nil then return "" end
    if v == math.floor(v) then return tostring(v) end
    return string.format("%.1f", v)
end

local function signed(v)
    if v == 0 then return "0" end
    return (v > 0 and "+" or "") .. num(v)
end

local function sum(items, into)
    for _, it in ipairs(items) do
        for token, value in pairs(it.tokens or {}) do
            if type(value) == "number" then into[token] = (into[token] or 0) + value end
        end
    end
    return into
end

local function names(items)
    local out = {}
    for _, it in ipairs(items) do out[#out + 1] = it.name or "?" end
    return table.concat(out, " + ")
end

local function weightOf(profile, token)
    if not profile then return nil end
    if profile.ignored and profile.ignored[token] then return "X" end
    return profile.weights and profile.weights[token]
end

-- Weapon details and type flags (Is*, speeds, min/max damage) mean nothing
-- summed over two items and crowd the table: shown only when weighted.
local function detail(token)
    return token:match("^Is") or token:match("Speed$") or token:match("MinDamage$")
        or token:match("MaxDamage$") or token == "SpeedBaseline"
        or (token:match("Dps$") and token ~= "Dps")
end

-- The stat table: the weighted stats first, then the others (muted, "not
-- weighted"), in the token order. Rows past MAX_ROWS are counted, never
-- silently dropped (view.moreRows).
local function statRows(cand, repl, profile)
    local weighted, others = {}, {}
    for _, token in ipairs(GG.Data.Stats.ORDER) do
        local a, b = repl[token], cand[token]
        local w = weightOf(profile, token)
        local isWeighted = w == "X" or (type(w) == "number" and w ~= 0)
        if ((a and a ~= 0) or (b and b ~= 0)) and (isWeighted or not detail(token)) then
            local list = isWeighted and weighted or others
            list[#list + 1] = token
        end
    end
    local ordered = {}
    for _, t in ipairs(weighted) do ordered[#ordered + 1] = t end
    for _, t in ipairs(others) do ordered[#ordered + 1] = t end
    local rows, more = {}, 0
    for _, token in ipairs(ordered) do
        local a, b = repl[token], cand[token]
        if #rows >= View.MAX_ROWS then
            more = more + 1
        else
            local delta = (b or 0) - (a or 0)
            local w = weightOf(profile, token)
            local level = "muted"
            local label = GG.ProfileView.StatLabel(token)
            if w == "X" then
                label = label .. " (ignored)"
            elseif type(w) == "number" and w ~= 0 then
                local effect = delta * w
                level = effect > 0 and "ok" or effect < 0 and "error" or "muted"
            else
                label = label .. " (not weighted)"
            end
            rows[#rows + 1] = { label = label, equipped = num(a or 0), candidate = num(b or 0),
                change = signed(delta), level = level }
        end
    end
    return rows, more
end

local BASELINE = {
    ["equipment-set"] = "a saved equipment set",
    observed = "saved %s equipment",
    ["fallback-current"] = "your current gear (estimate)",
}

function View.Build(result, data)
    local view = { rows = {}, info = {}, warnings = {}, noBaseline = false }
    local spec = data.specName or tostring(data.specKey)
    local candItems = { data.candidate }
    if data.companion then candItems[#candItems + 1] = data.companion end
    view.candidate = names(candItems)
    view.equipped = #(data.replaced or {}) > 0 and names(data.replaced) or "nothing (an empty slot)"

    if result.status == "pending" then
        view.status = { text = "Checking...", level = "muted" }
        return view
    end
    -- An item still loading: say so, never show its stats as zeros.
    for _, it in ipairs(candItems) do if it.tokens == nil then view.loading = true end end
    for _, it in ipairs(data.replaced or {}) do if it.tokens == nil then view.loading = true end end
    if not view.loading then
        view.rows, view.moreRows = statRows(sum(candItems, {}), sum(data.replaced or {}, {}), data.profile)
    end

    local s = result.score
    if s and type(s.candidate) == "number" then
        local change, level = "", "muted"
        if s.pct then
            change = string.format("%+.1f%%", s.pct * 100)
            level = s.pct > 0 and "ok" or s.pct < 0 and "error" or "muted"
        elseif s.delta then
            change, level = signed(s.delta), s.delta > 0 and "ok" or s.delta < 0 and "error" or "muted"
        end
        view.score = { equipped = string.format("%.1f", s.baseline or 0),
            candidate = string.format("%.1f", s.candidate), change = change, level = level }
    end

    if result.status == "upgrade" then
        local later = result.eligibility and result.eligibility.equipNow == false and result.eligibility.atLevel
        view.status = { text = "Potential upgrade for " .. spec .. (later and (" at level " .. later) or ""),
            level = later and "warn" or "ok" }
    elseif result.status == "no_upgrade" then
        view.status = { text = "Not an upgrade for " .. spec, level = "muted" }
    else
        view.status = { text = spec .. ": " .. GG.TooltipView.ResultText(result), level = "warn" }
    end

    local p = data.profile
    view.info[#view.info + 1] = { label = "Method", text = "stat weights (item score estimate)" }
    view.info[#view.info + 1] = { label = "Profile", text = p and (spec .. " \226\128\148 " .. p.name) or "no weights" }
    view.info[#view.info + 1] = { label = "Source", text = p and GG.ProfileView.SourceLabel(p.source) or "\226\128\148" }
    local b = result.baseline
    local base = b and (BASELINE[b.source] or tostring(b.source)) or "none"
    if b and b.source == "observed" then base = base:format(spec) end
    view.info[#view.info + 1] = { label = "Baseline", text = base }

    local rows = GG.Engine.Policy.TooltipRows({ current = result, own = {} }, { specs = "current" }, false)
    for _, n in ipairs(GG.TooltipView.Notes(rows, data.setWarnings ~= false)) do view.warnings[#view.warnings + 1] = n end
    if view.loading then table.insert(view.warnings, 1, "Item data still loading: stats shown once it arrives") end
    if view.moreRows and view.moreRows > 0 then
        view.warnings[#view.warnings + 1] = view.moreRows .. " more unweighted stat" .. (view.moreRows == 1 and "" or "s") .. " not shown"
    end
    if b and b.stale then view.warnings[#view.warnings + 1] = "The saved " .. spec .. " gear is over 14 days old" end
    view.noBaseline = b ~= nil and b.source == "fallback-current" and not data.current
    return view
end

return View
