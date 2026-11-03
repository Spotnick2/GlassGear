------------------------------------------------------------
-- Presentation/Theme.lua - which look renders the view-models (adr/0004).
-- "forever" (native, default, no library) or "glass" (LibGlass r11 pearl,
-- only while Glass UI lists Glass Gear and the player follows the suite).
-- The decision is made once per session; switching needs /reload.
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
local Theme = {}
GG.Theme = Theme

Theme.MIN_LIBGLASS = 11

function Theme.LibGlass()
    local stub = rawget(_G, "LibStub")
    if type(stub) ~= "table" and type(stub) ~= "function" then return nil, "library-missing" end
    local ok, lib, minor = pcall(stub, "LibGlass-1.0", true)
    if not ok or not lib then return nil, "library-missing" end
    if (minor or 0) < Theme.MIN_LIBGLASS then return nil, "library-too-old" end
    return lib, minor
end

-- Returns name, info. `suite` is GlassUI.Ask's answer.
function Theme.Decide(suite)
    if not (suite and suite.following) then
        return "forever", { reason = suite and suite.reason or L["not following Glass UI"] }
    end
    local lib, why = Theme.LibGlass()
    if not lib then return "forever", { reason = why } end
    return "glass", { preset = suite.theme and suite.theme.preset or "pearl" }
end

return Theme
