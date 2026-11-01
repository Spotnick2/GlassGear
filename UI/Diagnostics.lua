------------------------------------------------------------
-- UI/Diagnostics.lua - /glassgear (/gg) and the Settings category stub.
-- This is the shipped addon's own output (chat), not a probe.
------------------------------------------------------------

local GG = GlassGear
local Diagnostics = {}
GG.Diagnostics = Diagnostics

local function out(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fd4ffGlass Gear|r " .. msg)
end

-- The diagnostic lines (pure given GG's state, so tests can read them).
function Diagnostics.Lines()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local _, build = GetBuildInfo()
    add(string.format("build %s (measured on %s), API v%d, schema %d%s", tostring(build),
        GG.MEASURED_ON_BUILD, GG.API.API_VERSION, GG.SCHEMA, GG.readOnly and " READ-ONLY (newer data)" or ""))
    if GG.player then
        add(string.format("%s, %s level %d", tostring(GG.player.name), tostring(GG.player.class), GG.player.level or 0))
        add("current spec: " .. (GG.currentSpec or ("unknown (" .. tostring(GG.specReason) .. ") - map it: /gg spec <group> <key>")))
        for _, s in ipairs(GG.Data.Classes.Specs(GG.player.class)) do
            local p = GG.store and GG.Profiles.Active(GG.store, GG.player.key, s.key)
            add(string.format("  %s: %s", s.key, p and (p.name .. " [" .. tostring(p.source) .. "]") or "no weights"))
        end
    end
    local alt = GG.Integrations.RosterProvider.DetectAltStable()
    add("AltStable: " .. (alt.present and ("present, " .. (alt.usable and "usable" or alt.reason)) or "absent")
        .. " - alt upgrades and sync unavailable")
    add("theme: " .. tostring(GG.themeName) .. (GG.themeInfo and GG.themeInfo.reason and (" (" .. GG.themeInfo.reason .. ")") or ""))
    add("unavailable in this build: tooltips (GG-107), markers (GG-109/111), reveal (GG-110), protection (GG-301)")
    return lines
end

function Diagnostics.Slash(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    if cmd == "spec" then
        local group, key = rest:match("^(%d+)%s+(%S+)$")
        if not group or not GG.Data.Classes.Spec(key) then
            out("usage: /gg spec <1|2> <SPEC.KEY>  e.g. /gg spec 1 PRIEST.SHADOW")
            return
        end
        GG.charDB.specMap[tonumber(group)] = key
        GG.ResolveSpec()
        out("spec group " .. group .. " -> " .. key)
    elseif cmd == "import" then
        local spec, text = rest:match("^(%S+)%s+(.+)$")
        if not spec or not GG.Data.Classes.Spec(spec) then
            out("usage: /gg import <SPEC.KEY> ( Pawn: v1: \"Name\": ... )")
            return
        end
        local entry, parsed = GG.Profiles.ImportPawn(GG.store, GG.player.key, spec, text, time(), tostring(time()))
        if not entry then out("import failed: " .. tostring(parsed)) return end
        out(string.format("imported %s for %s (%s)", parsed.name, spec, parsed.source))
        for _, w in ipairs(parsed.warnings) do out("  warning: " .. w) end
        GG.Callbacks.Fire("ProfilesChanged", { charKeys = { GG.player.key } })
    else
        for _, line in ipairs(Diagnostics.Lines()) do out(line) end
    end
end

-- A Settings category so the addon is discoverable (porting guide: Settings
-- API). The real panel is GG-112.
function Diagnostics.RegisterSettings()
    local panel = CreateFrame("Frame")
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 16, -16)
    text:SetText("Glass Gear - foundation build. Settings arrive with GG-112.\nType /gg for diagnostics.")
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Glass Gear")
    Settings.RegisterAddOnCategory(category)
    return category
end

return Diagnostics
