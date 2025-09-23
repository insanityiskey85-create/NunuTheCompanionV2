#requires -Version 7
param(
  # --- Project info ---
  [string]$ProjectRoot = "C:\NunuCompanionApp V2.0\Nunu Companion App V2.0",
  [string]$CsprojName  = "NunuCompanionAppV2.csproj",
  [string]$InternalName = "NunuCompanionAppV2",
  [string]$FriendlyName = "Nunu Companion App V2.0",
  [string]$Author = "The Nunu",
  [string]$Punchline = "Minimal chat + memory.",
  [string]$Description = "Nunu Companion App (V2) — chat capture, simple memory, and a small viewer (Dalamud v13).",
  [int]$DalamudApiLevel = 13,
  [string[]]$Tags = @("utility","chat","nunu"),

  # --- GitHub repo info (used to author repo.json links) ---
  [string]$GitOwner = "insanityiskey85-create",
  [string]$GitRepo  = "NunuTheCompanionV2",
  [string]$Tag      = "v0.1.0",

  # --- Paths ---
  [string]$OutDir   = "C:\NunuCompanionApp V2.0\ReleaseArtifacts"
)

$ErrorActionPreference = 'Stop'
Write-Host "[Nunu] PS $($PSVersionTable.PSVersion)"

# Resolve csproj
$csproj = Join-Path $ProjectRoot $CsprojName
if (-not (Test-Path -LiteralPath $csproj)) { throw "[Nunu] csproj not found: $csproj" }

# Clean bin/obj
Write-Host "[Nunu] Cleaning bin/obj…" -ForegroundColor Yellow
Get-ChildItem -LiteralPath $ProjectRoot -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -in @('bin','obj') } |
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Restore + Build
Write-Host "[Nunu] dotnet restore…" -ForegroundColor Yellow
dotnet restore --nologo "$csproj"
if ($LASTEXITCODE -ne 0) { throw "[Nunu] Restore failed ($LASTEXITCODE)" }

Write-Host "[Nunu] dotnet build -c Release…" -ForegroundColor Yellow
dotnet build --nologo "$csproj" -c Release
if ($LASTEXITCODE -ne 0) { throw "[Nunu] Build failed ($LASTEXITCODE)" }

# Find latest TFM folder (net9*/net8*)
$release = Join-Path $ProjectRoot "bin\Release"
$tfmDir = Get-ChildItem -LiteralPath $release -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like "net9*windows*" -or $_.Name -like "net8*windows*" -or $_.Name -like "net9*" -or $_.Name -like "net8*" } |
  Sort-Object LastWriteTime -Desc | Select-Object -First 1
if (-not $tfmDir) { throw "[Nunu] No TFM under $release (expected net8*/net9*)" }

# Locate DLL
$dll = Get-ChildItem -LiteralPath $tfmDir.FullName -Filter "$InternalName.dll" -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Desc | Select-Object -First 1
if (-not $dll) {
  $dll = Get-ChildItem -LiteralPath $tfmDir.FullName -Filter "$InternalName*.dll" -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Desc | Select-Object -First 1
}
if (-not $dll) { throw "[Nunu] Built but no $InternalName*.dll in $($tfmDir.FullName)" }

# Read assembly version
try {
  $asmName = [System.Reflection.AssemblyName]::GetAssemblyName($dll.FullName)
  $assemblyVersion = $asmName.Version.ToString()
} catch {
  $assemblyVersion = "1.0.0.0"
}
Write-Host "[Nunu] AssemblyVersion: $assemblyVersion" -ForegroundColor Cyan

# Prepare output staging dir
if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
New-Item -ItemType Directory -Path $OutDir | Out-Null

$stage = Join-Path $OutDir $InternalName
New-Item -ItemType Directory -Path $stage | Out-Null

# Write manifest.json
$manifestPath = Join-Path $stage "manifest.json"
$tagsJson = ($Tags | ForEach-Object { '"' + $_ + '"' }) -join ', '
$manifestJson = @"
{
  "Author": "$Author",
  "Name": "$FriendlyName",
  "Punchline": "$Punchline",
  "Description": "$Description",
  "InternalName": "$InternalName",
  "AssemblyVersion": "$assemblyVersion",
  "ApplicableVersion": "any",
  "DalamudApiLevel": $DalamudApiLevel,
  "Tags": [ $tagsJson ],
  "RepoUrl": "https://github.com/$GitOwner/$GitRepo"
}
"@
$manifestJson | Set-Content -LiteralPath $manifestPath -Encoding UTF8

# Include DLL + icon.png
Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $stage "$InternalName.dll")

$iconCandidates = @(
  (Join-Path $ProjectRoot "icon.png"),
  (Join-Path $tfmDir.FullName "icon.png")
) | Where-Object { Test-Path -LiteralPath $_ }
if ($iconCandidates.Count -gt 0) {
  Copy-Item -LiteralPath $iconCandidates[0] -Destination (Join-Path $stage "icon.png") -Force
}

# Sanity check stage content
if ((Get-ChildItem -LiteralPath $stage -Force | Measure-Object).Count -lt 2) {
  throw "[Nunu] Staging folder seems incomplete: $stage"
}

# Make ZIP  (FIX: use -Path with wildcard, not -LiteralPath)
$zipPath = Join-Path $OutDir "$InternalName.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host "[Nunu] Built package: $zipPath" -ForegroundColor Green

# Generate repo.json
$download = "https://github.com/$GitOwner/$GitRepo/releases/download/$Tag/$InternalName.zip"
$iconUrl  = "https://raw.githubusercontent.com/$GitOwner/$GitRepo/main/icon.png"

$repoJson = @"
[
  {
    "Author": "$Author",
    "Name": "$FriendlyName",
    "Punchline": "$Punchline",
    "Description": "$Description",
    "InternalName": "$InternalName",
    "AssemblyVersion": "$assemblyVersion",
    "ApplicableVersion": "any",
    "DalamudApiLevel": $DalamudApiLevel,
    "Tags": [ $tagsJson ],
    "RepoUrl": "https://github.com/$GitOwner/$GitRepo",
    "IconUrl": "$iconUrl",
    "Changelog": "Initial release.",
    "DownloadLinkInstall": "$download",
    "DownloadLinkUpdate": "$download"
  }
]
"@
$repoPath = Join-Path $OutDir "repo.json"
$repoJson | Set-Content -LiteralPath $repoPath -Encoding UTF8

Write-Host "`n[Nunu] Artifacts ready in: $OutDir" -ForegroundColor Cyan
Get-ChildItem -LiteralPath $OutDir | Select Name,Length,LastWriteTime | Format-Table

Write-Host "`n[Nunu] Next steps:" -ForegroundColor Yellow
Write-Host "  1) Create GitHub Release $Tag in $GitOwner/$GitRepo and upload: $zipPath"
Write-Host "  2) Commit icon.png at repo root so IconUrl works."
Write-Host "  3) Host $repoPath (commit to main) and add its raw URL to Dalamud Custom Repos."
