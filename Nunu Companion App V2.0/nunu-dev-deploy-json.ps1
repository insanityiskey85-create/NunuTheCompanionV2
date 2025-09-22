#requires -Version 7
param(
  # Where your built plugin files live:
  [string]$SourceDir = "C:\NunuCompanionApp V2.0\Nunu Companion App V2.0\Dployed NunuCompanionAppV2.0",

  # Identity must match your DLL name (without .dll)
  [string]$InternalName = "NunuCompanionAppV2",

  # Display name + API level
  [string]$FriendlyName = "Nunu Companion App V2.0",
  [int]$DalamudApiLevel = 13
)

$ErrorActionPreference = 'Stop'
Write-Host "[Nunu] PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Cyan

# Resolve paths
$devRoot = Join-Path $env:AppData "XIVLauncher\devPlugins"
$dest    = Join-Path $devRoot $InternalName

# Ensure devPlugins folder exists
if (-not (Test-Path -LiteralPath $devRoot)) {
  New-Item -ItemType Directory -Path $devRoot | Out-Null
}

# Make/clean destination
if (-not (Test-Path -LiteralPath $dest)) {
  New-Item -ItemType Directory -Path $dest | Out-Null
}

# Find the DLL to deploy (prefer an exact name match, otherwise newest InternalName*.dll)
$dll = Get-ChildItem -LiteralPath $SourceDir -Filter "$InternalName.dll" -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Desc | Select-Object -First 1
if (-not $dll) {
  $dll = Get-ChildItem -LiteralPath $SourceDir -Filter "$InternalName*.dll" -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Desc | Select-Object -First 1
}
if (-not $dll) { throw "[Nunu] No DLL named $InternalName*.dll in $SourceDir" }

# Copy DLL (rename to exact InternalName.dll for safety)
Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $dest "$InternalName.dll") -Force

# Copy icon if we can find one
$iconDest = Join-Path $dest "icon.png"
$iconCandidates = @(
  (Join-Path $SourceDir "icon.png"),
  "C:\Users\insan\AppData\Roaming\XIVLauncher\devPlugins\NunuCompanionAppV2\icon.png"
)
foreach ($ic in $iconCandidates) {
  if (Test-Path -LiteralPath $ic) {
    Copy-Item -LiteralPath $ic -Destination $iconDest -Force
    break
  }
}

# Remove any YAML/YML to avoid manifest confusion
Get-ChildItem -LiteralPath $dest -Filter "*.yaml" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $dest -Filter "*.yml"  -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# Build a JSON manifest (PascalCase keys, the schema Dalamud expects)
$ver = $dll.VersionInfo.FileVersion
if (-not $ver) { $ver = "1.0.0.0" }

$manifest = [ordered]@{
  Author            = "The Nunu"
  Name              = $FriendlyName
  Punchline         = "Minimal chat + memory."
  Description       = "Nunu Companion App (V2) — chat capture, simple memory, and a small viewer."
  InternalName      = $InternalName
  AssemblyVersion   = $ver
  DalamudApiLevel   = $DalamudApiLevel
  ApplicableVersion = "any"
  Tags              = @("utility","chat","nunu")
}

$manifestPath = Join-Path $dest "manifest.json"
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

# Show what we deployed
Write-Host "`n[Nunu] Deployed to: $dest" -ForegroundColor Green
Get-ChildItem -LiteralPath $dest | Select Name,Length,LastWriteTime | Format-Table

Write-Host "`n[Nunu] Next steps:" -ForegroundColor Cyan
Write-Host "  • In-game: /xlplugins → Developer → Reload dev plugins (or restart Dalamud/XL)."
Write-Host "  • You should now see: $FriendlyName"
