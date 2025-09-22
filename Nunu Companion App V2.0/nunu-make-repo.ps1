#requires -Version 7
param(
  # Your project folder containing the .csproj, icon.png, etc.
  [string]$ProjectRoot = "C:\NunuCompanionApp V2.0\Nunu Companion App V2.0",
  # The base URL where the repo will be served. Script will try a local server on 8000.
  [string]$BaseUrl     = "http://127.0.0.1:8000/repo",
  # If you want to skip building and just package what's already in bin\Release
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

Write-Host "[Repo] PowerShell $($PSVersionTable.PSVersion) (x64: $([Environment]::Is64BitProcess))" -ForegroundColor Cyan

$csproj = Join-Path $ProjectRoot 'NunuCompanionAppV2.csproj'
if (!(Test-Path $csproj)) { throw "[Repo] Could not find .csproj at: $csproj" }

# --- 1) Build Release (unless skipped) ---
if (-not $SkipBuild) {
  Write-Host "[Repo] Building Release…" -ForegroundColor Cyan
  Push-Location $ProjectRoot
  dotnet build -c Release
  if ($LASTEXITCODE -ne 0) { throw "[Repo] dotnet build failed ($LASTEXITCODE)" }
  Pop-Location
} else {
  Write-Host "[Repo] Skipping build as requested." -ForegroundColor Yellow
}

# --- 2) Locate the build output (DLL) ---
$releaseDir = Join-Path $ProjectRoot 'bin\Release'
if (!(Test-Path $releaseDir)) { throw "[Repo] Release folder not found: $releaseDir" }

$dll = Get-ChildItem $releaseDir -Recurse -Filter 'NunuCompanionAppV2.dll' -File |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $dll) { throw "[Repo] Could not find NunuCompanionAppV2.dll under $releaseDir" }

# Try to discover version from file/product version, fallback to 1.0.0
$version = '1.0.0'
try {
  $vi = (Get-Item $dll.FullName).VersionInfo
  $cand = $vi.ProductVersion
  if ([string]::IsNullOrWhiteSpace($cand)) { $cand = $vi.FileVersion }
  if ($cand -match '^\d+(\.\d+){1,3}') { $version = $Matches[0] }
} catch {}

Write-Host "[Repo] Using DLL: $($dll.FullName)" -ForegroundColor Green
Write-Host "[Repo] Version:   $version" -ForegroundColor Green

# --- 3) Prepare repo folder structure ---
$repoDir   = Join-Path $ProjectRoot 'repo'
$plugDir   = Join-Path $repoDir 'NunuCompanionAppV2'
$stageDir  = Join-Path $plugDir 'stage'
$zipName   = "NunuCompanionAppV2_v$version.zip"
$zipPath   = Join-Path $plugDir $zipName
$zipLatest = Join-Path $plugDir 'latest.zip'

New-Item -ItemType Directory -Force -Path $repoDir  | Out-Null
New-Item -ItemType Directory -Force -Path $plugDir  | Out-Null
if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

# --- 4) Ensure manifest.json for inside the ZIP ---
$manifest = @{
  Author            = 'The Nunu'
  Name              = 'Nunu Companion App V2.0'
  InternalName      = 'NunuCompanionAppV2'
  Punchline         = 'Minimal chat + persona memory.'
  Description       = 'Nunu Companion App (V2) — chat capture, persona-based replies, and a small viewer (Dalamud v13).'
  ApplicableVersion = 'any'
  DalamudApiLevel   = 13
  LoadPriority      = 0
  Tags              = @('utility','chat','nunu')
}
$manifestPath = Join-Path $stageDir 'manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

# --- 5) Copy DLL and icon into stage / repo ---
Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $stageDir 'NunuCompanionAppV2.dll') -Force
$iconSrc = Join-Path $ProjectRoot 'icon.png'
if (Test-Path $iconSrc) {
  Copy-Item -LiteralPath $iconSrc -Destination (Join-Path $plugDir 'icon.png') -Force
}

# --- 6) Zip the staged payload ---
if (Test-Path $zipPath)   { Remove-Item $zipPath -Force }
if (Test-Path $zipLatest) { Remove-Item $zipLatest -Force }
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath
Copy-Item -LiteralPath $zipPath -Destination $zipLatest -Force

# --- 7) Create/Update pluginmaster.json ---
$pluginMaster = Join-Path $repoDir 'pluginmaster.json'
$epoch = [int][double]::Parse((Get-Date -Date (Get-Date).ToUniversalTime() -UFormat %s))

$dlUrl   = "$BaseUrl/NunuCompanionAppV2/latest.zip"
$iconUrl = "$BaseUrl/NunuCompanionAppV2/icon.png"

$entry = [ordered]@{
  Author              = $manifest.Author
  Name                = $manifest.Name
  InternalName        = $manifest.InternalName
  AssemblyVersion     = $version
  Description         = $manifest.Description
  ApplicableVersion   = $manifest.ApplicableVersion
  DalamudApiLevel     = $manifest.DalamudApiLevel
  Tags                = $manifest.Tags
  RepoUrl             = ""
  ImageUrls           = @()
  IconUrl             = (Test-Path (Join-Path $plugDir 'icon.png')) ? $iconUrl : $null
  Changelog           = "Local repository build $version"
  DownloadLinkInstall = $dlUrl
  DownloadLinkTesting = $dlUrl
  DownloadLinkUpdate  = $dlUrl
  LastUpdated         = $epoch
  LoadPriority        = 0
  IsHide              = $false
  IsTestingExclusive  = $false
}

if (Test-Path $pluginMaster) {
  try {
    $arr = Get-Content -LiteralPath $pluginMaster -Raw | ConvertFrom-Json
    if ($arr -isnot [System.Collections.IEnumerable]) { $arr = @() }
  } catch { $arr = @() }
} else {
  $arr = @()
}

$existing = $arr | Where-Object { $_.InternalName -eq $entry.InternalName }
if ($existing) {
  $new = @()
  foreach ($it in $arr) {
    if ($it.InternalName -eq $entry.InternalName) { $new += [pscustomobject]$entry }
    else { $new += $it }
  }
  $arr = $new
} else {
  $arr += [pscustomobject]$entry
}

$arr | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $pluginMaster -Encoding UTF8

# --- 8) Summary ---
Write-Host "`n[Repo] Created repo:" -ForegroundColor Cyan
Write-Host "       $repoDir"
Write-Host "       pluginmaster.json"
Write-Host "       NunuCompanionAppV2\latest.zip"
if (Test-Path (Join-Path $plugDir 'icon.png')) {
  Write-Host "       NunuCompanionAppV2\icon.png"
}
Write-Host "`n[Repo] Base URL: $BaseUrl" -ForegroundColor Cyan
Write-Host "Add to Dalamud → Plugin Installer → settings (gear) → Custom Repos:"
Write-Host "$BaseUrl/pluginmaster.json" -ForegroundColor Yellow

# --- 9) Offer to start a local web server (Python) ---
$repoParent = Split-Path $repoDir -Parent
Write-Host "`n[Repo] To serve locally now:" -ForegroundColor Cyan
Write-Host "cd `"$repoParent`"; python -m http.server 8000 --bind 127.0.0.1" -ForegroundColor Yellow

try {
  $py = Get-Command python -ErrorAction Stop
  Write-Host "[Repo] Detected Python at $($py.Source). Launching local server in a new window…" -ForegroundColor Green
  Start-Process -FilePath "python" -ArgumentList "-m","http.server","8000","--bind","127.0.0.1" -WorkingDirectory $repoParent
} catch {
  Write-Host "[Repo] Python not found on PATH. Start it manually with the command above." -ForegroundColor Yellow
}

Write-Host "`n[Repo] Done. Search 'Nunu Companion App V2.0' in the Plugin Installer." -ForegroundColor Cyan
