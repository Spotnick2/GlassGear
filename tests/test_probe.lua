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
    stats = { ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = 20, RESISTANCE0_NAME = 50 } }
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
H.check(logHas("Glass Gear UNSUPPORTED_STAT: ITEM_MOD_FIRE_DAMAGE_DONE_SHORT"),
    "a key Glass Gear can't map is named (fire isn't mapped yet)")
H.check(logHas("type 45 (spell power) 1449"), "each sample is labelled with its stat type")
H.check(logHas("no stats"), "a sample with no data says so")

-- Suffix: the three forms read the same item here.
local fullTrim, fullBase = NS.Suffix()
H.eq(fullTrim, true, "suffix: full and trimmed compared")
H.eq(fullBase, true, "suffix: full and base compared")

-- Scan: what's worn.
local count, scan = NS.Scan()
H.eq(count, 1, "the equipped item is scanned")
H.check(scan:find("1 items", 1, true) ~= nil, "...and summarised")

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
