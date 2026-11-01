------------------------------------------------------------
-- Core/Callbacks.lua - the public callback registry (docs/API.md).
-- Next-frame batched, xpcall per callback, never reentrant; one owner key
-- per (event, owner). The AltStable PublicAPI.lua:155-194 idiom.
------------------------------------------------------------

local GG = GlassGear
local Callbacks = {}
GG.Callbacks = Callbacks

Callbacks.EVENTS = {
    Ready = true, ProfilesChanged = true, EquipmentChanged = true, RosterChanged = true,
    EvaluationInvalidated = true, EvaluationReady = true, ItemDataReady = true,
}

local registry = {}   -- [event] = { [owner] = fn }
local queue = {}      -- { {event, payload} }
local scheduled, dispatching = false, false

function Callbacks.Register(event, fn, owner)
    if not Callbacks.EVENTS[event] then error("GlassGear: unknown callback event " .. tostring(event), 2) end
    if type(fn) ~= "function" then error("GlassGear: callback must be a function", 2) end
    if owner == nil then error("GlassGear: callback owner key required", 2) end
    registry[event] = registry[event] or {}
    registry[event][owner] = fn
end

function Callbacks.Unregister(event, owner)
    if registry[event] then registry[event][owner] = nil end
end

local function dispatch()
    scheduled = false
    if dispatching then return end
    dispatching = true
    local batch = queue
    queue = {}
    for _, item in ipairs(batch) do
        for _, fn in pairs(registry[item.event] or {}) do
            xpcall(function() fn(item.event, GG.Util.deepCopy(item.payload)) end, geterrorhandler())
        end
    end
    dispatching = false
    if #queue > 0 and not scheduled then
        scheduled = true
        C_Timer.After(0, dispatch)
    end
end

-- Queue an event for next frame. Identical consecutive payload-less events coalesce.
function Callbacks.Fire(event, payload)
    local last = queue[#queue]
    if payload == nil and last and last.event == event and last.payload == nil then return end
    queue[#queue + 1] = { event = event, payload = payload }
    if not scheduled then
        scheduled = true
        C_Timer.After(0, dispatch)
    end
end

return Callbacks
