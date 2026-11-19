------------------------------------------------------------
-- test_spec_mapping.lua - GG-104: mapping spec groups to specs on the
-- settings page. One radio column per group (+ Not set), saved per character,
-- the current spec re-resolved and answers invalidated; /gg spec through the
-- same Spec.Map (also "none"); the page follows a slash change; the active
-- and unlearned groups are labelled; read-only refuses; the tooltip hint.
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local GG = WoW.loadAddon()
local inval = {}
GG.API.RegisterCallback("EvaluationInvalidated", function(_, p) inval[#inval + 1] = p.reason end, "test_spec_mapping")

eq(GG.currentSpec, nil, "nothing mapped: no current spec")
local panel = GG.Options._Panel()
panel:Show()
local R = GG.Options.specRadios
check(R and #R == 2, "two radio columns (spec groups 1 and 2)")
eq(#R[1], 4, "...each: Discipline, Holy, Shadow, Not set")
local function radio(g, value) for _, rb in ipairs(R[g]) do if rb.value == value then return rb end end end
local function checked(g)
    local out = {}
    for _, rb in ipairs(R[g]) do if rb:GetChecked() then out[#out + 1] = rb.value end end
    return table.concat(out, ",")
end
eq(checked(1), "none", "group 1 starts on Not set")
eq(checked(2), "none", "group 2 too")

local function head(g) return GG.Options.specHeads[g]:GetText() end
eq(head(1), "Group 1 (active)", "the active group is labelled")
eq(head(2), "Group 2", "...the other isn't")

-- Choosing Shadow for group 1.
WoW.flush(); inval = {}
radio(1, "PRIEST.SHADOW"):Click()
WoW.flush()
eq(GG.charDB.specMap[1], "PRIEST.SHADOW", "the choice is saved for this character")
eq(GlassGearChar.specMap[1], "PRIEST.SHADOW", "...in the per-character SavedVariables")
eq(GG.currentSpec, "PRIEST.SHADOW", "...the current spec is resolved at once")
check(H.has(inval, "spec"), "...cached answers are invalidated")
eq(checked(1), "PRIEST.SHADOW", "...one radio checked in group 1")
check(GG.store:Get(GG.player.key .. ":PRIEST.SHADOW:baseline") ~= nil, "...and the spec's gear is recorded")

-- Group 2 to Holy; switching groups follows.
radio(2, "PRIEST.HOLY"):Click()
eq(GG.charDB.specMap[2], "PRIEST.HOLY", "group 2 -> Holy")
eq(GG.currentSpec, "PRIEST.SHADOW", "...the active group is still 1")
WoW.specGroup = 2
WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
WoW.flush()
eq(GG.currentSpec, "PRIEST.HOLY", "switching to group 2: Holy is current")
GG.Options.RefreshAll()
eq(head(2), "Group 2 (active)", "...the label moves to group 2")

-- A slash change while the page is open shows on it.
SlashCmdList.GLASSGEAR("spec 1 PRIEST.DISCIPLINE")
WoW.flush()
eq(checked(1), "PRIEST.DISCIPLINE", "/gg spec while the page is open: the radios follow")
SlashCmdList.GLASSGEAR("spec 1 none")
WoW.flush()
eq(GG.charDB.specMap[1], nil, "/gg spec 1 none clears the mapping")
eq(checked(1), "none", "...Not set is checked")
check(WoW.chatText():find("spec group 1 -> not set", 1, true) ~= nil, "...and says so")
SlashCmdList.GLASSGEAR("spec 1 WARRIOR.ARMS")
check(WoW.chatText():find("usage: /gg spec <1-2> <SPEC.KEY | none>", 1, true) ~= nil, "another class's spec: usage")
eq(GG.charDB.specMap[1], nil, "...nothing saved")

-- Not set on the active group: no current spec, the tooltip says where to set it.
radio(2, "none"):Click()
eq(GG.currentSpec, nil, "Not set on the active group: no current spec")
eq(GG.specReason, "unknown-spec", "...reason unknown-spec")
local view = GG.TooltipView.Build({ results = { { status = "no_upgrade", spec = "PRIEST.HOLY", reasons = {}, limitations = {} } } },
    GG.Engine.Policy and {} or {}, { currentSpec = nil })
local hint
for _, l in ipairs(view or {}) do if l.left:find("Current spec not set", 1, true) then hint = l.left end end
eq(hint, "Current spec not set: /gg options", "the tooltip points at the settings page")

-- Read-only: refused, nothing saved.
radio(2, "PRIEST.HOLY"):Click()
GG.readOnly = true
local ok, why = GG.Spec.Map(2, "PRIEST.SHADOW")
eq(ok, false, "read-only: Spec.Map refuses")
eq(why, "read-only", "...reason read-only")
GG.Options.RefreshAll()
eq(radio(2, "PRIEST.SHADOW"):IsEnabled(), false, "...the radios are disabled")
radio(2, "PRIEST.SHADOW"):Click()
eq(GG.charDB.specMap[2], "PRIEST.HOLY", "...a click changes nothing")
SlashCmdList.GLASSGEAR("spec 2 PRIEST.SHADOW")
check(WoW.chatText():find("read-only this session", 1, true) ~= nil, "...nor does /gg spec, which says why")
GG.readOnly = false

-- Pure guards.
eq(select(2, GG.Spec.Map(3, nil)), "bad-group", "group 3 doesn't exist")
eq(select(2, GG.Spec.Map(1, "MAGE.FIRE")), "not-this-class", "another class's spec is refused")
eq(GG.Spec.Map(2, "PRIEST.HOLY"), true, "the same mapping again is fine (no change)")

-- Without dual spec, group 2 is labelled.
WoW.numSpecGroups = 1
WoW.specGroup = 1
WoW.fire("ACTIVE_TALENT_GROUP_CHANGED", 1, 2)
WoW.flush()
GG.Options.RefreshAll()
eq(GG.Compat.NumSpecGroups(), 1, "GetNumSpecGroups read through Compat")
eq(head(2), "Group 2 (not learned)", "without dual spec, group 2 says it isn't learned")

eq(#WoW.errors, 0, "no error reached the error handler" .. (WoW.errors[1] and (": " .. tostring(WoW.errors[1])) or ""))
for name in pairs(WoW.globalWrites) do check(false, "undeclared global written: " .. name) end
-- FINDING (#83): the usage line for spec 1 WARRIOR.ARMS.
eq(H.acceptKnownStrays(), 1, "the /gg spec usage line's bare | (#83), and no other stray")
done("test_spec_mapping")
