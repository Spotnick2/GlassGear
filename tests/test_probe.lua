------------------------------------------------------------
-- test_probe.lua - GlassGearProbe (Tools/GlassGearProbe, /fp gg), the P4
-- module (GG-103), on the real ForeverProbe host loaded from ../ForeverProbe
-- (ForeverProbe docs/GUIDE.md section 8). ForeverProbe is private: CI sets
-- FOREVERPROBE_OPTIONAL=1 and this file skips there; locally it always runs.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

-- The host's loader (GlassChat/tests/harness.lua's loadForeverProbe), kept in
-- this file rather than the shared stubs (#65, the move to WowTestKit).
local function loadForeverProbe()
    local root = (os.getenv("FOREVERPROBE") or "../ForeverProbe"):gsub("\\", "/"):gsub("/$", "")
    local toc = io.open(root .. "/ForeverProbe.toc", "rb")
    if not toc then
        if os.getenv("FOREVERPROBE_OPTIONAL") == "1" then
            io.write("SKIPPED: ForeverProbe isn't here (private, local only); the probe tests run locally\n")
            os.exit(0)
        end
        error("ForeverProbe checkout not found at " .. root .. ": clone it there or set FOREVERPROBE", 0)
    end
    local files = {}
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = root .. "/" .. line end
    end
    toc:close()
    for _, file in ipairs(files) do assert(loadfile(file))("ForeverProbe", {}) end
    WoW.fire("ADDON_LOADED", "ForeverProbe")
    return rawget(_G, "ForeverProbe")
end

-- A few of the probe's samples, with the keys Forever is expected to return.
WoW.items[2231] = { name = "Inferno Robe", equipLoc = "INVTYPE_ROBE", classID = 4, subclassID = 1,
    stats = { ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = 20, ITEM_MOD_HERBALISM_SHORT = 5, RESISTANCE0_NAME = 50 } }
WoW.items[1449] = { name = "Minor Channeling Ring", equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0,
    stats = { ITEM_MOD_SPELL_POWER_SHORT = 7 } }
WoW.items[14094] = { name = "Beaded Wraps", equipLoc = "INVTYPE_WRIST", classID = 4, subclassID = 1,
    stats = { ITEM_MOD_INTELLECT_SHORT = 3, RESISTANCE0_NAME = 20 } }
WoW.equipped[5] = 2231

local GG = WoW.loadAddon()
H.check(GG ~= nil, "Glass Gear loads (the probe reads its Stats table)")
local FP = loadForeverProbe()
H.check(type(FP) == "table", "the ForeverProbe host loads")

rawset(_G, "GlassGearProbeDB", false)   -- declared, as the client does for a SavedVariable not yet saved
local NS = {}
assert(loadfile("Tools/GlassGearProbe/GlassGearProbe.lua"))("GlassGearProbe", NS)
WoW.fire("ADDON_LOADED", "GlassGearProbe")
H.eq(type(GlassGearProbeDB), "table", "the saved table is made at its own ADDON_LOADED")
H.eq(GlassGearProbeDB.loads, 1, "...and counts loads")

local function logHas(text)
    for _, line in ipairs(GlassGearProbeDB.log) do
        if tostring(line):find(text, 1, true) then return true end
    end
    return false
end

local chatBefore = #WoW.chatLines

-- Request: every sample and the suffix item, timed.
local n = NS.Request()
H.eq(n, #NS.SAMPLES, "every sample is requested")
local asked = {}
for _, id in ipairs(WoW.itemRequests) do asked[id] = true end
H.check(asked[2231] and asked[1449] and asked[14094], "...the samples and the suffix item")
WoW.fire("ITEM_DATA_LOAD_RESULT", 2231, true)
H.check(logHas("ITEM_DATA_LOAD_RESULT 2231"), "a load event of a requested item is logged with its delay")

-- Loaded: false while samples are missing (most aren't in the stubs).
local done, pending = NS.Loaded()
H.eq(done, false, "not all samples loaded")
H.check(tostring(pending):find("still loading", 1, true) ~= nil, "...and it says what's pending")

-- Samples: the keys per stat type, and Glass Gear's unsupported keys.
local types, summary = NS.Samples()
H.check(types >= 2, "the loaded samples are read")
H.check(summary:find("85:ITEM_MOD_FIRE_DAMAGE_DONE_SHORT", 1, true) ~= nil, "the summary gives the fire type's key")
H.check(logHas("Glass Gear UNSUPPORTED_STAT: ITEM_MOD_HERBALISM_SHORT"),
    "a key Glass Gear can't map is named (a profession skill)")
H.check(logHas("type 45 (spell power) 1449"), "each sample is labelled with its stat type")
H.check(logHas("no stats"), "a sample with no data says so")

-- Suffix: the three forms read the same item here.
local fullTrim, fullBase = NS.Suffix()
H.eq(fullTrim, "same", "suffix: full and trimmed compared")
H.eq(fullBase, "same", "suffix: full and base compared")
-- An unloaded suffix item is no evidence (PR #75 review).
WoW.cacheMiss[14094] = true
fullTrim, fullBase = NS.Suffix()
H.eq(fullTrim .. "/" .. fullBase, "unreadable/unreadable", "suffix not loaded: unreadable, never 'same'")
-- ...and the wait step waits for it.
local samples = NS.SAMPLES
NS.SAMPLES = { { 1449, 45, "spell power" } }
done, pending = NS.Loaded()
H.check(done == false and tostring(pending):find("14094", 1, true) ~= nil, "the wait step waits for the suffix item too")
WoW.cacheMiss[14094] = nil
H.eq((NS.Loaded()), true, "...and ends once it's loaded")
NS.SAMPLES = samples

-- Scan: what's worn.
local count, scan = NS.Scan()
H.eq(count, 1, "the equipped item is scanned")
H.check(scan:find("1 items, 0 enchanted", 1, true) ~= nil, "...and summarised; enchant 0 isn't an enchant: " .. scan)
-- An enchanted item, and a stripped form the client can't read: unreadable, not "same".
WoW.bags[0] = { [1] = { itemID = 1449, enchant = 1883 } }
-- The bag link, kept in this file (the shared stubs don't grow: #65).
C_Container.GetContainerItemLink = function(bag, slot)                                    -- 1173
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.hyperlink
end
local getStats = C_Item.GetItemStats
C_Item.GetItemStats = function(link)
    if tostring(link):find("^item:1449:1883") or not tostring(link):find("^item:1449") then return getStats(link) end
    return nil
end
count, scan = NS.Scan()
C_Item.GetItemStats = getStats
H.check(scan:find("2 items, 1 enchanted", 1, true) ~= nil, "an enchanted item is counted: " .. scan)
H.check(scan:find("0 differ when stripped/trimmed, 1 unreadable", 1, true) ~= nil, "...a failed stripped read is unreadable, never the full stats")
H.check(logHas("UNREADABLE: stripped item:1449:"), "...and logged with the string")
count, scan = NS.Scan()
H.check(scan:find("0 differ when stripped/trimmed, 0 unreadable", 1, true) ~= nil, "a readable stripped form compares normally")
WoW.bags[0] = nil

-- One item (what /fp gg item runs; /fp itself opens the host's console, which
-- these stubs don't draw).
NS.Item(" 1449 ")
H.check(logHas("item item:1449: ITEM_MOD_SPELL_POWER_SHORT=7"), "/fp gg item reads one item")
H.check(logHas("tooltip armor"), "...with its tooltip armor lines (or why not)")

-- Nothing in chat: diagnostics go to the console and the saved log.
H.eq(#WoW.chatLines, chatBefore, "the probe writes nothing to chat")

-- Clearing keeps the bound table.
local logTable = GlassGearProbeDB.log
NS._test.Probe:ClearLog()
NS._test.Probe:Say("after clear")
H.check(GlassGearProbeDB.log == logTable, "clear empties the log in place")
H.eq(#GlassGearProbeDB.log, 1, "...and the next line is saved")

H.done("test_probe")
