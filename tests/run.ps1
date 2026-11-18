<#
    run.ps1 - Run all Glass Gear unit tests.

    The tests are plain Lua 5.1 scripts on WowTestKit (tests\kit.pin names
    the commit and the client build). WoW uses Lua 5.1, so the tests do too,
    not the newer Lua that may be first on PATH.

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -KitDev      # the ..\WowTestKit working copy, not the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$KitDev
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Lua)) {
    Write-Error "Lua 5.1 interpreter not found at: $Lua  (pass -Lua <path>)"
    exit 1
}

$RepoRoot = Split-Path -Parent $PSScriptRoot

# Syntax-check every Lua file in the repo (shipped, tests, tools), not only
# the TOC's. A missing luac must fail the run: no test loads every file, so
# skipping this would let a syntax error through behind a green result.
Push-Location $RepoRoot
try {
    $luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"
    if (-not (Test-Path $luac)) {
        Write-Error "luac.exe not found next to $Lua; the syntax check cannot run."
        exit 1
    }
    $sources = Get-ChildItem -Recurse -Filter "*.lua" -File |
        Where-Object { $_.FullName -notmatch '\\\.git\\' } |
        ForEach-Object { Resolve-Path -Relative $_.FullName }
    if ($sources.Count -eq 0) { Write-Error "no Lua files found"; exit 1 }
    & $luac -p @sources
    if ($LASTEXITCODE -ne 0) {
        Write-Host "luac -p FAILED" -ForegroundColor Red
        exit 1
    }
    Remove-Item -LiteralPath (Join-Path $RepoRoot "luac.out") -ErrorAction SilentlyContinue
    Write-Host "luac -p: ok ($($sources.Count) files)" -ForegroundColor DarkGray
}
finally {
    Pop-Location
}

# The tests: WowTestKit's runner, at the pin (or -KitDev).
. (Join-Path $PSScriptRoot "kit.ps1")
$kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev
& (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "GlassGear.toc" -Lua $Lua
exit $LASTEXITCODE
