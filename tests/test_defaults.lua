------------------------------------------------------------
-- test_defaults.lua - GG-120: Glass Gear's default weights
-- (docs/research/default-weights.md, owner decisions 2026-11-01).
--
--   * the shipped table is empty (measured numbers only): nothing changes;
--   * a spec without an import scores with its default, labelled; an import
--     replaces it; the setting turns them off; never stored or synced;
--   * the tooltip tags the row "default weights" and says how to do better;
--     arrows draw normally;
--   * protection is soft: a default upgrade protects, a default "no upgrade"
--     is unchecked (it follows noWeights), never a reason for clear.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local INT, HEAL, SPI, SP = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT", "ITEM_MOD_SPIRIT_SHORT",
    "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"
local function shoulder(name, stats) return { name = name, equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 1, stats = stats } end
WoW.items[50] = shoulder("Old Mantle", { [INT] = 10 })
WoW.items[70] = shoulder("Healer Mantle", { [HEAL] = 30 })      -- Holy (default) up, Shadow down
WoW.items[63] = shoulder("Dim Mantle", { [INT] = 5 })           -- nobody's upgrade
WoW.equipped[3] = 50
WoW.bags[0] = { [1] = { itemID = 70, isBound = true }, [2] = { itemID = 63, isBound = true } }

local GG = WoW.loadAddon()
local api, D = GG.API, GG.Data.Defaults

-- What ships: nothing yet.
H.eq(D.Any(), false, "the shipped table is empty: measured numbers only (owner, 2026-11-01)")
H.eq(D.REVISION, 0, "...revision 0")
H.eq(api.GetCapabilities().features.defaultWeights, false, "...features.defaultWeights false")
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
SlashCmdList.GLASSGEAR('import PRIEST.SHADOW ( Pawn: v1: "Shadow": Class=Priest, Intellect=1, SpellDamage=1 )')
WoW.flush()
local function row(ref, spec)
    for _, r in ipairs(api.Evaluate({ item = ref, scope = "own" }).results) do if r.spec == spec then return r end end
end
H.eq(row({ bag = 0, slot = 1 }, "PRIEST.HOLY").reasons[1], "NO_WEIGHTS", "no defaults shipped: Holy has no weights")

-- A table as the owner's sims will fill it.
D.SPECS = {
    ["PRIEST.HOLY"] = { weights = { Healing = 1, Intellect = 0.6, Spirit = 0.7 } },
    ["PRIEST.DISCIPLINE"] = { weights = { Healing = 0.1, Intellect = 0.5 } },
}
D.REVISION, D.SOURCE = 1, "MythicSim stat weights (test)"
api._Invalidate("test")
H.eq(api.GetCapabilities().features.defaultWeights, true, "a filled table: features.defaultWeights")

local holy = row({ bag = 0, slot = 1 }, "PRIEST.HOLY")
H.eq(holy.status, "upgrade", "Holy scores with its default: the healer mantle is an upgrade")
H.eq(holy.profile.source, "default", "...profile source default")
H.eq(holy.profile.id, "default:PRIEST.HOLY", "...id default:<spec>")
H.eq(holy.profile.version, "defaults-1", "...the table's revision as its version")
H.check(H.has(holy.limitations, "DEFAULT_WEIGHTS"), "...limitation DEFAULT_WEIGHTS")
H.eq(H.has(row({ bag = 0, slot = 1 }, "PRIEST.SHADOW").limitations, "DEFAULT_WEIGHTS"), false, "an imported spec: no DEFAULT_WEIGHTS")
H.eq(api.GetProfile(GG.player.key, "PRIEST.HOLY").source, "default", "GetProfile: what Holy scores with, the default")
local none, why = api.GetProfile("Player-1-NOBODY", "PRIEST.HOLY")
H.eq(none == nil and why, "UNKNOWN_CHARACTER", "...never a default for a character Glass Gear doesn't know")
none, why = api.GetProfile(GG.player.key, "MAGE.FROST")
H.eq(none == nil and why, "UNKNOWN_SPEC", "...nor for another class's spec")
D.SPECS["MAGE.FROST"] = { weights = { Intellect = 1 } }
none, why = api.GetProfile(GG.player.key, "MAGE.FROST")
H.eq(none == nil and why, "UNKNOWN_SPEC", "...even when that spec has a default")
D.SPECS["MAGE.FROST"] = nil
local specs = api.GetSpecs(GG.player.key)
local holySpec
for _, s in ipairs(specs) do if s.key == "PRIEST.HOLY" then holySpec = s end end
H.eq(holySpec.hasProfile, false, "GetSpecs' hasProfile stays the player's own import")
for id in pairs(GG.db.entries) do H.check(not id:find("^default:"), "defaults are never stored: " .. id) end
SlashCmdList.GLASSGEAR("")
H.check(WoW.chat():find("PRIEST.HOLY: Glass Gear default weights [default]", 1, true) ~= nil, "/gg names the default")

-- The tooltip: tagged rows, one line on how to do better.
local function text(ref, key)
    local out = {}
    for _, l in ipairs(GG.TooltipView.Build(GG.Results.Get(ref, key), GG.Tooltip.ViewSettings(), { currentSpec = GG.currentSpec }) or {}) do
        out[#out + 1] = l.left .. (l.right and (" = " .. l.right) or "")
    end
    return table.concat(out, "\n")
end
local t = text({ bag = 0, slot = 1 }, "d1")
H.check(t:find("Holy  " .. GG.TooltipView.DEFAULT_TAG .. " = +", 1, true) ~= nil, "Holy's row is tagged default weights: " .. t)
H.check(t:find("Shadow  " .. GG.TooltipView.BADGE .. " =", 1, true) ~= nil, "...Shadow's (imported) isn't")
H.check(t:find("Default weights: import your own for better advice (/gg profiles)", 1, true) ~= nil, "...and the tooltip says how to do better")

-- The comparison names the source.
local cv = GG.CompareView.Build(holy, { specKey = "PRIEST.HOLY", specName = "Holy", candidate = { name = "Healer Mantle", tokens = {} },
    profile = api.GetProfile(GG.player.key, "PRIEST.HOLY") })
local source
for _, i in ipairs(cv and cv.info or {}) do if i.label == "Source" then source = i.text end end
H.eq(source, "default weights (not tuned to your gear)", "the comparison says the weights are defaults")

-- Protection: soft.
local p = api.AssessProtection({ bag = 0, slot = 1 })
H.eq(p.verdict, "protect", "a default-based upgrade protects (keeping is the safe direction)")
H.eq(p.recipients[1].spec, "PRIEST.HOLY", "...for Holy")
H.eq(p.recipients[1].defaultWeights, true, "...flagged default weights")
p = api.AssessProtection({ bag = 0, slot = 2 })
H.eq(p.verdict, "clear", "nobody's upgrade: Shadow's real weights decide (clear)")
H.eq(#p.unchecked, 2, "...the two default specs are unchecked, not reasons for clear")
H.check(H.has(p.reasons, "UNCHECKED_SPECS"), "...UNCHECKED_SPECS")
p = api.AssessProtection({ bag = 0, slot = 2 }, { noWeights = "keep" })
H.eq(p.verdict, "unknown", "noWeights keep: a default no-upgrade keeps the item")
H.check(H.has(p.reasons, "DEFAULT_WEIGHTS"), "...DEFAULT_WEIGHTS")
GG.Prefs.SetTracked(GG.player.key, "PRIEST.SHADOW", false, { "PRIEST.DISCIPLINE", "PRIEST.HOLY", "PRIEST.SHADOW" })
p = api.AssessProtection({ bag = 0, slot = 2 })
H.eq(p.verdict, "unknown", "only default specs tracked and no upgrade: unknown, never clear")
GG.Prefs.SetTracked(GG.player.key, "PRIEST.SHADOW", true, { "PRIEST.DISCIPLINE", "PRIEST.HOLY", "PRIEST.SHADOW" })

-- Arrows draw normally on a default.
SlashCmdList.GLASSGEAR("spec 1 PRIEST.HOLY")
WoW.flush()
local bag = ContainerFrameContainer.ContainerFrames[1]
WoW.showBag(bag, { { 0, 1 }, { 0, 2 } })
WoW.flush()
local m = GG.BagMarkers._marks[bag.Items[1]]
H.eq(m and m:IsShown() and m.kind, "green", "Holy current, a default-based upgrade: a normal green arrow")
SlashCmdList.GLASSGEAR("spec 1 PRIEST.SHADOW")
WoW.flush()

-- An import replaces the default; nothing merged.
SlashCmdList.GLASSGEAR('import PRIEST.HOLY ( Pawn: v1: "Holy": Class=Priest, Intellect=1 )')
WoW.flush()
holy = row({ bag = 0, slot = 1 }, "PRIEST.HOLY")
H.eq(holy.profile.source, "imported-pawn", "an import replaces Holy's default")
H.eq(holy.status, "no_upgrade", "...its own weights (Intellect only) decide")
H.eq(H.has(holy.limitations, "DEFAULT_WEIGHTS"), false, "...no DEFAULT_WEIGHTS")
H.check(text({ bag = 0, slot = 1 }, "d2"):find("Holy  " .. GG.TooltipView.DEFAULT_TAG, 1, true) == nil, "...and no tag")

-- The setting: off brings back "no weights".
local disc = row({ bag = 0, slot = 1 }, "PRIEST.DISCIPLINE")
H.eq(disc.profile.source, "default", "Discipline still on its default")
H.eq(GG.Prefs.Set("defaults.enabled", false), true, "defaults.enabled can be turned off")
H.eq(row({ bag = 0, slot = 1 }, "PRIEST.DISCIPLINE").reasons[1], "NO_WEIGHTS", "...then Discipline has no weights")
H.eq(GG.Prefs.Set("defaults.enabled", "yes"), false, "...the setting takes booleans only")
GG.Prefs.Set("defaults.enabled", true)
H.eq(row({ bag = 0, slot = 1 }, "PRIEST.DISCIPLINE").profile.source, "default", "...on again: the default")

-- The settings page offers the switch only when there are defaults.
SlashCmdList.GLASSGEAR("options")
local box
for _, f in ipairs(WoW.frames) do
    if f.label and f.label.text == "Default weights for specs without an import" then box = f end
end
H.check(box ~= nil, "the settings page has the default weights switch")
H.eq(box and box:GetChecked(), true, "...on")

H.eq(#WoW.errors, 0, "no errors" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
H.done("test_defaults")
