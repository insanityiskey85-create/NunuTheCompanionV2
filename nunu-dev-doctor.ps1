# nunu-dev-doctor.ps1 — make Nunu appear under Dev Plugins (API 13 / .NET 8)
$ErrorActionPreference = 'Stop'

$DevDir = Join-Path $env:AppData 'XIVLauncher\devPlugins\NunuCompanionAppV2'
if (-not (Test-Path $DevDir)) { New-Item -ItemType Directory -Force -Path $DevDir | Out-Null }

# 1) Find the single plugin DLL in your dev folder
$dlls = Get-ChildItem $DevDir -Filter *.dll -File | Sort-Object LastWriteTime -Descending
if ($dlls.Count -eq 0) { throw "No DLLs found in $DevDir. Drop your build here first." }
if ($dlls.Count -gt 1) { Write-Warning "Multiple DLLs present — using newest: $($dlls[0].Name)"; }
$dll = $dlls[0]

# 2) Read the true InternalName from the assembly (this is what the manifest MUST be named)
$internal = [Reflection.AssemblyName]::GetAssemblyName($dll.FullName).Name
Write-Host "[Nunu] InternalName (from DLL): $internal"

# 3) Ensure the manifest filename matches EXACTLY: <InternalName>.yaml
$yml = Join-Path $DevDir ($internal + '.yaml')
if (-not (Test-Path $yml)) {
@"
name: Nunu Companion App V2.0
author: The Nunu
punchline: Minimal chat + memory.
description: |-
  Nunu Companion App (V2) — chat capture, simple memory, and a small viewer (Dalamud v13).
"@ | Set-Content -Encoding UTF8 -Path $yml
Write-Host "[Nunu] Wrote manifest: $(Split-Path $yml -Leaf)"
} else { Write-Host "[Nunu] Manifest already exists: $(Split-Path $yml -Leaf)" }

# 4) Unblock the DLL & manifest (Windows MOTW can hide plugins)
Get-Item $dll.FullName, $yml | Unblock-File -ErrorAction SilentlyContinue

# 5) Show current dev folder contents (sanity)
"[Nunu] Dev dir: $DevDir"
Get-ChildItem $DevDir | Select Name,Length,LastWriteTime | Format-Table

# 6) Remind you to point Dalamud at this exact folder (once)
Write-Host "`n[Nunu] In-game: /xlsettings → Experimental → Dev Plugin Locations → Add:"
Write-Host "$DevDir"
Write-Host "[Nunu] Then /xlplugins → Dev Tools → Installed Dev Plugins → enable it, or just Reload Plugins.`n"

# 7) Tail recent log lines mentioning the internal name so you see why it hid before
$log = Join-Path $env:AppData 'XIVLauncher\dalamud.log'
if (Test-Path $log) {
  Write-Host "[Nunu] Recent log lines for ${internal}:"
  Get-Content $log -Tail 400 | Select-String -SimpleMatch $internal
} else {
  Write-Warning "[Nunu] No dalamud.log yet — start the game once, then reload plugins."
}
