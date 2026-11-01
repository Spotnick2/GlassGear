<#
    deploy.ps1 - Deploy Glass Gear to the WoW: Forever AddOns folder.

    Usage:
        pwsh Tools/deploy.ps1
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\Games\WoW\_forever_\Interface\AddOns"

    TOC-driven (Shatter's Tools/deploy.ps1 pattern): the deployed folder gets
    GlassGear.toc, LICENSE and exactly the files the TOC loads, each at its own
    relative path. A file the TOC names that is missing, or differs in case from
    the TOC line, fails the deploy before anything is copied.

    The embedded LibGlass-1.0 comes from the LibGlass checkout ($env:LIBGLASS,
    else ..\LibGlass) through that library's own Tools\deploy.ps1, first. A
    checkout off the .pkgmeta pin is a warning, not a failure.
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

if ($AddOnsPath -match '_anniversary_') {
    throw "Refusing to deploy the Forever build into the TBC Anniversary client ($AddOnsPath)."
}
if (-not (Test-Path -LiteralPath $AddOnsPath)) {
    throw "AddOns path not found: $AddOnsPath"
}

$tocPath = Join-Path $RepoRoot "GlassGear.toc"
$tocLines = Get-Content -LiteralPath $tocPath
if (-not ($tocLines | Where-Object { $_ -match '^##\s*Interface:\s*16001\s*$' })) {
    throw "GlassGear.toc is not a Forever TOC (## Interface: 16001 missing)."
}

$files = @()
foreach ($line in $tocLines) {
    $entry = $line.Trim()
    if ($entry -eq "" -or $entry.StartsWith("#") -or $entry.StartsWith("Libs\")) { continue }
    $files += $entry
}

# Validate everything first: a half-copied addon is worse than none.
$missing = @()
foreach ($rel in $files) {
    $src = Join-Path $RepoRoot $rel
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { $missing += $rel; continue }
    $dir = $RepoRoot
    foreach ($segment in ($rel -split '\\')) {
        $actual = (Get-ChildItem -LiteralPath $dir -Force | Where-Object { $_.Name -ieq $segment } | Select-Object -First 1).Name
        if ($actual -cne $segment) { $missing += "$rel (case: on disk '$actual')"; break }
        $dir = Join-Path $dir $actual
    }
}
if ($missing.Count -gt 0) {
    throw "GlassGear.toc names files that are missing or differ in case:`n  " + ($missing -join "`n  ")
}

$LibGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
if (-not (Test-Path -LiteralPath (Join-Path $LibGlass "Tools\deploy.ps1"))) {
    throw "LibGlass checkout not found at $LibGlass (clone github.com/Spotnick2/LibGlass there, or set `$env:LIBGLASS)."
}
. (Join-Path $PSScriptRoot "LibGlassPin.ps1")
Write-LibGlassPinStatus $RepoRoot $LibGlass "this deploy tests a library the release won't ship"
& pwsh -NoProfile -File (Join-Path $LibGlass "Tools\deploy.ps1") -Addon GlassGear -AddOnsPath $AddOnsPath
if ($LASTEXITCODE -ne 0) { throw "LibGlass deploy refused; Glass Gear was not touched." }

$dest = Join-Path $AddOnsPath "GlassGear"
Write-Host "Deploying Glass Gear (Forever) -> $dest" -ForegroundColor Cyan
foreach ($rel in @("GlassGear.toc", "LICENSE") + $files) {
    $src = Join-Path $RepoRoot $rel
    $target = Join-Path $dest $rel
    $targetDir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $target -Force
}
Write-Host "  copied $($files.Count + 2) files" -ForegroundColor DarkGray

$expected = @{}
foreach ($rel in @("GlassGear.toc", "LICENSE") + $files) { $expected[$rel.ToLowerInvariant()] = $true }
foreach ($item in Get-ChildItem -LiteralPath $dest -Recurse -File | Where-Object { $_.FullName -notlike (Join-Path $dest "Libs\*") }) {
    $rel = $item.FullName.Substring($dest.Length + 1)
    if (-not $expected.ContainsKey($rel.ToLowerInvariant())) {
        Write-Host "  note: $rel is in the deployed folder but not in the TOC" -ForegroundColor DarkYellow
    }
}

# Substitute @project-version@ in the DEPLOYED copy only.
$rev = $null
if (Get-Command git -ErrorAction SilentlyContinue) {
    try { $rev = (git -C $RepoRoot rev-parse --short HEAD 2>$null) } catch { $rev = $null }
}
$label = if ($rev) { "dev-$rev" } else { "dev" }
$deployedToc = Join-Path $dest "GlassGear.toc"
(Get-Content -LiteralPath $deployedToc -Raw).Replace('@project-version@', $label) |
    Set-Content -LiteralPath $deployedToc -NoNewline
Write-Host "  version -> $label (deployed copy only)" -ForegroundColor DarkGray

Write-Host "Done." -ForegroundColor Green
Write-Host ""
Write-Host "In-game:" -ForegroundColor Yellow
Write-Host "  /console scriptErrors 1   (errors are OFF by default on this client)"
Write-Host "  a brand-new addon folder needs a full client restart once; then /reload"
Write-Host "  /gg"
