param(
  [string]$ProjectRoot = "C:\NunuCompanionApp V2.0\Nunu Companion App V2.0",
  [string]$InternalName = "NunuCompanionAppV2",
  [string]$Author = "The Nunu",
  [string]$Name = "Nunu Companion App V2.0",
  [string]$Punchline = "Minimal chat + memory.",
  [string]$Description = "Nunu Companion App (V2) — chat capture, simple memory, and a small viewer (Dalamud v13).",
  [string]$AssemblyVersion = "1.0.0.0",
  [int]$DalamudApiLevel = 13,
  [string]$RepoUrl = "https://github.com/insanityiskey85-create/NunuTheCompanionV2",
  [string]$IconPath = "C:\Users\insan\AppData\Roaming\XIVLauncher\devPlugins\NunuCompanionAppV2\icon.png",
  [string]$ReleaseOut = "C:\NunuCompanionApp V2.0\ReleaseArtifacts"
)

$ErrorActionPreference = "Stop"

# Locate a Release/net9* output containing the plugin DLL
$bin = Join-Path $ProjectRoot "bin\Release"
Write-Host "[Nunu] Searching for $InternalName*.dll under: $bin"
$dll = Get-ChildItem -LiteralPath $bin -Recurse -Filter "$InternalName*.dll" |
  Where-Object { $_.DirectoryName -match "net9" } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $dll) { throw "[Nunu] Could not find $InternalName*.dll under $bin (net9). Build first." }

# Stage folder
$stage = Join-Path $ReleaseOut $InternalName
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

# Copy DLL
Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $stage $dll.Name)

# Optional icon
if (Test-Path -LiteralPath $IconPath) {
  Copy-Item -LiteralPath $IconPath -Destination (Join-Path $stage "icon.png")
  Write-Host "[Nunu] Included icon.png"
} else {
  Write-Warning "[Nunu] Icon file not found at: $IconPath (continuing without icon)"
}

# Write manifest.json (MANDATORY for release zips)
$manifest = [ordered]@{
  Author           = $Author
  Name             = $Name
  Punchline        = $Punchline
  Description      = $Description
  InternalName     = $InternalName
  AssemblyVersion  = $AssemblyVersion
  ApplicableVersion= "any"
  DalamudApiLevel  = $DalamudApiLevel
  RepoUrl          = $RepoUrl
  IconUrl          = "https://raw.githubusercontent.com/insanityiskey85-create/NunuTheCompanionV2/main/icon.png"
  Tags             = @("utility","chat","nunu")
}
$manifestPath = Join-Path $stage "manifest.json"
$manifest | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $manifestPath -Encoding utf8
Write-Host "[Nunu] Wrote manifest.json"

# Create ZIP at ReleaseArtifacts\NunuCompanionAppV2.zip
New-Item -ItemType Directory -Path $ReleaseOut -ErrorAction SilentlyContinue | Out-Null
$zipPath = Join-Path $ReleaseOut "$InternalName.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath
Write-Host "[Nunu] Packed: $zipPath"

# Quick sanity check: ensure required files are present in the zip
$tmp = Join-Path $ReleaseOut "tmp_extract_$InternalName"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null
Expand-Archive -LiteralPath $zipPath -DestinationPath $tmp
$hasDll = Test-Path (Join-Path $tmp "$InternalName*.dll")
$hasManifest = Test-Path (Join-Path $tmp "manifest.json")
if (-not ($hasDll -and $hasManifest)) {
  throw "[Nunu] Zip sanity check failed. DLL or manifest.json missing."
}
Remove-Item $tmp -Recurse -Force

Write-Host "`n[Nunu] ✅ Release zip ready:"
Write-Host "  $zipPath"
Write-Host "Upload this file as a release asset and point repo.json DownloadLinkInstall/Update at it."
