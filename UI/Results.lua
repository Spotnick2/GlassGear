------------------------------------------------------------
-- UI/Results.lua - one evaluation per displayed item, shared by every surface
-- (tooltips GG-107, bag markers GG-109, loot GG-111).
--
--   Results.Get(ref, key) -> response   (cached, or a new API.Evaluate)
--   Results.Listen(fn)                 fn(key) when an item's answer arrives,
--                                      fn(nil) when everything was dropped
--   Results.Reset()                    drop every answer, cancel pending requests
--
-- Answers stay until EvaluationInvalidated (spec, profiles, equipment, level,
-- skills), so a surface redrawing often costs a lookup, and an item whose data
-- is loading makes one API request, not one per redraw or per surface.
------------------------------------------------------------

local GG = GlassGear
local Results = {}
GG.Results = Results

Results.CACHE_MAX = 400
-- Terminal answers worth asking again on the next look, never kept.
local RETRY = { NOT_READY = true, OVERLOADED = true, ITEM_QUEUE_FULL = true, ITEM_DATA_UNAVAILABLE = true }

local cache, count = {}, 0      -- [key] = { response, requestId|nil }
local requests = {}             -- [requestId] = key, while pending
local listeners = {}
local registered = false

local function retryable(response)
    for _, r in ipairs(response.results or {}) do
        for _, reason in ipairs(r.reasons or {}) do if RETRY[reason] then return true end end
    end
    return false
end

function Results.AnyPending(response)
    for _, r in ipairs(response and response.results or {}) do if r.status == "pending" then return true end end
    return false
end

local function notify(key)
    local handler = geterrorhandler()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, key)
        if not ok then handler("GlassGear results: " .. tostring(err)) end
    end
end

function Results.Listen(fn) listeners[#listeners + 1] = fn end

function Results.Reset()
    for id in pairs(requests) do GG.API.CancelRequest(id) end
    cache, count, requests = {}, 0, {}
end

local function remember(key, response)
    if retryable(response) then return end
    if not cache[key] then
        if count >= Results.CACHE_MAX then Results.Reset() end
        count = count + 1
    end
    cache[key] = { response = response }
    if Results.AnyPending(response) then
        cache[key].requestId = response.requestId
        requests[response.requestId] = key
    end
end

function Results.Get(ref, key)
    local entry = cache[key]
    if entry then return entry.response end
    -- No `context`: in M1 nothing in the evaluation depends on it, which is what
    -- lets every surface share one answer. A surface whose answer would differ
    -- (alts on loot, GG-111/GG-203) must key and ask separately. Every own spec
    -- and the tracked alts' (GG-203): the tooltip and markers filter them.
    local response = GG.API.Evaluate({ item = ref, scope = "own+tracked" })
    remember(key, response)
    return response
end

function Results.Peek(key)
    local entry = cache[key]
    return entry and entry.response
end

local function onReady(_, payload)
    local key = payload and requests[payload.requestId]
    if not key then return end
    requests[payload.requestId] = nil
    local entry = cache[key]
    if not (entry and entry.requestId == payload.requestId) then return end
    if retryable(payload.response) then
        cache[key] = nil
        count = count - 1
    else
        entry.response, entry.requestId = payload.response, nil
    end
    notify(key)
end

local function onInvalidated()
    Results.Reset()
    notify(nil)
end

function Results.Initialize()
    if registered then return end
    registered = true
    GG.Callbacks.Register("EvaluationReady", onReady, "GlassGear.Results")
    GG.Callbacks.Register("EvaluationInvalidated", onInvalidated, "GlassGear.Results")
end

return Results
