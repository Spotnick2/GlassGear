------------------------------------------------------------
-- test_manifest.lua - TOC, .pkgmeta and the TOC's files (GG-001).
------------------------------------------------------------

local H = dofile("tests/harness.lua")

eq(H.directive("Interface"), "16001", "Forever interface (1.60.1)")
eq(H.directive("Version"), "@" .. "project-version" .. "@", "packager token, never a literal version")
eq(H.directive("SavedVariables"), "GlassGearDB", "account-wide table")
eq(H.directive("SavedVariablesPerCharacter"), "GlassGearChar", "per-character table (not 'PerCharacter')")
eq(H.directive("OptionalDeps"), "AltStable, GlassUI", "integrations are optional, never Dependencies")
eq(H.directive("Dependencies"), nil, "no hard dependency")
eq(H.directive("Category"), "|cff7fd4ffGlass|r", "Glass family category line")
eq(H.directive("X-Curse-Project-ID"), "1778699", "the CurseForge project ID (RELEASING.md)")
eq(H.directive("X-Wago-ID"), "O67b5PN3", "the Wago project ID: the wago job uploads to the project the packaged TOC names")

-- What every addon TOC must get right (WowTestKit): the interface, the
-- version token, each listed .lua file exists, each entry is listed once.
Kit.checkToc("GlassGear.toc")

-- Every TOC entry exists with the exact case.
local function listDir(dir)
    local names = {}
    local p = io.popen('dir /b "' .. dir:gsub("/", "\\") .. '" 2>nul')
    if p then for name in p:lines() do names[#names + 1] = name end p:close() end
    return names
end
local onWindows = package.config:sub(1, 1) == "\\"
for _, file in ipairs(H.tocFiles()) do
    local path = file:gsub("\\", "/")
    local f = io.open(path, "rb")
    check(f ~= nil, "TOC entry exists: " .. file)
    if f then f:close() end
    if onWindows then
        local dir = "."
        for segment in path:gmatch("[^/]+") do
            local found = false
            for _, name in ipairs(listDir(dir)) do if name == segment then found = true end end
            check(found, "TOC entry case matches disk: " .. file)
            dir = dir .. "/" .. segment
        end
    end
    local text = H.readFile(path) or ""
    check(not text:find("@project%-[%w-]+@"), "no packager keyword in " .. file)
end

local libs = H.tocFiles(true)
eq(libs[1], "Libs\\LibGlass-1.0\\LibGlass-1.0.xml", "LibGlass is the only embedded library")
eq(H.tocFiles()[1], "Core\\Init.lua", "the namespace loads first")
eq(H.tocFiles()[#H.tocFiles()], "Core\\Main.lua", "lifecycle loads last")

local pkg = H.readFile(".pkgmeta") or ""
check(pkg:find("package%-as: GlassGear") ~= nil, ".pkgmeta packages as GlassGear")
check(pkg:find("Libs/LibGlass%-1%.0:%s*\n%s*url: https://github.com/Spotnick2/LibGlass%s*\n%s*tag: r11") ~= nil,
    "LibGlass pinned to tag r11")
for _, ignored in ipairs({ "docs", "tests", "Tools", "Locales/enUS.lua", "Libs/LibGlass-1.0/tests" }) do
    check(pkg:find("\n  %- " .. ignored:gsub("%-", "%%-") .. "\n") ~= nil, ".pkgmeta ignores " .. ignored)
end

done("test_manifest")
