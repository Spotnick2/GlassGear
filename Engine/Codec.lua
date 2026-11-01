------------------------------------------------------------
-- Engine/Codec.lua - the GG1 one-line entry codec (docs/SCHEMA.md). Pure.
--
--   Codec.Encode(entry) -> line | nil, "too-large"|"bad-entry"
--   Codec.Decode(line)  -> entry | nil, "unknown-schema"|"bad-entry"
------------------------------------------------------------

local GG = GlassGear
local Codec = {}
GG.Engine.Codec = Codec

Codec.MAX_BYTES = 2048
Codec.MAX_NAME = 24
Codec.MAX_TOKENS = 40

local function esc(s)
    s = tostring(s or "")
    return (s:gsub("\\", "\\\\"):gsub("|", "\\p"):gsub("\n", "\\n"):gsub(";", "\\s"):gsub(",", "\\c"))
end

local UNESC = { p = "|", n = "\n", s = ";", c = "," }
local function unesc(s)
    return (s:gsub("\\(.)", function(c) return UNESC[c] or c end))
end

-- Splits on an unescaped separator character (one byte, not "\").
local function split(s, sep)
    local out, buf, i = {}, {}, 1
    while i <= #s do
        local c = s:sub(i, i)
        if c == "\\" then
            buf[#buf + 1] = s:sub(i, i + 1); i = i + 2
        elseif c == sep then
            out[#out + 1] = table.concat(buf); buf = {}; i = i + 1
        else
            buf[#buf + 1] = c; i = i + 1
        end
    end
    out[#out + 1] = table.concat(buf)
    return out
end

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

local function weight(n)
    n = math.max(-999.999, math.min(999.999, n))
    local s = string.format("%.3f", n):gsub("0+$", ""):gsub("%.$", "")
    return s
end

local function encodeProfile(d)
    if type(d.weights) ~= "table" or #(d.name or "") > Codec.MAX_NAME then return nil end
    local keys, n = {}, 0
    for k in pairs(d.weights) do keys[#keys + 1] = k end
    table.sort(keys)
    local w = {}
    for _, k in ipairs(keys) do w[#w + 1] = k .. "=" .. weight(d.weights[k]); n = n + 1 end
    local ig = {}
    for k in pairs(d.ignored or {}) do ig[#ig + 1] = k; n = n + 1 end
    table.sort(ig)
    if n > Codec.MAX_TOKENS then return nil end
    return table.concat({ esc(d.specKey), esc(d.name), esc(d.source), b36(d.updatedAt),
        table.concat(w, ","), table.concat(ig, ",") }, ";")
end

local OCC = { occupied = "o", empty = "e", unknown = "u" }
local OCC_BACK = { o = "occupied", e = "empty", u = "unknown" }

local function encodeBaseline(d)
    local slots = {}
    for slot in pairs(d.slots or {}) do slots[#slots + 1] = slot end
    table.sort(slots)
    local parts = {}
    for _, slot in ipairs(slots) do
        local s = d.slots[slot]
        local code = OCC[s.state] or "u"
        local item = (code == "o" and s.item) or ""
        if item ~= "" and not item:match("^%d+:%d*:%-?%d*$") then return nil end
        parts[#parts + 1] = slot .. ":" .. code .. (item ~= "" and (":" .. item) or "")
    end
    return table.concat({ esc(d.specKey), esc(d.source), b36(d.capturedAt), table.concat(parts, ",") }, ";")
end

function Codec.Encode(e)
    if type(e) ~= "table" or type(e.id) ~= "string" or type(e.version) ~= "string" then return nil, "bad-entry" end
    local kind = e.kind == "profile" and "p" or e.kind == "baseline" and "b" or nil
    if not kind then return nil, "bad-entry" end
    local payload = ""
    if not e.deleted then
        payload = (kind == "p" and encodeProfile or encodeBaseline)(e.data or {})
        if not payload then return nil, "bad-entry" end
    end
    local flags = (e.deleted and "d" or "") .. (e.conflict and ("c" .. esc(e.conflict.of)) or "")
    local anc = {}
    for i, v in ipairs(e.ancestors or {}) do
        if i > 20 then break end
        anc[#anc + 1] = esc(v)
    end
    local line = table.concat({ "GG1", kind, esc(e.id), esc(e.version), table.concat(anc, ","), flags, payload }, "|")
    if #line > Codec.MAX_BYTES then return nil, "too-large" end
    return line
end

local function decodeProfile(p)
    local f = split(p, ";")
    if #f ~= 6 then return nil end
    local d = { specKey = unesc(f[1]), name = unesc(f[2]), source = unesc(f[3]),
        updatedAt = tonumber(f[4], 36), weights = {}, ignored = {} }
    if not d.updatedAt or #d.name > Codec.MAX_NAME then return nil end
    for pair in (f[5] .. ","):gmatch("([^,]*),") do
        if pair ~= "" then
            local k, v = pair:match("^(%w+)=(%-?[%d%.]+)$")
            if not k or not GG.Data.Stats.TOKENS[k] then return nil end
            d.weights[k] = tonumber(v)
        end
    end
    for k in (f[6] .. ","):gmatch("([^,]*),") do
        if k ~= "" then
            if not GG.Data.Stats.TOKENS[k] then return nil end
            d.ignored[k] = true
        end
    end
    return d
end

local function decodeBaseline(p)
    local f = split(p, ";")
    if #f ~= 4 then return nil end
    local d = { specKey = unesc(f[1]), source = unesc(f[2]), capturedAt = tonumber(f[3], 36), slots = {} }
    if not d.capturedAt then return nil end
    for part in (f[4] .. ","):gmatch("([^,]*),") do
        if part ~= "" then
            local slot, code, item = part:match("^(%d+):([oeu]):?(.*)$")
            if not slot then return nil end
            local s = { state = OCC_BACK[code] }
            if code == "o" then
                if not item:match("^%d+:%d*:%-?%d*$") then return nil end
                s.item = item
            end
            d.slots[tonumber(slot)] = s
        end
    end
    return d
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
    if f[5] ~= "" then
        for _, v in ipairs(split(f[5], ",")) do e.ancestors[#e.ancestors + 1] = unesc(v) end
        if #e.ancestors > 20 then return nil, "bad-entry" end
    end
    local flags = f[6]
    if flags:sub(1, 1) == "d" then e.deleted = true; flags = flags:sub(2) end
    if flags:sub(1, 1) == "c" then e.conflict = { of = unesc(flags:sub(2)) } end
    if not e.deleted then
        e.data = (kind == "profile" and decodeProfile or decodeBaseline)(f[7])
        if not e.data then return nil, "bad-entry" end
    end
    return e
end

return Codec
