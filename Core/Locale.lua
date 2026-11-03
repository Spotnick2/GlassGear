------------------------------------------------------------
-- Locale.lua - the player-facing text (GG-403).
--
-- Every string the player reads goes through GG.L, keyed by its English
-- text: L["Not an upgrade for %s"]:format(spec). A missing translation is
-- the English key itself, so the addon never shows a blank or a key name.
-- Text built from parts is one format string, so a translation can order
-- the parts its own way.
--
--   GG.L[english]                    the client language's text, or english
--   GG.Locale.Register(locale, t)    t = { [english] = translation }; kept
--                                    only for the client's locale
--   GG.Locale.current                GetLocale() (dump :4982), "enUS" without it
--
-- A translation whose %-specifiers differ from its key's (count or kind) is
-- dropped at registration, never formatted: a bad translation can't break
-- a format call. Comparisons never read these strings (they are
-- locale-independent: GetItemStats keys, Pawn tokens, reason codes).
--
-- Locales/enUS.lua is the catalogue of every key (the translators'
-- template, not loaded); tests/test_locale.lua keeps it in step with the
-- code. Translations go in Locales/<locale>.lua, listed in the TOC.
------------------------------------------------------------

local GG = GlassGear
local Locale = {}
GG.Locale = Locale

local getLocale = rawget(_G, "GetLocale")
Locale.current = type(getLocale) == "function" and getLocale() or "enUS"

local strings = {}

GG.L = setmetatable({}, {
    __index = function(_, key) return strings[key] or key end,
    __newindex = function(_, key) error("GlassGear: GG.L is read-only (" .. tostring(key) .. ")", 2) end,
})

-- The %-specifiers of a format string, in order ("%%" is a literal).
function Locale.Specifiers(s)
    local out = {}
    for spec in s:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*([%a])") do out[#out + 1] = spec end
    return table.concat(out)
end

-- Returns the number of translations kept, and the keys dropped.
function Locale.Register(locale, t)
    if locale ~= Locale.current or type(t) ~= "table" then return 0, {} end
    local kept, dropped = 0, {}
    for key, text in pairs(t) do
        if type(key) == "string" and type(text) == "string" and text ~= ""
            and Locale.Specifiers(key) == Locale.Specifiers(text) then
            strings[key] = text
            kept = kept + 1
        else
            dropped[#dropped + 1] = tostring(key)
        end
    end
    table.sort(dropped)
    return kept, dropped
end

-- Test seam: forget every translation (and optionally act as another locale).
function Locale._Reset(locale)
    for k in pairs(strings) do strings[k] = nil end
    if locale then Locale.current = locale end
end

return Locale
