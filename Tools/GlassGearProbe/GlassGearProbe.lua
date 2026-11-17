-- GlassGearProbe: Glass Gear's throwaway measurement module, on ForeverProbe
-- (/fp gg). docs/FOREVER-PROBE.md has the checks; this is P4 (GG-103, #4).
--
-- /fp steps gg stats: what C_Item.GetItemStats returns on Forever.
--   - Sample items, one or two per ItemSparse stat type (StatModifier_bonusStat,
--     wago.tools ItemSparse 70532): requested, timed to their load events,
--     then each one's keys and values. The answer for spell damage, healing,
--     mp5, the six school damages and bonus armor comes from these, whatever
--     the owner carries. Bonus armor is also read off the tooltip's armor lines.
--   - A random-suffix item (a bonus ID on Forever) as its full link, the
--     trimmed baseline string Glass Gear stores, and the bare item.
--   - Everything worn and carried: each link's keys, and whether the enchant-
--     stripped and trimmed strings Glass Gear reads give the same stats.
--   With Glass Gear loaded, every key Glass Gear can't map is named
--   (UNSUPPORTED_STAT), through its own GlassGear.Data.Stats.
-- Commands: /fp gg request, samples, suffix, bags, item <id|link>, clear.
--
-- Every client API is read with rawget (the host's rule), so the offline
-- tests' strict stubs only need what a test drives.

local ADDON, NS = ...
local MAX_LOG = 5000
local LOAD_TIMEOUT = 20

local Probe = ForeverProbe:Module("GlassGearProbe", { api = 1, cmd = "gg" })
local Show = Probe.Show

local function say(msg) Probe:Say(msg) end
local function G(name) return rawget(_G, name) end
local function api(ns, fn)
    local t = G(ns)
    return type(t) == "table" and t[fn] or nil
end
local function secret(v)
    local is = G("issecretvalue")
    return is ~= nil and is(v)
end
local function now()
    local precise = G("GetTimePreciseSec")
    if precise then return precise() end
    return G("GetTime")()
end

-- One or two items per ItemSparse stat type (the type's name is our reading
-- of the samples, to be confirmed by the keys). Item IDs from the 70532 table.
NS.SAMPLES = {
    { 763, 3, "agility" }, { 1189, 4, "strength" }, { 1077, 5, "intellect" }, { 744, 6, "spirit" },
    { 935, 7, "stamina" }, { 7946, 12, "defense" }, { 7920, 13, "dodge" }, { 12639, 14, "parry" },
    { 4975, 15, "block rating" }, { 4383, 31, "hit" }, { 3854, 32, "crit" }, { 17142, 36, "haste" },
    { 2907, 37, "expertise?" }, { 3566, 38, "attack power" }, { 10510, 39, "ranged attack power" },
    { 7049, 41, "healing" }, { 2943, 42, "spell damage" }, { 10659, 43, "mana per 5" },
    { 1449, 45, "spell power" }, { 10779, 46, "health per 5" }, { 16444, 47, "spell penetration" },
    { 11307, 48, "block value" }, { 3844, 50, "bonus armor" }, { 6731, 50, "bonus armor" },
    { 4790, 51, "a resistance" }, { 4327, 52, "a resistance" }, { 1462, 54, "a resistance" },
    { 7951, 55, "a resistance" }, { 12405, 56, "a resistance" }, { 21189, 83, "?" },
    { 253899, 84, "holy damage?" }, { 2231, 85, "fire damage" }, { 7386, 86, "nature damage" },
    { 4324, 87, "frost damage" }, { 4323, 88, "shadow damage" }, { 11263, 89, "arcane damage (a wand)" },
    { 12252, 124, "?" }, { 10696, 127, "?" }, { 23078, 128, "undead slaying?" },
    { 11906, 131, "beast slaying?" }, { 12775, 90, "a weapon skill?" }, { 7349, 112, "a profession skill?" },
    { 6367, 117, "fishing?" },
}
-- "Beaded Wraps of the Sorcerer": a random suffix as a bonus ID (AltStable's
-- measurement), in the three forms Glass Gear meets it.
NS.SUFFIX = {
    full = "item:14094::::::::10:1482:::1:12745",
    trimmed = "item:14094::::::::::::1:12745",
    base = "item:14094",
}

local requests = {}   -- [itemID] = { at, cached, events = { "EVENT +ms success" } }

-- The fields of an item string or link (1 = item ID, 2 = enchant, ...).
local function fields(link)
    local body = type(link) == "string" and link:match("item:([^|]+)")
    if not body then return nil end
    local f, n = {}, 0
    for v in (body .. ":"):gmatch("([^:]*):") do n = n + 1; f[n] = v end
    return f
end

local function itemString(link)
    return type(link) == "string" and link:match("(item:[%-%d:]+)") or link
end

-- The enchant-stripped string, as Glass Gear reads stats (adr/0003).
local function stripped(link)
    local s = itemString(link)
    local GG = G("GlassGear")
    if GG and GG.Engine and GG.Engine.Score and GG.Engine.Score.StripEnchant then
        return GG.Engine.Score.StripEnchant(s)
    end
    return (s:gsub("^(item:%-?%d+):[^:]*", "%1:"))
end

local function trimmed(link)
    local GG = G("GlassGear")
    if GG and GG.Compat and GG.Compat.GearItemString then return GG.Compat.GearItemString(link) end
end

-- GetItemStats as sorted "KEY=value" pairs; nil and why on a miss.
local function stats(link)
    local fn = api("C_Item", "GetItemStats")
    if not fn then return nil, "C_Item.GetItemStats missing" end
    local ok, raw = pcall(fn, link)
    if not ok then return nil, "ERROR " .. tostring(raw) end
    if secret(raw) then return nil, "<secret>" end
    if type(raw) ~= "table" then return nil, "returned " .. Show(raw) end
    local keys = {}
    for k, v in pairs(raw) do
        if secret(k) or secret(v) then keys[#keys + 1] = "<secret>" else keys[#keys + 1] = tostring(k) .. "=" .. Show(v) end
    end
    table.sort(keys)
    return keys, raw
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- The keys Glass Gear can't map, by its own table (when it's loaded).
local function unsupported(raw, link)
    local GG = G("GlassGear")
    local S = GG and GG.Data and GG.Data.Stats
    if not (S and S.FromItemStats) or type(raw) ~= "table" then return nil end
    local facts
    local instant = api("C_Item", "GetItemInfoInstant")
    if instant then
        local ok, _, _, _, equipLoc, _, classID, subclassID = pcall(instant, link)
        if ok then facts = { equipLoc = equipLoc, classID = classID, subclassID = subclassID } end
    end
    local ok, _, miss = pcall(S.FromItemStats, raw, facts)
    if ok then return miss end
end

-- The tooltip's lines that name armor, with their colour (bonus armor shows
-- green on top of the white base line).
local function armorLines(link)
    local fn = api("C_TooltipInfo", "GetHyperlink")
    if not fn then return "C_TooltipInfo.GetHyperlink missing" end
    local ok, data = pcall(fn, link)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return "no tooltip data" end
    local out = {}
    for i, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not secret(text) and text:find("%d") and text:find("[Aa]rmor") then
            local c = line.leftColor
            local rgb = "?"
            if type(c) == "table" and type(c.r) == "number" then rgb = ("%.2f,%.2f,%.2f"):format(c.r, c.g, c.b) end
            out[#out + 1] = ("[%d] %s (%s)"):format(i, Probe.Plain(text), rgb)
        end
    end
    return #out > 0 and table.concat(out, " | ") or "no armor line"
end

------------------------------------------------------------
-- Loading the samples, timed
------------------------------------------------------------

local function isLoaded(id)
    local info = api("C_Item", "GetItemInfo")
    local name = info and info(id)
    return name ~= nil and type((stats("item:" .. id))) == "table"
end

function NS.Request()
    local request, cached = api("C_Item", "RequestLoadItemDataByID"), api("C_Item", "IsItemDataCachedByID")
    if not request then say("C_Item.RequestLoadItemDataByID missing") return 0, 0 end
    local n, warm = 0, 0
    for _, s in ipairs(NS.SAMPLES) do
        local id = s[1]
        local wasCached = cached and cached(id) or false
        if wasCached then warm = warm + 1 end
        requests[id] = { at = now(), cached = wasCached, events = {} }
        local ok, err = pcall(request, id)
        if not ok then say(("request %d: ERROR %s"):format(id, tostring(err))) end
        n = n + 1
    end
    local sfx = 14094
    if not requests[sfx] then
        requests[sfx] = { at = now(), cached = cached and cached(sfx) or false, events = {} }
        pcall(request, sfx)
    end
    say(("requested %d sample items; %d already cached"):format(n, warm))
    return n, warm
end

-- The wait step: done once every sample answers (info and stats).
function NS.Loaded()
    local missing = {}
    for _, s in ipairs(NS.SAMPLES) do
        if not isLoaded(s[1]) then missing[#missing + 1] = s[1] end
    end
    if #missing == 0 then return true, "all loaded" end
    return false, (#missing .. " still loading: " .. table.concat(missing, ",", 1, math.min(#missing, 8)))
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, id, success)
    local r = requests[id]
    if not r then return end
    local ms = math.floor((now() - r.at) * 1000 + 0.5)
    r.events[#r.events + 1] = ("%s +%dms %s"):format(event, ms, Show(success))
    say(("%s %s +%dms success=%s (cached at request: %s)"):format(event, Show(id), ms, Show(success), Show(r.cached)))
end)
Probe:RegisterEvents(events, { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" })

------------------------------------------------------------
-- The readings
------------------------------------------------------------

-- One item: its keys, Glass Gear's unsupported ones, and (on request) its armor lines.
local function readItem(link, label, withArmor)
    local keys, rawOrWhy = stats(link)
    if not keys then
        say(("%s %s: no stats (%s)"):format(label, link, tostring(rawOrWhy)))
        return nil
    end
    say(("%s %s: %s"):format(label, link, #keys > 0 and table.concat(keys, " ") or "(empty table)"))
    local miss = unsupported(rawOrWhy, link)
    if miss and #miss > 0 then say(("%s   Glass Gear UNSUPPORTED_STAT: %s"):format(label, table.concat(miss, " "))) end
    if withArmor then say(("%s   tooltip armor: %s"):format(label, armorLines(link))) end
    return keys, rawOrWhy
end

-- Every sample; returns "type: keys" for the step's result.
function NS.Samples()
    local byType, summary = {}, {}
    for _, s in ipairs(NS.SAMPLES) do
        local id, stat, what = s[1], s[2], s[3]
        local info = api("C_Item", "GetItemInfo")
        local name = info and info(id)
        local label = ("type %d (%s) %d %s"):format(stat, what, id, Show(name))
        local keys = readItem("item:" .. id, label, stat == 50 or stat == 7)
        if keys then
            byType[stat] = byType[stat] or {}
            for _, kv in ipairs(keys) do byType[stat][kv:match("^([^=]+)")] = true end
        end
        local r = requests[id]
        if r then say(("%s   load: cached %s, %s"):format(label, Show(r.cached), #r.events > 0 and table.concat(r.events, ", ") or "no event")) end
    end
    local types = {}
    for t in pairs(byType) do types[#types + 1] = t end
    table.sort(types)
    for _, t in ipairs(types) do
        local ks = {}
        for k in pairs(byType[t]) do ks[#ks + 1] = k end
        table.sort(ks)
        summary[#summary + 1] = t .. ":" .. table.concat(ks, ",")
    end
    say("SUMMARY " .. table.concat(summary, " ; "))
    return #types, table.concat(summary, " ; ")
end

-- The suffix item in its three forms.
function NS.Suffix()
    local full = readItem(NS.SUFFIX.full, "suffix full", false)
    local trim = readItem(NS.SUFFIX.trimmed, "suffix trimmed", false)
    local base = readItem(NS.SUFFIX.base, "suffix base", false)
    local fullTrim, fullBase = same(full, trim), same(full, base)
    say(("suffix: full = trimmed %s; full = base %s"):format(Show(fullTrim), Show(fullBase)))
    return fullTrim, fullBase
end

-- What the player wears and carries.
local function links()
    local out = {}
    local inv = G("GetInventoryItemLink")
    for slot = 1, 19 do
        local link = inv and inv("player", slot)
        if type(link) == "string" then out[#out + 1] = { link = link, where = "slot " .. slot } end
    end
    local num, get = api("C_Container", "GetContainerNumSlots"), api("C_Container", "GetContainerItemLink")
    if num and get then
        for bag = 0, 4 do
            for i = 1, (num(bag) or 0) do
                local link = get(bag, i)
                if type(link) == "string" then out[#out + 1] = { link = link, where = ("bag %d.%d"):format(bag, i) } end
            end
        end
    end
    return out
end

function NS.Scan()
    local items, enchanted, suffixed, differ, unsup = links(), 0, 0, 0, 0
    for _, it in ipairs(items) do
        local f = fields(it.link) or {}
        local ench = f[2] ~= nil and f[2] ~= ""
        local bonuses = tonumber(f[13] or "") or 0
        if ench then enchanted = enchanted + 1 end
        if bonuses > 0 then suffixed = suffixed + 1 end
        local label = ("%s%s%s"):format(it.where, ench and " enchant=" .. f[2] or "", bonuses > 0 and " bonusIDs=" .. bonuses or "")
        local s = itemString(it.link)
        local full, raw = readItem(s, label, false)
        if full then
            local miss = unsupported(raw, s)
            if miss and #miss > 0 then unsup = unsup + 1 end
            local st, tr = stripped(s), trimmed(s)
            local a = st ~= s and stats(st) or full
            local b = tr and tr ~= s and stats(tr) or full
            if not same(full, a) or not same(full, b) then
                differ = differ + 1
                say(("%s   DIFFERS: stripped %s -> %s ; trimmed %s -> %s"):format(label, st,
                    type(a) == "table" and table.concat(a, " ") or Show(a), Show(tr),
                    type(b) == "table" and table.concat(b, " ") or Show(b)))
            end
        end
    end
    local summary = ("%d items, %d enchanted, %d with bonus IDs, %d differ when stripped/trimmed, %d with unsupported keys")
        :format(#items, enchanted, suffixed, differ, unsup)
    say("SCAN " .. summary)
    return #items, summary
end

------------------------------------------------------------
-- Commands and the procedure
------------------------------------------------------------

Probe:Command("request", function() NS.Request() end, "request the sample items (timed to their load events)")
Probe:Command("samples", function() NS.Samples() end, "every sample's GetItemStats keys")
Probe:Command("suffix", function() NS.Suffix() end, "a random-suffix item: full link, trimmed string, bare item")
Probe:Command("bags", function() NS.Scan() end, "what you wear and carry: keys, and stripped/trimmed forms")
function NS.Item(args)
    local arg = args and args:match("^%s*(.-)%s*$") or ""
    local link = tonumber(arg) and ("item:" .. arg) or itemString(arg)
    if link == "" then say("usage: /fp gg item <itemID | link>") return end
    readItem(link, "item", true)
end
Probe:Command("item", NS.Item, "one item's keys and tooltip armor lines: /fp gg item <id|link>")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

Probe:Steps("stats", {
    title = "P4: what GetItemStats returns (GG-103)",
    { text = "Requesting the sample items, one or two per kind of stat. Nothing to do.", auto = true,
      run = function() return NS.Request() end },
    { text = "Waiting for their item data to load (up to " .. LOAD_TIMEOUT .. " s).", wait = NS.Loaded, timeout = LOAD_TIMEOUT },
    { text = "Reading every sample's stats and the armor lines of its tooltip.", auto = true,
      run = function() return NS.Samples() end },
    { text = "Reading a random-suffix item in its three forms.", auto = true, run = function() return NS.Suffix() end },
    { text = "Reading what you wear and carry, with and without enchants.", auto = true,
      run = function() return NS.Scan() end },
    { text = "If the result above says 0 enchanted, put on (or bag) an enchanted item and press Scan again. Otherwise press Skip.",
      button = "Scan again", run = function() return NS.Scan() end },
    { text = "Press Reload now (or type /reload) to save the results.", reload = true },
})

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED" })
boot:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    Probe:Ready()
    if type(GlassGearProbeDB) ~= "table" then GlassGearProbeDB = {} end
    if type(GlassGearProbeDB.log) ~= "table" then GlassGearProbeDB.log = {} end
    Probe:UseLog(GlassGearProbeDB.log, MAX_LOG)
    GlassGearProbeDB.loads = (GlassGearProbeDB.loads or 0) + 1
    say("loaded (" .. GlassGearProbeDB.loads .. " loads). /fp gg for the commands, /fp steps gg stats for P4")
end)

NS._test = { Probe = Probe, requests = requests }   -- the test seam, never on _G
