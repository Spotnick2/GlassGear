------------------------------------------------------------
-- harness.lua - the tests' own helpers. The assertions are WowTestKit's
-- globals (check, eq, done), loaded by tests/wow_stubs.lua:
--
--     dofile("tests/wow_stubs.lua")      -- a test that loads the addon
--     local H = dofile("tests/harness.lua")
--     eq(actual, expected, "what this proves")
--     done("test_thing")
--
-- A pure test (the engine, no game API) dofiles only this file: it loads the
-- kit for the assertions, then takes the stub core's client functions off
-- again, so a pure module that calls one still fails as it did without
-- stubs (AGENTS.md, "Pure engine").
--
-- Run from the repo root so the relative paths resolve.
------------------------------------------------------------

if not rawget(_G, "Kit") then
    dofile("tests/kit.lua")
    -- Lua's own print, pcall and xpcall stay (the core's count a swallowed
    -- secret touch, and print feeds done()'s stray-"|" check).
    local keep = { print = true, pcall = true, xpcall = true }
    for _, name in ipairs(Kit.CORE_GLOBALS) do
        if not keep[name] then rawset(_G, name, nil) end
    end
    for name in pairs(Kit.CORE_FRAMEXML) do rawset(_G, name, nil) end
end

local H = {}

local TOC = "GlassGear.toc"

-- Runs fn and checks it raises; returns the error text.
function H.raises(fn, msg)
    local ok, err = pcall(fn)
    check(not ok, (msg or "expected an error") .. " (it returned normally)")
    return err
end

-- Runs fn and checks it does not raise.
function H.ok(fn, msg)
    local ok, err = pcall(fn)
    check(ok, (msg or "unexpected error") .. ": " .. tostring(err))
    return ok
end

-- A whole file as text with CRLF normalised, or nil if it does not exist.
function H.readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end

-- The value of a `## Name: value` directive, or nil.
function H.directive(name)
    local toc = assert(H.readFile(TOC), TOC .. " not found - run from the repo root")
    -- Escape the name: "X-Curse-Project-ID" contains "-", a Lua pattern
    -- quantifier, so an unescaped match silently finds nothing.
    local escaped = name:gsub("(%W)", "%%%1")
    for line in (toc .. "\n"):gmatch("([^\n]*)\n") do
        local value = (line:gsub("%s+$", "")):match("^##%s*" .. escaped .. ":%s*(.*)$")
        if value then return value end
    end
    return nil
end

-- Every file the TOC loads, in order, with the TOC's backslashes.
-- The addon's own TOC files (in the repo), or with `libs` the embedded
-- libraries' entries (Libs\..., fetched by the packager, never committed).
function H.tocFiles(libs)
    local files = {}
    for _, file in ipairs(Kit.tocLines(TOC)) do
        if (file:match("^Libs\\") ~= nil) == (libs == true) then files[#files + 1] = file end
    end
    return files
end

-- Loads the pure modules (no game API) into a fresh GlassGear namespace, in
-- TOC order. Engine tests use this instead of the stubs.
function H.loadPure()
    GlassGear = nil
    for _, f in ipairs({ "Core/Init.lua", "Core/Locale.lua", "Data/Stats.lua", "Data/Slots.lua", "Data/Classes.lua",
        "Data/ItemSets.lua", "Engine/Score.lua", "Engine/SlotCompare.lua", "Engine/SetBonus.lua",
        "Engine/Evaluate.lua", "Engine/Policy.lua", "Engine/EntrySync.lua", "Engine/Codec.lua",
        "Profiles/PawnString.lua", "Profiles/Profiles.lua", "Item/ItemContext.lua",
        "Character/Spec.lua", "Character/Baselines.lua", "Presentation/TooltipView.lua",
        "Presentation/MarkerView.lua" }) do
        dofile(f)
    end
    return GlassGear
end

-- FINDING (GlassGear#83): /gg spec's usage line "<SPEC.KEY | none>" holds a
-- bare "|", which the client reads as an escape. done() fails on any stray
-- "|"; a test that prints that line lets exactly it through until it's fixed,
-- so any other stray still fails. Returns how many it let through.
function H.acceptKnownStrays()
    local keep, known = {}, 0
    for _, line in ipairs(WoW.strays) do
        if line:find("usage: /gg spec <1-", 1, true) and line:find("<SPEC.KEY | none>", 1, true) then
            known = known + 1
        else
            keep[#keep + 1] = line
        end
    end
    WoW.strays = keep
    return known
end

-- True when list contains value.
function H.has(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end

return H
