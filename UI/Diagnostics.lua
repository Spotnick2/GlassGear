------------------------------------------------------------
-- UI/Diagnostics.lua - /glassgear (/gg): diagnostics, spec mapping, imports,
-- /gg options (the settings page is UI/Options.lua) and /gg profiles
-- (UI/ProfilesWindow.lua).
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
        add("current spec: " .. (GG.currentSpec or ("unknown (" .. tostring(GG.specReason)
        .. ") - map it in /gg options, or /gg spec <group> <key>")))
        for _, s in ipairs(GG.Data.Classes.Specs(GG.player.class)) do
            local p = GG.store and GG.Profiles.Active(GG.store, GG.player.key, s.key)
            add(string.format("  %s: %s", s.key, p and (p.name .. " [" .. tostring(p.source) .. "]") or "no weights"))
            add("    gear: " .. GG.Capture.Status(s.key, time()))
        end
    end
    -- The roster (GG-201): what AltStable gives, or exactly what is missing.
    local alt = GG.Integrations.RosterProvider.Status()
    if not alt.present then
        add("AltStable: absent - only this character is known")
    elseif not alt.usable then
        add("AltStable: present, " .. tostring(alt.reason) .. " - only this character is known")
    else
        add(string.format("AltStable: %d of your other characters (%d on this account, %d on your other accounts)%s",
            alt.own, math.max(0, alt.self - 1), alt.ownAccount,
            alt.thirdParty > 0 and (", " .. alt.thirdParty .. " not yours (never used)") or "")
            .. (alt.reason and (" - " .. alt.reason) or ""))
    end
    add("alt upgrades: GG-203 (needs the entry-sync library and the transfer-rule probe)")
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
    add("weights: /gg profiles (import, edit, export; up to "
        .. GG.Profiles.MAX_PER_SPEC .. " profiles per spec)")
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
        local none = key and key:lower() == "none"
        local ok, why = false, "usage"
        if group and (none or GG.Spec.ValidMapping(GG.player.class, group, key)) then
            ok, why = GG.Spec.Map(group, not none and key or nil)
        end
        if not ok then
            if why == "read-only" then out("read-only this session: the spec mapping can't change") return end
            out(string.format("usage: /gg spec <1-%d> <SPEC.KEY | none> (a %s spec)  e.g. /gg spec 1 %s",
                GG.Spec.MAX_GROUPS, tostring(GG.player.class), specExample()))
            return
        end
        out("spec group " .. group .. " -> " .. (none and "not set" or key))
    elseif cmd == "set" then
        -- /gg set <SPEC.KEY> <set name> | none | auto: compare that spec with a
        -- saved set; none: never a set, not even one assigned in the client;
        -- auto: the set assigned in the client, if any (the default).
        local spec, name = rest:match("^(%S+)%s+(.+)$")
        if not spec or not ownSpec(spec) then
            out(string.format("usage: /gg set <SPEC.KEY> <equipment set name | none | auto> (a %s spec)",
                tostring(GG.player.class)))
            return
        end
        if name:lower() == "none" then
            GG.charDB.equipSetMap[spec] = { none = true }
            out(spec .. ": no equipment set, not even one assigned in the client; compared with the gear it wore")
        elseif name:lower() == "auto" then
            GG.charDB.equipSetMap[spec] = nil
            out(spec .. ": the equipment set assigned to it in the client, if any; else the gear it wore")
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
        GG.Capture.CheckSets()
        GG.API._Invalidate("baselines", { GG.player.key })
    elseif cmd == "options" or cmd == "config" then
        if not GG.Options.Open() then out("settings: Esc > Options > AddOns > Glass Gear") end
    elseif cmd == "profiles" or cmd == "weights" then
        local spec = rest ~= "" and rest or nil
        if spec and not ownSpec(spec) then
            out(string.format("usage: /gg profiles [SPEC.KEY] (a %s spec)", tostring(GG.player.class)))
            return
        end
        local ok, why = GG.ProfilesWindow.Open(spec)
        if not ok then out("profiles window unavailable: " .. tostring(why)) end
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
        GG.Profiles.Changed(GG.player.key)
    else
        for _, line in ipairs(Diagnostics.Lines()) do out(line) end
    end
end

return Diagnostics
