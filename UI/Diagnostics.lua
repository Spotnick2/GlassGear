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
        .. " - alt upgrades unavailable")
    add("profile sync: unavailable (entry-sync library ES-001, GG-202)")
    add("theme: " .. tostring(GG.themeName) .. (GG.themeInfo and GG.themeInfo.reason and (" (" .. GG.themeInfo.reason .. ")") or ""))
    add("tooltip rows: " .. (GG.tooltipHooked and "on" or ("unavailable (" .. tostring(GG.tooltipReason) .. ")")))
    add("bag markers: " .. (GG.bagMarkersOn and ("on (" .. tostring(GG.bagMarkersInfo) .. " bag frames)")
        or ("unavailable (" .. tostring(GG.bagMarkersInfo) .. ")")))
    local mod = GG.db and GG.db.settings.reveal.modifier or "CTRL"
    add("reveal: " .. (mod == "NONE" and "off" or ("hold " .. mod .. " to show off-spec upgrades")))
    add("unavailable in this build: loot markers (GG-111), protection (GG-301)")
    return lines
end

local function ownSpec(key)
    for _, s in ipairs(GG.Data.Classes.Specs(GG.player.class)) do
        if s.key == key then return true end
    end
    return false
end

local function specExample()
    local s = GG.Data.Classes.Specs(GG.player.class)[1]
    return s and s.key or "PRIEST.SHADOW"
end

function Diagnostics.Slash(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    if cmd == "spec" then
        local group, key = rest:match("^(%d+)%s+(%S+)$")
        group = tonumber(group)
        if not group or not GG.Spec.ValidMapping(GG.player.class, group, key) then
            out(string.format("usage: /gg spec <1-%d> <SPEC.KEY> (a %s spec)  e.g. /gg spec 1 %s",
                GG.Spec.MAX_GROUPS, tostring(GG.player.class), specExample()))
            return
        end
        GG.charDB.specMap[group] = key
        GG.ResolveSpec()
        GG.API._Invalidate("spec", { GG.player.key })
        out("spec group " .. group .. " -> " .. key)
    elseif cmd == "import" then
        local spec, text = rest:match("^(%S+)%s+(.+)$")
        if not spec or not ownSpec(spec) then
            out(string.format("usage: /gg import <SPEC.KEY> ( Pawn: v1: \"Name\": ... ) (a %s spec)",
                tostring(GG.player.class)))
            return
        end
        local entry, parsed, replaced = GG.Profiles.ImportPawn(GG.store, GG.player.key, spec, text, time(),
            nil, GG.player.class)
        if not entry then out("import failed: " .. tostring(parsed)) return end
        out(string.format("%s %s for %s (%s)", replaced and "replaced weights with" or "imported",
            parsed.name, spec, parsed.source))
        for _, w in ipairs(parsed.warnings) do out("  warning: " .. w) end
        GG.Callbacks.Fire("ProfilesChanged", { charKeys = { GG.player.key } })
        GG.API._Invalidate("profiles", { GG.player.key })
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
