------------------------------------------------------------
-- UI/Reveal.lua - the reveal modifier (GG-110).
--
-- Effective reveal = the chosen modifier is down (either side) and no edit
-- box has keyboard focus (Policy.NewReveal). It is recomputed:
--   * on MODIFIER_STATE_CHANGED;
--   * whenever a reveal surface (bags; loot with GG-111) shows or is redrawn;
--   * by a 0.1 s poll that runs only while a surface is visible, so a release
--     while typing in chat (no modifier event reaches us then) still clears it.
-- Listeners hear only real changes. Glass Gear never consumes a click: Ctrl-
-- click still opens the dressing room. Nothing is saved; no reload.
------------------------------------------------------------

local GG = GlassGear
local Reveal = {}
GG.Reveal = Reveal

Reveal.POLL = 0.1

local state = GG.Engine.Policy.NewReveal()
local surfaces = {}           -- [frame] = true while shown
local listeners = {}
local poller, events
local elapsed = 0

local function modifier()
    return GG.db and GG.db.settings.reveal.modifier or "CTRL"
end

local function notify(active)
    local handler = geterrorhandler()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, active)
        if not ok then handler("GlassGear reveal: " .. tostring(err)) end
    end
end

function Reveal.Listen(fn) listeners[#listeners + 1] = fn end

function Reveal.Active() return state.active end

-- Recompute from the live inputs. `quiet` skips the listeners (a surface
-- redrawing itself already uses the fresh state).
function Reveal.Update(quiet)
    local active, changed = state:Update(modifier(), GG.Compat.ModifierDown(modifier()),
        GG.Compat.KeyboardFocused())
    if changed and not quiet then notify(active) end
    return active, changed
end

local function anySurface()
    for _ in pairs(surfaces) do return true end
    return false
end

local function onUpdate(_, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < Reveal.POLL then return end
    elapsed = 0
    Reveal.Update()
end

-- A reveal surface showed or hid: the poll runs only while one is visible.
function Reveal.SurfaceShown(frame, isShown)
    surfaces[frame] = isShown and true or nil
    if poller then
        if anySurface() then
            poller:SetScript("OnUpdate", onUpdate)
        else
            poller:SetScript("OnUpdate", nil)
            elapsed = 0
        end
    end
    Reveal.Update()
end

function Reveal.Initialize()
    if events then return end
    events = CreateFrame("Frame")
    poller = CreateFrame("Frame")
    events:RegisterEvent("MODIFIER_STATE_CHANGED")
    events:SetScript("OnEvent", function()
        local ok, err = pcall(Reveal.Update)
        if not ok then geterrorhandler()("GlassGear reveal: " .. tostring(err)) end
    end)
end

-- Test seams.
Reveal._surfaces = surfaces
function Reveal._Poller() return poller end

return Reveal
