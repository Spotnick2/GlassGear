------------------------------------------------------------
-- fixtures.lua - illustrative items, profiles and baselines for the engine
-- tests. Names and numbers are made up; they model shapes, not real items.
------------------------------------------------------------

local F = {}

-- Engine item facts (what Compat.ItemFacts returns), built from stats.
function F.item(o)
    local Stats = GlassGear.Data.Stats
    local tokens, unsupported = Stats.FromItemStats(o.stats or {}, o)
    return {
        ready = o.ready ~= false, itemID = o.itemID or 1, itemString = o.itemString or ("item:" .. (o.itemID or 1)),
        equipLoc = o.equipLoc, classID = o.classID or 4, subclassID = o.subclassID or 1,
        reqLevel = o.reqLevel or 1, setID = o.setID, hasSpell = o.hasSpell, unique = o.unique,
        tokens = tokens, unsupported = unsupported, bindType = o.bindType,
    }
end

-- A baseline slot from item-like options.
function F.slot(o)
    local it = F.item(o)
    return { state = "occupied", itemID = it.itemID, itemString = it.itemString, equipLoc = it.equipLoc,
        tokens = it.tokens, unique = it.unique, setID = it.setID }
end

-- A full baseline: every gear slot empty unless given.
function F.baseline(slots, extra)
    local b = { source = "observed", capturedAt = 1000, slots = {} }
    for _, s in ipairs(GlassGear.Data.Slots.GEAR) do b.slots[s] = { state = "empty" } end
    for s, v in pairs(slots or {}) do b.slots[s] = v end
    for k, v in pairs(extra or {}) do b[k] = v end
    return b
end

F.shadow = { id = "p-shadow", source = "imported-pawn", version = "w:1",
    weights = { Intellect = 0.42, SpellDamage = 1.0, CritRating = 0.68, Stamina = 0.1 }, ignored = {} }
F.holy = { id = "p-holy", source = "imported-pawn", version = "w:2",
    weights = { Intellect = 0.6, Healing = 1.0, Spirit = 0.5, Mp5 = 1.2 }, ignored = {} }

F.priest = { key = "G-Karuzo", name = "Karuzo", realm = "Forever", provenance = "self", class = "PRIEST", level = 60 }
F.paladin = { key = "G-Elegia", name = "Elegia", realm = "Forever", provenance = "own-account", class = "PALADIN", level = 60 }

return F
