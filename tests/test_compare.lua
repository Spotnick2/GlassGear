------------------------------------------------------------
-- test_compare.lua - GG-113: the detailed comparison (mockup 08). The pure
-- view (stat table, score, verdict, method/profile/source/baseline,
-- warnings, the companion in the candidate column) and the window driven
-- like a player: /gg compare with a link or the hovered item, spec tabs,
-- "no equipment recorded" with a saved set, pending data, invalidation,
-- View profile.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

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
H.eq(v.equipped, "Frostweave Shoulders", "equipped: the replaced item")
H.eq(v.candidate, "Moonwoven Mantle", "candidate")
local byLabel = {}
for _, row in ipairs(v.rows) do byLabel[row.label] = row end
H.eq(byLabel["Intellect"] and byLabel["Intellect"].change, "+4", "Intellect 8 -> 12: +4")
H.eq(byLabel["Intellect"].level, "ok", "...weighted, better: green")
H.eq(byLabel["Spell Damage"] and byLabel["Spell Damage"].change, "+6", "Spell power 12 -> 18: +6")
H.eq(byLabel["Stamina (not weighted)"] and byLabel["Stamina (not weighted)"].change, "-4", "Stamina shown, marked not weighted")
H.eq(byLabel["Stamina (not weighted)"].level, "muted", "...muted")
local vs = CV.Build(r, { specName = "Shadow", candidate = { name = "M", tokens = facts.tokens },
    replaced = { { name = "F", tokens = old.tokens } }, profile = { name = "T", weights = { Stamina = 1 } } })
local sta
for _, row in ipairs(vs.rows) do if row.label == "Stamina" then sta = row end end
H.eq(sta and sta.level, "error", "a weighted stat that goes down: red")
H.eq(v.score.equipped, "20.0", "item score on the profile scale: 20 (8 + 12)")
H.eq(v.score.candidate, "30.0", "...the candidate's: 30")
H.eq(v.score.change, "+50.0%", "...+50 %")
H.eq(v.status.text, "Potential upgrade for Shadow", "the verdict")
H.eq(v.info[1].text, "stat weights (item score estimate)", "method")
H.eq(v.info[2].text, "Shadow \226\128\148 Raid", "profile")
H.eq(v.info[3].text, "Imported Pawn weights", "source")
H.check(v.info[4].text:find("saved Shadow equipment", 1, true) ~= nil, "baseline")
H.eq(v.noBaseline, false, "the current spec always has gear")
local pend = CV.Build({ status = "pending", reasons = {}, limitations = {} }, { specName = "Shadow",
    candidate = { name = "X", tokens = {} }, replaced = {} })
H.eq(pend.status.text, "Checking...", "pending: checking")

------------------------------------------------------------
-- The window.
------------------------------------------------------------
SlashCmdList.GLASSGEAR("compare")
H.check(WoW.chat():find("usage: /gg compare", 1, true) ~= nil, "nothing hovered, nothing pasted: usage")
SlashCmdList.GLASSGEAR("compare " .. WoW.link(51))
local frame = Win._Frame()
local Wd = Win._W
H.check(frame and frame:IsShown(), "/gg compare <link> opens the window")
H.eq(Win._state.spec, "PRIEST.SHADOW", "...on the current spec")
H.eq(Wd.candidate:GetText(), "Moonwoven Mantle", "...the candidate")
H.eq(Wd.equipped:GetText(), "Frostweave Shoulders", "...what it replaces")
H.eq(Wd.score[4]:GetText(), "+50.0%", "...the score change")
H.eq(Wd.status:GetText(), "Potential upgrade for Shadow", "...the verdict")
H.check(H.has(UISpecialFrames, Win.NAME), "Escape closes it")

-- Holy: no recorded gear -> choose a saved set.
WoW.sets[3] = { name = "Holy Set", items = { [3] = 53 }, ignored = {} }
Wd.specs[2]:Click()
H.eq(Win._state.spec, "PRIEST.HOLY", "the Holy tab")
H.eq(Wd.noBase.shown, true, "no Holy equipment recorded: said so")
H.check(Wd.noBase:GetText():find("No Holy equipment recorded", 1, true) ~= nil, "...in words")
H.eq(Wd.sets[1].label_text, "Holy Set", "...with the saved sets offered")
H.eq(Wd.sets[2].shown, false, "...one button per set")
Wd.sets[1]:Click()
WoW.flush()
H.eq(GG.charDB.equipSetMap["PRIEST.HOLY"] and GG.charDB.equipSetMap["PRIEST.HOLY"].name, "Holy Set", "choosing it maps the set")
H.check(Wd.status:GetText():find("Not an upgrade for Holy", 1, true) ~= nil, "...the comparison follows (30 Int in the set beats it)")
H.eq(Wd.noBase.shown, false, "...and the notice is gone")
H.check(Wd.baseline:GetText():find("equipment set 'Holy Set'", 1, true) ~= nil, "...the gear line names the set")

-- Invalidation re-renders: new weights.
Wd.specs[3]:Click()
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Raid2": Class=Priest, Intellect=2 )')
WoW.flush()
H.eq(Wd.score[3]:GetText(), "24.0", "a weight change shows at once (2 x 12)")
H.eq(Wd.info[2][2]:GetText(), "Shadow \226\128\148 Raid2", "...and the profile line")

-- Warnings: an unmodelled set piece.
SlashCmdList.GLASSGEAR("compare " .. WoW.link(52))
H.check(Wd.warnings:GetText():find("bonus not scored", 1, true) ~= nil, "a set piece: the bonus isn't scored, said so")

-- A companion (a 1H against a 2H) is named in the candidate column.
local cv = CV.Build({ status = "upgrade", score = { candidate = 25, baseline = 20, delta = 5, pct = 0.25 },
    reasons = {}, limitations = {}, baseline = { source = "observed" } },
    { specName = "Holy", candidate = { name = "Mace", tokens = { Intellect = 15 } },
      companion = { name = "Orb", tokens = { Intellect = 10 } }, replaced = { { name = "Staff", tokens = { Intellect = 20 } } } })
H.eq(cv.candidate, "Mace + Orb", "a companion is named with the candidate")
H.eq(cv.rows[1].candidate, "25", "...and its stats count on the candidate side")

-- The hovered item.
local tip = WoW.newTooltip("GameTooltip")
WoW.showItem(tip, { type = 0, id = 51, hyperlink = WoW.link(51) })
SlashCmdList.GLASSGEAR("compare")
H.eq(Wd.candidate:GetText(), "Moonwoven Mantle", "/gg compare alone: the item last hovered")

-- Pending data, then the answer.
WoW.items[60] = shoulder("Late Mantle", { [INT] = 40 })
WoW.cacheMiss[60] = true
SlashCmdList.GLASSGEAR("compare " .. WoW.link(60))
H.eq(Wd.status:GetText(), "Checking...", "data loading: checking")
WoW.cacheMiss[60] = nil
WoW.fire("ITEM_DATA_LOAD_RESULT", 60, true)
WoW.flush()
H.eq(Wd.status:GetText(), "Potential upgrade for Shadow", "...then the verdict, without asking again")

-- View profile.
Wd.viewProfile:Click()
H.check(GG.ProfilesWindow._Frame() and GG.ProfilesWindow._Frame():IsShown(), "View profile opens the profiles window")
H.eq(GG.ProfilesWindow._state.spec, "PRIEST.SHADOW", "...on the compared spec")
Wd.close:Click()
H.eq(frame:IsShown(), false, "Close closes")

H.eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
for name in pairs(WoW.globalWrites) do H.check(false, "undeclared global written: " .. name) end
H.done("test_compare")
