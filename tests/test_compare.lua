------------------------------------------------------------
-- test_compare.lua - GG-113: the detailed comparison (mockup 08). The pure
-- view (stat table, score, verdict, method/profile/source/baseline,
-- warnings, the companion in the candidate column) and the window driven
-- like a player: /gg compare with a link or the hovered item, spec tabs,
-- "no equipment recorded" with a saved set, pending data, invalidation,
-- View profile.
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local INT, STA, SP = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_SPELL_POWER_SHORT"
local function shoulder(name, stats, extra)
    local t = { name = name, equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = stats }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end
WoW.items[50] = shoulder("Frostweave Shoulders", { [INT] = 8, [STA] = 12, [SP] = 12 })
WoW.items[51] = shoulder("Moonwoven Mantle", { [INT] = 12, [STA] = 8, [SP] = 18 })
WoW.items[52] = shoulder("Set Mantle", { [INT] = 9 }, { setID = 999999 })
WoW.items[53] = shoulder("Saved Mantle", { [INT] = 30 })
WoW.items[55] = shoulder("Plate Pauldrons", { [INT] = 40 }, { subclassID = 4 })   -- priests can't wear plate
WoW.items[10] = { name = "Staff", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 10, stats = { [INT] = 20 } }
WoW.items[11] = { name = "Mace", equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subclassID = 4, stats = { [INT] = 15 } }
WoW.items[12] = { name = "Orb", equipLoc = "INVTYPE_HOLDABLE", classID = 4, subclassID = 0, stats = { [INT] = 10 } }
WoW.equipped = { [3] = 50, [16] = 10 }
WoW.bags[0] = { [1] = { itemID = 53, isBound = true } }

local GG = WoW.loadAddon()
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR("spec 2 PRIEST.HOLY")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Raid": Class=Priest, Intellect=1, SpellDamage=1 )')
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Heal": Class=Priest, Intellect=1, Healing=1 )')
WoW.flush()
local CV, Win = GG.CompareView, GG.CompareWindow

------------------------------------------------------------
-- The view, pure.
------------------------------------------------------------
local r = GG.API.Evaluate({ item = WoW.link(51), scope = "current" }).results[1]
local facts = GG.Compat.ItemFacts(WoW.link(51))
local old = GG.Compat.ItemFacts(r.replaces.items[1])
local v = CV.Build(r, { specKey = "PRIEST.SHADOW", specName = "Shadow", current = true,
    candidate = { name = "Moonwoven Mantle", tokens = facts.tokens },
    replaced = { { name = "Frostweave Shoulders", tokens = old.tokens } },
    profile = GG.Profiles.Active(GG.store, GG.player.key, "PRIEST.SHADOW"), baselineText = "now" })
eq(v.equipped, "Frostweave Shoulders", "equipped: the replaced item")
eq(v.candidate, "Moonwoven Mantle", "candidate")
local byLabel = {}
for _, row in ipairs(v.rows) do byLabel[row.label] = row end
eq(byLabel["Intellect"] and byLabel["Intellect"].change, "+4", "Intellect 8 -> 12: +4")
eq(byLabel["Intellect"].level, "ok", "...weighted, better: green")
eq(byLabel["Spell Damage"] and byLabel["Spell Damage"].change, "+6", "Spell power 12 -> 18: +6")
eq(byLabel["Stamina (not weighted)"] and byLabel["Stamina (not weighted)"].change, "-4", "Stamina shown, marked not weighted")
eq(byLabel["Stamina (not weighted)"].level, "muted", "...muted")
local vs = CV.Build(r, { specName = "Shadow", candidate = { name = "M", tokens = facts.tokens },
    replaced = { { name = "F", tokens = old.tokens } }, profile = { name = "T", weights = { Stamina = 1 } } })
local sta
for _, row in ipairs(vs.rows) do if row.label == "Stamina" then sta = row end end
eq(sta and sta.level, "error", "a weighted stat that goes down: red")
eq(v.score.equipped, "20.0", "item score on the profile scale: 20 (8 + 12)")
eq(v.score.candidate, "30.0", "...the candidate's: 30")
eq(v.score.change, "+50.0%", "...+50 %")
eq(v.status.text, "Potential upgrade for Shadow", "the verdict")
eq(v.info[1].text, "stat weights (item score estimate)", "method")
eq(v.info[2].text, "Shadow \226\128\148 Raid", "profile")
eq(v.info[3].text, "Imported Pawn weights", "source")
check(v.info[4].text:find("saved Shadow equipment", 1, true) ~= nil, "baseline")
eq(v.noBaseline, false, "the current spec always has gear")
local pend = CV.Build({ status = "pending", reasons = {}, limitations = {} }, { specName = "Shadow",
    candidate = { name = "X", tokens = {} }, replaced = {} })
eq(pend.status.text, "Checking...", "pending: checking")

-- Weapon details and type flags only when weighted; weighted stats first.
local function rowsOf(view) local t = {} for _, x in ipairs(view.rows) do t[#t + 1] = x.label end return table.concat(t, ",") end
local wv = CV.Build({ status = "no_upgrade", reasons = {}, limitations = {}, score = { candidate = 1, baseline = 1, delta = 0 } },
    { specName = "S", candidate = { name = "A", tokens = { Intellect = 5, IsCloth = 1, Speed = 2.6, MinDamage = 10, MeleeDps = 40 } },
      replaced = { { name = "B", tokens = { Intellect = 4, IsCloth = 1, Speed = 2.4 } } }, profile = { name = "P", weights = {} } })
eq(rowsOf(wv), "Intellect (not weighted)", "type flags, speeds, damage ranges and DPS variants hidden when unweighted")
wv = CV.Build({ status = "no_upgrade", reasons = {}, limitations = {}, score = { candidate = 1, baseline = 1, delta = 0 } },
    { specName = "S", candidate = { name = "A", tokens = { Intellect = 5, Speed = 2.6 } },
      replaced = { { name = "B", tokens = { Intellect = 4, Speed = 2.4 } } }, profile = { name = "P", weights = { Speed = 1 } } })
eq(rowsOf(wv), "Weapon Speed,Intellect (not weighted)", "...shown when weighted, and weighted stats come first")
local many = {}
for i, t in ipairs({ "Strength", "Agility", "Stamina", "Intellect", "Spirit", "Armor", "HitRating", "CritRating",
    "HasteRating", "ExpertiseRating", "SpellPenetration", "Ap", "Rap", "Mp5" }) do many[t] = i end
wv = CV.Build({ status = "no_upgrade", reasons = {}, limitations = {}, score = { candidate = 1, baseline = 1, delta = 0 } },
    { specName = "S", candidate = { name = "A", tokens = many }, replaced = {}, profile = { name = "P", weights = { Mp5 = 1 } } })
eq(wv.rows[1].label, "Mana per 5 sec", "a weighted stat is never cut by the row limit")
eq(wv.moreRows, 2, "...rows past the limit are counted")
check(wv.warnings[#wv.warnings]:find("2 more unweighted stats not shown", 1, true) ~= nil, "...and said")
local neg = CV.Build({ status = "no_upgrade", reasons = {}, limitations = {}, score = { candidate = 5, baseline = 8, delta = -3 } },
    { specName = "S", candidate = { name = "A", tokens = {} }, replaced = {} })
eq(neg.score.level, "error", "a negative change without a percentage is red")
local setv = function(on) return CV.Build({ status = "upgrade", reasons = {}, limitations = { "SET_BONUS_GAINED:1:2" },
    score = { candidate = 2, baseline = 1, delta = 1, pct = 1 }, baseline = { source = "observed" } },
    { specName = "S", candidate = { name = "A", tokens = {} }, replaced = {}, setWarnings = on }) end
local function anyWarning(view, needle) for _, w in ipairs(view.warnings) do if w:find(needle, 1, true) then return true end end return false end
eq(anyWarning(setv(true), "Completes a 2-piece"), true, "set-bonus warnings on: named")
eq(anyWarning(setv(false), "Completes a 2-piece"), false, "...off (the setting): not named")
local lv = CV.Build({ status = "upgrade", reasons = {}, limitations = {}, score = { candidate = 2, baseline = 1, delta = 1, pct = 1 } },
    { specName = "S", candidate = { name = "A", tokens = { Intellect = 1 } }, replaced = { { name = "B", tokens = nil } } })
eq(lv.loading, true, "a replaced item still loading: loading")
eq(#lv.rows, 0, "...no stat rows (never zeros)")
check(anyWarning(lv, "still loading"), "...and said")

------------------------------------------------------------
-- The window.
------------------------------------------------------------
SlashCmdList.GLASSGEAR("compare")
check(WoW.chatText():find("usage: /gg compare", 1, true) ~= nil, "nothing hovered, nothing pasted: usage")
SlashCmdList.GLASSGEAR("compare " .. WoW.link(51))
local frame = Win._Frame()
local Wd = Win._W
check(frame and frame:IsShown(), "/gg compare <link> opens the window")
eq(Win._state.spec, "PRIEST.SHADOW", "...on the current spec")
eq(Wd.candidate:GetText(), "Moonwoven Mantle", "...the candidate")
eq(Wd.equipped:GetText(), "Frostweave Shoulders", "...what it replaces")
eq(Wd.score[4]:GetText(), "+50.0%", "...the score change")
eq(Wd.status:GetText(), "Potential upgrade for Shadow", "...the verdict")
check(H.has(UISpecialFrames, Win.NAME), "Escape closes it")
eq(frame.titleText:GetText(), "Glass Gear \194\183 Compare", "the title (a middle dot)")
check(Wd.info[4][2]:GetText() == "saved Shadow equipment", "the baseline line is short (no repeated status)")

-- Holy: no recorded gear -> choose a saved set.
WoW.sets[3] = { name = "Holy Set", items = { [3] = 53 }, ignored = {} }
Wd.specs[2]:Click()
eq(Win._state.spec, "PRIEST.HOLY", "the Holy tab")
eq(Wd.noBase._shown, true, "no Holy equipment recorded: said so")
eq(Wd.baseline:GetText(), "Holy gear: none recorded (compared with your current gear)", "...the gear line short")
check(Wd.noBase:GetText():find("No Holy equipment recorded", 1, true) ~= nil, "...in words")
eq(Wd.sets[1]._text, "Holy Set", "...with the saved sets offered")
eq(Wd.sets[2]._shown, false, "...one button per set")
Wd.sets[1]:Click()
WoW.flush()
eq(GG.charDB.equipSetMap["PRIEST.HOLY"] and GG.charDB.equipSetMap["PRIEST.HOLY"].name, "Holy Set", "choosing it maps the set")
check(Wd.status:GetText():find("Not an upgrade for Holy", 1, true) ~= nil, "...the comparison follows (30 Int in the set beats it)")
eq(Wd.noBase._shown, false, "...and the notice is gone")
check(Wd.baseline:GetText():find("equipment set 'Holy Set'", 1, true) ~= nil, "...the gear line names the set")

-- Invalidation re-renders: new weights.
Wd.specs[3]:Click()
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Raid2": Class=Priest, Intellect=2 )')
WoW.flush()
eq(Wd.score[3]:GetText(), "24.0", "a weight change shows at once (2 x 12)")
eq(Wd.info[2][2]:GetText(), "Shadow \226\128\148 Raid2", "...and the profile line")

-- Warnings: an unmodelled set piece.
SlashCmdList.GLASSGEAR("compare " .. WoW.link(52))
check(Wd.warnings:GetText():find("bonus not scored", 1, true) ~= nil, "a set piece: the bonus isn't scored, said so")

-- A companion (a 1H against a 2H) is named in the candidate column.
local cv = CV.Build({ status = "upgrade", score = { candidate = 25, baseline = 20, delta = 5, pct = 0.25 },
    reasons = {}, limitations = {}, baseline = { source = "observed" } },
    { specName = "Holy", candidate = { name = "Mace", tokens = { Intellect = 15 } },
      companion = { name = "Orb", tokens = { Intellect = 10 } }, replaced = { { name = "Staff", tokens = { Intellect = 20 } } } })
eq(cv.candidate, "Mace + Orb", "a companion is named with the candidate")
eq(cv.rows[1].candidate, "25", "...and its stats count on the candidate side")

-- No configuration compared (no weights, ineligible...): never an empty
-- slot, never deltas against zeros; the candidate's own stats only.
local nv = CV.Build({ status = "unknown", reasons = { "NO_WEIGHTS" }, limitations = {} },
    { specName = "Discipline", candidate = { name = "Moonwoven Mantle", tokens = facts.tokens }, replaced = nil })
eq(nv.compared, false, "a result without a configuration: not compared")
eq(nv.equipped, "not compared", "...the equipped side says so (not an empty slot)")
local nb = {}
for _, row in ipairs(nv.rows) do nb[row.label] = row end
eq(nb["Intellect (not weighted)"] and nb["Intellect (not weighted)"].candidate, "12", "...the candidate's stats shown")
eq(nb["Intellect (not weighted)"].equipped, "", "...no equipped value")
eq(nb["Intellect (not weighted)"].change, "", "...no change against zero")
eq(nv.score, nil, "...and no item score")
SlashCmdList.GLASSGEAR("compare " .. WoW.link(51))
Wd.specs[1]:Click()
eq(Win._state.spec, "PRIEST.DISCIPLINE", "the Discipline tab (no weights)")
check(Wd.status:GetText():find("Discipline", 1, true) ~= nil, "...its verdict: " .. Wd.status:GetText())
eq(Wd.equipped:GetText(), "not compared", "...the worn shoulders aren't shown as an empty slot")
for _, row in ipairs(Wd.rows) do
    eq(row[2]:GetText(), "", "...no equipped stat (" .. tostring(row[1]:GetText()) .. ")")
    eq(row[4]:GetText(), "", "...no change")
end
SlashCmdList.GLASSGEAR("compare " .. WoW.link(55))
Wd.specs[3]:Click()
eq(Win._state.spec, "PRIEST.SHADOW", "a plate item on Shadow")
eq(GG.API.Evaluate({ item = WoW.link(55), scope = "current" }).results[1].status, "ineligible", "(ineligible for Shadow: plate)")
eq(Wd.equipped:GetText(), "not compared", "an ineligible item: not compared, not an empty slot")
eq(Wd.score[2]:GetText(), "", "...no item score against zero")

-- The hovered item.
local tip = WoW.newTooltip("GameTooltip")
WoW.showItem(tip, { type = 0, id = 51, hyperlink = WoW.link(51) })
SlashCmdList.GLASSGEAR("compare")
eq(Wd.candidate:GetText(), "Moonwoven Mantle", "/gg compare alone: the item last hovered")

-- Pending data, then the answer.
WoW.items[60] = shoulder("Late Mantle", { [INT] = 40 })
WoW.cacheMiss[60] = true
SlashCmdList.GLASSGEAR("compare " .. WoW.link(60))
eq(Wd.status:GetText(), "Checking...", "data loading: checking")
WoW.cacheMiss[60] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 60, true)
WoW.flush()
eq(Wd.status:GetText(), "Potential upgrade for Shadow", "...then the verdict, without asking again")

-- A hovered bag item is remembered by its link, not its bag position.
WoW.bags[0][9] = { itemID = 51, isBound = true }
local btip = WoW.newTooltip("GameTooltip")
btip.GetOwner = function() return { GetBagID = function() return 0 end, GetID = function() return 9 end } end
GG.Tooltip._OnItemTooltip(btip, { type = 0, id = 51 })
eq(type(GG.Tooltip.lastRef), "string", "the hovered bag item is kept as its link")
WoW.bags[0][9] = { itemID = 50, isBound = true }   -- the bags were sorted
SlashCmdList.GLASSGEAR("compare")
eq(Wd.candidate:GetText(), "Moonwoven Mantle", "...so a sort doesn't change what /gg compare compares")
WoW.bags[0][9] = nil

-- A replaced item still loading, then shown.
WoW.items[54] = shoulder("Slow Mantle", { [INT] = 1 })
GG.API._cache.clear()
WoW.sets[3].items[3] = 54
WoW.bags[0][1] = { itemID = 54, isBound = true }
WoW.cacheMiss[54] = true
WoW.fire("EQUIPMENT_SETS_CHANGED")
WoW.flush()
Wd.specs[2]:Click()
WoW.flush()
check(Wd.warnings:GetText():find("still loading", 1, true) ~= nil or Wd.status:GetText() == "Checking...",
    "a set item still loading: never shown as zeros")

-- Closing leaves nothing running.
WoW.items[61] = shoulder("Pending Mantle", { [INT] = 50 })
WoW.cacheMiss[61] = true
SlashCmdList.GLASSGEAR("compare " .. WoW.link(61))
local reqs = GG.API._state.requestCount
check(reqs > 0, "a pending comparison holds a request")
frame:Hide()
eq(GG.API._state.requestCount, reqs - 1, "closing the window cancels it")
WoW.cacheMiss[61], WoW.cacheMiss[54] = nil, nil

-- View profile.
Wd.viewProfile:Click()
check(GG.ProfilesWindow._Frame() and GG.ProfilesWindow._Frame():IsShown(), "View profile opens the profiles window")
eq(GG.ProfilesWindow._state.spec, "PRIEST.SHADOW", "...on the compared spec")
eq(GG.ProfilesWindow._Frame().titleText:GetText(), "Glass Gear \194\183 Profiles", "the profiles window title (a middle dot)")
Wd.close:Click()
eq(frame:IsShown(), false, "Close closes")

-- A class with four specs: every tab inside the window.
Win._Reset()
GG.player.class = "DRUID"
SlashCmdList.GLASSGEAR("compare " .. WoW.link(51))
local tabs = Win._W.specs
eq(#tabs, 4, "a Druid gets four tabs")
check(tabs[4].x ~= nil and tabs[4].x + 100 <= Win.W, "...the fourth inside the window")
GG.player.class = "PRIEST"
Win._Reset()

eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
for name in pairs(WoW.globalWrites) do check(false, "undeclared global written: " .. name) end
done("test_compare")
