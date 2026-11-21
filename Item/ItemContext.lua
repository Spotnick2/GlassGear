------------------------------------------------------------
-- Item/ItemContext.lua - binding classification and transfer eligibility
-- (PRD section 3, adr/0003). The decisions are pure; Compat feeds the facts.
--
-- Binding classes:
--   "bound"          a bag instance bound to this character
--   "account-bound"  bound to an account (BoA kinds) - transfer unknown until probed
--   "unbound"        a bag instance not bound (BoE, or no binding)
--   "hypothetical"   a link with no instance (loot, vendor, chat): bindType only
-- Transfer is tri-state: eligible | ineligible | unknown, with reasons.
------------------------------------------------------------

local GG = GlassGear
local ItemContext = {}
GG.ItemContext = ItemContext

-- Enum.ItemBind values (wow-ui-source ItemConstantsDocumentation.lua:249-263).
ItemContext.BIND = { NONE = 0, ON_ACQUIRE = 1, ON_EQUIP = 2, ON_USE = 3, QUEST = 4,
    TO_WOW_ACCOUNT = 7, TO_BNET_ACCOUNT = 8, TO_BNET_ACCOUNT_UNTIL_EQUIPPED = 9 }
local B = ItemContext.BIND

-- facts = { instance = bool, isBound = bool|nil, accountBound = bool|nil, bindType = number|nil }
function ItemContext.Classify(facts)
    if not facts.instance then return "hypothetical" end
    if facts.accountBound then return "account-bound" end
    if facts.isBound == true then return "bound" end
    if facts.isBound == false then return "unbound" end
    return "unknown"
end

-- Transfer from the current character to `recipient`.
--   binding   = ItemContext.Classify(...)
--   bindType  = the item's bind type (for hypothetical links)
--   from      = { realm, ruleset, faction }
--   recipient = { provenance, realm, ruleset, faction, current = bool }
-- `ruleset` is AltStable's ("Normal", "PvP", "RP", "RPPvP", "Hardcore").
-- Forever hides the realm since the 2026-11-20 server hotfix (GetRealmName()
-- is "", #88), so a realm is nil for most characters: mail goes by faction
-- and ruleset, as AltStable's own rule does. A realm still decides when both
-- are known. Each check needs both sides known; nothing known claims nothing.
-- Mail rules (same faction + same ruleset or realm) are PROPOSED until GG-116
-- measures them: across rulesets is the owner's word from play, and between
-- two realms of one ruleset is untried.
local function differ(a, b) return a ~= nil and b ~= nil and a ~= b end
local function same(a, b) return a ~= nil and a == b end
function ItemContext.Transfer(binding, bindType, from, recipient)
    local out = { state = "unknown", reasons = {} }
    local function done(state, reason)
        out.state = state
        out.reasons[#out.reasons + 1] = reason
        return out
    end
    if recipient.current then return done("eligible", "SAME_CHARACTER") end
    local prov = recipient.provenance
    if prov ~= "self" and prov ~= "own-account" then return done("ineligible", "NOT_OWN_CHARACTER") end

    if binding == "bound" then return done("ineligible", "SOULBOUND") end
    if binding == "account-bound" then return done("unknown", "ACCOUNT_BOUND_UNPROBED") end
    if binding == "hypothetical" then
        if bindType == B.ON_ACQUIRE or bindType == B.QUEST then return done("ineligible", "BIND_ON_PICKUP") end
        return done("unknown", "NOT_AN_INSTANCE")
    end
    if binding ~= "unbound" then return done("unknown", "BIND_STATE_UNKNOWN") end

    from = from or {}
    if differ(from.ruleset, recipient.ruleset) then return done("ineligible", "OTHER_RULESET") end
    if differ(from.realm, recipient.realm) then return done("ineligible", "OTHER_REALM") end
    if differ(from.faction, recipient.faction) then return done("ineligible", "OTHER_FACTION") end
    local why
    if same(from.faction, recipient.faction) then
        if same(from.realm, recipient.realm) then why = "MAIL_SAME_REALM_FACTION"
        elseif same(from.ruleset, recipient.ruleset) then why = "MAIL_SAME_RULESET_FACTION" end
    end
    if not why then return done("unknown", "RECIPIENT_LOCATION_UNKNOWN") end
    out.proposed = true   -- rule pending GG-116
    return done("eligible", why)
end

return ItemContext
