------------------------------------------------------------
-- Core/DB.lua - SavedVariables, defaults and migrations (docs/SCHEMA.md).
-- A table newer than this code is left untouched and Glass Gear runs
-- read-only that session.
------------------------------------------------------------

local GG = GlassGear
local DB = {}
GG.DB = DB

DB.DEFAULTS = {
    settings = {
        tooltip = { specs = "all", selected = {}, alts = true },
        markers = { scope = "current", selected = {}, markTransferable = true, threshold = 0.005 },
        reveal = { modifier = "CTRL" },
        protection = { scope = "tracked", threshold = 0.005, noWeights = "ignore" },
        levelWindow = { enabled = true, lookAhead = 0 },
        specArmor = true,
        setBonusWarnings = true,
        defaults = { enabled = true },      -- GG-120: Glass Gear's default weights
        appearance = { theme = "forever" },
    },
    ui = { windows = {} },      -- window positions (GG-105); never synced
}

-- MIGRATIONS[n] upgrades schema n-1 to n. None yet: schema 1 is the first.
DB.MIGRATIONS = {}

local function fill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            fill(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Returns the account table, the character table and readOnly.
function DB.Load(account, char)
    local readOnly = false
    account = type(account) == "table" and account or {}
    char = type(char) == "table" and char or {}
    for _, t in ipairs({ account, char }) do
        local from = t.schema or 0
        if from > GG.SCHEMA then
            readOnly = true
        else
            for n = from + 1, GG.SCHEMA do
                if DB.MIGRATIONS[n] then DB.MIGRATIONS[n](t) end
            end
            t.schema = GG.SCHEMA
        end
    end
    if not readOnly then
        fill(account, DB.DEFAULTS)
        account.tracked = account.tracked or {}
        account.entries = account.entries or {}
        account.replicaState = account.replicaState or {}
        char.specMap = char.specMap or {}
        char.equipSetMap = char.equipSetMap or {}
        char.observed = char.observed or {}
    end
    return account, char, readOnly
end

return DB
