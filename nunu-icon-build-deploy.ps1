# nunu-icon-build-deploy.ps1
# One-shot: wire icon.png + manifest, build Release, deploy to DevPlugins.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Note([string]$m){ Write-Host "[Nunu] $m" }
function Die([string]$m){ Write-Error $m; exit 1 }

# ---- Paths (adjust if your layout changes) ----
$ProjDir   = 'C:\NunuCompanionApp V2.0\Nunu Companion App V2.0'
$Csproj    = Join-Path $ProjDir 'NunuCompanionAppV2.csproj'
$DevDir    = "$env:AppData\XIVLauncher\devPlugins\NunuCompanionAppV2"

# Icon comes from your working dev plugin folder (as provided)
$IconSrc   = 'C:\Users\insan\AppData\Roaming\XIVLauncher\devPlugins\NunuCompanionAppV2\icon.png'
$IconDest  = Join-Path $ProjDir 'icon.png'

# Manifest we’ll ship with the DLL
$ManifestPath = Join-Path $ProjDir 'Manifest.json'

# Basic metadata (kept in sync with your project)
$InternalName = 'NunuCompanionAppV2'
$DisplayName  = 'Nunu Companion App V2.0'
$Author       = 'The Nunu'
$Punchline    = 'Minimal chat + memory.'
$Description  = 'Nunu Companion App (V2) — chat capture, simple memory, persona-driven replies.'
$DalamudApi   = 13   # use 13; change if your environment needs another

# ---- Sanity checks ----
if(-not (Test-Path -LiteralPath $Csproj)){ Die "csproj not found: $Csproj" }
if(-not (Test-Path -LiteralPath $ProjDir)){ Die "Project directory missing: $ProjDir" }

# ---- Ensure icon.png in project ----
if(Test-Path -LiteralPath $IconSrc){
  Copy-Item -LiteralPath $IconSrc -Destination $IconDest -Force
  Note "Icon copied from dev to project."
} elseif(-not (Test-Path -LiteralPath $IconDest)){
  Die "Icon not found: $IconSrc (and no icon.png in project)."
} else {
  Note "Using existing project icon.png."
}

# ---- Ensure Manifest.json (points to icon.png) ----
$manifestJson = @"
{
  "Name": "$DisplayName",
  "InternalName": "$InternalName",
  "Author": "$Author",
  "Punchline": "$Punchline",
  "Description": "$Description",
  "DalamudApiLevel": $DalamudApi,
  "Tags": ["utility","chat","nunu"],
  "IconUrl": "icon.png",
  "Dll": "$InternalName.dll"
}
"@
Set-Content -LiteralPath $ManifestPath -Value $manifestJson -Encoding UTF8
Note "Manifest.json written."

# ---- Patch csproj so icon + manifest are copied to output ----
[xml]$xml = Get-Content -LiteralPath $Csproj
$projNode = $xml.SelectSingleNode('/Project')
if(-not $projNode){ Die "Malformed csproj: <Project> node not found." }

function Ensure-ItemCopy([System.Xml.XmlDocument]$doc, [System.Xml.XmlElement]$project, [string]$fileName){
  $ig = $project.SelectSingleNode("ItemGroup[None[@Include='$fileName']]")
  if(-not $ig){ $ig = $doc.CreateElement('ItemGroup'); [void]$project.AppendChild($ig) }
  $n = $ig.SelectSingleNode("None[@Include='$fileName']")
  if(-not $n){ $n = $doc.CreateElement('None'); $n.SetAttribute('Include', $fileName); [void]$ig.AppendChild($n) }
  $copy = $n.SelectSingleNode('CopyToOutputDirectory')
  if(-not $copy){ $copy = $doc.CreateElement('CopyToOutputDirectory'); [void]$n.AppendChild($copy) }
  $copy.InnerText = 'Always'
}

Ensure-ItemCopy $xml $projNode 'icon.png'
Ensure-ItemCopy $xml $projNode 'Manifest.json'

$xml.Save($Csproj)
Note "csproj patched to copy icon + manifest."

# ---- Build (Release / .NET 8) ----
Note "dotnet restore…"
dotnet restore "$Csproj" --nologo | Out-Host
if($LASTEXITCODE -ne 0){ Die "restore failed ($LASTEXITCODE)" }

Note "dotnet build Release…"
dotnet build "$Csproj" -c Release -v m --nologo | Out-Host
if($LASTEXITCODE -ne 0){ Die "build failed ($LASTEXITCODE)" }

# ---- Locate latest build output ----
$binRoot = Join-Path $ProjDir 'bin'
$outDll = Get-ChildItem -LiteralPath $binRoot -Recurse -File -Filter "$InternalName.dll" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
if(-not $outDll){ Die "Could not find build output $InternalName.dll under $binRoot" }
$outDir = $outDll.Directory.FullName
Note "Output: $outDir"

# ---- Deploy to DevPlugins ----
if(-not (Test-Path -LiteralPath $DevDir)){ New-Item -ItemType Directory -Path $DevDir | Out-Null }
Copy-Item -LiteralPath (Join-Path $outDir "$InternalName.dll") -Destination $DevDir -Force
Copy-Item -LiteralPath (Join-Path $outDir 'Manifest.json')      -Destination $DevDir -Force
Copy-Item -LiteralPath (Join-Path $outDir 'icon.png')           -Destination $DevDir -Force

# Fallback: if the build output didn't include icon/manifest for any reason, copy from project
if(-not (Test-Path -LiteralPath (Join-Path $DevDir 'icon.png'))){
  Copy-Item -LiteralPath $IconDest -Destination $DevDir -Force
}
if(-not (Test-Path -LiteralPath (Join-Path $DevDir 'Manifest.json'))){
  Copy-Item -LiteralPath $ManifestPath -Destination $DevDir -Force
}

# ---- Summary ----
Note "Deployed files:"
Get-ChildItem -LiteralPath $DevDir -File | Where-Object { $_.Name -in @("$InternalName.dll",'Manifest.json','icon.png') } |
  Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize

Write-Host "`n[Nunu] All done. /xlreload in-game to see the shiny icon. WAH!"
