------------------------------------------------------------
-- UI/Diagnostics.lua - /glassgear (/gg): diagnostics, spec mapping, imports,
-- and /gg options (the settings page is UI/Options.lua).
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
            add("    gear: " .. GG.Capture.Status(s.key, time()))
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
    add("loot markers: " .. (GG.lootMarkersOn and ("on (" .. tostring(GG.lootMarkersInfo) .. ")")
        or ("unavailable (" .. tostring(GG.lootMarkersInfo) .. ")")))
    local mod = GG.db and GG.db.settings.reveal.modifier or "CTRL"
    add("reveal: " .. (mod == "NONE" and "off" or ("hold " .. mod .. " to show off-spec upgrades")))
    add("settings: " .. (GG.optionsOn and "Esc > Options > AddOns > Glass Gear (/gg options)"
        or ("unavailable (" .. tostring(GG.optionsInfo) .. ")")))
    add("unavailable in this build: protection (GG-301), bag addons (GG-401)")
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
        GG.Capture.Request()
        out("spec group " .. group .. " -> " .. key)
    elseif cmd == "set" then
        -- /gg set <SPEC.KEY> <set name> | none: compare that spec with a saved set.
        local spec, name = rest:match("^(%S+)%s+(.+)$")
        if not spec or not ownSpec(spec) then
            out(string.format("usage: /gg set <SPEC.KEY> <equipment set name | none> (a %s spec)",
                tostring(GG.player.class)))
            return
        end
        if name:lower() == "none" then
            GG.charDB.equipSetMap[spec] = nil
            out(spec .. ": no equipment set; compared with the gear it wore")
        else
            local sets = GG.Compat.EquipmentSets()
            if not sets then out("equipment sets are not available") return end
            local found
            for _, s in ipairs(sets) do if s.name:lower() == name:lower() then found = s end end
            if not found then
                local names = {}
                for _, s in ipairs(sets) do names[#names + 1] = s.name end
                out("no equipment set named '" .. name .. "'" .. (#names > 0 and (". Sets: " .. table.concat(names, ", ")) or ""))
                return
            end
            GG.charDB.equipSetMap[spec] = { id = found.id, name = found.name }
            out(spec .. " -> equipment set '" .. found.name .. "'")
        end
        GG.API._Invalidate("baselines", { GG.player.key })
    elseif cmd == "options" or cmd == "config" then
        if not GG.Options.Open() then out("settings: Esc > Options > AddOns > Glass Gear") end
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

return Diagnostics
