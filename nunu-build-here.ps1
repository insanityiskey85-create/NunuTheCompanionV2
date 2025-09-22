# nunu-deploy-here.ps1 — build and deploy straight to your folder

# === HARD PATHS ===
$RepoRoot      = 'C:\NunuCompanionApp V2.0'
$DeployDir     = 'C:\NunuCompanionApp V2.0\Nunu Companion App V2.0\Dployed NunuCompanionAppV2.0'
$DalamudDir    = 'C:\Users\insan\AppData\Roaming\XIVLauncher\addon\Hooks\dev'   # contains Dalamud.dll

# Project/manifest details
$InternalName  = 'NunuCompanionAppV2'
$DisplayName   = 'Nunu Companion App V2.0'
$Author        = 'The Nunu'
$ApiLevel      = 9
$Configuration = 'Release'

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Note([string]$m){ Write-Host "[*] $m" }
function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p | Out-Null } }

# 0) Verify Dalamud assemblies (direct refs build)
$req = @('Dalamud.dll','Dalamud.Interface.dll','Dalamud.Plugin.dll','ImGui.NET.dll')
foreach($r in $req){
  $p = Join-Path $DalamudDir $r
  if(-not (Test-Path -LiteralPath $p)){ throw "Missing: $p" }
}
Note "Using Dalamud assemblies from: $DalamudDir"

# 1) Locate project
Ensure-Dir $RepoRoot
$csproj = Get-ChildItem -LiteralPath $RepoRoot -Recurse -Filter *.csproj -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } |
          Select-Object -First 1
if(-not $csproj){ throw "No .csproj found under $RepoRoot." }
$ProjDir = $csproj.Directory.FullName
Note "Project: $($csproj.FullName)"

# 2) Ensure manifest next to project (snake_case)
$ManifestPath = Join-Path $ProjDir "$InternalName.yaml"
$manifest = @"
# Dalamud manifest (YAML)
name: $DisplayName
author: $Author
punchline: Persona + chat companion (V2).
description: |-
  Nunu Companion App (V2) — persona lives in plugin config; one-DLL drop.
internal_name: $InternalName
dalamud_api_level: $ApiLevel
dll:
  - "$InternalName.dll"
repo_url:
tags: [utility, chat, nunu]
"@
Set-Content -LiteralPath $ManifestPath -Value $manifest -Encoding UTF8
Note "Manifest ensured: $(Split-Path $ManifestPath -Leaf)"

# 3) Patch .csproj to Microsoft.NET.Sdk + direct refs to $DalamudDir
[xml]$xml = Get-Content -LiteralPath $csproj.FullName
$projectNode = $xml.SelectSingleNode('/Project'); if(-not $projectNode){ $projectNode = $xml.CreateElement('Project'); [void]$xml.AppendChild($projectNode) }
$projectNode.SetAttribute('Sdk','Microsoft.NET.Sdk')

function Ensure-Child([System.Xml.XmlDocument]$doc,[System.Xml.XmlNode]$parent,[string]$name){
  $n = $parent.SelectSingleNode($name); if(-not $n){ $n = $doc.CreateElement($name); [void]$parent.AppendChild($n) }; $n
}
function Ensure-Prop([System.Xml.XmlDocument]$doc,[System.Xml.XmlNode]$pg,[string]$name,[string]$value){
  $n = $pg.SelectSingleNode($name); if(-not $n){ $n = $doc.CreateElement($name); [void]$pg.AppendChild($n) }
  if($value){ $n.InnerText = $value }
}

$pg = $projectNode.SelectSingleNode('PropertyGroup'); if(-not $pg){ $pg = Ensure-Child $xml $projectNode 'PropertyGroup' }
Ensure-Prop $xml $pg 'TargetFramework' 'net8.0-windows'
Ensure-Prop $xml $pg 'Nullable' 'enable'
Ensure-Prop $xml $pg 'ImplicitUsings' 'enable'
Ensure-Prop $xml $pg 'AssemblyName' $InternalName
Ensure-Prop $xml $pg 'RootNamespace' $InternalName

# Reference group
$ig = $projectNode.SelectSingleNode("ItemGroup[@Label='DalamudRefs']")
if(-not $ig){ $ig = $xml.CreateElement('ItemGroup'); $ig.SetAttribute('Label','DalamudRefs'); [void]$projectNode.AppendChild($ig) }

foreach($r in $req){
  $full = Join-Path $DalamudDir $r
  $refName = [IO.Path]::GetFileNameWithoutExtension($full)
  $node = $ig.SelectSingleNode("Reference[@Include='$refName']")
  if(-not $node){
    $node = $xml.CreateElement('Reference')
    $node.SetAttribute('Include',$refName)
    $hp = $xml.CreateElement('HintPath'); $hp.InnerText = $full; [void]$node.AppendChild($hp)
    [void]$ig.AppendChild($node)
  } else {
    $hp = $node.SelectSingleNode('HintPath'); if(-not $hp){ $hp = $xml.CreateElement('HintPath'); [void]$node.AppendChild($hp) }
    $hp.InnerText = $full
  }
}

# Copy manifest on build
$ig2 = $projectNode.SelectSingleNode("ItemGroup[@Label='NunuAuto']")
if(-not $ig2){ $ig2 = $xml.CreateElement('ItemGroup'); $ig2.SetAttribute('Label','NunuAuto'); [void]$projectNode.AppendChild($ig2) }
$n = $ig2.SelectSingleNode("None[@Include='$InternalName.yaml']"); if(-not $n){ $n = $xml.CreateElement('None'); $n.SetAttribute('Include',"$InternalName.yaml"); [void]$ig2.AppendChild($n) }
$n.SetAttribute('CopyToOutputDirectory','Always')

$xml.Save($csproj.FullName)
Note "Patched csproj for direct references."

# 4) Restore + Build
Push-Location $ProjDir
try {
  Note "dotnet restore…"
  dotnet restore | Out-Host
  if($LASTEXITCODE -ne 0){ throw "restore failed ($LASTEXITCODE)" }

  Note "dotnet build ($Configuration)…"
  dotnet build -c $Configuration `
    -p:AssemblyName=$InternalName `
    -p:RootNamespace=$InternalName `
    | Out-Host
  if($LASTEXITCODE -ne 0){ throw "build failed ($LASTEXITCODE)" }
}
finally { Pop-Location }

# 5) Deploy to your folder
$binRoot = Join-Path $ProjDir 'bin'
$outDll = Get-ChildItem -LiteralPath $binRoot -Recurse -File -Filter "$InternalName.dll" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
if(-not $outDll){ throw "Build output not found for $InternalName.dll under $binRoot." }
$outDir = $outDll.Directory.FullName
Ensure-Dir $DeployDir
Note "Output: $outDir"

$items = @($outDll.FullName)
$yamlOut = Join-Path $outDir "$InternalName.yaml"
if(Test-Path -LiteralPath $yamlOut){ $items += $yamlOut } else { $items += $ManifestPath }
$iconOut = Join-Path $outDir 'icon.png'
if(Test-Path -LiteralPath $iconOut){ $items += $iconOut }

foreach($f in $items){
  Copy-Item -LiteralPath $f -Destination $DeployDir -Force
  Note "Deployed: $(Split-Path $f -Leaf)"
}

Write-Host "`n=== Build + Deploy complete ==="
Write-Host "Drop: $DeployDir"
