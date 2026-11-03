------------------------------------------------------------
-- Presentation/MarkerView.lua - an API response as the input of
-- Policy.Marker (GG-109, adr/0006). Pure.
--
--   MarkerView.View(response, bound, surface, bindType) -> view
--     bags: bound = the instance's bind state; loot: bindType (BoP/BoE rules)
--   MarkerView.Settings(markerSettings, specKeys) -> Policy.Marker settings
--
-- The marker scope is its own setting (adr/0006): "current" marks only the
-- current spec green and leaves off-specs to the reveal and to transferable
-- items; "selected" also marks the chosen own specs' upgrades amber, always;
-- "own" does that for every own spec.
------------------------------------------------------------

local GG = GlassGear
local View = {}
GG.MarkerView = View

function View.View(response, bound, surface, bindType)
    local view = { own = {}, alts = {}, bound = bound, surface = surface, bindType = bindType }
    for _, r in ipairs(response and response.results or {}) do
        if r.status ~= "unsupported" and r.spec then
            if r.current and not view.current then
                view.current = r
            else
                view.own[#view.own + 1] = r
            end
        end
    end
    return view
end

function View.Settings(markers, specKeys)
    markers = markers or {}
    local ownSpecs
    if markers.scope == "own" or markers.scope == "selected" then
        ownSpecs = {}
        local chosen = type(markers.selected) == "table" and markers.selected or {}
        for _, key in ipairs(specKeys or {}) do
            if markers.scope == "own" or chosen[key] then ownSpecs[key] = true end
        end
    end
    return { markTransferable = markers.markTransferable ~= false, ownSpecs = ownSpecs }
end

return View
