------------------------------------------------------------
-- Core/Main.lua - lifecycle (loaded last). ADDON_LOADED: SavedVariables,
-- the Glass UI question and the theme. PLAYER_LOGIN: character, spec,
-- entry store, then Ready. Nothing here hooks tooltips or bags yet (M1).
------------------------------------------------------------

local GG = GlassGear
local frame = CreateFrame("Frame")
GG.frame = frame

-- A fresh writer token every session (adr/0001): never persisted.
local function newWriter()
    return string.format("%x%x", math.floor(GetTime() * 1000) % 0x7fffffff, math.random(0, 0x7fffffff))
end

function GG.ResolveSpec()
    local group = GG.Compat.ActiveSpecGroup()
    GG.currentSpec, GG.specReason = GG.Spec.Resolve(GG.player.class, GG.charDB.specMap, group, nil)
end

local ticking = false
local function tick()
    if GG.API._Tick(GetTime()) then
        C_Timer.After(1, tick)
    else
        ticking = false
    end
end

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= GG.NAME then return end
    frame:UnregisterEvent("ADDON_LOADED")
    GlassGearDB, GlassGearChar, GG.readOnly = GG.DB.Load(GlassGearDB, GlassGearChar)
    if GG.readOnly then
        -- Newer data than this code: leave it untouched, work on in-memory defaults.
        GG.db, GG.charDB = GG.DB.Load({}, {})
    else
        GG.db, GG.charDB = GlassGearDB, GlassGearChar
    end
    GG.suite = GG.Integrations.GlassUI.Ask()
    GG.themeName, GG.themeInfo = GG.Theme.Decide(GG.suite)
end

function handlers.PLAYER_LOGIN()
    GG.player = GG.Compat.Player()
    GG.store = GG.Engine.EntrySync.New(GG.db.entries, newWriter())
    GG.ResolveSpec()
    GG.Diagnostics.RegisterSettings()
    GG.API._SetReady()
end

function handlers.ACTIVE_TALENT_GROUP_CHANGED()
    if GG.player then
        GG.ResolveSpec()
        GG.Callbacks.Fire("EvaluationInvalidated", { reason = "spec" })
    end
end

function handlers.PLAYER_EQUIPMENT_CHANGED()
    if GG.player then
        GG.Callbacks.Fire("EquipmentChanged", { charKeys = { GG.player.key } })
        GG.Callbacks.Fire("EvaluationInvalidated", { reason = "equipment" })
    end
end

-- Started by the API when an item begins waiting for its data.
function GG.StartTick()
    if not ticking then ticking = true; C_Timer.After(1, tick) end
end

local function itemArrived(itemID)
    if GG.player and itemID then GG.API._ItemDataArrived(itemID) end
end
handlers.GET_ITEM_INFO_RECEIVED = itemArrived
handlers.ITEM_DATA_LOAD_RESULT = itemArrived

for event in pairs(handlers) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)

SLASH_GLASSGEAR1 = "/glassgear"
SLASH_GLASSGEAR2 = "/gg"
SlashCmdList.GLASSGEAR = function(msg) GG.Diagnostics.Slash(msg) end
