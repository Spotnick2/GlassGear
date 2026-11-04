------------------------------------------------------------
-- Data/Defaults.lua - Glass Gear's own default weights (GG-120,
-- docs/research/default-weights.md). Read-only data, never stored or synced.
--
--   Defaults.For(specKey)  -> profile (the engine's shape) | nil
--   Defaults.Any()         -> true when the table has any spec
--
-- A spec without an imported profile scores with its default, while
-- settings.defaults.enabled is on (Profiles.Effective). Any import replaces
-- it: nothing is merged, deleted or migrated. Results scored with one carry
-- the limitation DEFAULT_WEIGHTS: the tooltip tags the row "default weights",
-- and protection is soft (a default-based upgrade protects, a default-based
-- "no upgrade" is unchecked, never a reason for clear: Policy.Protection).
--
-- SPECS is empty on purpose: the owner's decision (2026-11-01) is to ship
-- measured numbers, not the research draft. The source is the owner's own
-- stat-weight sims on MythicSim (mythicsim.com/wow-forever/sim, run by hand:
-- its terms forbid scripted sims) once GG-103 has confirmed the client's stat
-- units. Filling it in:
--   * one entry per spec key (Data/Classes.lua), Pawn tokens the scorer reads
--     (docs/FORMATS.md), our own numbers rounded, primary stat = 1;
--   * REVISION + 1 (it is the profiles' version: answers built on the old
--     table are never served again after an update);
--   * SOURCE says where they came from (engine build, date), shown in /gg.
------------------------------------------------------------

local GG = GlassGear
local Defaults = {}
GG.Data.Defaults = Defaults

Defaults.REVISION = 0
Defaults.SOURCE = nil       -- e.g. "MythicSim stat weights, engine 043aa9f2, WoW 1.60.1.70707, 2026-11-05"

-- [specKey] = { weights = { Token = number, ... } }
Defaults.SPECS = {}

function Defaults.Any() return next(Defaults.SPECS) ~= nil end

function Defaults.For(specKey)
    local d = type(specKey) == "string" and Defaults.SPECS[specKey]
    if type(d) ~= "table" or type(d.weights) ~= "table" then return nil end
    local weights = {}
    for token, v in pairs(d.weights) do weights[token] = v end
    return { id = "default:" .. specKey, version = "defaults-" .. Defaults.REVISION, specKey = specKey,
        name = GG.L["Glass Gear default weights"], origin = Defaults.SOURCE or GG.L["Glass Gear default weights"],
        source = "default", updatedAt = nil,
        weights = weights, ignored = {}, ignoredTokens = {}, missing = {}, armor = nil }
end

return Defaults
