------------------------------------------------------------
-- UI/CompareWindow.lua - the detailed comparison window (GG-113, mockup 08):
-- one item against a chosen spec's gear, with the stats behind the
-- estimate, the score on the profile's scale, the verdict, how it was made
-- (method, profile, source, baseline) and what it leaves out. A spec with no
-- recorded gear offers a saved set (Capture.MapSet).
--
-- /gg compare [item link] (UI/Diagnostics.lua). The text comes from
-- Presentation/CompareView.lua; the frame from UI/Window.lua.
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
local Win = {}
GG.CompareWindow = Win

Win.NAME = "GlassGearCompareFrame"
Win.W, Win.H = 470, 600
Win.MAX_SETS = 4

local UIW = GG.Window
local label, button, color, fill = UIW.Label, UIW.Button, UIW.Color, UIW.Fill
local frame
local W = {}
local state = { ref = nil, spec = nil, response = nil, requestId = nil }

local function at(region, x, y, parent)
    region:SetPoint("TOPLEFT", parent or frame, "TOPLEFT", x, y)
    return region
end

local waiting = {}            -- [itemID] = true: shown items still loading

-- An item for the view; tokens = nil while its data loads (never zeros),
-- and its load is requested so the window can show it on arrival.
local function itemData(itemString)
    local f = itemString and GG.Compat.ItemFacts(itemString)
    local ready = f and f.ready
    if f and not ready then
        waiting[f.itemID] = true
        GG.Compat.RequestItem(f.itemID)
    end
    return { name = GG.Compat.ItemName(itemString) or L["item %s"]:format(tostring(f and f.itemID or "?")),
        tokens = ready and f.tokens or nil }
end

local function resultFor(spec)
    for _, r in ipairs(state.response and state.response.results or {}) do
        if r.spec == spec then return r end
    end
end

-- Ask the API for every own spec; a pending answer completes through
-- EvaluationReady.
local function evaluate()
    if state.requestId then GG.API.CancelRequest(state.requestId) end
    state.response = GG.API.Evaluate({ item = state.ref, scope = "own", context = "compare" })
    state.requestId = GG.Results.AnyPending(state.response) and state.response.requestId or nil
end

local function specButtons()
    W.specs = {}
    local list = GG.Data.Classes.Specs(GG.player.class)
    -- Every tab inside the window, whatever the number of specs (a Druid has four).
    local gap = 6
    local width = math.floor((Win.W - 24 - gap * (#list - 1)) / math.max(1, #list))
    for i, s in ipairs(list) do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(width, 22)
        b.x = 12 + (i - 1) * (width + gap)
        at(b, b.x, -34)
        b.text = label(b, s.name, "GameFontNormal")
        b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.specKey = s.key
        b:SetScript("OnClick", function() Win.SelectSpec(s.key) end)
        W.specs[#W.specs + 1] = b
    end
end

local function build()
    frame = UIW.New({ name = Win.NAME, key = "compare", width = Win.W, height = Win.H,
        title = L["Glass Gear \194\183 Compare"], onShow = function() Win.Render() end, offsetX = 300,
        onHide = function()
            -- Nothing left running for a closed window.
            if state.requestId then GG.API.CancelRequest(state.requestId); state.requestId = nil end
        end })
    -- Shown items whose data was loading: draw them once it arrives.
    local events = CreateFrame("Frame", nil, frame)
    events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    events:SetScript("OnEvent", function(_, _, itemID)
        if itemID and waiting[itemID] and frame:IsShown() then
            waiting[itemID] = nil
            Win.Render()
        end
    end)
    specButtons()
    W.baseline = at(label(frame, "", "GameFontHighlightSmall"), 14, -62)
    W.baseline:SetWidth(440)
    at(label(frame, L["Equipped"], "GameFontDisableSmall"), 14, -82)
    W.equipped = at(label(frame, "", "GameFontHighlight"), 14, -96)
    W.equipped:SetWidth(210)
    at(label(frame, L["Candidate"], "GameFontDisableSmall"), 240, -82)
    W.candidate = at(label(frame, "", "GameFontHighlight"), 240, -96)
    W.candidate:SetWidth(210)

    -- The stat table.
    local cols = { 14, 210, 290, 380 }
    local heads = { L["Stat"], L["Equipped"], L["Candidate"], L["Change"] }
    for i, h in ipairs(heads) do at(label(frame, h, "GameFontNormalSmall"), cols[i], -124) end
    W.rows = {}
    for i = 1, GG.CompareView.MAX_ROWS do
        local y = -142 - (i - 1) * 17
        local r = {}
        for c = 1, 4 do r[c] = at(label(frame, "", "GameFontHighlightSmall"), cols[c], y) end
        r[1]:SetWidth(190)
        W.rows[i] = r
    end
    W.score = {}
    for c = 1, 4 do W.score[c] = at(label(frame, "", "GameFontHighlight"), cols[c], -352) end
    W.scoreNote = at(label(frame, L["Scores on the same profile scale."], "GameFontDisableSmall"), 14, -370)
    W.status = at(label(frame, "", "GameFontNormal"), 14, -392)
    W.status:SetWidth(440)
    W.info = {}
    for i = 1, 4 do
        local y = -416 - (i - 1) * 15
        W.info[i] = { at(label(frame, "", "GameFontDisableSmall"), 14, y), at(label(frame, "", "GameFontHighlightSmall"), 90, y) }
        W.info[i][2]:SetWidth(370)
    end
    W.warnings = at(label(frame, "", "GameFontHighlightSmall"), 14, -480)
    W.warnings:SetWidth(440)

    -- A spec with no recorded gear: choose a saved set.
    W.noBase = at(label(frame, "", "GameFontNormal"), 14, -520)
    W.noBase:SetWidth(440)
    W.sets = {}
    for i = 1, Win.MAX_SETS do
        local b = button(frame, "", 105, function(self) Win.ChooseSet(self.setName) end)
        at(b, 14 + (i - 1) * 110, -540)
        W.sets[i] = b
    end

    W.viewProfile = at(button(frame, L["View profile"], 120, function() GG.ProfilesWindow.Open(state.spec) end), 14, -570)
    W.close = at(button(frame, L["Close"], 90, function() frame:Hide() end), 366, -570)

    GG.Callbacks.Register("EvaluationReady", function(_, p)
        if frame:IsShown() and p and p.requestId == state.requestId then
            state.response, state.requestId = p.response, nil
            Win.Render()
        end
    end, "GlassGear.CompareWindow")
    GG.Callbacks.Register("EvaluationInvalidated", function()
        if frame:IsShown() and state.ref then evaluate(); Win.Render() end
    end, "GlassGear.CompareWindow")
end

function Win.SelectSpec(spec)
    state.spec = spec
    Win.Render()
end

function Win.ChooseSet(name)
    if not (state.spec and name) then return end
    local ok, msg = GG.Capture.MapSet(state.spec, name)
    W.message = msg
    if not ok then W.noBase:SetText(msg) end
end

function Win.Render()
    if not (frame and state.response) then return end
    local spec = state.spec
    for _, b in ipairs(W.specs) do
        fill(b, b.specKey == spec and UIW.COLORS.selected or UIW.COLORS.plain)
    end
    local r = resultFor(spec) or { status = "unknown", reasons = { "NO_RESULT" }, limitations = {} }
    local link = GG.Compat.ResolveItemRef(state.ref)
    -- What it replaces only when a configuration was compared: a result
    -- without one (no weights, ineligible, a slot not known) never shows an
    -- empty slot or deltas against zeros (CompareView: replaced = nil).
    local replaced = r.replaces and {} or nil
    for _, s in ipairs(r.replaces and r.replaces.items or {}) do replaced[#replaced + 1] = itemData(s) end
    local s = GG.Data.Classes.Spec(spec)
    local cand = itemData(link)
    cand.name = GG.Compat.ItemName(link) or "?"
    local view = GG.CompareView.Build(r, {
        specKey = spec, specName = s and s.name or spec, current = spec == GG.currentSpec,
        candidate = cand,
        companion = r.replaces and r.replaces.companion and itemData(r.replaces.companion) or nil,
        replaced = replaced,
        profile = GG.Profiles.Active(GG.store, GG.player.key, spec),
        setWarnings = GG.db.settings.setBonusWarnings ~= false,
    })
    -- The gear line: short (the long hint is /gg's).
    local status, kind = GG.Capture.Status(spec, time())
    if kind == "none" then status = L["none recorded (compared with your current gear)"] end
    W.baseline:SetText(L["%s gear: %s"]:format(s and s.name or spec, status))
    W.equipped:SetText(view.equipped)
    W.candidate:SetText(view.candidate)
    for i, row in ipairs(W.rows) do
        local v = view.rows[i]
        row[1]:SetText(v and v.label or "")
        row[2]:SetText(v and v.equipped or "")
        row[3]:SetText(v and v.candidate or "")
        row[4]:SetText(v and v.change or "")
        if v then color(row[1], v.level == "muted" and "muted" or "white"); color(row[4], v.level) end
    end
    local sc = view.score
    W.score[1]:SetText(sc and L["Item score"] or "")
    W.score[2]:SetText(sc and sc.equipped or "")
    W.score[3]:SetText(sc and sc.candidate or "")
    W.score[4]:SetText(sc and sc.change or "")
    if sc then color(W.score[4], sc.level) end
    W.status:SetText(view.status and view.status.text or "")
    color(W.status, view.status and view.status.level or "muted")
    for i, line in ipairs(W.info) do
        local v = view.info[i]
        line[1]:SetText(v and L["%s:"]:format(v.label) or "")
        line[2]:SetText(v and v.text or "")
    end
    W.warnings:SetText(table.concat(view.warnings, "\n"))
    color(W.warnings, "warn")

    W.noBase:SetShown(view.noBaseline)
    W.noBase:SetText(view.noBaseline
        and L["No %s equipment recorded: compared with your current gear (estimate). Use a saved set:"]:format(s and s.name or spec)
        or "")
    local sets = view.noBaseline and GG.Compat.EquipmentSets() or {}
    for i, b in ipairs(W.sets) do
        local set = sets and sets[i]
        b.setName = set and set.name
        b:SetText(set and set.name or "")
        b:SetShown(set ~= nil)
    end
    W.view = view
end

-- Returns true | false, reason.
function Win.Open(ref, spec)
    if not (GG.player and GG.store and GG.API.IsReady()) then return false, L["not ready"] end
    if not frame then
        local ok, err = pcall(build)
        if not ok then
            frame = nil
            geterrorhandler()("GlassGear compare window: " .. tostring(err))
            return false, L["build failed"]
        end
    end
    state.ref = ref
    state.spec = spec or (GG.currentSpec ~= "UNKNOWN" and GG.currentSpec) or GG.Data.Classes.Specs(GG.player.class)[1].key
    evaluate()
    if frame:IsShown() then Win.Render() else frame:Show() end
    return true
end

-- Test seams.
function Win._Frame() return frame end
function Win._Reset()
    if frame then frame:Hide() end
    frame = nil
    for k in pairs(W) do W[k] = nil end
end
Win._W = W
Win._state = state

return Win
