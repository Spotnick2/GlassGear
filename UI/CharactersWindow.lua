------------------------------------------------------------
-- UI/CharactersWindow.lua - the characters page (GG-204, mockup 06): the
-- player's own characters across their WoW accounts, from AltStable
-- (GG-201), with the specs disenchant protection tracks for each, how fresh
-- each character's gear is, and which specs have no weights.
--
-- /gg characters, or the settings page's button. The tracked specs are
-- Prefs' (the protection scope, adr/0006); alts are opted in, the current
-- character's specs are tracked by default. Until protection can assess an
-- alt (GG-203: alt rows), an alt's boxes are shown dimmed and can't be
-- ticked, and the page says so: a tick must never promise protection that
-- doesn't happen. Pairing and sync stay AltStable's: "Open AltStable",
-- never a second pairing UI.
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
local Win = {}
GG.CharactersWindow = Win

Win.NAME = "GlassGearCharactersFrame"
Win.W, Win.H = 520, 520
Win.ROW_H = 58
Win.MAX_ROWS = 24
Win.SPECS_MAX = 4

local UIW = GG.Window
local label, button, color = UIW.Label, UIW.Button, UIW.Color
local frame
local W = {}

local function at(region, x, y, parent)
    region:SetPoint("TOPLEFT", parent or frame, "TOPLEFT", x, y)
    return region
end

-- Can disenchant protection keep an alt's upgrades? Only once evaluations
-- have alt rows (GG-203: the API's `alts` feature); until then it assesses
-- the current character's tracked specs alone.
function Win.AltProtectionActive()
    local ok, caps = pcall(GG.API.GetCapabilities)
    return ok and type(caps) == "table" and caps.features and caps.features.alts == true or false
end

Win.NOTE_ACTIVE = L["Disenchant protection keeps upgrades for the ticked specs. Synced data does not guarantee an item can be transferred."]
Win.NOTE_ALTS_INACTIVE = L["Disenchant protection keeps upgrades for this character's ticked specs; alts can't be protected yet. Synced data does not guarantee an item can be transferred."]

local function age(seconds)
    local d = math.floor(seconds / 86400)
    if d >= 1 then return d == 1 and L["%d day"]:format(d) or L["%d days"]:format(d) end
    local h = math.floor(seconds / 3600)
    if h >= 1 then return L["%d h"]:format(h) end
    return L["minutes"]
end

-- The groups to show: this account first, then each other account (by its
-- AltStable label, display only: ownership is the provenance).
function Win.Groups(chars)
    local groups, byKey = {}, {}
    local function group(key, title)
        if not byKey[key] then
            byKey[key] = { title = title, chars = {} }
            groups[#groups + 1] = byKey[key]
        end
        return byKey[key]
    end
    local selfLabel
    for _, c in ipairs(chars) do
        if (c.current or c.provenance == "self") and c.account and c.account ~= "" then selfLabel = c.account end
    end
    for _, c in ipairs(chars) do
        if c.current or c.provenance == "self" then
            local g = group("self", selfLabel and L["This account (Account %s)"]:format(selfLabel) or L["This account"])
            g.chars[#g.chars + 1] = c
        else
            -- The label is the player's free text: it names a group, it never
            -- proves one. Unlabelled, or labelled like this account, they share
            -- one honest heading.
            local label = c.account
            local named = label and label ~= "" and label ~= selfLabel
            local g = group(named and ("acct:" .. label) or "other",
                named and L["Account %s"]:format(label) or L["Your other accounts"])
            g.chars[#g.chars + 1] = c
        end
    end
    -- "This account" comes first: Characters() lists the current character first.
    return groups
end

-- The status line of a character: its gear's freshness, and its weights.
function Win.StatusOf(c, now, usable)
    local level, text
    if c.current then
        level, text = "ok", L["Gear: what you wear now"]
    else
        local gear = GG.Integrations.RosterProvider.Gear(c.guid, usable)
        local at = gear and gear.capturedAt
        if not at then
            level, text = "muted", L["No gear recorded: play this character once"]
        elseif now - at >= GG.Baselines.STALE_AFTER then
            level, text = "warn", L["Gear snapshot %s old: refresh by playing this character"]:format(age(now - at))
        else
            level, text = "ok", L["Gear %s ago"]:format(age(now - at))
        end
    end
    local withWeights = 0
    local specs = GG.Data.Classes.Specs(c.class or "")
    for _, s in ipairs(specs) do
        if GG.Profiles.Active(GG.store, c.key, s.key) then withWeights = withWeights + 1 end
    end
    local weights = withWeights == 0 and L["no weights"] or L["%d of %d specs with weights"]:format(withWeights, #specs)
    return text .. " \194\183 " .. weights, level
end

local function buildRow(i)
    local row = CreateFrame("Frame", nil, W.child)
    row:SetSize(Win.W - 50, Win.ROW_H)
    row.name = label(row, "", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
    row.sub = label(row, "", "GameFontHighlightSmall")
    row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -20)
    row.status = label(row, "", "GameFontHighlightSmall")
    row.status:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -38)
    row.status:SetWidth(Win.W - 60)
    row.checks = {}
    for j = 1, Win.SPECS_MAX do
        local cb = UIW.CheckButton(row, "", function(self) Win.SetTracked(row, j, self:GetChecked() and true or false) end)
        cb:SetPoint("TOPLEFT", row, "TOPLEFT", 170 + ((j - 1) % 2) * 150, -2 - math.floor((j - 1) / 2) * 18)
        row.checks[j] = cb
    end
    W.rows[i] = row
    return row
end

function Win.SetTracked(row, j, on)
    local c = row.char
    local s = c and row.specs[j]
    if not s then return end
    if not c.current and not Win.AltProtectionActive() then Win.Refresh(); return end
    local keys = {}
    for _, x in ipairs(row.specs) do keys[#keys + 1] = x.key end
    GG.Prefs.SetTracked(c.key, s.key, on, keys)
    Win.Refresh()
end

local function build()
    frame = UIW.New({ name = Win.NAME, key = "characters", width = Win.W, height = Win.H,
        title = L["Glass Gear \194\183 Characters"], onShow = function() Win.Refresh() end, offsetX = -300 })
    W.status = at(label(frame, "", "GameFontHighlight"), 14, -34)
    W.status:SetWidth(Win.W - 28)
    W.unavailable = at(label(frame, "", "GameFontHighlight"), 14, -60)
    W.unavailable:SetWidth(Win.W - 28)
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetSize(Win.W - 44, Win.H - 160)
    at(scroll, 12, -60)
    if not scroll.ScrollBar then
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
        end)
    end
    W.scroll = scroll
    W.more = at(label(frame, "", "GameFontDisableSmall"), 14, -(Win.H - 106))
    W.child = CreateFrame("Frame", nil, scroll)
    W.child:SetSize(Win.W - 50, 100)
    scroll:SetScrollChild(W.child)
    W.rows, W.heads = {}, {}
    W.note = at(label(frame, Win.NOTE_ALTS_INACTIVE, "GameFontDisableSmall"), 14, -(Win.H - 92))
    W.note:SetWidth(Win.W - 28)
    W.footer = at(label(frame, L["Sync managed by AltStable"], "GameFontHighlightSmall"), 14, -(Win.H - 58))
    W.openAltStable = at(button(frame, L["Open AltStable"], 140, function()
        local ok, why = GG.Integrations.RosterProvider.OpenAltStable()
        if not ok then W.footer:SetText(why); color(W.footer, "warn") end
    end), Win.W - 154, -(Win.H - 62))
    -- Follow whatever changes what the page shows: the roster, weights,
    -- tracked specs set elsewhere (settings, Defaults), an alt's gear.
    local function follow() if frame:IsShown() then Win.Refresh() end end
    for _, event in ipairs({ "RosterChanged", "ProfilesChanged", "EvaluationInvalidated", "EquipmentChanged" }) do
        GG.Callbacks.Register(event, follow, "GlassGear.CharactersWindow")
    end
end

function Win.Refresh()
    if not (frame and GG.player) then return end
    local RP = GG.Integrations.RosterProvider
    local st = RP.Status()
    local usable = st.present and st.usable
    if usable and st.reason then
        -- Usable, but a call failed (GetCharacters, the callbacks): never "connected".
        W.status:SetText(L["AltStable: %s"]:format(tostring(st.reason)))
        color(W.status, "warn")
    else
        W.status:SetText(usable and L["AltStable connected"] or L["AltStable unavailable"])
        color(W.status, usable and "ok" or "muted")
    end
    W.unavailable:SetShown(not usable)
    W.unavailable:SetText(usable and ""
        or st.present and L["Current-character comparisons still work. Alt suggestions need AltStable (%s)."]:format(tostring(st.reason))
        or L["Current-character comparisons still work. Alt suggestions need AltStable."])
    -- Between the header and the note, whatever the header's height.
    W.scroll:ClearAllPoints()
    W.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, usable and -60 or -100)
    W.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 112)
    -- AltStable present, even too old: its sheet is where to fix it.
    UIW.Dim(W.openAltStable, not RP.CanOpenAltStable())
    W.footer:SetText(L["Sync managed by AltStable"])
    color(W.footer, "info")
    local altProtection = Win.AltProtectionActive()
    W.note:SetText(altProtection and Win.NOTE_ACTIVE or Win.NOTE_ALTS_INACTIVE)

    local now = time()
    local chars = GG.Integrations.RosterProvider.Characters(GG.player)
    local y, n, h = 0, 0, 0
    for _, head in ipairs(W.heads) do head:Hide() end
    local hidden = 0
    for _, g in ipairs(Win.Groups(chars)) do
        if n >= Win.MAX_ROWS then
            hidden = hidden + #g.chars                 -- no empty headings past the limit
        else
        h = h + 1
        local head = W.heads[h]
        if not head then
            head = label(W.child, "", "GameFontNormal")
            W.heads[h] = head
        end
        head:SetPoint("TOPLEFT", W.child, "TOPLEFT", 4, -y)
        head:SetText(g.title)
        head:Show()
        y = y + 20
        for _, c in ipairs(g.chars) do
            if n >= Win.MAX_ROWS then hidden = hidden + 1 else
            n = n + 1
            local row = W.rows[n] or buildRow(n)
            row:SetPoint("TOPLEFT", W.child, "TOPLEFT", 0, -y)
            row.char = c
            row.specs = GG.Data.Classes.Specs(c.class or "")
            local name = tostring(c.name)
            if c.current then name = L["%s  (you)"]:format(name) end
            if c.hidden then name = L["%s  (hidden in AltStable)"]:format(name) end
            row.name:SetText(name)
            color(row.name, c.hidden and "muted" or "warn")
            local className = GG.ProfileView.ClassLabel(c.class or "?")
            local sub = L["Level %s %s"]:format(tostring(c.level or "?"), className)
            if c.provenance == "own-account" and c.provenanceVia then
                sub = L["%s \194\183 seen by %s"]:format(sub, tostring(c.provenanceVia))
            end
            row.sub:SetText(sub)
            local text, level = Win.StatusOf(c, now, usable)
            row.status:SetText(text)
            color(row.status, level)
            for j, cb in ipairs(row.checks) do
                local s = row.specs[j]
                cb:SetShown(s ~= nil)
                cb.label:SetShown(s ~= nil)
                if s then
                    cb.label:SetText(s.name)
                    cb:SetChecked(GG.Prefs.IsTracked(c.key, s.key))
                    UIW.Dim(cb, GG.readOnly or (not c.current and not altProtection))
                end
            end
            row:Show()
            y = y + Win.ROW_H
            end
        end
        end
    end
    for i = n + 1, #W.rows do W.rows[i]:Hide() end
    W.more:SetText(hidden == 0 and ""
        or hidden == 1 and L["%d more character not shown"]:format(hidden)
        or L["%d more characters not shown"]:format(hidden))
    W.hidden = hidden
    W.child:SetHeight(math.max(100, y))
    W.count = n
end

-- Returns true | false, reason.
function Win.Open()
    if not (GG.player and GG.store) then return false, L["not ready"] end
    if not frame then
        local ok, err = pcall(build)
        if not ok then
            frame = nil
            geterrorhandler()("GlassGear characters window: " .. tostring(err))
            return false, L["build failed"]
        end
    end
    if frame:IsShown() then Win.Refresh() else frame:Show() end
    return true
end

-- Test seams.
function Win._Frame() return frame end
Win._W = W

return Win
