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
-- A translation whose %-specifiers differ from its key's (count or kind), or
-- that string.format would refuse (a stray "%"), is dropped at
-- registration, never formatted: a bad translation can't break a format
-- call. Comparisons never read these strings (they are
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

-- The %-specifiers of a format string, in order ("%%" is a literal), or nil
-- when string.format would refuse it: every "%" must start "%%" or a whole
-- conversion Lua 5.1 accepts (at most 5 flags, 2-digit width and precision,
-- lstrlib.c's c d i o u x X e E f g G q s). "100% (%s)" is nil, not "s".
local CONVERSIONS = "[cdiouxXeEfgGqs]"
function Locale.Specifiers(s)
    if type(s) ~= "string" then return nil end
    local out, i = {}, 1
    while true do
        local p = s:find("%", i, true)
        if not p then return table.concat(out) end
        if s:sub(p + 1, p + 1) == "%" then
            i = p + 2
        else
            local flags, width, dot, prec, conv = s:match("^%%([%-%+ #0]*)(%d*)(%.?)(%d*)(.?)", p)
            if #flags > 5 or #width > 2 or #prec > 2 or (dot == "" and prec ~= "")
                or conv == "" or not conv:match(CONVERSIONS) then
                return nil
            end
            out[#out + 1] = conv
            i = p + 1 + #flags + #width + #dot + #prec + 1
        end
    end
end

-- Returns the number of translations kept, and the keys dropped.
function Locale.Register(locale, t)
    if locale ~= Locale.current or type(t) ~= "table" then return 0, {} end
    local kept, dropped = 0, {}
    for key, text in pairs(t) do
        local spec = type(key) == "string" and Locale.Specifiers(key)
        if spec and type(text) == "string" and text ~= "" and Locale.Specifiers(text) == spec then
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
