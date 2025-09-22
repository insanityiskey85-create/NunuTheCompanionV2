#requires -Version 7
param(
  # Where your built DLL + manifest live:
  [string]$CustomDir = "C:\NunuCompanionApp V2.0\Nunu Companion App V2.0\Dployed NunuCompanionAppV2.0",

  # Plugin identity
  [string]$InternalName   = "NunuCompanionAppV2",
  [string]$FriendlyName   = "Nunu Companion App V2.0",
  [int]   $DalamudApiLevel = 13,

  # Optional icon (copied only if present)
  [string]$IconPath = "C:\Users\insan\AppData\Roaming\XIVLauncher\devPlugins\NunuCompanionAppV2\icon.png"
)

$ErrorActionPreference = 'Stop'
Write-Host "[Nunu] PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Cyan

# 1) Ensure custom folder exists
if (-not (Test-Path -LiteralPath $CustomDir)) {
  New-Item -ItemType Directory -Path $CustomDir | Out-Null
  Write-Host "[Nunu] Created custom dir: $CustomDir" -ForegroundColor Yellow
}

# 2) Ensure DLL + manifest; write minimal YAML if none exists
$dll  = Join-Path $CustomDir "$InternalName.dll"
$yaml = Join-Path $CustomDir "$InternalName.yaml"

if (-not (Test-Path -LiteralPath $yaml)) {
  # Infer version from DLL if present
  $ver = "1.0.0.0"
  if (Test-Path -LiteralPath $dll) {
    $fv = (Get-Item $dll).VersionInfo.FileVersion
    if ($fv) { $ver = $fv }
  }

  $yamlContent = @"
name: $FriendlyName
author: The Nunu
punchline: Minimal chat + memory (dev).
description: |
  Nunu Companion App (V2) — chat capture, simple memory, and a small viewer.
internal_name: $InternalName
assembly_version: "$ver"
dalamud_api_level: $DalamudApiLevel
dll:
  - "$InternalName.dll"
tags: [utility, chat, nunu]
"@
  Set-Content -LiteralPath $yaml -Value $yamlContent -Encoding utf8
  Write-Host "[Nunu] Wrote manifest: $yaml" -ForegroundColor Yellow
}

# 3) Optional icon copy (FIXED: wrap Test-Path calls so -and is an operator, not a parameter)
$destIcon = Join-Path $CustomDir "icon.png"
if ((Test-Path -LiteralPath $IconPath) -and -not (Test-Path -LiteralPath $destIcon)) {
  Copy-Item -LiteralPath $IconPath -Destination $destIcon -Force
  Write-Host "[Nunu] Copied icon.png" -ForegroundColor Yellow
}

# 4) Create a junction in devPlugins that points to $CustomDir
$devPlugins = Join-Path $env:AppData "XIVLauncher\devPlugins"
if (-not (Test-Path -LiteralPath $devPlugins)) {
  New-Item -ItemType Directory -Path $devPlugins | Out-Null
}

$linkPath = Join-Path $devPlugins $InternalName

# If something already exists at linkPath, safely clear it
if (Test-Path -LiteralPath $linkPath) {
  try {
    $attr = (Get-Item -LiteralPath $linkPath).Attributes
    if ($attr -band [IO.FileAttributes]::ReparsePoint) {
      Remove-Item -LiteralPath $linkPath -Force
    } else {
      $backup = "$linkPath.backup.$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
      Rename-Item -LiteralPath $linkPath -NewName (Split-Path -Leaf $backup)
      Write-Host "[Nunu] Backed up existing dev folder to: $backup" -ForegroundColor Yellow
    }
  } catch {
    throw "[Nunu] Could not prepare devPlugins link location: $($_.Exception.Message)"
  }
}

New-Item -ItemType Junction -Path $linkPath -Target $CustomDir | Out-Null

# 5) Print summary
Write-Host "`n[Nunu] Custom dev plugin directory:" -ForegroundColor Green
Write-Host "  $CustomDir"
Get-ChildItem -LiteralPath $CustomDir | Select Name,Length,LastWriteTime | Format-Table

Write-Host "`n[Nunu] Junction created:" -ForegroundColor Green
Write-Host "  $linkPath  ->  $CustomDir"

Write-Host "`n[Nunu] Next steps:" -ForegroundColor Cyan
Write-Host "  • In-game: /xlplugins → Developer → Reload dev plugins (or restart Dalamud/XL)"
Write-Host "  • You should now see: $FriendlyName"
