------------------------------------------------------------
-- test_tooltip.lua - tooltip rows for all own specs (GG-107): the post-call,
-- the rows and their texts, pending -> refresh, caching, guards.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local INT, SP = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"
WoW.items[50] = { name = "Old Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    stats = { [INT] = 10 } }
WoW.items[60] = { name = "Shadow Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    bindType = 2, stats = { [INT] = 5, [SP] = 10 } }
WoW.items[61] = { name = "Elixir", equipLoc = "", classID = 0, subclassID = 0 }
WoW.items[62] = { name = "Far Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    minLevel = 62, stats = { [INT] = 30 } }
WoW.items[63] = { name = "Proc Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    spell = "Chance on hit", stats = { [INT] = 20 } }
WoW.items[64] = { name = "Slow Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    stats = { [INT] = 40 } }
WoW.equipped[3] = 50
WoW.bags[0] = { [1] = { itemID = 60, isBound = false, guid = "Item-1-AAA" } }

local GG = WoW.loadAddon()
local tip = WoW.newTooltip("GameTooltip")
local function bagData() return { type = 0, id = 60, guid = "Item-1-AAA" } end

local function texts(t)
    local out = {}
    for _, l in ipairs(t.lines) do out[#out + 1] = l.left .. (l.right and (" | " .. l.right) or "") end
    return table.concat(out, "\n")
end
local function line(t, needle)
    for _, l in ipairs(t.lines) do
        if (l.left .. (l.right or "")):find(needle, 1, true) then return l end
    end
end

-- Registered once, at login.
H.eq(#(WoW.postCalls[0] or {}), 1, "one item post-call registered")
H.eq(GG.tooltipHooked, true, "the hook reports on")
SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("tooltip rows: on", 1, true) ~= nil, "/gg reports tooltip rows on")

-- No spec mapped, no weights: every spec reads "no weights", never 0.
WoW.showItem(tip, bagData(), WoW.bagButton(0, 1))
H.eq(tip.lines[1].left, "item lines", "Blizzard's own lines stay first and intact")
H.eq(tip.lines[2].left, "Glass Gear", "the Glass Gear block follows")
H.eq(#tip.lines, 7, "title, three specs, spec hint, footer")
for _, spec in ipairs({ "Discipline", "Holy", "Shadow" }) do
    local l = line(tip, spec)
    H.eq(l and l.right, "no weights", spec .. ": no weights")
end
H.check(not texts(tip):find("CURRENT", 1, true), "no spec is marked current without a mapping")
H.check(line(tip, "Current spec not set") ~= nil, "the hint explains why")
H.check(not texts(tip):find("0.0%", 1, true), "no row reads 0 for missing weights")

-- Map Shadow, import Shadow and Holy weights: the block re-evaluates.
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1, SpellDamage=1 )')
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy": Class=Priest, Intellect=1 )')
WoW.flush()
WoW.showItem(tip, bagData(), WoW.bagButton(0, 1))
local cur = tip.lines[3]
H.check(cur.left:find("^Shadow") and cur.left:find("CURRENT", 1, true), "current spec first and marked CURRENT")
H.eq(cur.right, "+50.0%", "Shadow: (15 - 10) / 10")
H.eq(cur.rc[1] < 0.5 and cur.rc[2] == 1, true, "upgrade in green")
H.eq(tip.lines[4].left, "Discipline", "then the other specs in tree order")
H.eq(tip.lines[4].right, "no weights", "Discipline still has no weights")
H.eq(tip.lines[5].left, "Holy", "Holy compact")
H.eq(tip.lines[5].right, "-50.0%", "Holy: (5 - 10) / 10")
H.eq(tip.lines[5].rc[1] == 1 and tip.lines[5].rc[2] < 0.5, true, "loss in red")
H.check(line(tip, "Current spec not set") == nil, "no hint once the spec is mapped")
H.check(line(tip, "other specs vs current gear") ~= nil, "the footer says off-specs compare with current gear")
H.check(line(tip, "Weighted item score") ~= nil, "the estimate footer")

-- Tooltip settings: current spec only.
GG.db.settings.tooltip.specs = "current"
WoW.showItem(tip, bagData(), WoW.bagButton(0, 1))
H.check(line(tip, "Holy") == nil and line(tip, "Discipline") == nil, "specs = current hides the others")
GG.db.settings.tooltip.specs = "all"

-- Not for us: non-equippable items, comparison tooltips, forbidden tooltips.
WoW.items[61].stats = {}
WoW.showItem(tip, { type = 0, id = 61, hyperlink = WoW.link(61) })
H.eq(#tip.lines, 1, "a non-equippable item gets no block")
local shop = WoW.newTooltip("ShoppingTooltip1")
WoW.showItem(shop, { type = 0, id = 60, hyperlink = WoW.link(60) })
H.eq(#shop.lines, 1, "comparison tooltips get no block")
local forbidden = WoW.newTooltip("GameTooltip")
forbidden.forbidden = true
WoW.showItem(forbidden, bagData())
H.eq(#forbidden.lines, 1, "forbidden tooltips are left alone")

-- A chat link (ItemRefTooltip: hyperlink only) works the same.
local ref = WoW.newTooltip("ItemRefTooltip")
WoW.showItem(ref, { type = 0, id = 60, hyperlink = WoW.link(60) })
H.eq(ref.lines[3] and ref.lines[3].right, "+50.0%", "chat-link tooltip rows")

-- Level window: two levels above, default look-ahead 0 -> "at level 62 (in 2)".
WoW.showItem(ref, { type = 0, id = 62, hyperlink = WoW.link(62) })
H.eq(ref.lines[3].right, "at level 62 (in 2)", "above the level window: when, not a score")
GG.db.settings.levelWindow.lookAhead = 2
GG.Tooltip.Reset()
WoW.showItem(ref, { type = 0, id = 62, hyperlink = WoW.link(62) })
H.eq(ref.lines[3].right, "+200.0% at level 62 (in 2)", "inside the look-ahead: scored, with the level")
-- A later item that loses keeps its level too (PR #33 review).
WoW.items[65] = { name = "Weak Far Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    minLevel = 62, stats = { [INT] = 5 } }
WoW.showItem(ref, { type = 0, id = 65, hyperlink = WoW.link(65) })
H.eq(ref.lines[3].right, "-50.0% at level 62 (in 2)", "a later-level loss says when it could be worn")
GG.db.settings.levelWindow.lookAhead = 0
GG.Tooltip.Reset()

-- Unscored parts of the replaced gear are named (PR #33 review): a plain
-- candidate against a proc item, and stats nobody can score.
WoW.equipped[3] = 63
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
WoW.flush()
WoW.showItem(ref, { type = 0, id = 60, hyperlink = WoW.link(60) })
H.check(line(ref, "The replaced item has an effect that isn't scored") ~= nil, "the replaced item's effect is flagged")
H.check(line(ref, "Has an effect that isn't scored") == nil, "...not the candidate's")
WoW.items[66] = { name = "Odd Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    stats = { [INT] = 30, ITEM_MOD_MYSTERY_SHORT = 3 } }
WoW.showItem(ref, { type = 0, id = 66, hyperlink = WoW.link(66) })
H.check(line(ref, "Not scored: an unrecognised stat") ~= nil, "an unrecognised stat on the item is named")
WoW.equipped[3] = 66
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
WoW.flush()
WoW.showItem(ref, { type = 0, id = 60, hyperlink = WoW.link(60) })
H.check(line(ref, "Not scored on the replaced item: an unrecognised stat") ~= nil, "...and on the replaced item")
local refreshesBefore = ref.refreshes
WoW.equipped[3] = 50
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
WoW.flush()
H.check(ref.refreshes > refreshesBefore, "an invalidation refreshes the open tooltip")
ref.refreshes = 0

-- Unscored effects are named.
WoW.showItem(ref, { type = 0, id = 63, hyperlink = WoW.link(63) })
H.check(line(ref, "Has an effect that isn't scored") ~= nil, "an equip/use effect is flagged")

-- Pending: one request however often the tooltip rebuilds, then a refresh.
WoW.cacheMiss[64] = true
local before = GG.API._state.requestCount
WoW.showItem(ref, { type = 0, id = 64, hyperlink = WoW.link(64) })
H.eq(ref.lines[3].right, "checking...", "pending item: checking...")
WoW.showItem(ref, { type = 0, id = 64, hyperlink = WoW.link(64) })
WoW.showItem(ref, { type = 0, id = 64, hyperlink = WoW.link(64) })
H.eq(GG.API._state.requestCount, before + 1, "rebuilds reuse the one pending request")
WoW.cacheMiss[64] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 64, true)
WoW.flush()
H.eq(ref.refreshes, 1, "the open tooltip is refreshed once the data arrives")
H.eq(ref.lines[3].right, "+300.0%", "...with the real rows")

-- An owner with UpdateTooltip rebuilds itself: no forced refresh.
WoW.cacheMiss[64] = true
GG.Tooltip.Reset()
local selfUpdating = WoW.newTooltip("GameTooltip")
WoW.bags[0][2] = { itemID = 64, isBound = true, guid = "Item-1-BBB" }
WoW.showItem(selfUpdating, { type = 0, id = 64, guid = "Item-1-BBB" }, WoW.bagButton(0, 2, true))
WoW.cacheMiss[64] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 64, true)
WoW.flush()
H.eq(selfUpdating.refreshes, 0, "bag buttons with UpdateTooltip aren't force-refreshed")
WoW.showItem(selfUpdating, { type = 0, id = 64, guid = "Item-1-BBB" }, WoW.bagButton(0, 2, true))
H.eq(selfUpdating.lines[3].right, "+300.0%", "...and show the result on their next rebuild")

-- Equipment changes invalidate: the cached answer is dropped.
WoW.equipped[3] = 64
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
WoW.flush()
WoW.showItem(tip, bagData(), WoW.bagButton(0, 1))
H.eq(tip.lines[3].right, "-62.5%", "after equipping a better item, the same mantle is a loss")

-- A failure inside the hook never reaches the tooltip caller.
local saved = GG.API.Evaluate
GG.API.Evaluate = function() error("boom") end
GG.Tooltip.Reset()
local errs = #WoW.errors
H.ok(function() WoW.showItem(tip, bagData(), WoW.bagButton(0, 1)) end, "hook errors are caught")
H.eq(#WoW.errors, errs + 1, "...and reported to the error handler")
H.eq(#tip.lines, 1, "...leaving Blizzard's lines alone")
GG.API.Evaluate = saved

-- Registering again is a no-op.
H.eq(GG.Tooltip.Initialize(), true, "Initialize again: still on")
H.eq(#WoW.postCalls[0], 1, "...without a second post-call")

H.done("test_tooltip")
