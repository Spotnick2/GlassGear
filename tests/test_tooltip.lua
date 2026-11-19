------------------------------------------------------------
-- test_tooltip.lua - tooltip rows for all own specs (GG-107): the post-call,
-- the rows and their texts, pending -> refresh, caching, guards.
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

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
GG.db.settings.tooltip.specs = "all"   -- every spec's row; the fold (GG-123) is tested at the end
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
eq(#(WoW.postCalls[0] or {}), 1, "one item post-call registered")
eq(GG.tooltipHooked, true, "the hook reports on")
SlashCmdList.GLASSGEAR("")
check(WoW.chatText():find("tooltip rows: on", 1, true) ~= nil, "/gg reports tooltip rows on")

-- No spec mapped, no weights: every spec reads "no weights", never 0.
WoW.showItem(tip, bagData(), WoW.bagButton(0, 1))
eq(tip.lines[1].left, "item lines", "Blizzard's own lines stay first and intact")
eq(tip.lines[2].left, "Glass Gear", "the Glass Gear block follows")
eq(#tip.lines, 7, "title, three specs, spec hint, footer")
for _, spec in ipairs({ "Discipline", "Holy", "Shadow" }) do
    local l = line(tip, spec)
    eq(l and l.right, "no weights", spec .. ": no weights")
end
check(not texts(tip):find("CURRENT", 1, true), "no spec is marked current without a mapping")
check(line(tip, "Current spec not set") ~= nil, "the hint explains why")
check(not texts(tip):find("0.0%", 1, true), "no row reads 0 for missing weights")

-- Map Shadow, import Shadow and Holy weights: the block re-evaluates.
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1, SpellDamage=1 )')
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy": Class=Priest, Intellect=1 )')
WoW.flush()
WoW.showItem(tip, bagData(), WoW.bagButton(0, 1))
local cur = tip.lines[3]
check(cur.left:find("^Shadow") and cur.left:find("CURRENT", 1, true), "current spec first and marked CURRENT")
eq(cur.right, "+50.0%", "Shadow: (15 - 10) / 10")
eq(cur.rc[1] < 0.5 and cur.rc[2] == 1, true, "upgrade in green")
eq(tip.lines[4].left, "Discipline", "then the other specs in tree order")
eq(tip.lines[4].right, "no weights", "Discipline still has no weights")
eq(tip.lines[5].left, "Holy", "Holy compact")
eq(tip.lines[5].right, "-50.0%", "Holy: (5 - 10) / 10")
eq(tip.lines[5].rc[1] == 1 and tip.lines[5].rc[2] < 0.5, true, "loss in red")
check(line(tip, "Current spec not set") == nil, "no hint once the spec is mapped")
check(line(tip, "other specs vs current gear") ~= nil, "the footer says off-specs compare with current gear")
check(line(tip, "Weighted item score") ~= nil, "the estimate footer")

-- Tooltip settings: current spec only.
GG.db.settings.tooltip.specs = "current"
WoW.showItem(tip, bagData(), WoW.bagButton(0, 1))
check(line(tip, "Holy") == nil and line(tip, "Discipline") == nil, "specs = current hides the others")

-- GG-123: the hidden specs fold into one line under the current spec; the
-- reveal key (Ctrl by default) unfolds them while held.
eq(tip.lines[4].left, "+ 2 other specs (hold Ctrl)", "the folded specs: one line, right under the current spec")
eq(tip.lines[4].right, nil, "...nothing on its right when no hidden spec has an upgrade")
check(line(tip, "other specs vs current gear") == nil, "...and the footer doesn't speak of hidden specs")
local before = tip.refreshes or 0
WoW.keys.CTRL = true
WoW.fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
eq((tip.refreshes or 0) - before, 1, "holding Ctrl refreshes the open tooltip")
check(line(tip, "Holy") ~= nil and line(tip, "Discipline") ~= nil, "...which now lists every spec")
check(line(tip, "other specs (hold") == nil, "...without the folded line")
check(line(tip, "other specs vs current gear") ~= nil, "...and the footer is back")
WoW.keys.CTRL = nil
WoW.fire("MODIFIER_STATE_CHANGED", "LCTRL", 0)
check(line(tip, "Holy") == nil and line(tip, "+ 2 other specs") ~= nil, "releasing it folds them again")
-- A hidden upgrade isn't missed: the best one is on the folded line.
WoW.items[67] = { name = "Bright Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    stats = { [INT] = 12 } }
local bright = WoW.newTooltip("ItemRefTooltip")
WoW.showItem(bright, { type = 0, id = 67, hyperlink = WoW.link(67) })
local fold = line(bright, "+ 2 other specs")
eq(fold and fold.right, "Holy +20.0%", "the folded line names the best hidden upgrade")
eq(fold and fold.rc[2] == 1 and fold.rc[1] < 0.5, true, "...in green")
-- Two hidden upgrades: the larger one is named (Discipline, Int + Spirit: 15 / 10).
WoW.items[68] = { name = "Calm Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    stats = { [INT] = 12, ITEM_MOD_SPIRIT_SHORT = 3 } }
SlashCmdList.GLASSGEAR('import PRIEST.DISCIPLINE ( Pawn: v1: "Disc": Class=Priest, Intellect=1, Spirit=1 )')
WoW.flush()
WoW.showItem(bright, { type = 0, id = 68, hyperlink = WoW.link(68) })
fold = line(bright, "+ 2 other specs")
eq(fold and fold.right, "Discipline +50.0%", "two hidden upgrades: the larger one is named")
-- The folded upgrade keeps its warnings (PR #78 review): a lost set bonus,
-- stale or estimated gear that exist only on that hidden spec are still said.
local function r(spec, status, pct, extra)
    local x = { status = status, spec = spec, score = pct and { pct = pct } or nil, reasons = {}, limitations = {},
        eligibility = { equipNow = true, reasons = {} } }
    for k, v in pairs(extra or {}) do x[k] = v end
    return x
end
local folded = GG.TooltipView.Build({ results = {
    r("PRIEST.SHADOW", "no_upgrade", -0.1, { current = true }),
    r("PRIEST.HOLY", "upgrade", 0.2, { limitations = { "SET_BONUS_LOST:500:2" }, reasons = { "BASELINE_STALE" } }),
    r("PRIEST.DISCIPLINE", "upgrade", 0.05, { reasons = { "BASELINE_FALLBACK" } }),
} }, { specs = "current", reveal = "CTRL" }, { currentSpec = "PRIEST.SHADOW" })
local foldedText = {}
for _, l in ipairs(folded) do foldedText[#foldedText + 1] = l.left .. (l.right and (" | " .. l.right) or "") end
foldedText = table.concat(foldedText, "\n")
check(foldedText:find("+ 2 other specs (hold Ctrl) | Holy +20.0%", 1, true) ~= nil, "folded: Holy's upgrade is named: " .. foldedText)
check(foldedText:find("Breaks a 2-piece set bonus (not scored)", 1, true) ~= nil, "...with its lost set bonus")
check(foldedText:find("Gear recorded over 14 days ago: Holy", 1, true) ~= nil, "...and its stale gear")
check(foldedText:find("other specs vs current gear", 1, true) == nil,
    "a spec still folded (Discipline, not named) adds no warning of its own")

-- Selected specs: the unselected ones fold.
GG.db.settings.tooltip.specs = "selected"
GG.db.settings.tooltip.selected = { ["PRIEST.HOLY"] = true }
WoW.showItem(tip, bagData(), WoW.bagButton(0, 1))
check(line(tip, "Holy") ~= nil and line(tip, "+ 1 other spec (hold Ctrl)") ~= nil, "selected: Holy shown, Discipline folded")
GG.db.settings.tooltip.selected = {}
GG.db.settings.tooltip.specs = "current"
-- The key's name follows the setting; no key, nothing to fold behind.
GG.db.settings.reveal.modifier = "ALT"
WoW.showItem(tip, bagData(), WoW.bagButton(0, 1))
check(line(tip, "+ 2 other specs (hold Alt)") ~= nil, "reveal key Alt: the line says Alt")
GG.db.settings.reveal.modifier = "NONE"
WoW.showItem(tip, bagData(), WoW.bagButton(0, 1))
check(line(tip, "other spec") == nil and line(tip, "Holy") == nil, "reveal key none: the scope as chosen, no fold line")
GG.db.settings.reveal.modifier = "CTRL"
-- A tooltip is a reveal surface on its own (PR #78 review): with no bag or
-- loot window open, a focus change while the key is held still unfolds it.
eq(next(GG.Reveal._surfaces), nil, "no bag or loot surface open")
local chatLink = WoW.newTooltip("ItemRefTooltip")
function chatLink:HookScript(event, fn) self.hooks = self.hooks or {}; self.hooks[event] = fn end
WoW.showItem(chatLink, { type = 0, id = 60, hyperlink = WoW.link(60) })
eq(GG.Reveal._surfaces[chatLink], true, "the tooltip is a reveal surface while shown")
check(GG.Reveal._Poller()._scripts.OnUpdate ~= nil, "...so the reveal poll runs")
WoW.focus = {}                                     -- typing in chat
WoW.keys.CTRL = true
WoW.fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
check(line(chatLink, "+ 2 other specs") ~= nil, "Ctrl while typing: still folded")
WoW.focus = nil                                    -- focus leaves the box, Ctrl still held
GG.Reveal._Poller()._scripts.OnUpdate(GG.Reveal._Poller(), 0.2)
check(line(chatLink, "Holy") ~= nil and line(chatLink, "+ 2 other specs") == nil,
    "the poll sees the focus leave and the tooltip unfolds")
WoW.keys.CTRL = nil
WoW.fire("MODIFIER_STATE_CHANGED", "LCTRL", 0)
chatLink:Hide()
chatLink.hooks.OnHide(chatLink)
eq(GG.Reveal._surfaces[chatLink], nil, "hidden: no longer a surface")
eq(GG.Reveal._Poller()._scripts.OnUpdate, nil, "...and the poll stops")
-- No current spec: nothing to fold to, every spec shows.
local function res(spec) return { status = "no_upgrade", spec = spec, score = { pct = 0 }, reasons = {}, limitations = {} } end
local noCur = GG.TooltipView.Build({ results = { res("PRIEST.HOLY"), res("PRIEST.SHADOW") } },
    { specs = "current", reveal = "CTRL" }, {})
eq(noCur and noCur[2].left .. "/" .. noCur[3].left, "Holy/Shadow", "no current spec: every spec, nothing folded")
GG.db.settings.tooltip.specs = "all"

-- Not for us: non-equippable items, comparison tooltips, forbidden tooltips.
WoW.items[61].stats = {}
WoW.showItem(tip, { type = 0, id = 61, hyperlink = WoW.link(61) })
eq(#tip.lines, 1, "a non-equippable item gets no block")
local shop = WoW.newTooltip("ShoppingTooltip1")
WoW.showItem(shop, { type = 0, id = 60, hyperlink = WoW.link(60) })
eq(#shop.lines, 1, "comparison tooltips get no block")
local forbidden = WoW.newTooltip("GameTooltip")
forbidden.forbidden = true
WoW.showItem(forbidden, bagData())
eq(#forbidden.lines, 1, "forbidden tooltips are left alone")

-- A chat link (ItemRefTooltip: hyperlink only) works the same.
local ref = WoW.newTooltip("ItemRefTooltip")
WoW.showItem(ref, { type = 0, id = 60, hyperlink = WoW.link(60) })
eq(ref.lines[3] and ref.lines[3].right, "+50.0%", "chat-link tooltip rows")

-- Level window: two levels above, default look-ahead 0 -> "at level 62 (in 2)".
WoW.showItem(ref, { type = 0, id = 62, hyperlink = WoW.link(62) })
eq(ref.lines[3].right, "at level 62 (in 2)", "above the level window: when, not a score")
GG.Prefs.Set("levelWindow.lookAhead", 2)     -- as the settings page does (invalidates)
WoW.flush()
GG.Tooltip.Reset()
WoW.showItem(ref, { type = 0, id = 62, hyperlink = WoW.link(62) })
eq(ref.lines[3].right, "+200.0% at level 62 (in 2)", "inside the look-ahead: scored, with the level")
-- A later item that loses keeps its level too (PR #33 review).
WoW.items[65] = { name = "Weak Far Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    minLevel = 62, stats = { [INT] = 5 } }
WoW.showItem(ref, { type = 0, id = 65, hyperlink = WoW.link(65) })
eq(ref.lines[3].right, "-50.0% at level 62 (in 2)", "a later-level loss says when it could be worn")
GG.db.settings.levelWindow.lookAhead = 0
GG.Tooltip.Reset()

-- Unscored parts of the replaced gear are named (PR #33 review): a plain
-- candidate against a proc item, and stats nobody can score.
WoW.equipped[3] = 63
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
WoW.flush()
WoW.showItem(ref, { type = 0, id = 60, hyperlink = WoW.link(60) })
check(line(ref, "The replaced item has an effect that isn't scored") ~= nil, "the replaced item's effect is flagged")
check(line(ref, "Has an effect that isn't scored") == nil, "...not the candidate's")
WoW.items[66] = { name = "Odd Mantle", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1,
    stats = { [INT] = 30, ITEM_MOD_MYSTERY_SHORT = 3 } }
WoW.showItem(ref, { type = 0, id = 66, hyperlink = WoW.link(66) })
check(line(ref, "Not scored: an unrecognised stat") ~= nil, "an unrecognised stat on the item is named")
WoW.equipped[3] = 66
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
WoW.flush()
WoW.showItem(ref, { type = 0, id = 60, hyperlink = WoW.link(60) })
check(line(ref, "Not scored on the replaced item: an unrecognised stat") ~= nil, "...and on the replaced item")
local refreshesBefore = ref.refreshes
WoW.equipped[3] = 50
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
WoW.flush()
check(ref.refreshes > refreshesBefore, "an invalidation refreshes the open tooltip")
ref.refreshes = 0

-- Unscored effects are named.
WoW.showItem(ref, { type = 0, id = 63, hyperlink = WoW.link(63) })
check(line(ref, "Has an effect that isn't scored") ~= nil, "an equip/use effect is flagged")

-- Pending: one request however often the tooltip rebuilds, then a refresh.
WoW.cacheMiss[64] = true
local before = GG.API._state.requestCount
WoW.showItem(ref, { type = 0, id = 64, hyperlink = WoW.link(64) })
eq(ref.lines[3].right, "checking...", "pending item: checking...")
WoW.showItem(ref, { type = 0, id = 64, hyperlink = WoW.link(64) })
WoW.showItem(ref, { type = 0, id = 64, hyperlink = WoW.link(64) })
eq(GG.API._state.requestCount, before + 1, "rebuilds reuse the one pending request")
WoW.cacheMiss[64] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 64, true)
WoW.flush()
eq(ref.refreshes, 1, "the open tooltip is refreshed once the data arrives")
eq(ref.lines[3].right, "+300.0%", "...with the real rows")

-- An owner with UpdateTooltip rebuilds itself: no forced refresh.
WoW.cacheMiss[64] = true
GG.Tooltip.Reset()
local selfUpdating = WoW.newTooltip("GameTooltip")
WoW.bags[0][2] = { itemID = 64, isBound = true, guid = "Item-1-BBB" }
WoW.showItem(selfUpdating, { type = 0, id = 64, guid = "Item-1-BBB" }, WoW.bagButton(0, 2, true))
WoW.cacheMiss[64] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 64, true)
WoW.flush()
eq(selfUpdating.refreshes, 0, "bag buttons with UpdateTooltip aren't force-refreshed")
WoW.showItem(selfUpdating, { type = 0, id = 64, guid = "Item-1-BBB" }, WoW.bagButton(0, 2, true))
eq(selfUpdating.lines[3].right, "+300.0%", "...and show the result on their next rebuild")

-- Equipment changes invalidate: the cached answer is dropped.
WoW.equipped[3] = 64
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
WoW.flush()
WoW.showItem(tip, bagData(), WoW.bagButton(0, 1))
eq(tip.lines[3].right, "-62.5%", "after equipping a better item, the same mantle is a loss")

-- A failure inside the hook never reaches the tooltip caller.
local saved = GG.API.Evaluate
GG.API.Evaluate = function() error("boom") end
GG.Tooltip.Reset()
local errs = #WoW.errors
H.ok(function() WoW.showItem(tip, bagData(), WoW.bagButton(0, 1)) end, "hook errors are caught")
eq(#WoW.errors, errs + 1, "...and reported to the error handler")
eq(#tip.lines, 1, "...leaving Blizzard's lines alone")
GG.API.Evaluate = saved

-- Registering again is a no-op.
eq(GG.Tooltip.Initialize(), true, "Initialize again: still on")
eq(#WoW.postCalls[0], 1, "...without a second post-call")

done("test_tooltip")
