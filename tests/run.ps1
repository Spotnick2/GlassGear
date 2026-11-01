<#
    run.ps1 - Run all Glass Gear unit tests.

    The tests are plain Lua 5.1 scripts (no dependencies). WoW uses Lua 5.1,
    so the tests do too, not the newer Lua that may be first on PATH.

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Lua)) {
    Write-Error "Lua 5.1 interpreter not found at: $Lua  (pass -Lua <path>)"
    exit 1
}

$RepoRoot = Split-Path -Parent $PSScriptRoot

# Run from the repo root so the tests can dofile('tests/...') and read
# GlassGear.toc with paths relative to the project.
Push-Location $RepoRoot
try {
    # Syntax-check every Lua file in the repo (shipped, tests, tools). A
    # missing luac must fail the run: no test loads every file, so skipping
    # this would let a syntax error through behind a green result.
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

    $failed = 0
    Get-ChildItem (Join-Path $PSScriptRoot "test_*.lua") | Sort-Object Name | ForEach-Object {
        Write-Host "-- $($_.Name) " -NoNewline -ForegroundColor Cyan
        & $Lua $_.FullName
        if ($LASTEXITCODE -ne 0) { $failed++ }
    }

    if ($failed -gt 0) {
        Write-Host "$failed test file(s) FAILED" -ForegroundColor Red
        exit 1
    }
    Write-Host "All test files passed." -ForegroundColor Green
}
finally {
    Pop-Location
}
