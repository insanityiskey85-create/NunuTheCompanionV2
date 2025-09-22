# nunu-diagnose-load.ps1 — safe diagnosis for Nunu load issues
# - Auto-finds the newest Dalamud.log (dev/testing/stable)
# - Validates DevPlugins folder, manifest, dll
# - (Optional) quarantines noisy plugins if -Quarantine is passed

param([switch]$Quarantine)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Note([string]$m){ Write-Host "[Nunu] $m" }

# --- Paths ---
$devRoot = Join-Path $env:AppData 'XIVLauncher\devPlugins'
$nunuDir = Join-Path $devRoot 'NunuCompanionAppV2'

function Get-LatestDalamudLog {
  $roots = @(
    (Join-Path $env:AppData 'XIVLauncher\addon\Hooks\dev'),
    (Join-Path $env:AppData 'XIVLauncher\addon\Hooks\testing'),
    (Join-Path $env:AppData 'XIVLauncher\addon\Hooks\stable'),
    (Join-Path $env:AppData 'XIVLauncher\addon\Hooks')
  )

  $cands = @()
  foreach($r in $roots){
    try {
      $p = Join-Path $r 'Dalamud.log'
      if(Test-Path -LiteralPath $p){ $cands += Get-Item -LiteralPath $p }
    } catch {}
  }

  if($cands.Count -gt 0){
    return ($cands | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
  }

  # Deep search fallback
  $hooks = Join-Path $env:AppData 'XIVLauncher\addon\Hooks'
  if(Test-Path -LiteralPath $hooks){
    $hit = Get-ChildItem -LiteralPath $hooks -Recurse -File -Filter 'Dalamud.log' -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if($hit){ return $hit.FullName }
  }
  return $null
}

# --- 0) Sanity: dev folder + files ---
if(!(Test-Path -LiteralPath $nunuDir)){ throw "Dev folder missing: $nunuDir" }
Note "Dev dir: $nunuDir"
Get-ChildItem -LiteralPath $nunuDir -File | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize

# --- 1) Kill stray YAML (forces Manifest.json) ---
$yaml = Join-Path $nunuDir 'NunuCompanionAppV2.yaml'
if(Test-Path -LiteralPath $yaml){
  Rename-Item -LiteralPath $yaml -NewName 'NunuCompanionAppV2.yaml.bak' -Force
  Note "Renamed stray YAML → NunuCompanionAppV2.yaml.bak"
}

# --- 2) Validate Manifest.json + dll + icon ---
$manifest = Join-Path $nunuDir 'Manifest.json'
if(!(Test-Path -LiteralPath $manifest)){ throw "Missing Manifest.json in $nunuDir" }
try{
  $m = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
}catch{
  throw "Manifest.json is invalid JSON: $($_.Exception.Message)"
}
if($m.InternalName -ne 'NunuCompanionAppV2'){ throw "InternalName must be 'NunuCompanionAppV2' (is '$($m.InternalName)')" }
if($m.Dll -ne 'NunuCompanionAppV2.dll'){ throw "Dll must be 'NunuCompanionAppV2.dll' (is '$($m.Dll)')" }
if(-not (Test-Path -LiteralPath (Join-Path $nunuDir $m.Dll))){ throw "DLL missing: $($m.Dll)" }
if(-not (Test-Path -LiteralPath (Join-Path $nunuDir 'icon.png'))){ Note "icon.png missing — not fatal, just not pretty." }
Note "Manifest OK. ApiLevel=$($m.DalamudApiLevel)"

# --- 3) Find newest Dalamud.log (safe) ---
$log = Get-LatestDalamudLog
if([string]::IsNullOrWhiteSpace($log)){
  Note "Dalamud log not found; skipping log-based checks."
}else{
  Note "Using log: $log"
  # Show last few lines mentioning Nunu
  Get-Content -LiteralPath $log -Tail 200 -ErrorAction SilentlyContinue |
    Select-String -SimpleMatch 'NunuCompanionAppV2','Nunu Companion App V2.0','[Nunu]' |
    ForEach-Object { "[log] " + $_.Line }
}

# --- 4) Detect IPC timeout offenders (optional quarantine) ---
if(-not [string]::IsNullOrWhiteSpace($log)){
  $suspects = @()
  Get-Content -LiteralPath $log -Tail 500 -ErrorAction SilentlyContinue |
    Select-String -Pattern 'IPC didn''t published|LASTEXCEPTION' |
    ForEach-Object {
      # Try to extract a plugin-ish token from the line (best-effort)
      if($_.Line -match '([A-Za-z0-9][A-Za-z0-9\._-]{2,})Namespace\.IPC'){
        $suspects += $Matches[1]
      }
    }
  $suspects = $suspects | Sort-Object -Unique
  if($suspects.Count -gt 0){
    Note "IPC suspects: $($suspects -join ', ')"
    if($Quarantine){
      $quar = Join-Path $devRoot '_disabled_by_nunu'
      if(!(Test-Path -LiteralPath $quar)){ New-Item -ItemType Directory -Path $quar | Out-Null }
      Get-ChildItem -LiteralPath $devRoot -Directory | Where-Object {
        $_.Name -ne 'NunuCompanionAppV2' -and ($suspects | Where-Object { $_ -and ($_.ToLower()) -like ("*" + $_.Name.ToLower() + "*") })
      } | ForEach-Object {
        Note "Quarantine → $($_.FullName)"
        Move-Item -LiteralPath $_.FullName -Destination $quar -Force
      }
    } else {
      Note "Run again with -Quarantine to move suspect plugins aside."
    }
  } else {
    Note "No IPC offenders detected in latest log tail."
  }
} else {
  Note "Skipping IPC checks (no log)."
}

Note "If game is running, use /xlreload. Otherwise start XIVLauncher and open DevPlugins."
