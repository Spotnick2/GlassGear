------------------------------------------------------------
-- Engine/Score.lua - weighted item score (adr/0003). Pure: no game calls.
--
--   Score.Compute(tokens, profile) -> {
--     score, ignoredHit = token|nil, noSupported = bool, used = {token=contribution} }
--
-- `tokens` is Data.Stats.FromItemStats output for an enchant-stripped item.
-- A token the profile marks ignored (Pawn "X") makes the item ineligible for
-- that profile (ignoredHit), as Pawn treats X.
------------------------------------------------------------

local GG = GlassGear
local Score = {}
GG.Engine.Score = Score

function Score.Compute(tokens, profile)
    local weights = profile and profile.weights or {}
    local ignored = profile and profile.ignored or {}
    local total, used, any = 0, {}, false
    local ignoredHit
    for token, value in pairs(tokens or {}) do
        if ignored[token] and value ~= 0 then
            ignoredHit = ignoredHit and (ignoredHit < token and ignoredHit or token) or token
        end
        local w = weights[token]
        if w and value ~= 0 then
            local c = w * value
            used[token] = c
            total = total + c
            any = true
        end
    end
    return { score = total, ignoredHit = ignoredHit, noSupported = not any, used = used }
end

-- Item strings: "item:<id>:<enchant>:..." links and trimmed baseline strings.
-- StripEnchant keeps every other field (gems, the bonus block that carries a
-- Forever random suffix), as Pawn does, so both sides
-- compare without enchants.
function Score.StripEnchant(itemString)
    if type(itemString) ~= "string" then return itemString end
    local head, id, enchant, rest = itemString:match("^(.-item:)(%-?%d+):(%-?%d*)(.*)$")
    if head then return head .. id .. ":" .. rest end
    return itemString
end

return Score
