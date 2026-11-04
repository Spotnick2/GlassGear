------------------------------------------------------------
-- Character/Capture.lua - per-spec baselines for the current character
-- (GG-108, adr/0003): what each spec wears, and which one a result uses.
--
--   Capture.Request()          observe the current spec's gear soon (coalesced)
--   Capture.Observe(now)       observe now -> ok, what
--   Capture.BaselineFor(spec, live, now) -> baseline | nil, missing itemIDs,
--                              fromLive (the baseline is the current gear)
--   Capture.SetFor(spec)       the equipment set used for a spec, if any
--   Capture.CheckSets()        after a bag change: invalidate if a set's pieces moved
--   Capture.Status(spec, now)  one line for /gg, and its kind ("set" | "current" |
--                              "recorded" | "none": callers branch on it, never on the text)
--
-- Observed baselines are entries in the entry store (adr/0001), id
-- "<guid>:<specKey>:baseline", source "observed": the gear worn while that
-- spec was the current one. They are written on login, after an equipment
-- change and after a spec change, coalesced over Capture.DELAY so a set swap
-- (many PLAYER_EQUIPMENT_CHANGED) or the gear swap after a talent switch is
-- read once, settled. Unchanged gear rewrites only every REFRESH_AFTER.
--
-- Precedence per spec (adr/0003):
--   1. an equipment set mapped to the spec (/gg set), else the set the client
--      assigned to that spec's group (unless /gg set <spec> none);
--   2. the current spec: what is worn now (observed, live);
--      another spec: its stored observed baseline (stale after 14 days);
--   3. the current gear, labelled fallback-current.
------------------------------------------------------------

local GG = GlassGear
local L = GG.L
local Capture = {}
GG.Capture = Capture

Capture.DELAY = 2
Capture.MAX_ATTEMPTS = 5

local scheduled = false
local attempts = 0
local hydrated = {}          -- [entryId .. "@" .. version] = baseline (complete hydrations only)
local setSig                 -- Compat.SetSignature of the sets in use, last seen

function Capture.ID(guid, specKey) return guid .. ":" .. specKey .. ":baseline" end

local function usableSpec(spec) return spec ~= nil and spec ~= "UNKNOWN" end

function Capture.Observe(now)
    if GG.readOnly then return false, "read-only" end
    if not (GG.player and GG.store) then return false, "not-ready" end
    local spec = GG.currentSpec
    if not usableSpec(spec) then return false, "unknown-spec" end
    local live, missing = GG.Compat.EquippedBaseline(now)
    if #missing > 0 then
        for _, id in ipairs(missing) do GG.Compat.RequestItem(id) end
        return false, "pending"
    end
    local snap = GG.Baselines.Snapshot(live, spec, "observed", now, GG.specGroup, GG.Engine.Codec.MAX_ITEM)
    local id = Capture.ID(GG.player.key, spec)
    local e = GG.store:Get(id)
    if e and (e.deleted or e.conflict) then return false, "not-editable" end
    if e and not GG.Baselines.NeedsWrite(e.data, snap, now) then return true, "unchanged" end
    local ok, err
    if e then ok, err = GG.store:Edit(id, e.version, snap) else ok, err = GG.store:Create(id, "baseline", snap, "self") end
    if not ok then return false, err end
    GG.API._Invalidate("baselines", { GG.player.key })
    return true, "written"
end

local function run()
    scheduled = false
    local ok, what = Capture.Observe(time())
    if not ok and what == "pending" and attempts < Capture.MAX_ATTEMPTS then
        attempts = attempts + 1
        Capture.Request(true)
        return
    end
    attempts = 0
end

function Capture.Request(retry)
    if not retry then attempts = 0 end
    if scheduled then return end
    scheduled = true
    C_Timer.After(Capture.DELAY, function()
        local ok, err = pcall(run)
        if not ok then
            scheduled = false
            geterrorhandler()("GlassGear capture: " .. tostring(err))
        end
    end)
end

-- The set for a spec: the player's own mapping first, else the client's
-- assignment for the spec group mapped to this spec. Returns id, name, origin.
-- { none = true } (/gg set <spec> none) turns both off.
function Capture.SetFor(spec)
    local map = GG.charDB and GG.charDB.equipSetMap or {}
    local m = map[spec]
    if type(m) == "table" and m.none then return nil end
    if type(m) == "table" and m.id then return m.id, m.name, "mapped" end
    for group, key in pairs(GG.charDB and GG.charDB.specMap or {}) do
        if key == spec then
            local id = GG.Compat.EquipmentSetForGroup(group)
            if id then return id, nil, "client" end
        end
    end
end

local function hydrate(e)
    local key = e.id .. "@" .. tostring(e.version)
    if hydrated[key] then return hydrated[key], {} end
    local b, missing = GG.Baselines.Hydrate(e.data, GG.Compat.ItemFacts)
    if #missing == 0 then hydrated[key] = b end
    return b, missing
end
-- A stored baseline entry, hydrated (kept per entry version): the current
-- character's specs here, an alt's in Character/Alts.lua (GG-203).
Capture.Hydrate = hydrate

-- Map a spec to a saved set by name, or "none" (no set, not even the
-- client's) or "auto" (the client's, if any). The one setter behind
-- /gg set and the comparison window. Returns ok, message.
function Capture.MapSet(spec, name)
    if GG.readOnly then return false, L["read-only this session: the set mapping can't change"] end
    if not (GG.player and GG.charDB) then return false, L["not ready"] end
    local lower = tostring(name or ""):lower()
    local msg
    if lower == "none" then
        GG.charDB.equipSetMap[spec] = { none = true }
        msg = L["%s: no equipment set, not even one assigned in the client; compared with the gear it wore"]:format(spec)
    elseif lower == "auto" then
        GG.charDB.equipSetMap[spec] = nil
        msg = L["%s: the equipment set assigned to it in the client, if any; else the gear it wore"]:format(spec)
    else
        local sets = GG.Compat.EquipmentSets()
        if not sets then return false, L["equipment sets are not available"] end
        local found
        for _, s in ipairs(sets) do if s.name:lower() == lower then found = s end end
        if not found then
            local names = {}
            for _, s in ipairs(sets) do names[#names + 1] = s.name end
            if #names > 0 then
                return false, L["no equipment set named '%s'. Sets: %s"]:format(tostring(name), table.concat(names, ", "))
            end
            return false, L["no equipment set named '%s'"]:format(tostring(name))
        end
        GG.charDB.equipSetMap[spec] = { id = found.id, name = found.name }
        msg = L["%s -> equipment set '%s'"]:format(spec, found.name)
    end
    Capture.CheckSets()
    GG.API._Invalidate("baselines", { GG.player.key })
    return true, msg
end

-- The ids of the sets the own specs use, distinct.
local function setsInUse()
    local ids, seen = {}, {}
    if not GG.player then return ids end
    for _, s in ipairs(GG.Data.Classes.Specs(GG.player.class)) do
        local id = Capture.SetFor(s.key)
        if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

-- A set slot resolves to the instance worn or in the bags, so a set piece
-- moving in or out of the bags changes that set's baseline: answers already
-- given are invalidated. Nothing happens while no spec uses a set.
function Capture.CheckSets()
    local sig = GG.Compat.SetSignature(setsInUse())
    local changed = setSig ~= nil and sig ~= setSig
    setSig = sig
    if changed and GG.player then GG.API._Invalidate("baselines", { GG.player.key }) end
    return changed
end

function Capture.BaselineFor(spec, live, now)
    local setID = Capture.SetFor(spec)
    if setID then
        local b, missing = GG.Compat.EquipmentSetBaseline(setID, now)
        if b then
            if #missing > 0 then return nil, missing end
            return GG.Baselines.Choose({ equipmentSet = b }), {}
        end
    end
    if spec == GG.currentSpec then
        return GG.Baselines.Choose({ observed = live }), {}, true
    end
    local e = GG.player and GG.store and GG.store:Get(Capture.ID(GG.player.key, spec))
    if e and not e.deleted and not e.conflict and e.data then
        local b, missing = hydrate(e)
        if #missing > 0 then return nil, missing end
        local chosen = GG.Baselines.Choose({ observed = b })
        chosen.stale, chosen.expiresAt = GG.Baselines.Freshness(e.data, now)
        return chosen, {}
    end
    return GG.Baselines.Choose({ current = live }), {}, true
end

local function age(seconds)
    local days = math.floor(seconds / 86400)
    if days >= 1 then return L["%d d ago"]:format(days) end
    local hours = math.floor(seconds / 3600)
    return hours >= 1 and L["%d h ago"]:format(hours) or L["just now"]
end

function Capture.Status(spec, now)
    local setID, name, origin = Capture.SetFor(spec)
    if setID then
        local client = origin == "client"
        if name then
            return (client and L["equipment set '%s' (assigned in the client)"] or L["equipment set '%s'"]):format(name), "set"
        end
        return (client and L["equipment set #%s (assigned in the client)"] or L["equipment set #%s"]):format(tostring(setID)), "set"
    end
    -- Equipment sets turned off for this spec (/gg set <spec> none): each line says how to turn them back on.
    local m = GG.charDB and GG.charDB.equipSetMap and GG.charDB.equipSetMap[spec]
    local off = type(m) == "table" and m.none and true or false
    if spec == GG.currentSpec then
        if off then return L["what you wear now (current spec) (equipment sets off: /gg set %s auto)"]:format(spec), "current" end
        return L["what you wear now (current spec)"], "current"
    end
    local e = GG.player and GG.store and GG.store:Get(Capture.ID(GG.player.key, spec))
    if e and not e.deleted and e.data and e.data.capturedAt then
        local stale = GG.Baselines.Freshness(e.data, now)
        local when = age(now - e.data.capturedAt)
        if stale and off then
            return L["recorded %s (stale: play it again) (equipment sets off: /gg set %s auto)"]:format(when, spec), "recorded"
        elseif stale then
            return L["recorded %s (stale: play it again)"]:format(when), "recorded"
        elseif off then
            return L["recorded %s (equipment sets off: /gg set %s auto)"]:format(when, spec), "recorded"
        end
        return L["recorded %s"]:format(when), "recorded"
    end
    if off then
        return L["none recorded: compared with your current gear (estimate). Play it once, or /gg set %s <set name> (equipment sets off: /gg set %s auto)"]
            :format(spec, spec), "none"
    end
    return L["none recorded: compared with your current gear (estimate). Play it once, or /gg set %s <set name>"]:format(spec), "none"
end

-- Test seam.
function Capture._Reset() scheduled, attempts, hydrated, setSig = false, 0, {}, nil end

return Capture
