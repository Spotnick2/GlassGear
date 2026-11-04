------------------------------------------------------------
-- UI/Diagnostics.lua - /glassgear (/gg): diagnostics, spec mapping, imports,
-- /gg options (the settings page is UI/Options.lua) and /gg profiles
-- (UI/ProfilesWindow.lua).
-- This is the shipped addon's own output (chat), not a probe.
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
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
    add((GG.readOnly and L["build %s (measured on %s), API v%d, schema %d READ-ONLY (newer data)"]
        or L["build %s (measured on %s), API v%d, schema %d"]):format(tostring(build),
        GG.MEASURED_ON_BUILD, GG.API.API_VERSION, GG.SCHEMA))
    if GG.player then
        add(L["%s, %s level %d"]:format(tostring(GG.player.name), tostring(GG.player.class), GG.player.level or 0))
        if GG.currentSpec then
            add(L["current spec: %s"]:format(GG.currentSpec))
        else
            add(L["current spec: unknown (%s) - map it in /gg options, or /gg spec <group> <key>"]:format(
                tostring(GG.specReason)))
        end
        for _, s in ipairs(GG.Data.Classes.Specs(GG.player.class)) do
            local p = GG.store and GG.Profiles.Effective(GG.store, GG.player.key, s.key)
            add(string.format("  %s: %s", s.key, p and (p.name .. " [" .. tostring(p.source) .. "]") or L["no weights"]))
            add("    " .. L["gear: %s"]:format((GG.Capture.Status(s.key, time()))))
        end
    end
    -- The roster (GG-201): what AltStable gives, or exactly what is missing.
    local alt = GG.Integrations.RosterProvider.Status()
    if not alt.present then
        add(L["AltStable: absent - only this character is known"])
    elseif not alt.usable then
        add(L["AltStable: present, %s - only this character is known"]:format(tostring(alt.reason)))
    elseif alt.thirdParty > 0 then
        if alt.reason then
            add(L["AltStable: %d of your other characters (%d on this account, %d on your other accounts), %d not yours (never used) - %s"]
                :format(alt.own, alt.self, alt.ownAccount, alt.thirdParty, alt.reason))
        else
            add(L["AltStable: %d of your other characters (%d on this account, %d on your other accounts), %d not yours (never used)"]
                :format(alt.own, alt.self, alt.ownAccount, alt.thirdParty))
        end
    elseif alt.reason then
        add(L["AltStable: %d of your other characters (%d on this account, %d on your other accounts) - %s"]
            :format(alt.own, alt.self, alt.ownAccount, alt.reason))
    else
        add(L["AltStable: %d of your other characters (%d on this account, %d on your other accounts)"]
            :format(alt.own, alt.self, alt.ownAccount))
    end
    -- Alt rows (GG-203): the alt specs ticked on the Characters page.
    if alt.usable then
        add(L["alt upgrades: %d alt specs ticked (/gg characters); your other account's alts need profile sync"]
            :format(#GG.Alts.Tracked()))
    else
        add(L["alt upgrades: off (they need AltStable)"])
    end
    add(L["profile sync: unavailable (entry-sync library ES-001, GG-202)"])
    local themeWhy = GG.themeInfo and GG.themeInfo.reason
    add(themeWhy and L["theme: %s (%s)"]:format(tostring(GG.themeName), themeWhy)
        or L["theme: %s"]:format(tostring(GG.themeName)))
    add(GG.tooltipHooked and L["tooltip rows: on"]
        or L["tooltip rows: unavailable (%s)"]:format(tostring(GG.tooltipReason)))
    add(GG.bagMarkersOn and L["bag markers: on (%s bag frames)"]:format(tostring(GG.bagMarkersInfo))
        or L["bag markers: unavailable (%s)"]:format(tostring(GG.bagMarkersInfo)))
    add(GG.BagAddons.Status())
    add(GG.lootMarkersOn and L["loot markers: on (%s)"]:format(tostring(GG.lootMarkersInfo))
        or L["loot markers: unavailable (%s)"]:format(tostring(GG.lootMarkersInfo)))
    local mod = GG.db and GG.db.settings.reveal.modifier or "CTRL"
    add(mod == "NONE" and L["reveal: off"] or L["reveal: hold %s to show off-spec upgrades"]:format(mod))
    add(GG.optionsOn and L["settings: Esc > Options > AddOns > Glass Gear (/gg options)"]
        or L["settings: unavailable (%s)"]:format(tostring(GG.optionsInfo)))
    add(L["weights: /gg profiles (import, edit, export; up to %d profiles per spec)"]:format(GG.Profiles.MAX_PER_SPEC))
    add(L["disenchant protection: ready for Shatter (GlassGear.API.AssessProtection, tracked specs)"])
    add(L["unavailable in this build: markers on %s"]:format(table.concat(GG.BagAddons.UNSUPPORTED, ", ")))
    return lines
end

-- The runtime's counters (GG-402): evaluations, cache, deferrals, queues.
function Diagnostics.StatsLines()
    local S = GG.API._state
    local st = S.stats
    local lookups = st.hits + st.misses
    local jobs = 0
    for _ in pairs(S.jobs) do jobs = jobs + 1 end
    return {
        L["stats: %d evaluations, %d answers from the cache of %d lookups (%d%%), %d rows put off to a later frame"]:format(
            st.evaluations, st.hits, lookups, lookups > 0 and math.floor(st.hits * 100 / lookups) or 0, st.deferredRows),
        "  " .. L["cache %d/%d answers, generation %d; %d pending jobs (%d rows), %d requests, %d item loads"]:format(
            GG.API._cache.size, GG.API.LIMITS.cache, S.generation, jobs, S.jobRows, S.requestCount, S.waitingCount),
        "  " .. L["the most time spent comparing in one frame: %.1f ms"]:format(st.maxFrameMs or 0),
        "  " .. L["limits: %d rows per frame, %d jobs, %d requests, %d item loads"]:format(
            GG.API.LIMITS.perFrame, GG.API.LIMITS.jobs, GG.API.LIMITS.requests, GG.API.LIMITS.itemQueue),
    }
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
            if why == "read-only" then out(L["read-only this session: the spec mapping can't change"]) return end
            out(L["usage: /gg spec <1-%d> <SPEC.KEY | none> (a %s spec)  e.g. /gg spec 1 %s"]:format(
                GG.Spec.MAX_GROUPS, tostring(GG.player.class), specExample()))
            return
        end
        out(none and L["spec group %d -> not set"]:format(group) or L["spec group %d -> %s"]:format(group, key))
    elseif cmd == "set" then
        -- /gg set <SPEC.KEY> <set name> | none | auto: compare that spec with a
        -- saved set; none: never a set, not even one assigned in the client;
        -- auto: the set assigned in the client, if any (the default).
        local spec, name = rest:match("^(%S+)%s+(.+)$")
        if not spec or not ownSpec(spec) then
            out(L["usage: /gg set <SPEC.KEY> <equipment set name | none | auto> (a %s spec)"]:format(
                tostring(GG.player.class)))
            return
        end
        local _, msg = GG.Capture.MapSet(spec, name)
        out(msg)
    elseif cmd == "characters" or cmd == "chars" then
        local ok, why = GG.CharactersWindow.Open()
        if not ok then out(L["characters page unavailable: %s"]:format(tostring(why))) end
    elseif cmd == "compare" then
        -- /gg compare [item link]: a pasted link (Shift-click), else the item
        -- last shown in a tooltip.
        local ref = rest:find("|Hitem:", 1, true) and rest or GG.Tooltip.lastRef
        if not ref then
            out(L["usage: /gg compare [item link]  (hover an item first, or Shift-click one into the command)"])
            return
        end
        local ok, why = GG.CompareWindow.Open(ref)
        if not ok then out(L["comparison unavailable: %s"]:format(tostring(why))) end
    elseif cmd == "stats" then
        -- GG-402: what the runtime did this session, to measure in game.
        -- "/gg stats reset" starts the counters again (one reading per phase).
        if rest == "reset" then
            local st = GG.API._state.stats
            for k in pairs(st) do st[k] = 0 end
            out(L["stats reset"])
            return
        end
        for _, line in ipairs(Diagnostics.StatsLines()) do out(line) end
    elseif cmd == "options" or cmd == "config" then
        if not GG.Options.Open() then out(L["settings: Esc > Options > AddOns > Glass Gear"]) end
    elseif cmd == "profiles" or cmd == "weights" then
        local spec = rest ~= "" and rest or nil
        if spec and not ownSpec(spec) then
            out(L["usage: /gg profiles [SPEC.KEY] (a %s spec)"]:format(tostring(GG.player.class)))
            return
        end
        local ok, why = GG.ProfilesWindow.Open(spec)
        if not ok then out(L["profiles window unavailable: %s"]:format(tostring(why))) end
    elseif cmd == "import" then
        local spec, text = rest:match("^(%S+)%s+(.+)$")
        if not spec or not ownSpec(spec) then
            out(L["usage: /gg import <SPEC.KEY> ( Pawn: v1: \"Name\": ... ) (a %s spec)"]:format(
                tostring(GG.player.class)))
            return
        end
        local entry, parsed, replaced = GG.Profiles.ImportPawn(GG.store, GG.player.key, spec, text, time(),
            nil, GG.player.class)
        if not entry then out(L["import failed: %s"]:format(tostring(parsed))) return end
        out((replaced and L["replaced weights with %s for %s (%s)"] or L["imported %s for %s (%s)"]):format(
            parsed.name, spec, parsed.source))
        for _, w in ipairs(parsed.warnings) do out("  " .. L["warning: %s"]:format(w)) end
        GG.Profiles.Changed(GG.player.key)
    else
        for _, line in ipairs(Diagnostics.Lines()) do out(line) end
    end
end

return Diagnostics
