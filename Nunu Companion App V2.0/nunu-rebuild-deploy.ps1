#requires -Version 7
param(
  # Your solution root (folder that contains the .csproj)
  [string]$ProjectRoot = "C:\NunuCompanionApp V2.0\Nunu Companion App V2.0",

  # The plugin project file name
  [string]$CsprojName  = "NunuCompanionAppV2.csproj",

  # Output "drop" folder you asked for
  [string]$DropDir     = "C:\NunuCompanionApp V2.0\Nunu Companion App V2.0\Dployed NunuCompanionAppV2.0",

  # DevPlugins deploy target (Dalamud scans here)
  [string]$DevPlugins  = (Join-Path $env:AppData "XIVLauncher\devPlugins"),

  # Identity / naming
  [string]$InternalName = "NunuCompanionAppV2",
  [string]$FriendlyName = "Nunu Companion App V2.0",
  [int]$DalamudApiLevel = 13
)

$ErrorActionPreference = 'Stop'
Write-Host "[Nunu] PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Cyan

# ---------------------------------------------------------
# 0) Paths & quick checks
# ---------------------------------------------------------
$csproj = Join-Path $ProjectRoot $CsprojName
if (-not (Test-Path -LiteralPath $csproj)) {
  throw "[Nunu] Can't find csproj: $csproj"
}

# Check Dalamud hooks path so you catch ImGui reference problems early
$HooksPath = Join-Path $env:AppData "XIVLauncher\addon\Hooks\dev"
Write-Host "[Nunu] Hooks path: $HooksPath"
$need = @(
  "Dalamud.dll",
  "Dalamud.Bindings.ImGui.dll"   # needed for ImGuiNET
)
$missing = @()
foreach($n in $need){
  if(-not (Test-Path -LiteralPath (Join-Path $HooksPath $n))){ $missing += $n }
}
if($missing.Count -gt 0){
  Write-Warning "[Nunu] Missing from Hooks path: $($missing -join ', ')"
  Write-Warning "       If build fails with ImGuiNET not found, update your references to point at: $HooksPath"
}

# ---------------------------------------------------------
# 1) Clean bin/obj (robust; avoids Filter array issues)
# ---------------------------------------------------------
Write-Host "[Nunu] Cleaning bin/obj…" -ForegroundColor Yellow
Get-ChildItem -LiteralPath $ProjectRoot -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -in @('bin','obj') } |
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------
# 2) Restore & Build (Release)
#     Targets .NET 9 Windows if your csproj is set to net9.0-windows10.0.22000.0
# ---------------------------------------------------------
Write-Host "[Nunu] dotnet restore…" -ForegroundColor Yellow
dotnet restore "$csproj"
if ($LASTEXITCODE -ne 0) { throw "[Nunu] Restore failed ($LASTEXITCODE)" }

Write-Host "[Nunu] dotnet build -c Release…" -ForegroundColor Yellow
dotnet build "$csproj" -c Release
if ($LASTEXITCODE -ne 0) { throw "[Nunu] Build failed ($LASTEXITCODE)" }

# ---------------------------------------------------------
# 3) Locate build output (pick latest net9*windows* or net8* if present)
# ---------------------------------------------------------
$release = Join-Path $ProjectRoot "bin\Release"
if (-not (Test-Path -LiteralPath $release)) {
  throw "[Nunu] No Release folder produced at $release"
}

$tfmDir = Get-ChildItem -LiteralPath $release -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like "net9*windows*" -or $_.Name -like "net8*windows*" -or $_.Name -like "net9*" -or $_.Name -like "net8*" } |
  Sort-Object LastWriteTime -Desc | Select-Object -First 1

if (-not $tfmDir) { throw "[Nunu] Could not locate TFM under $release (expected net9* or net8*). Build likely failed." }

# Find dll
$dll = Get-ChildItem -LiteralPath $tfmDir.FullName -Filter "$InternalName.dll" -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Desc | Select-Object -First 1
if (-not $dll) {
  $dll = Get-ChildItem -LiteralPath $tfmDir.FullName -Filter "$InternalName*.dll" -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Desc | Select-Object -First 1
}
if (-not $dll) {
  throw "[Nunu] Build succeeded but could not find $InternalName*.dll in $($tfmDir.FullName)"
}

Write-Host "[Nunu] Found build: $($dll.FullName)" -ForegroundColor Green

# ---------------------------------------------------------
# 4) Recreate Drop & copy payload
# ---------------------------------------------------------
Write-Host "[Nunu] Staging drop → $DropDir" -ForegroundColor Yellow
if (Test-Path -LiteralPath $DropDir) { Remove-Item -LiteralPath $DropDir -Recurse -Force }
New-Item -ItemType Directory -Path $DropDir | Out-Null

Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $DropDir "$InternalName.dll")

# Pick an icon if available
$iconCandidates = @(
  (Join-Path $ProjectRoot "icon.png"),
  (Join-Path $tfmDir.FullName "icon.png"),
  (Join-Path $env:AppData "XIVLauncher\devPlugins\$InternalName\icon.png")
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($iconCandidates) {
  Copy-Item -LiteralPath $iconCandidates -Destination (Join-Path $DropDir "icon.png") -Force
}

# Write manifest.json in the drop too (useful to inspect)
$ver = $dll.VersionInfo.FileVersion; if (-not $ver) { $ver = "1.0.0.0" }
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
$dropManifest = Join-Path $DropDir "manifest.json"
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $dropManifest -Encoding UTF8

Write-Host ""
Get-ChildItem -LiteralPath $DropDir | Select Name,Length,LastWriteTime | Format-Table

# ---------------------------------------------------------
# 5) Deploy to Dalamud devPlugins (so it appears in /xlplugins → Developer)
# ---------------------------------------------------------
$dest = Join-Path $DevPlugins $InternalName
if (Test-Path -LiteralPath $dest) {
  Remove-Item -LiteralPath $dest -Recurse -Force
}
New-Item -ItemType Directory -Path $dest | Out-Null

Copy-Item -LiteralPath (Join-Path $DropDir "$InternalName.dll") -Destination (Join-Path $dest "$InternalName.dll")
if (Test-Path -LiteralPath (Join-Path $DropDir "icon.png")) {
  Copy-Item -LiteralPath (Join-Path $DropDir "icon.png") -Destination (Join-Path $dest "icon.png") -Force
}
Copy-Item -LiteralPath $dropManifest -Destination (Join-Path $dest "manifest.json") -Force

# Ensure no YAML in dev folder (avoid loader confusion)
Get-ChildItem -LiteralPath $dest -Filter "*.yaml" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $dest -Filter "*.yml"  -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host "`n[Nunu] Deployed to devPlugins: $dest" -ForegroundColor Green
Get-ChildItem -LiteralPath $dest | Select Name,Length,LastWriteTime | Format-Table

Write-Host "`n[Nunu] Next:" -ForegroundColor Cyan
Write-Host "  • In-game: /xlplugins → Developer → Reload dev plugins (or restart Dalamud/XL)."
Write-Host "  • You should now see: $FriendlyName"
