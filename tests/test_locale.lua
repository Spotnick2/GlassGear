------------------------------------------------------------
-- test_locale.lua - GG-403: the player's text goes through GG.L.
--
--   * GG.L: a missing translation is the English key; read-only; only the
--     client's locale registers; a translation whose %-specifiers differ
--     from its key's is dropped, never formatted;
--   * the code's keys are literal (L["..."], never L[variable]) and
--     Locales/enUS.lua lists exactly them (Tools/locale_catalogue.py);
--   * every translation file in the TOC loads right after Core\Locale.lua
--     and uses catalogue keys only;
--   * a pseudo-locale translating every key reaches the player's screens:
--     /gg, the tooltip, the windows, the settings page - and nothing breaks.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

------------------------------------------------------------
-- GG.L itself.
------------------------------------------------------------
GlassGear = nil
dofile("Core/Init.lua")
dofile("Core/Locale.lua")
local GG = GlassGear
local L, Locale = GG.L, GG.Locale
H.eq(Locale.current, "enUS", "the client's locale (GetLocale)")
H.eq(L["Not an upgrade for %s"], "Not an upgrade for %s", "no translation: the English key")
H.check(not pcall(function() L["x"] = "y" end), "GG.L is read-only")
H.eq((Locale.Register("deDE", { ["Close"] = "Schlie\195\159en" })), 0, "another locale's translations are ignored")
H.eq(L["Close"], "Close", "...English stays")
Locale._Reset("deDE")
local kept, dropped = Locale.Register("deDE", {
    ["Close"] = "Schlie\195\159en",
    ["Not an upgrade for %s"] = "Kein Upgrade f\195\188r %s",
    ["%d of %d specs with weights"] = "%d von %s Spezialisierungen",   -- %d -> %s: dropped
    ["Gear %s ago"] = "Ausr\195\188stung vor",                            -- a specifier lost: dropped
    ["Empty"] = "",                                                        -- empty: dropped
})
H.eq(kept, 2, "the client's locale registers")
H.eq(table.concat(dropped, "|"), "%d of %d specs with weights|Empty|Gear %s ago", "...a changed specifier or an empty text is dropped")
H.eq(L["Not an upgrade for %s"]:format("Schatten"), "Kein Upgrade f\195\188r Schatten", "a translated format string")
H.eq(L["Gear %s ago"]:format("2 h"), "Gear 2 h ago", "a dropped translation formats as English, never errors")
H.eq(Locale.Specifiers("%s: %+.1f%% (%d)"), "sfd", "specifiers, %% excluded")
Locale._Reset("enUS")

------------------------------------------------------------
-- The keys in the code and the catalogue.
------------------------------------------------------------
local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end

local function codeFiles()
    local out = {}
    for _, file in ipairs(H.tocFiles()) do
        local rel = file:gsub("\\", "/")
        if not rel:match("^Locales/") and rel ~= "Core/Locale.lua" then out[#out + 1] = rel end
    end
    return out
end

-- Every L["..."] key of a source, decoded (Lua escapes), in order.
local function keysIn(src)
    local keys, i = {}, 1
    while true do
        local s, e = src:find('L%["', i)
        if not s then return keys end
        local prev = s > 1 and src:sub(s - 1, s - 1) or " "
        if prev:match("[%w_]") then
            i = e + 1
        else
            local j = e + 1
            while src:sub(j, j) ~= '"' do
                if src:sub(j, j) == "\\" then j = j + 2 else j = j + 1 end
            end
            local raw = src:sub(e + 1, j - 1)
            if src:sub(j + 1, j + 1) == "]" then keys[#keys + 1] = assert(loadstring('return "' .. raw .. '"'))() end
            i = j + 1
        end
    end
end

local used, usedIn, total = {}, {}, 0
for _, rel in ipairs(codeFiles()) do
    local src = read(rel)
    for _, k in ipairs(keysIn(src)) do
        if not used[k] then used[k] = true; usedIn[k] = rel; total = total + 1 end
    end
    -- A key is always literal: never L[name], L[a .. b], L[[...]].
    local code = src:gsub("%-%-[^\n]*", "")
    for pos, nextChar in code:gmatch("()[^%w_]L%[(.)") do
        H.check(nextChar == '"', rel .. ": a literal key (L[\"...\"]) at byte " .. pos)
    end
end
H.check(total > 100, "the player's text goes through GG.L (" .. total .. " keys)")

local catalogue = dofile("Locales/enUS.lua")
local inCatalogue, dup = {}, 0
for _, k in ipairs(catalogue) do
    if inCatalogue[k] then dup = dup + 1 end
    inCatalogue[k] = true
end
H.eq(dup, 0, "the catalogue lists each key once")
local missing, extra = {}, {}
for k in pairs(used) do if not inCatalogue[k] then missing[#missing + 1] = k .. " (" .. usedIn[k] .. ")" end end
for k in pairs(inCatalogue) do if not used[k] then extra[#extra + 1] = k end end
table.sort(missing); table.sort(extra)
H.eq(#missing, 0, "every key in the code is in Locales/enUS.lua (python -I Tools/locale_catalogue.py)"
    .. (missing[1] and (": " .. missing[1]) or ""))
H.eq(#extra, 0, "the catalogue holds no key the code doesn't use" .. (extra[1] and (": " .. extra[1]) or ""))

-- Translation files: listed right after Core\Locale.lua, catalogue keys only.
local toc = H.tocFiles()
local afterLocale = false
for i, file in ipairs(toc) do
    if file == "Core\\Locale.lua" then afterLocale = i end
end
H.check(afterLocale ~= false, "Core\\Locale.lua is in the TOC")
H.eq(toc[afterLocale - 1], "Core\\Init.lua", "...right after the namespace")
for i, file in ipairs(toc) do
    if file:match("^Locales\\") then
        H.check(i > afterLocale, file .. " loads after Core\\Locale.lua")
        H.check(file ~= "Locales\\enUS.lua", "the catalogue is never loaded")
        local captured
        local realRegister = Locale.Register
        Locale.Register = function(locale, t) captured = t; return 0, {} end
        dofile((file:gsub("\\", "/")))
        Locale.Register = realRegister
        for k, text in pairs(captured or {}) do
            H.check(inCatalogue[k] == true, file .. ": a catalogue key: " .. tostring(k))
            H.eq(Locale.Specifiers(text), Locale.Specifiers(k), file .. ": same specifiers: " .. tostring(k))
        end
    end
end

------------------------------------------------------------
-- A pseudo-locale reaches the player's screens.
------------------------------------------------------------
local OPEN, CLOSE = "\194\171", "\194\187"     -- << >>
-- Upper-case outside %-specifiers and |c/|r escapes, between << >>: no
-- English survives, so code that still matches English text fails here.
local function shout(k)
    local out, i = {}, 1
    while i <= #k do
        local s, e = k:find("^%%%%", i)
        if not s then s, e = k:find("^%%[%-%+ #0]*%d*%.?%d*%a", i) end
        if not s then s, e = k:find("^|c%x%x%x%x%x%x%x%x", i) end
        if not s then s, e = k:find("^|[rn]", i) end
        if s then
            out[#out + 1] = k:sub(s, e)
            i = e + 1
        else
            out[#out + 1] = k:sub(i, i):upper()
            i = i + 1
        end
    end
    return OPEN .. table.concat(out) .. CLOSE
end
local pseudo = {}
for _, k in ipairs(catalogue) do pseudo[k] = shout(k) end

GlassGear = nil
WoW.reset()
WoW.locale = "xxXX"
local INT = "ITEM_MOD_INTELLECT_SHORT"
WoW.items[50] = { name = "Old Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = { [INT] = 10 } }
WoW.items[51] = { name = "New Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = { [INT] = 20 } }
WoW.equipped[3] = 50
WoW.bags[0] = { [1] = { itemID = 51, isBound = true } }
GG = WoW.loadAddon({ afterFile = function(file)
    if file == "Core\\Locale.lua" then
        local n = GlassGear.Locale.Register("xxXX", pseudo)
        H.eq(n, #catalogue, "(the pseudo-locale registers every key)")
    end
end })
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1 )')
WoW.flush()
local function translated(text) return type(text) == "string" and text:find(OPEN, 1, true) ~= nil end

SlashCmdList.GLASSGEAR("")
H.check(translated(WoW.chat()), "/gg prints the translations")
local tip = WoW.newTooltip("GameTooltip")
WoW.showItem(tip, { type = 0, id = 51, hyperlink = WoW.link(51) })
local anyTip = false
for _, l in ipairs(tip.lines) do if translated(l.left) or translated(l.right) then anyTip = true end end
H.check(anyTip, "the tooltip rows are translated")
SlashCmdList.GLASSGEAR("compare " .. WoW.link(51))
H.check(translated(GG.CompareWindow._Frame().titleText:GetText()), "the compare window title is translated")
H.check(translated(GG.CompareWindow._W.status:GetText()), "...and its verdict")
SlashCmdList.GLASSGEAR("profiles")
H.check(translated(GG.ProfilesWindow._Frame().titleText:GetText()), "the profiles window title is translated")
local armor = GG.ProfilesWindow._W.armorDefault.label:GetText()
H.check(armor:find(pseudo["Cloth"], 1, true) ~= nil and not armor:find("SPEC DEFAULT)", 1, true),
    "the armor default label holds the translated armor alone, never a stripped English note: " .. armor)
H.eq(GG.ProfileView.ClassLabel("PRIEST"), "Priest", "an export's Class= stays English")
SlashCmdList.GLASSGEAR("compare " .. WoW.link(51))
GG.CompareWindow.SelectSpec("PRIEST.HOLY")
H.eq(GG.CompareWindow._W.baseline:GetText(),
    pseudo["%s gear: %s"]:format(pseudo["Holy"], pseudo["none recorded (compared with your current gear)"]),
    "no Holy gear recorded: the short line, decided by the status kind, not by English text")
rawset(_G, "LOCALIZED_CLASS_NAMES_MALE", { PRIEST = "Pr\195\170tre" })
SlashCmdList.GLASSGEAR("characters")
H.check(translated(GG.CharactersWindow._W.status:GetText()), "the characters page is translated")
local me
for _, r in ipairs(GG.CharactersWindow._W.rows) do if r:IsShown() and r.char and r.char.current then me = r end end
H.check(me and me.sub:GetText():find("Pr\195\170tre", 1, true) ~= nil, "...class names in the client's language")
rawset(_G, "LOCALIZED_CLASS_NAMES_MALE", nil)
H.eq(#WoW.errors, 0, "nothing breaks in another language" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
H.eq(GG.API.Evaluate({ item = WoW.link(51), scope = "current" }).results[1].status, "upgrade",
    "comparisons don't read the text: still an upgrade")

H.done("test_locale")
