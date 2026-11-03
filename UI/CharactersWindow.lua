------------------------------------------------------------
-- UI/CharactersWindow.lua - the characters page (GG-204, mockup 06): the
-- player's own characters across their WoW accounts, from AltStable
-- (GG-201), with the specs disenchant protection tracks for each, how fresh
-- each character's gear is, and which specs have no weights.
--
-- /gg characters, or the settings page's button. The tracked specs are
-- Prefs' (the protection scope, adr/0006); alts are opted in, the current
-- character's specs are tracked by default. Pairing and sync stay
-- AltStable's: "Open AltStable", never a second pairing UI.
------------------------------------------------------------

local GG = GlassGear
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

local function age(seconds)
    local d = math.floor(seconds / 86400)
    if d >= 1 then return d .. (d == 1 and " day" or " days") end
    local h = math.floor(seconds / 3600)
    if h >= 1 then return h .. " h" end
    return "minutes"
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
    for _, c in ipairs(chars) do
        if c.current or c.provenance == "self" then
            local g = group("self", "This account")
            g.chars[#g.chars + 1] = c
            -- The label of any of its characters (the current one has none of its own).
            if c.account and c.account ~= "" and g.title == "This account" then
                g.title = "This account (Account " .. c.account .. ")"
            end
        else
            local k = (c.account and c.account ~= "") and ("acct:" .. c.account) or "other"
            local g = group(k, (c.account and c.account ~= "") and ("Account " .. c.account) or "Your other account")
            g.chars[#g.chars + 1] = c
        end
    end
    -- "This account" comes first: Characters() lists the current character first.
    return groups
end

-- The status line of a character: its gear's freshness, and its weights.
function Win.StatusOf(c, now)
    local level, text
    if c.current then
        level, text = "ok", "Gear: what you wear now"
    else
        local gear = GG.Integrations.RosterProvider.Gear(c.guid)
        local at = gear and gear.capturedAt
        if not at then
            level, text = "muted", "No gear recorded: play this character once"
        elseif now - at >= GG.Baselines.STALE_AFTER then
            level, text = "warn", "Gear snapshot " .. age(now - at) .. " old: refresh by playing this character"
        else
            level, text = "ok", "Gear " .. age(now - at) .. " ago"
        end
    end
    local withWeights = 0
    local specs = GG.Data.Classes.Specs(c.class or "")
    for _, s in ipairs(specs) do
        if GG.Profiles.Active(GG.store, c.key, s.key) then withWeights = withWeights + 1 end
    end
    local weights = withWeights == 0 and "no weights" or (withWeights .. " of " .. #specs .. " specs with weights")
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
    local keys = {}
    for _, x in ipairs(row.specs) do keys[#keys + 1] = x.key end
    GG.Prefs.SetTracked(c.key, s.key, on, keys)
    Win.Refresh()
end

local function build()
    frame = UIW.New({ name = Win.NAME, key = "characters", width = Win.W, height = Win.H,
        title = "Glass Gear \194\183 Characters", onShow = function() Win.Refresh() end, offsetX = -300 })
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
    W.child = CreateFrame("Frame", nil, scroll)
    W.child:SetSize(Win.W - 50, 100)
    scroll:SetScrollChild(W.child)
    W.rows, W.heads = {}, {}
    W.note = at(label(frame, "Disenchant protection keeps upgrades for the ticked specs. "
        .. "Synced data does not guarantee an item can be transferred.", "GameFontDisableSmall"), 14, -(Win.H - 92))
    W.note:SetWidth(Win.W - 28)
    W.footer = at(label(frame, "Sync managed by AltStable", "GameFontHighlightSmall"), 14, -(Win.H - 58))
    W.openAltStable = at(button(frame, "Open AltStable", 140, function()
        GG.Integrations.RosterProvider.OpenAltStable()
    end), Win.W - 154, -(Win.H - 62))
    GG.Callbacks.Register("RosterChanged", function() if frame:IsShown() then Win.Refresh() end end, "GlassGear.CharactersWindow")
    GG.Callbacks.Register("ProfilesChanged", function() if frame:IsShown() then Win.Refresh() end end, "GlassGear.CharactersWindow")
end

function Win.Refresh()
    if not (frame and GG.player) then return end
    local st = GG.Integrations.RosterProvider.Status()
    local usable = st.present and st.usable
    W.status:SetText(usable and "AltStable connected" or "AltStable unavailable")
    color(W.status, usable and "ok" or "muted")
    W.unavailable:SetShown(not usable)
    W.unavailable:SetText(usable and "" or ("Current-character comparisons still work. Alt suggestions need AltStable"
        .. (st.present and (" (" .. tostring(st.reason) .. ")") or "") .. "."))
    W.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, usable and -60 or -100)
    UIW.Dim(W.openAltStable, not usable)

    local now = time()
    local chars = GG.Integrations.RosterProvider.Characters(GG.player)
    local y, n, h = 0, 0, 0
    for _, head in ipairs(W.heads) do head:Hide() end
    for _, g in ipairs(Win.Groups(chars)) do
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
            if n >= Win.MAX_ROWS then break end
            n = n + 1
            local row = W.rows[n] or buildRow(n)
            row:SetPoint("TOPLEFT", W.child, "TOPLEFT", 0, -y)
            row.char = c
            row.specs = GG.Data.Classes.Specs(c.class or "")
            row.name:SetText(tostring(c.name) .. (c.current and "  (you)" or "") .. (c.hidden and "  (hidden in AltStable)" or ""))
            color(row.name, c.hidden and "muted" or "warn")
            local className = GG.ProfileView.ClassLabel(c.class or "?")
            row.sub:SetText("Level " .. tostring(c.level or "?") .. " " .. className
                .. (c.provenance == "own-account" and c.provenanceVia and (" \194\183 seen by " .. c.provenanceVia) or ""))
            local text, level = Win.StatusOf(c, now)
            row.status:SetText(text)
            color(row.status, level)
            for j, cb in ipairs(row.checks) do
                local s = row.specs[j]
                cb:SetShown(s ~= nil)
                cb.label:SetShown(s ~= nil)
                if s then
                    cb.label:SetText(s.name)
                    cb:SetChecked(GG.Prefs.IsTracked(c.key, s.key))
                    UIW.Dim(cb, GG.readOnly)
                end
            end
            row:Show()
            y = y + Win.ROW_H
        end
    end
    for i = n + 1, #W.rows do W.rows[i]:Hide() end
    W.child:SetHeight(math.max(100, y))
    W.count = n
end

-- Returns true | false, reason.
function Win.Open()
    if not (GG.player and GG.store) then return false, "not ready" end
    if not frame then
        local ok, err = pcall(build)
        if not ok then
            frame = nil
            geterrorhandler()("GlassGear characters window: " .. tostring(err))
            return false, "build failed"
        end
    end
    if frame:IsShown() then Win.Refresh() else frame:Show() end
    return true
end

-- Test seams.
function Win._Frame() return frame end
Win._W = W

return Win
