------------------------------------------------------------
-- test_entry_sync.lua - the adr/0001 per-entry model with a simulated
-- transport, the GG1 codec, and the size budget (M0 fixtures listed in the
-- ADR). Two stores stand for the owner's two WoW accounts.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
local GG = H.loadPure()
local ES, Codec = GG.Engine.EntrySync, GG.Engine.Codec

local function prof(name, w) return { specKey = "PRIEST.HOLY", name = name, source = "manual", updatedAt = 1,
    weights = { Intellect = w or 1 }, ignored = {} } end
local function send(fromStore, id, toStore, label)
    -- Through the codec, as the wire would.
    local line = assert(Codec.Encode(fromStore.entries[id]))
    return toStore:Receive(assert(Codec.Decode(line)), label or "A")
end
local function sendAll(from, to)
    for _, id in ipairs(ES.ToPull(to, from:Manifest())) do send(from, id, to) end
end

local ID = "G-Karuzo:PRIEST.HOLY:1"

-- Lag fast-forward: A edits three times while B is offline.
local A, B = ES.New({}, "wa"), ES.New({}, "wb")
local e = A:Create(ID, "profile", prof("Raid"))
H.eq(send(A, ID, B), "replace", "unknown id: adopt")
for i = 1, 3 do e = A:Edit(ID, e.version, prof("Raid", i + 1)) end
H.eq(send(A, ID, B), "replace", "descendant: fast-forward")
H.eq(B.entries[ID].data.weights.Intellect, 4, "B has A's latest")
H.eq(send(A, ID, B), "ignore", "duplicate delivery: ignore")

-- Divergent edits: conflict copy, durable suppression of replays.
local v = B.entries[ID].version
local eb = B:Edit(ID, v, prof("Raid B", 9))
local ea = A:Edit(ID, v, prof("Raid A", 7))
H.eq(send(A, ID, B), "conflict", "divergent: keep local, store incoming as a copy")
local copyId = ID .. "~" .. ea.version
H.eq(B.entries[ID].data.name, "Raid B", "B keeps its own root")
H.eq(B.entries[copyId].data.name, "Raid A", "A's version kept whole as a copy")
H.eq(send(A, ID, B), "ignore", "replay of the same branch: ignore")
local bVersion = B.entries[ID].version
for i = 1, 25 do B:Edit(ID, B.entries[ID].version, prof("Raid B", i)) end
H.eq(send(A, ID, B), "ignore", "replay after 25 more edits: the recorded copy suppresses it")

-- Stale expected version refused.
local _, err = B:Edit(ID, bVersion, prof("late"))
H.eq(err, "stale", "edit with a stale expected version is refused")

-- Resolution converges in both orders, including the asymmetric mirror copy.
A, B = ES.New({}, "ra"), ES.New({}, "rb")
A:Create(ID, "profile", prof("Base"))
send(A, ID, B)
local base = A.entries[ID].version
local va = A:Edit(ID, base, prof("A", 2)).version
local vb = B:Edit(ID, base, prof("B", 3)).version
H.eq(send(B, ID, A, "B"), "conflict", "A stores B's branch")
H.eq(send(A, ID, B, "A"), "conflict", "B stores A's branch (mirror)")
local root = A:Resolve(ID .. "~" .. vb, "theirs", va)
H.eq(root.data.name, "B", "A keeps B's version")
H.eq(A.entries[ID .. "~" .. vb].deleted, true, "A's copy retired")
H.eq(send(A, ID, B), "replace", "B fast-forwards to the resolution")
H.eq(B.entries[ID .. "~" .. va].deleted, true, "B retires its mirror copy (the one receive-side mint)")
H.eq(send(A, ID, B), "ignore", "duplicate resolution: no-op")
local versionsBefore = B.entries[ID .. "~" .. va].version
send(A, ID, B)
H.eq(B.entries[ID .. "~" .. va].version, versionsBefore, "repeated retirement mints nothing")
H.eq(A.entries[ID].version, B.entries[ID].version, "roots converged")

-- Tombstone vs edit, both ways.
A, B = ES.New({}, "ta"), ES.New({}, "tb")
A:Create(ID, "profile", prof("Base"))
send(A, ID, B)
local tv = A.entries[ID].version
A:Delete(ID, tv)
B:Edit(ID, tv, prof("Edited"))
H.eq(send(A, ID, B), "conflict", "edited here, deleted there: a deletion copy")
local dcopy
for id, x in pairs(B.entries) do if x.conflict then dcopy = x end end
H.eq(dcopy.conflict.deletion, true, "copy marked as a deletion")
H.eq(send(B, ID, A), "conflict", "deleted here, edited there: a live copy")
H.eq(A.entries[ID].deleted, true, "A's root stays deleted until resolved")
-- The deletion copy travels (codec + a third peer) and resolves.
local dline = assert(Codec.Encode(dcopy))
local C = ES.New({}, "tc")
H.eq(C:Receive(assert(Codec.Decode(dline)), "B"), "replace", "a third peer accepts the deletion copy")
H.eq(C.entries[dcopy.id].conflict.deletion, true, "...with its deletion flag")
local rootB = B:Resolve(dcopy.id, "delete", B.entries[ID].version)
H.eq(rootB.deleted, true, "'delete here too' tombstones the root")
H.check(Codec.Encode(rootB) ~= nil, "the resolution encodes")
H.eq(send(B, ID, A), "replace", "...and A fast-forwards to it")

-- A conflict copy of another kind is refused; its content never reaches the root.
local foreign = { id = ID .. "~zz:1", kind = "baseline", version = "zz:1", ancestors = {},
    conflict = { of = ID }, data = { specKey = "PRIEST.HOLY", source = "observed", capturedAt = 1, slots = {} } }
local A2 = ES.New({}, "k")
A2:Create(ID, "profile", prof("Base"))
H.eq(select(2, A2:Receive(foreign, "x")), "bad-entry", "cross-kind copy refused")
H.eq(select(2, A2:Receive({ id = "G-1:PRIEST.HOLY:9", kind = "profile", version = "v:1", ancestors = {},
    data = { specKey = "PRIEST.HOLY", name = "x", source = "imported-pawn", updatedAt = 1, weights = { Intellect = 5000 } } }, "x")),
    "bad-entry", "out-of-range weight refused on receipt")
-- Malformed flags and optional fields: rejected, never thrown, store untouched.
local live = A2.entries[ID].version
H.eq(select(2, A2:Receive({ id = ID, kind = "profile", version = "zz:2", ancestors = { live }, deleted = "false" }, "x")),
    "bad-entry", "a non-boolean deleted flag is refused")
H.eq(A2.entries[ID].deleted, nil, "...and the live root is untouched")
for _, field in ipairs({ "ignored", "ignoredTokens", "missing", "armor" }) do
    local d = prof("Odd")
    d[field] = true
    local ok, res = pcall(A2.Receive, A2, { id = "G-1:PRIEST.HOLY:" .. field, kind = "profile", version = "zz:3",
        ancestors = {}, data = d }, "x")
    H.check(ok and res == nil, "malformed optional field '" .. field .. "' rejected without an error")
end
H.eq(select(2, A2:Receive({ id = ID .. "~q:1", kind = "profile", version = "q:1", ancestors = {},
    conflict = { of = ID, retired = "yes" }, data = prof("x") }, "x")), "bad-entry", "a non-boolean conflict flag is refused")

H.eq(select(2, A2:Create("G-1:PRIEST.HOLY:10", "profile", { specKey = "NOPE", name = "x", source = "manual", updatedAt = 1, weights = {} })),
    "bad-data:specKey", "local writes are validated too")

-- Incomparable tombstones: lexical tie-break, both keep the greater.
A, B = ES.New({}, "xa"), ES.New({}, "xb")
A:Create(ID, "profile", prof("Base"))
send(A, ID, B)
tv = A.entries[ID].version
A:Delete(ID, tv)
B:Delete(ID, tv)
send(A, ID, B); send(B, ID, A)
H.eq(A.entries[ID].version, B.entries[ID].version, "incomparable tombstones converge")

-- Restored SavedVariables: a new session token never reuses a version.
local saved = {}
local S1 = ES.New(saved, "s1")
S1:Create(ID, "profile", prof("Base"))
local snapshot = {}
for k, x in pairs(saved) do snapshot[k] = { id = x.id, kind = x.kind, version = x.version, ancestors = {}, data = x.data } end
local peer = ES.New({}, "peer")
send(S1, ID, peer)
S1:Edit(ID, S1.entries[ID].version, prof("Edit 1"))
send(S1, ID, peer)
local S2 = ES.New(snapshot, "s2")             -- restored backup, fresh token
S2:Edit(ID, S2.entries[ID].version, prof("Different edit"))
H.check(S2.entries[ID].version ~= peer.entries[ID].version, "different content, different version")
H.eq(send(S2, ID, peer), "conflict", "...so the peer sees a conflict, not a silent 'same version'")

-- Aged-out ancestry: at most one conservative copy, never a root change.
A, B = ES.New({}, "ga"), ES.New({}, "gb")
A:Create(ID, "profile", prof("Base"))
send(A, ID, B)
local old = { id = ID, kind = "profile", version = A.entries[ID].version, ancestors = {}, data = prof("Base") }
for i = 1, 22 do B:Edit(ID, B.entries[ID].version, prof("B", i)) end
local rootBefore = B.entries[ID].version
H.eq(B:Receive(old, "A"), "conflict", "history aged out: one conservative copy")
H.eq(B:Receive(old, "A"), "ignore", "and only one")
H.eq(B.entries[ID].version, rootBefore, "root unchanged")

-- Multi-page manifest exchange: idle peers still converge; lost deliveries retried.
A, B = ES.New({}, "ma"), ES.New({}, "mb")
for i = 1, 7 do A:Create("G-Karuzo:PRIEST.HOLY:" .. i, "profile", prof("P" .. i)) end
local rounds, lost = 0, true
repeat
    rounds = rounds + 1
    local pull = ES.ToPull(B, A:Manifest())
    for n = 1, math.min(3, #pull) do           -- at most 3 outstanding per exchange
        if lost and n == 1 then lost = false   -- the first answer is lost on the wire
        else send(A, pull[n], B) end
    end
until #ES.ToPull(B, A:Manifest()) == 0 or rounds > 10
H.check(rounds <= 4, "idle peers converge through timed exchanges (rounds: " .. rounds .. ")")
H.eq(#ES.ToPull(A, B:Manifest()), 0, "confirmed: manifests match both ways")

-- Inventory: a pending weight change keeps the character maybeBehind.
A, B = ES.New({}, "ia"), ES.New({}, "ib")
A:Create(ID, "profile", prof("P0"))
send(A, ID, B)
H.eq(ES.MaybeBehind(B, A:Manifest(), "G-Karuzo:"), false, "in sync")
A:Edit(ID, A.entries[ID].version, prof("P1", 5))
A:Create("G-Karuzo:PRIEST.SHADOW:1", "profile", prof("Q"))
send(A, "G-Karuzo:PRIEST.SHADOW:1", B)        -- Q arrives, P1 does not
H.eq(ES.MaybeBehind(B, A:Manifest(), "G-Karuzo:"), true, "P1 outstanding: maybeBehind despite receiving Q")
send(A, ID, B)
H.eq(ES.MaybeBehind(B, A:Manifest(), "G-Karuzo:"), false, "cleared only when the manifests match")

-- Codec: complete round trips (every field), escaping, refusals, sizes.
local function deepEq(x, y)
    if type(x) ~= type(y) then return false end
    if type(x) ~= "table" then return x == y end
    for k, v in pairs(x) do if not deepEq(v, y[k]) then return false end end
    for k in pairs(y) do if x[k] == nil then return false end end
    return true
end
local full = { id = "G-1:PALADIN.PROTECTION:u1", kind = "profile", version = "w:5", ancestors = { "w:4", "w:3" },
    data = { specKey = "PALADIN.PROTECTION", name = "Tank", origin = "Prot WoWSims Weights (TBC)", source = "wowsims-pawn-ep",
        updatedAt = 1793500000, weights = { Stamina = 1, Strength = 0.5 }, ignored = { Spirit = true },
        ignoredTokens = { Mana = "7", Armor2 = "0.012" }, missing = { "DefenseRating", "BlockValue" }, armor = { 1, 4 } } }
H.check(deepEq(assert(Codec.Decode(assert(Codec.Encode(full)))), full), "profile entry round-trips completely")
local fullB = { id = "G-1:PALADIN.PROTECTION:baseline", kind = "baseline", version = "w:6", ancestors = {},
    data = { specKey = "PALADIN.PROTECTION", source = "observed", capturedAt = 1793500000, group = 2,
        slots = { [1] = { state = "occupied", item = "item:14094::::::::::::1:12745" }, [2] = { state = "empty" }, [3] = { state = "unknown" } } } }
H.check(deepEq(assert(Codec.Decode(assert(Codec.Encode(fullB)))), fullB), "baseline entry round-trips (spec group kept)")
local good = assert(Codec.Encode(full))
H.eq(select(2, Codec.Decode((good:gsub("Stamina=1", "Stamina=1.2.3", 1)))), "bad-entry", "malformed number refused")
H.eq(select(2, Codec.Decode((good:gsub("Stamina=1", "Stamina=10000", 1)))), "bad-entry", "out-of-range weight refused")
H.eq(select(2, Codec.Decode((assert(Codec.Encode(fullB)):gsub("1:o:", "999:o:", 1)))), "bad-entry", "slot outside the gear slots refused")
H.eq(select(2, Codec.Decode((assert(Codec.Encode(fullB)):gsub(";2;1:o:", ";garbage;1:o:", 1)))), "bad-entry", "a malformed spec group is refused")
H.eq(select(2, Codec.Decode((good:gsub("|w:4,w:3|", "|w:4,w:3|q", 1)))), "bad-entry", "unknown flag refused")
local tricky = { id = "G-1:PRIEST.HOLY:x|y", kind = "profile", version = "w:1", ancestors = { "w:0" },
    data = { specKey = "PRIEST.HOLY", name = "a;b,c|d", source = "imported-pawn", updatedAt = 1793500000,
        weights = { Intellect = 0.42, Healing = -1.5 }, ignored = { Spirit = true } } }
local back = assert(Codec.Decode(assert(Codec.Encode(tricky))))
H.eq(back.id, tricky.id, "id with | survives")
H.eq(back.data.name, "a;b,c|d", "name with separators survives")
H.eq(back.data.weights.Healing, -1.5, "negative weight")
H.eq(back.data.ignored.Spirit, true, "X survives")
H.eq(back.data.updatedAt, 1793500000, "timestamp base36 round trip")
H.check(not Codec.Encode(tricky):find("\n"), "never a raw newline")
local bl = { id = "G-1:PRIEST.HOLY:baseline", kind = "baseline", version = "w:2", ancestors = {},
    data = { specKey = "PRIEST.HOLY", source = "observed", capturedAt = 1793500000,
        slots = { [1] = { state = "occupied", item = "item:14094::::::::::::1:12745" }, [2] = { state = "empty" }, [3] = { state = "unknown" } } } }
back = assert(Codec.Decode(assert(Codec.Encode(bl))))
H.eq(back.data.slots[1].item, "item:14094::::::::::::1:12745", "the bonus ID carrying the suffix is kept in baselines")
local oldForm = (assert(Codec.Encode(bl)):gsub("item%:14094%:%:%:%:%:%:%:%:%:%:%:%:1%:12745", "19019:0:1234", 1))
H.eq(select(2, Codec.Decode(oldForm)), "bad-entry", "the old id:enchant:suffix form is refused")
local long = (assert(Codec.Encode(bl)):gsub("item%:14094%:%:%:%:%:%:%:%:%:%:%:%:1%:12745", "item:1" .. string.rep(":1", 40), 1))
H.eq(select(2, Codec.Decode(long)), "bad-entry", "an item string over MAX_ITEM is refused")
H.eq(back.data.slots[2].state, "empty", "empty")
H.eq(back.data.slots[3].state, "unknown", "unknown")
H.eq(select(2, Codec.Decode("GG2|p|x|v||| ")), "unknown-schema", "newer schema refused")
H.eq(select(2, Codec.Decode("GG1|p|x|v|||Bogus=1")), "bad-entry", "malformed payload refused")
local tomb = assert(Codec.Decode(assert(Codec.Encode({ id = "a", kind = "profile", version = "w:3", ancestors = {}, deleted = true }))))
H.eq(tomb.deleted, true, "tombstone round trip")

-- Size budget (targets, adr/0001). A bounded stress fixture (not a proof of the
-- maximum): the 40 longest token names, a 24-char name of
-- characters that all need escaping, a long origin, 20 ancestors and a
-- conflict-copy id and flag.
local root = "Player-1234-0ABCDEF0:DRUID.FERAL_TANK:" .. string.rep("9", 20)
local worst = { id = root .. "~ffffffffffffffff:99999", kind = "profile", version = "ffffffffffffffff:99999",
    ancestors = {}, conflict = { of = root },
    data = { specKey = "DRUID.FERAL_TANK", name = string.rep("|", 24), origin = string.rep(";", 60),
        source = "wowsims-pawn-ep", updatedAt = 1793500000, weights = {}, ignored = {} } }
for i = 1, 20 do worst.ancestors[i] = "ffffffffffffffff:" .. (99900 + i) end
local longest = {}
for _, t in ipairs(GG.Data.Stats.ORDER) do longest[#longest + 1] = t end
table.sort(longest, function(a, b) return #a > #b or (#a == #b and a < b) end)
for n = 1, 40 do worst.data.weights[longest[n]] = -123.456 end
local wline = assert(Codec.Encode(worst))
H.check(#wline <= Codec.MAX_BYTES, "the stress profile entry fits 2 KB (" .. #wline .. " bytes)")
-- The exact boundary: 2048 bytes encode, 2049 are too-large.
local pad = #"GG1|p||w:1||d|"
H.check(Codec.Encode({ id = string.rep("x", Codec.MAX_BYTES - pad), kind = "profile", version = "w:1", deleted = true }) ~= nil,
    "an entry of exactly 2048 bytes encodes")
H.eq(select(2, Codec.Encode({ id = string.rep("x", Codec.MAX_BYTES - pad + 1), kind = "profile", version = "w:1", deleted = true })),
    "too-large", "2049 bytes is too-large")
worst.data.name = string.rep("N", 25)
H.eq(select(2, Codec.Encode(worst)), "bad-entry", "over-long name refused")
local big = { id = string.rep("x", 2100), kind = "profile", version = "w:1", ancestors = {}, deleted = true }
H.eq(select(2, Codec.Encode(big)), "too-large", "oversized entry -> too-large, stays local")

-- Backfill for 50 characters: 3 specs x 4 worst-case profiles, a full baseline
-- and one tombstone per spec, all encoded. A 100-id manifest page fits the
-- 16 KB batch limit even if escaping doubles it (adr/0001, transport limits).
worst.data.name = string.rep("N", 24)
local slots = {}
-- A heavy but real-looking item: enchant, suffix bonus, two more bonuses, one modifier.
local HEAVY = "item:99999:9999::::::::::99:3:99999:99999:99999:1:9:99999"
for _, slot in ipairs(GG.Data.Slots.GEAR) do slots[slot] = { state = "occupied", item = HEAVY } end
-- The largest legal baseline: every gear slot at MAX_ITEM, 20 worst-case
-- ancestors, a conflict-copy id. It must still fit one entry.
local maxSlots = {}
for _, slot in ipairs(GG.Data.Slots.GEAR) do
    maxSlots[slot] = { state = "occupied", item = ("item:99999" .. string.rep(":9", 40)):sub(1, Codec.MAX_ITEM) }
end
local maxB = { id = string.format("Player-1234-%08X:%s:baseline~ffffffffffffffff:99999", 1, "PALADIN.PROTECTION"),
    kind = "baseline", version = worst.version, ancestors = worst.ancestors,
    conflict = { of = string.format("Player-1234-%08X:%s:baseline", 1, "PALADIN.PROTECTION") },
    data = { specKey = "PALADIN.PROTECTION", source = "fallback-current", capturedAt = 1793500000, group = 2, slots = maxSlots } }
local maxEnc, maxErr = Codec.Encode(maxB)
H.check(maxEnc ~= nil, "the largest legal baseline fits one entry (" .. tostring(maxEnc and #maxEnc or maxErr) .. " bytes)")

local total, ids = 0, {}
for c = 1, 50 do
    for sp = 1, 3 do
        local specKey = ({ "PRIEST.DISCIPLINE", "PRIEST.HOLY", "PRIEST.SHADOW" })[sp]
        for p = 1, 4 do
            local idp = string.format("Player-1234-%08X:%s:%020d", c, specKey, p)
            worst.id, worst.conflict = idp, nil
            worst.data.specKey = specKey
            total = total + #assert(Codec.Encode(worst))
            ids[#ids + 1] = idp .. "=" .. worst.version
        end
        local b = { id = string.format("Player-1234-%08X:%s:baseline", c, specKey), kind = "baseline",
            version = worst.version, ancestors = worst.ancestors,
            data = { specKey = specKey, source = "observed", capturedAt = 1793500000, group = 1, slots = slots } }
        total = total + #assert(Codec.Encode(b))
        local t = { id = string.format("Player-1234-%08X:%s:old", c, specKey), kind = "profile",
            version = worst.version, ancestors = worst.ancestors, deleted = true }
        total = total + #assert(Codec.Encode(t))
    end
end
local page = table.concat(ids, ",", 1, 100)
H.check(2 * #page <= 16 * 1024, "a 100-id manifest page fits 16 KB even doubled by escaping (" .. #page .. " bytes)")
print(string.format("  info: worst-case full backfill for 50 characters ~ %d KB before compression (paged by the entry-sync library, ES-001)", math.floor(total / 1024)))

-- Inventory -> protection: an outstanding weight change keeps protection from "clear".
A, B = ES.New({}, "pa"), ES.New({}, "pb")
A:Create(ID, "profile", prof("P0"))
send(A, ID, B)
A:Edit(ID, A.entries[ID].version, prof("P1", 5))
local result = { status = "no_upgrade", character = { provenance = "own-account" }, spec = "PRIEST.HOLY",
    eligibility = { equipNow = true }, limitations = {}, reasons = {},
    baseline = { source = "observed", complete = true, maybeBehind = ES.MaybeBehind(B, A:Manifest(), "G-Karuzo:") } }
H.eq(GG.Engine.Policy.Protection({ result }).verdict, "unknown", "weights changed on the other account: not clear")
send(A, ID, B)
result.baseline.maybeBehind = ES.MaybeBehind(B, A:Manifest(), "G-Karuzo:")
H.eq(GG.Engine.Policy.Protection({ result }).verdict, "clear", "clear once the manifests match")

H.done("test_entry_sync")
