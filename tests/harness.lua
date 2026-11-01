------------------------------------------------------------
-- harness.lua - tiny assertion harness.
--
--     local H = dofile("tests/harness.lua")
--     H.eq(actual, expected, "what this proves")
--     H.done("test_thing")
--
-- Run from the repo root so the relative paths resolve.
------------------------------------------------------------

local H = { run = 0, failures = 0 }

function H.check(cond, msg)
    H.run = H.run + 1
    if not cond then
        H.failures = H.failures + 1
        print("  FAIL: " .. (msg or "assertion failed"))
    end
end

function H.eq(a, b, msg)
    H.check(a == b, (msg or "values differ") ..
        "  (expected " .. tostring(b) .. ", got " .. tostring(a) .. ")")
end

-- Runs fn and checks it raises; returns the error text.
function H.raises(fn, msg)
    local ok, err = pcall(fn)
    H.check(not ok, (msg or "expected an error") .. " (it returned normally)")
    return err
end

-- Runs fn and checks it does not raise.
function H.ok(fn, msg)
    local ok, err = pcall(fn)
    H.check(ok, (msg or "unexpected error") .. ": " .. tostring(err))
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

-- The TOC as a list of lines, trailing whitespace stripped.
function H.tocLines()
    local toc = assert(H.readFile("GlassGear.toc"), "GlassGear.toc not found - run from the repo root")
    local lines = {}
    for line in (toc .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = (line:gsub("%s+$", ""))
    end
    return lines
end

-- The value of a `## Name: value` directive, or nil.
function H.directive(name)
    -- Escape the name: "X-Curse-Project-ID" contains "-", a Lua pattern
    -- quantifier, so an unescaped match silently finds nothing.
    local escaped = name:gsub("(%W)", "%%%1")
    for _, line in ipairs(H.tocLines()) do
        local value = line:match("^##%s*" .. escaped .. ":%s*(.*)$")
        if value then return value end
    end
    return nil
end

-- Every file the TOC loads, in order, with the TOC's backslashes.
-- The addon's own TOC files (in the repo), or with `libs` the embedded
-- libraries' entries (Libs\..., fetched by the packager, never committed).
function H.tocFiles(libs)
    local files = {}
    for _, line in ipairs(H.tocLines()) do
        local file = line:match("^%s*([^#%s].-)%s*$")
        if file and (file:match("^Libs\\") ~= nil) == (libs == true) then files[#files + 1] = file end
    end
    return files
end

-- Loads the pure modules (no game API) into a fresh GlassGear namespace, in
-- TOC order. Engine tests use this instead of the stubs.
function H.loadPure()
    GlassGear = nil
    for _, f in ipairs({ "Core/Init.lua", "Data/Stats.lua", "Data/Slots.lua", "Data/Classes.lua",
        "Data/ItemSets.lua", "Engine/Score.lua", "Engine/SlotCompare.lua", "Engine/SetBonus.lua",
        "Engine/Evaluate.lua", "Engine/Policy.lua", "Engine/EntrySync.lua", "Engine/Codec.lua",
        "Profiles/PawnString.lua", "Profiles/Profiles.lua", "Item/ItemContext.lua",
        "Character/Spec.lua", "Character/Baselines.lua", "Presentation/TooltipView.lua" }) do
        dofile(f)
    end
    return GlassGear
end

-- True when list contains value.
function H.has(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end

function H.done(name)
    if H.failures > 0 then
        print(string.format("%s: %d/%d FAILED", name, H.failures, H.run))
        os.exit(1)
    end
    print(string.format("%s: %d tests passed", name, H.run))
end

return H
