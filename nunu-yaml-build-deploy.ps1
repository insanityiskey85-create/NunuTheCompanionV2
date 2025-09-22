# nunu-yaml-build-deploy.ps1
# Build + deploy using YAML manifest only (no Manifest.json).

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Note([string]$m){ Write-Host "[Nunu] $m" }
function Die ([string]$m){ Write-Error $m; exit 1 }

# --- paths & metadata ---
$ProjDir   = 'C:\NunuCompanionApp V2.0\Nunu Companion App V2.0'
$Csproj    = Join-Path $ProjDir 'NunuCompanionAppV2.csproj'
$DevDir    = Join-Path $env:AppData 'XIVLauncher\devPlugins\NunuCompanionAppV2'
$IconSrc   = Join-Path $ProjDir 'icon.png'   # keep a copy in project root
$YamlPath  = Join-Path $ProjDir 'NunuCompanionAppV2.yaml'

$Internal  = 'NunuCompanionAppV2'
$Display   = 'Nunu Companion App V2.0'
$Author    = 'The Nunu'
$Punchline = 'Minimal chat + memory.'
$Desc      = 'Nunu Companion App (V2) — chat capture, simple memory, persona-driven replies.'
$ApiLevel  = 13  # your current Dalamud (13.x)

# --- sanity ---
if(!(Test-Path -LiteralPath $Csproj)){ Die "csproj not found: $Csproj" }
if(!(Test-Path -LiteralPath $ProjDir)){ Die "Project dir missing: $ProjDir" }

# --- write YAML manifest (only) ---
$yaml = @"
name: $Display
author: $Author
punchline: $Punchline
description: |-
  $Desc
internal_name: $Internal
dalamud_api_level: $ApiLevel
dll:
  - "$Internal.dll"
tags: [utility, chat, nunu]
"@
Set-Content -LiteralPath $YamlPath -Value $yaml -Encoding UTF8
Note "Wrote YAML: $YamlPath"

# --- ensure icon present (optional but nice) ---
if(!(Test-Path -LiteralPath $IconSrc)){
  Note "icon.png not found in project (optional). Place one at: $IconSrc"
}

# --- patch csproj: copy YAML + icon, remove Manifest.json copy ---
[xml]$xml = Get-Content -LiteralPath $Csproj
$proj = $xml.SelectSingleNode('/Project'); if(-not $proj){ Die "Malformed csproj: <Project> missing" }

function Ensure-NoneCopy([xml]$doc, [System.Xml.XmlElement]$projNode, [string]$file){
  $ig = $projNode.SelectSingleNode("ItemGroup[None[@Include='$file']]")
  if(-not $ig){ $ig = $doc.CreateElement('ItemGroup'); [void]$projNode.AppendChild($ig) }
  $n = $ig.SelectSingleNode("None[@Include='$file']")
  if(-not $n){ $n = $doc.CreateElement('None'); $n.SetAttribute('Include', $file); [void]$ig.AppendChild($n) }
  $copy = $n.SelectSingleNode('CopyToOutputDirectory')
  if(-not $copy){ $copy = $doc.CreateElement('CopyToOutputDirectory'); [void]$n.AppendChild($copy) }
  $copy.InnerText = 'Always'
}

# copy YAML + icon to output
Ensure-NoneCopy $xml $proj 'NunuCompanionAppV2.yaml'
if(Test-Path -LiteralPath $IconSrc){ Ensure-NoneCopy $xml $proj 'icon.png' }

# remove Manifest.json copy items if present
$nodes = $proj.SelectNodes("ItemGroup/None[@Include='Manifest.json']")
if($nodes){
  foreach($n in $nodes){
    $parent = $n.ParentNode
    [void]$parent.RemoveChild($n)
    if($parent.ChildNodes.Count -eq 0){ [void]$proj.RemoveChild($parent) }
  }
  Note "Removed Manifest.json copy entries from csproj."
}

$xml.Save($Csproj)
Note "csproj patched."

# --- build (Release/.NET 8) ---
Note "dotnet restore…"
dotnet restore "$Csproj" --nologo | Out-Host
if($LASTEXITCODE -ne 0){ Die "restore failed ($LASTEXITCODE)" }

Note "dotnet build Release…"
dotnet build "$Csproj" -c Release -v m --nologo | Out-Host
if($LASTEXITCODE -ne 0){ Die "build failed ($LASTEXITCODE)" }

# --- find latest output folder ---
$binRoot = Join-Path $ProjDir 'bin'
$outDll = Get-ChildItem -LiteralPath $binRoot -Recurse -File -Filter "$Internal.dll" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
if(-not $outDll){ Die "Build output not found for $Internal.dll" }
$outDir = $outDll.Directory.FullName
Note "Output: $outDir"

# --- deploy to DevPlugins (YAML-only) ---
if(!(Test-Path -LiteralPath $DevDir)){ New-Item -ItemType Directory -Path $DevDir | Out-Null }
Copy-Item -LiteralPath (Join-Path $outDir "$Internal.dll") -Destination $DevDir -Force
Copy-Item -LiteralPath (Join-Path $outDir 'NunuCompanionAppV2.yaml') -Destination $DevDir -Force
if(Test-Path -LiteralPath (Join-Path $outDir 'icon.png')){
  Copy-Item -LiteralPath (Join-Path $outDir 'icon.png') -Destination $DevDir -Force
} elseif(Test-Path -LiteralPath $IconSrc){
  Copy-Item -LiteralPath $IconSrc -Destination $DevDir -Force
}

# nuke any JSON manifest in dev dir to avoid conflicts
$json = Join-Path $DevDir 'Manifest.json'
if(Test-Path -LiteralPath $json){
  Remove-Item -LiteralPath $json -Force
  Note "Removed stray Manifest.json in DevPlugins."
}

# --- summary ---
Note "Deployed files:"
Get-ChildItem -LiteralPath $DevDir -File | Where-Object {
  $_.Name -in @("$Internal.dll",'NunuCompanionAppV2.yaml','icon.png')
} | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize

Write-Host "`n[Nunu] YAML path sung. /xlreload in-game to refresh the list. WAH!"
