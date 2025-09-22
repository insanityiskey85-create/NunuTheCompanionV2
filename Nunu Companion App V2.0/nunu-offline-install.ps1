<# nunu-offline-install.ps1 — v1.1
   Offline installer for a Dalamud plugin from a local ZIP.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)]
  [string]$ZipPath,

  [Parameter(Mandatory=$false)]
  [string]$InternalName,

  [switch]$Dev,
  [switch]$Force,
  [string]$Sha256
)

$ErrorActionPreference = 'Stop'
function Write-Note($m){ Write-Host "[Nunu] $m" }

# --- helpers ---------------------------------------------------------------
function Remove-PathSafely([string]$p){
  try {
    if ($p -and (Test-Path -LiteralPath $p)) {
      Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
    }
  } catch { } # hush, little voidling
}

# --- main ------------------------------------------------------------------
$tmp = $null
try {
  # Resolve ZIP
  if (-not $ZipPath) {
    $candidates = Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.zip -File | Sort-Object LastWriteTime -Descending
    if ($candidates.Count -eq 0) { throw "No -ZipPath provided and no *.zip found beside the script." }
    if ($candidates.Count -gt 1) { Write-Note "Multiple ZIPs found; using newest: $($candidates[0].Name)" }
    $ZipPath = $candidates[0].FullName
  }
  $ZipPath = (Resolve-Path -LiteralPath $ZipPath).Path
  if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) { throw "ZIP not found: $ZipPath" }

  # Optional integrity
  if ($Sha256) {
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath).Hash.ToLower()
    if ($h -ne $Sha256.ToLower()) { throw "SHA256 mismatch. Expected $Sha256; got $h" }
    Write-Note "SHA256 verified."
  }

  # Temp extract
  $tmp = Join-Path $env:TEMP ("nunu_offline_" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $tmp -Force | Out-Null
  Write-Note "Extracting → $tmp"
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $tmp -Force

  # Find manifest & root
  $manifests = Get-ChildItem -Path $tmp -Filter manifest.json -Recurse -File
  if ($manifests.Count -eq 0) { throw "No manifest.json found in ZIP." }

  $pluginRoot = $manifests[0].Directory.FullName
  $manifest   = Get-Content -LiteralPath $manifests[0].FullName -Raw | ConvertFrom-Json
  $derivedInternal = $manifest.InternalName
  if ([string]::IsNullOrWhiteSpace($derivedInternal) -and [string]::IsNullOrWhiteSpace($InternalName)) {
    throw "InternalName missing in manifest and not provided via -InternalName."
  }
  if (-not $InternalName) { $InternalName = $derivedInternal }

  # Ensure folder name matches InternalName
  $currentFolderName = Split-Path -Leaf $pluginRoot
  if ($currentFolderName -ne $InternalName) {
    Write-Note "Adjusting folder: '$currentFolderName' → '$InternalName'"
    $adjusted = Join-Path (Split-Path -Parent $pluginRoot) $InternalName
    Remove-PathSafely $adjusted
    Rename-Item -LiteralPath $pluginRoot -NewName $InternalName
    $pluginRoot = $adjusted
  }

  # DLL sanity
  $dll = Get-ChildItem -LiteralPath $pluginRoot -Filter ($InternalName + ".dll") -File -ErrorAction SilentlyContinue
  if (-not $dll) { Write-Note "Warning: '$InternalName.dll' not found beside manifest. Dalamud may not load it." }

  # Target
  $base = if ($Dev) { Join-Path $env:AppData 'XIVLauncher\addons\Dalamud\DevPlugins' }
          else       { Join-Path $env:AppData 'XIVLauncher\addons\Dalamud\plugins' }
  if (-not (Test-Path -LiteralPath $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }

  $target = Join-Path $base $InternalName
  if (Test-Path -LiteralPath $target) {
    if ($Force) {
      Write-Note "Removing existing $target"
      Remove-PathSafely $target
    } else {
      $ans = Read-Host "Target exists: $target . Overwrite? (y/N)"
      if ($ans -notin @('y','Y','yes','YES')) { throw "Aborted by user." }
      Remove-PathSafely $target
    }
  }

  # Copy into place
  Write-Note "Installing → $target"
  Copy-Item -LiteralPath $pluginRoot -Destination $target -Recurse -Force

  # Cleanup temp (safe)
  Remove-PathSafely $tmp

  # Success
  if ($Dev) {
    Write-Host "`n[Nunu] Installed to DevPlugins."
    Write-Host "[Nunu] Dalamud → Settings → Experimental → enable “Load dev plugins”, then restart."
  } else {
    Write-Host "`n[Nunu] Installed to plugins folder. Restart the game or /xlplugins → reload."
  }
  Write-Host "[Nunu] InternalName: $InternalName | DalamudApiLevel: $($manifest.DalamudApiLevel)"
  Write-Host "[Nunu] The chorus is ready."
  exit 0
}
catch {
  # Try to clean temp, but never die on cleanup
  Remove-PathSafely $tmp
  Write-Error $_.Exception.Message
  exit 1
}
