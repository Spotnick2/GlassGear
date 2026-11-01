------------------------------------------------------------
-- test_formats_doc.lua - docs/FORMATS.md and Data/Stats.lua agree on every
-- token's status (supported / derived / reported-unsupported) and key.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
local GG = H.loadPure()
local Stats = GG.Data.Stats
local doc = assert(H.readFile("docs/FORMATS.md"), "docs/FORMATS.md missing")

local function expand(cell)
    -- "Fire/Nature/Frost/Shadow/ArcaneResist" -> FireResist, NatureResist, ...
    local out = {}
    if cell:find("/", 1, true) then
        local parts = {}
        for p in cell:gmatch("[^/]+") do parts[#parts + 1] = p end
        local last = parts[#parts]
        local tail = last:match("^%u%l+(%u.*)$")
        if tail then
            for i, p in ipairs(parts) do out[#out + 1] = (i == #parts) and p or (p .. tail) end
            return out
        end
    end
    for t in cell:gmatch("[%w]+") do out[#out + 1] = t end
    return out
end

local checked = 0
for line in doc:gmatch("[^\n]+") do
    local tok, key, status = line:match("^|%s*([%w/ ,]+)%s*|%s*(.-)%s*|%s*([%w%- ]+)")
    -- Prose rows ("... and the other ... variants") name groups, not tokens: skipped.
    if tok and not tok:find("Pawn token") and not line:find("variants") and status then
        status = status:match("^(%S+)")
        if status == "supported" or status == "derived" or status == "reported-unsupported" then
            local tokens = expand((tok:gsub("%s+$", "")))
            for _, t in ipairs(tokens) do
                if Stats.TOKENS[t] then
                    H.eq(Stats.STATUS[t], status, "status of " .. t .. " matches FORMATS.md")
                    local k = key:match("`([%u%d_]+)`")
                    if #tokens == 1 and k and status == "supported" and not key:find("expected") and Stats.ITEM_MOD[k] then
                        H.check(H.has(Stats.ITEM_MOD[k], t), t .. " is fed by " .. k)
                    end
                    checked = checked + 1
                end
            end
        end
    end
end
H.check(checked >= 25, "the doc's token tables were found (" .. checked .. " tokens checked)")

H.done("test_formats_doc")
