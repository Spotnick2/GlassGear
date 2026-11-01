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

-- Codec: round trip, escaping, refusals, sizes.
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
        slots = { [1] = { state = "occupied", item = "19019:0:1234" }, [2] = { state = "empty" }, [3] = { state = "unknown" } } } }
back = assert(Codec.Decode(assert(Codec.Encode(bl))))
H.eq(back.data.slots[1].item, "19019:0:1234", "suffix kept in baselines")
H.eq(back.data.slots[2].state, "empty", "empty")
H.eq(back.data.slots[3].state, "unknown", "unknown")
H.eq(select(2, Codec.Decode("GG2|p|x|v||| ")), "unknown-schema", "newer schema refused")
H.eq(select(2, Codec.Decode("GG1|p|x|v|||Bogus=1")), "bad-entry", "malformed payload refused")
local tomb = assert(Codec.Decode(assert(Codec.Encode({ id = "a", kind = "profile", version = "w:3", ancestors = {}, deleted = true }))))
H.eq(tomb.deleted, true, "tombstone round trip")

-- Size budget (targets, adr/0001): worst-case entry with 20 ancestors.
local worst = { id = "Player-1234-0ABCDEF0:DRUID.FERAL_TANK:9999999999", kind = "profile", version = "ffffffffffffffff:99999",
    ancestors = {}, data = { specKey = "DRUID.FERAL_TANK", name = string.rep("N", 24), source = "wowsims-pawn-ep",
        updatedAt = 1793500000, weights = {}, ignored = {} } }
for i = 1, 20 do worst.ancestors[i] = "ffffffffffffffff:" .. (99900 + i) end
local n = 0
for t in pairs(GG.Data.Stats.TOKENS) do
    if n < 40 then worst.data.weights[t] = -123.456; n = n + 1 end
end
local line = assert(Codec.Encode(worst))
H.check(#line <= Codec.MAX_BYTES, "worst-case profile entry fits 2 KB (" .. #line .. " bytes)")
worst.data.name = string.rep("N", 25)
H.eq(select(2, Codec.Encode(worst)), "bad-entry", "over-long name refused")
local big = { id = string.rep("x", 2100), kind = "profile", version = "w:1", ancestors = {}, deleted = true }
H.eq(select(2, Codec.Encode(big)), "too-large", "oversized entry -> too-large, stays local")

-- Backfill for 50 characters incl. tombstones: report totals; a 100-id manifest page fits 24 KB.
local total, ids = 0, {}
for c = 1, 50 do
    for s = 1, 3 do
        for p = 1, 4 do
            local idp = string.format("Player-1234-%08X:PRIEST.SPEC%d:%d", c, s, p)
            worst.id, worst.data.name = idp, string.rep("N", 24)
            total = total + #assert(Codec.Encode(worst))
            ids[#ids + 1] = idp .. "=" .. worst.version
        end
        total = total + 600   -- a baseline entry (19 compact items) is well under 600 bytes
    end
end
local page = table.concat(ids, ",", 1, 100)
H.check(#page < 24 * 1024, "a 100-id manifest page fits 24 KB (" .. #page .. " bytes)")
print(string.format("  info: worst-case full backfill for 50 characters ~ %d KB before compression", math.floor(total / 1024)))

H.done("test_entry_sync")
