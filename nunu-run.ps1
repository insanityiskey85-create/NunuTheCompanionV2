# nunu-run.ps1 — run the helper PS1s in order and build
# Usage:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\NunuCompanionApp V2.0\nunu-run.ps1"
#   pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\NunuCompanionApp V2.0\nunu-run.ps1" -Mode net8
#   pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\NunuCompanionApp V2.0\nunu-run.ps1" -Mode net9

param(
  [ValidateSet('auto','net8','net9')]
  [string]$Mode = 'auto'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# === Paths ===
$Root    = 'C:\NunuCompanionApp V2.0'
$Scripts = Join-Path $Root 'scripts'
$Build8  = Join-Path $Scripts 'nunu-build-net8.ps1'
$Build9  = Join-Path $Scripts 'nunu-build-modern.ps1'
$San     = Join-Path $Scripts 'nunu-sanitize-cs.ps1'
$Fix12   = Join-Path $Scripts 'nunu-fix-imgui-v12.ps1'
$Fix13   = Join-Path $Scripts 'nunu-fix-imgui-v13.ps1'

function Note([string]$m){ Write-Host "[Nunu] $m" }
function Run([string]$path, [string[]]$args=@()){
  if(-not (Test-Path -LiteralPath $path)){ Note "Skip (not found): $path"; return }
  Note "Running: $(Split-Path $path -Leaf)"
  & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $path @args
  if($LASTEXITCODE -ne 0){ throw "Script failed: $path (exit $LASTEXITCODE)" }
}

# === Detect installed SDKs ===
$sdks = & dotnet --list-sdks 2>$null
$has8 = $false; $has9 = $false
foreach($s in ($sdks | ForEach-Object { ($_ -split '\s+')[0] })){
  if($s -match '^8\.'){$has8=$true}
  if($s -match '^9\.'){$has9=$true}
}

# === Decide target ===
$target = $Mode
if($target -eq 'auto'){
  $have8script = Test-Path -LiteralPath $Build8
  $have9script = Test-Path -LiteralPath $Build9

  if($have8script -and $has8){ $target = 'net8' }
  elseif($have9script -and $has9){ $target = 'net9' }
  elseif($have8script){ $target = 'net8' }   # fall back to script presence
  elseif($have9script){ $target = 'net9' }
  else { throw "No build scripts found in $Scripts" }
}
Note "Target selected: $target"

# === Run in order ===
# 1) Sanitize sources (safe to run always)
Run $San

# 2) Adjust ImGui usings for the chosen API
switch($target){
  'net8' { Run $Fix12 }   # move to ImGuiNET (API 12)
  'net9' { Run $Fix13 }   # move to Dalamud.Bindings.ImGui (API 13)
}

# 3) Build for the target
switch($target){
  'net8' { Run $Build8 }
  'net9' { Run $Build9 }
}

Note "All steps complete. Drop folder is printed by the build script."
