------------------------------------------------------------
-- Engine/Codec.lua - entry data validation and the GG1 one-line codec
-- (docs/SCHEMA.md). Pure.
--
--   Codec.ValidData(kind, data) -> bool, why   (also used by EntrySync on receipt)
--   Codec.Encode(entry) -> line | nil, "too-large"|"bad-entry"
--   Codec.Decode(line)  -> entry | nil, "unknown-schema"|"bad-entry"
------------------------------------------------------------

local GG = GlassGear
local Codec = {}
GG.Engine.Codec = Codec

Codec.MAX_BYTES = 2048
Codec.MAX_NAME = 24
Codec.MAX_TOKENS = 40
Codec.MAX_ABS = 999.999
Codec.SOURCES = {
    profile = { ["imported-pawn"] = true, ["wowsims-pawn-ep"] = true, manual = true, default = true, ["sim-result"] = true },
    baseline = { ["equipment-set"] = true, observed = true, ["fallback-current"] = true },
}
local STATES = { occupied = true, empty = true, unknown = true }
local ITEM = "^%d+:%d+:%-?%d+$"

local function isKey(s) return type(s) == "string" and GG.Data.Classes.Spec(s) ~= nil end
local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end

------------------------------------------------------------
-- Validation (every field; a failure rejects the whole entry)
------------------------------------------------------------
function Codec.ValidData(kind, d)
    if type(d) ~= "table" then return false, "no-data" end
    if not isKey(d.specKey) then return false, "specKey" end
    if not Codec.SOURCES[kind] or not Codec.SOURCES[kind][d.source] then return false, "source" end
    if kind == "profile" then
        if type(d.name) ~= "string" or #d.name > Codec.MAX_NAME then return false, "name" end
        if d.origin ~= nil and type(d.origin) ~= "string" then return false, "origin" end
        for _, field in ipairs({ "ignored", "ignoredTokens", "missing", "armor" }) do
            if d[field] ~= nil and type(d[field]) ~= "table" then return false, field end
        end
        if not finite(d.updatedAt) then return false, "updatedAt" end
        local n = 0
        if type(d.weights) ~= "table" then return false, "weights" end
        for k, v in pairs(d.weights) do
            if not GG.Data.Stats.TOKENS[k] or not finite(v) or math.abs(v) > Codec.MAX_ABS then return false, "weight:" .. tostring(k) end
            n = n + 1
        end
        for k, v in pairs(d.ignored or {}) do
            if not GG.Data.Stats.TOKENS[k] or v ~= true then return false, "ignored" end
            n = n + 1
        end
        for k, v in pairs(d.ignoredTokens or {}) do
            if type(k) ~= "string" or not k:match("^%w+$") or type(v) ~= "string" or not v:match("^[%w%.%-]+$") then
                return false, "ignoredTokens"
            end
            n = n + 1
        end
        if n > Codec.MAX_TOKENS then return false, "too-many-tokens" end
        for _, t in ipairs(d.missing or {}) do if not GG.Data.Stats.TOKENS[t] then return false, "missing" end end
        if d.armor ~= nil then
            if type(d.armor) ~= "table" then return false, "armor" end
            for _, a in ipairs(d.armor) do if not GG.Data.Classes.ARMOR_NAME[a] then return false, "armor" end end
        end
        return true
    elseif kind == "baseline" then
        if not finite(d.capturedAt) then return false, "capturedAt" end
        if d.group ~= nil and not (d.group == 1 or d.group == 2) then return false, "group" end
        if type(d.slots) ~= "table" then return false, "slots" end
        local gear = {}
        for _, s in ipairs(GG.Data.Slots.GEAR) do gear[s] = true end
        for slot, v in pairs(d.slots) do
            if not gear[slot] or type(v) ~= "table" or not STATES[v.state] then return false, "slot" end
            if v.state == "occupied" then
                if type(v.item) ~= "string" or not v.item:match(ITEM) then return false, "slot-item" end
            elseif v.item ~= nil then
                return false, "slot-item"
            end
        end
        return true
    end
    return false, "kind"
end

------------------------------------------------------------
-- Escaping and splitting
------------------------------------------------------------
local function esc(s)
    s = tostring(s or "")
    return (s:gsub("\\", "\\\\"):gsub("|", "\\p"):gsub("\n", "\\n"):gsub(";", "\\s"):gsub(",", "\\c"):gsub("=", "\\e"))
end
local UNESC = { p = "|", n = "\n", s = ";", c = ",", e = "=" }
local function unesc(s) return (s:gsub("\\(.)", function(c) return UNESC[c] or c end)) end

local function split(s, sep)
    local out, buf, i = {}, {}, 1
    while i <= #s do
        local c = s:sub(i, i)
        if c == "\\" then buf[#buf + 1] = s:sub(i, i + 1); i = i + 2
        elseif c == sep then out[#out + 1] = table.concat(buf); buf = {}; i = i + 1
        else buf[#buf + 1] = c; i = i + 1 end
    end
    out[#out + 1] = table.concat(buf)
    return out
end
local function list(s) if s == "" then return {} end return split(s, ",") end

local function b36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    while n > 0 do
        local r = n % 36
        out = digits:sub(r + 1, r + 1) .. out
        n = math.floor(n / 36)
    end
    return out
end
local function fromB36(s) return s:match("^[0-9a-z]+$") and tonumber(s, 36) or nil end

local function weight(n)
    return (string.format("%.3f", n):gsub("0+$", ""):gsub("%.$", ""))
end
local function strictNumber(s)
    if not s:match("^%-?%d+$") and not s:match("^%-?%d+%.%d+$") then return nil end
    local n = tonumber(s)
    if not n or math.abs(n) > Codec.MAX_ABS then return nil end
    return n
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

------------------------------------------------------------
-- Payloads
------------------------------------------------------------
-- profile: specKey;name;origin;source;updatedAt;weights;ignored;ignoredTokens;missing;armor
local function encodeProfile(d)
    local w, ig, ex = {}, {}, {}
    for _, k in ipairs(sortedKeys(d.weights)) do w[#w + 1] = k .. "=" .. weight(d.weights[k]) end
    for _, k in ipairs(sortedKeys(d.ignored)) do ig[#ig + 1] = k end
    for _, k in ipairs(sortedKeys(d.ignoredTokens)) do ex[#ex + 1] = k .. "=" .. d.ignoredTokens[k] end
    local armor = {}
    for _, a in ipairs(d.armor or {}) do armor[#armor + 1] = tostring(a) end
    return table.concat({ esc(d.specKey), esc(d.name), esc(d.origin or ""), esc(d.source), b36(d.updatedAt),
        table.concat(w, ","), table.concat(ig, ","), table.concat(ex, ","), table.concat(d.missing or {}, ","),
        d.armor and ("a" .. table.concat(armor, ",")) or "" }, ";")
end

local function decodeProfile(p)
    local f = split(p, ";")
    if #f ~= 10 then return nil end
    local d = { specKey = unesc(f[1]), name = unesc(f[2]), source = unesc(f[4]), updatedAt = fromB36(f[5]),
        weights = {}, ignored = {}, ignoredTokens = {}, missing = {} }
    if f[3] ~= "" then d.origin = unesc(f[3]) end
    for _, pair in ipairs(list(f[6])) do
        local k, v = pair:match("^(%w+)=(.+)$")
        local n = v and strictNumber(v)
        if not n then return nil end
        d.weights[k] = n
    end
    for _, k in ipairs(list(f[7])) do d.ignored[k] = true end
    for _, pair in ipairs(list(f[8])) do
        local k, v = pair:match("^(%w+)=(.+)$")
        if not k then return nil end
        d.ignoredTokens[k] = v
    end
    for _, t in ipairs(list(f[9])) do d.missing[#d.missing + 1] = t end
    if f[10] ~= "" then
        if f[10]:sub(1, 1) ~= "a" then return nil end
        d.armor = {}
        for _, a in ipairs(list(f[10]:sub(2))) do
            local n = tonumber(a)
            if not n or not a:match("^%d+$") then return nil end
            d.armor[#d.armor + 1] = n
        end
    end
    return d
end

local OCC = { occupied = "o", empty = "e", unknown = "u" }
local OCC_BACK = { o = "occupied", e = "empty", u = "unknown" }

-- baseline: specKey;source;capturedAt;group;slot:code[:item],...
local function encodeBaseline(d)
    local parts = {}
    for _, slot in ipairs(sortedKeys(d.slots)) do
        local s = d.slots[slot]
        local code = OCC[s.state]
        parts[#parts + 1] = slot .. ":" .. code .. (code == "o" and (":" .. s.item) or "")
    end
    return table.concat({ esc(d.specKey), esc(d.source), b36(d.capturedAt), d.group and tostring(d.group) or "",
        table.concat(parts, ",") }, ";")
end

local function decodeBaseline(p)
    local f = split(p, ";")
    if #f ~= 5 then return nil end
    local d = { specKey = unesc(f[1]), source = unesc(f[2]), capturedAt = fromB36(f[3]), slots = {} }
    if f[4] ~= "" then
        if f[4] ~= "1" and f[4] ~= "2" then return nil end
        d.group = tonumber(f[4])
    end
    for _, part in ipairs(list(f[5])) do
        local slot, code, item = part:match("^(%d+):([oeu]):?(.*)$")
        if not slot then return nil end
        slot = tonumber(slot)
        if d.slots[slot] then return nil end
        local s = { state = OCC_BACK[code] }
        if code == "o" then s.item = item elseif item ~= "" then return nil end
        d.slots[slot] = s
    end
    return d
end

------------------------------------------------------------
-- Entries: GG1|kind|id|version|ancestors|flags|payload
-- flags (comma list): d = deleted, x = deletion conflict, r = retired copy,
-- c<root id> = conflict copy of that root.
------------------------------------------------------------
function Codec.Encode(e)
    if type(e) ~= "table" or type(e.id) ~= "string" or type(e.version) ~= "string" then return nil, "bad-entry" end
    local kind = e.kind == "profile" and "p" or e.kind == "baseline" and "b" or nil
    if not kind then return nil, "bad-entry" end
    local contentless = e.deleted or (e.conflict and e.conflict.deletion)
    local payload = ""
    if not contentless then
        if not Codec.ValidData(e.kind, e.data) then return nil, "bad-entry" end
        payload = (kind == "p" and encodeProfile or encodeBaseline)(e.data)
    end
    local flags = {}
    if e.deleted then flags[#flags + 1] = "d" end
    if e.conflict then
        flags[#flags + 1] = "c" .. esc(e.conflict.of)
        if e.conflict.deletion then flags[#flags + 1] = "x" end
        if e.conflict.retired then flags[#flags + 1] = "r" end
    end
    local anc = {}
    for i, v in ipairs(e.ancestors or {}) do
        if i > 20 then return nil, "bad-entry" end
        anc[#anc + 1] = esc(v)
    end
    local line = table.concat({ "GG1", kind, esc(e.id), esc(e.version), table.concat(anc, ","),
        table.concat(flags, ","), payload }, "|")
    if #line > Codec.MAX_BYTES then return nil, "too-large" end
    return line
end

function Codec.Decode(line)
    if type(line) ~= "string" then return nil, "bad-entry" end
    local schema = line:match("^(GG%d+)|")
    if schema ~= "GG1" then return nil, "unknown-schema" end
    local f = split(line, "|")
    if #f ~= 7 then return nil, "bad-entry" end
    local kind = f[2] == "p" and "profile" or f[2] == "b" and "baseline" or nil
    if not kind then return nil, "bad-entry" end
    local e = { id = unesc(f[3]), kind = kind, version = unesc(f[4]), ancestors = {} }
    if e.id == "" or e.version == "" then return nil, "bad-entry" end
    for _, v in ipairs(list(f[5])) do e.ancestors[#e.ancestors + 1] = unesc(v) end
    if #e.ancestors > 20 then return nil, "bad-entry" end
    for _, flag in ipairs(list(f[6])) do
        if flag == "d" then e.deleted = true
        elseif flag == "x" then e.conflict = e.conflict or {}; e.conflict.deletion = true
        elseif flag == "r" then e.conflict = e.conflict or {}; e.conflict.retired = true
        elseif flag:sub(1, 1) == "c" and #flag > 1 then e.conflict = e.conflict or {}; e.conflict.of = unesc(flag:sub(2))
        else return nil, "bad-entry" end
    end
    if e.conflict and not e.conflict.of then return nil, "bad-entry" end
    local contentless = e.deleted or (e.conflict and e.conflict.deletion)
    if contentless then
        if f[7] ~= "" then return nil, "bad-entry" end
    else
        e.data = (kind == "profile" and decodeProfile or decodeBaseline)(f[7])
        if not e.data or not Codec.ValidData(kind, e.data) then return nil, "bad-entry" end
    end
    return e
end

return Codec
