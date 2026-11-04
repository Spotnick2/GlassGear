------------------------------------------------------------
-- Character/Alts.lua - the player's own alts as recipients (GG-203).
--
--   Alts.Tracked()                  the tracked alts' specs, in the roster's
--                                   order then tree order: { {char, spec}, ... }
--   Alts.BaselineFor(c, spec, now)  -> baseline | nil, missing itemIDs, why
--   Alts.Recipient(c, baseline)     Evaluate's recipient for an alt
--   Alts.Companions(baseline)       its worn hands, for a one-hander's partner
--   Alts.Transfer(facts, instance, c)  ItemContext.Transfer from this character
--   Alts.Forget()                   on every invalidation (API._Invalidate)
--
-- An alt's gear per spec (adr/0003). Another character's equipment sets
-- can't be read, so:
--   1. observed: what it wore while it played that spec with Glass Gear on
--      this WoW account (its entry "<guid>:<spec>:baseline" in the shared
--      store, GG-108);
--   2. its worn gear from AltStable's last scan (AS-003), labelled
--      fallback-current.
-- Both go stale after 14 days, like the current character's. A fallback or
-- stale baseline never lets protection clear an item (Policy.Protection).
--
-- Dual wield: the client says it only for the logged-in character. An alt
-- counts as dual-wielding when its baseline has a weapon in the off-hand;
-- otherwise a one-hander is compared for its main hand only.
--
-- Only own characters reach here (RosterProvider lists self and
-- own-account, never third-party). Profiles are the alt's own: authored on
-- this WoW account they are in the shared store; the other account's arrive
-- with sync (GG-202) and are "no weights" until then.
------------------------------------------------------------

local GG = GlassGear
local Alts = {}
GG.Alts = Alts

-- Per generation (Alts.Forget on every invalidation):
local gearMemo = {}     -- [guid] = { baseline, capturedAt }: AltStable gear, hydrated
local gearRead = {}     -- [guid] = AltStable's answer (false: none): read once, even while
                        -- its items load (hydration is retried; the read is not)

function Alts.Forget() gearMemo, gearRead = {}, {} end
Alts.reads = 0          -- AltStable gear reads (tests: once per alt per generation)

function Alts.Tracked()
    local out = {}
    local RP = GG.Integrations.RosterProvider
    if not (GG.player and GG.db and RP.DetectAltStable().usable) then return out end
    for _, c in ipairs(RP.Characters(GG.player)) do
        if c ~= GG.player and c.key ~= GG.player.key and c.class then
            for _, s in ipairs(GG.Data.Classes.Specs(c.class)) do
                if GG.Prefs.IsTracked(c.key, s.key) then out[#out + 1] = { char = c, spec = s.key } end
            end
        end
    end
    return out
end

-- AltStable's slots in the stored-baseline shape (Baselines.Snapshot's).
local function storedFromGear(gear)
    local slots = {}
    for _, slot in ipairs(GG.Data.Slots.GEAR) do
        local s = type(gear.slots) == "table" and gear.slots[slot]
        if type(s) == "table" and s.state == "empty" then
            slots[slot] = { state = "empty" }
        elseif type(s) == "table" and s.state == "occupied" and type(s.itemString) == "string" then
            local item = GG.Compat.GearItemString(s.itemString)
            slots[slot] = item and { state = "occupied", item = item } or { state = "unknown" }
        else
            slots[slot] = { state = "unknown" }
        end
    end
    return { slots = slots, capturedAt = gear.capturedAt }
end

local function observed(c, spec, now)
    local e = GG.store and GG.store:Get(GG.Capture.ID(c.key, spec))
    if not (e and not e.deleted and not e.conflict and e.data) then return nil end
    local b, missing = GG.Capture.Hydrate(e)
    if #missing > 0 then return nil, missing end
    local chosen = GG.Baselines.Choose({ observed = b })
    chosen.stale, chosen.expiresAt = GG.Baselines.Freshness(e.data, now)
    return chosen, {}
end

local function lastSeen(c, now)
    local m = gearMemo[c.key]
    if not m then
        local gear = gearRead[c.key]
        if gear == nil then
            Alts.reads = Alts.reads + 1
            gear = GG.Integrations.RosterProvider.Gear(c.key)
            if type(gear) ~= "table" then gear = false end
            gearRead[c.key] = gear
        end
        if not gear then return nil, {}, "NO_ALT_GEAR" end
        local b, missing = GG.Baselines.Hydrate(storedFromGear(gear), GG.Compat.ItemFacts)
        if #missing > 0 then return nil, missing end
        m = { baseline = GG.Baselines.Choose({ current = b }), capturedAt = gear.capturedAt }
        gearMemo[c.key] = m
    end
    local chosen = {}
    for k, v in pairs(m.baseline) do chosen[k] = v end
    chosen.stale, chosen.expiresAt = GG.Baselines.Freshness({ capturedAt = m.capturedAt }, now)
    return chosen, {}
end

function Alts.BaselineFor(c, spec, now)
    local b, missing = observed(c, spec, now)
    if b then return b, {} end
    if missing then return nil, missing end
    return lastSeen(c, now)
end

function Alts.Recipient(c, baseline)
    local oh = baseline and baseline.slots and baseline.slots[17]
    return { key = c.key, name = c.name, realm = c.realm, faction = c.faction, provenance = c.provenance,
        class = c.class, level = c.level, current = false,
        canDualWield = oh ~= nil and oh.state == "occupied" and oh.classID == 2 }
end

function Alts.Companions(baseline)
    local lists = { [16] = {}, [17] = {} }
    for _, s in ipairs({ 16, 17 }) do
        local worn = baseline and baseline.slots and baseline.slots[s]
        if worn and worn.state == "occupied" then
            local copy = {}
            for k, v in pairs(worn) do copy[k] = v end
            copy.worn = true
            lists[s][1] = copy
        end
    end
    return lists
end

local B = GG.ItemContext.BIND
local ACCOUNT = { [B.TO_WOW_ACCOUNT] = true, [B.TO_BNET_ACCOUNT] = true, [B.TO_BNET_ACCOUNT_UNTIL_EQUIPPED] = true }

-- `facts` must be loaded (its bindType tells account-bound kinds apart).
function Alts.Transfer(facts, instance, c)
    local binding = GG.ItemContext.Classify({ instance = instance ~= nil, isBound = instance and instance.bound,
        accountBound = ACCOUNT[facts.bindType or -1] == true })
    local p = GG.player
    return GG.ItemContext.Transfer(binding, facts.bindType, { realm = p.realm, faction = p.faction },
        { provenance = c.provenance, realm = c.realm, faction = c.faction, current = false })
end

return Alts
