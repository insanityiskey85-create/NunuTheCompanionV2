# nunu-build-to-folder.ps1 — resilient build & deploy (SDK or fallback), drops to your path
# FIX: wrap each Test-Path call in () when using -and inside if().

# === CONFIG ===
$RepoRoot      = 'C:\NunuCompanionApp V2.0'
$InternalName  = 'NunuCompanionAppV2'
$DisplayName   = 'Nunu Companion App V2.0'
$Author        = 'The Nunu'
$Punchline     = 'Persona + chat companion (V2).'
$Description   = 'Nunu Companion App (V2) — persona lives in plugin config; one-DLL drop.'
$ApiLevel      = 9
$Configuration = 'Release'

# Your custom drop path:
$DeployDir     = 'C:\NunuCompanionApp V2.0\Nunu Companion App V2.0\Dployed NunuCompanionAppV2.0'
# ==============

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Note([string]$m){ Write-Host "[*] $m" }
function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p | Out-Null } }

# --- discover project ---
Ensure-Dir $RepoRoot
$csproj = Get-ChildItem -LiteralPath $RepoRoot -Filter *.csproj -Recurse -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } |
          Select-Object -First 1
if(-not $csproj){ throw "No .csproj found under $RepoRoot." }
$ProjDir = $csproj.Directory.FullName
Note "Project: $($csproj.FullName)"

# --- logs ---
$Logs = Join-Path $RepoRoot 'build-logs'; Ensure-Dir $Logs
$ts = (Get-Date).ToString('yyyyMMdd_HHmmss')
$restoreLog = Join-Path $Logs "restore_$ts.log"
$buildLog   = Join-Path $Logs "build_$ts.log"
$binlog     = Join-Path $Logs "msbuild_$ts.binlog"

# --- manifest (snake_case) ---
$ManifestPath = Join-Path $ProjDir "$InternalName.yaml"
$manifest = @"
# Dalamud manifest (YAML)
name: $DisplayName
author: $Author
punchline: $Punchline
description: |-
  $Description
internal_name: $InternalName
dalamud_api_level: $ApiLevel
dll:
  - "$InternalName.dll"
repo_url:
tags: [utility, chat, nunu]
"@
Set-Content -LiteralPath $ManifestPath -Value $manifest -Encoding UTF8
Note "Manifest ensured: $(Split-Path $ManifestPath -Leaf)"

# --- helper: patch csproj for Dalamud SDK ---
function Use-DalamudSdk {
  param([string]$CsprojPath)
  [xml]$xml = Get-Content -LiteralPath $CsprojPath
  $projectNode = $xml.SelectSingleNode('/Project'); if(-not $projectNode){ throw 'Invalid .csproj: missing <Project> root.' }
  $projectNode.SetAttribute('Sdk','Dalamud.NET.Sdk/13.1.0')

  function Ensure-Child([System.Xml.XmlDocument]$doc,[System.Xml.XmlNode]$parent,[string]$name){
    $n = $parent.SelectSingleNode($name); if(-not $n){ $n=$doc.CreateElement($name); [void]$parent.AppendChild($n) }; $n
  }
  function Ensure-Prop([System.Xml.XmlDocument]$doc,[System.Xml.XmlNode]$pg,[string]$name,[string]$value){
    $n=$pg.SelectSingleNode($name); if(-not $n){ $n=$doc.CreateElement($name); [void]$pg.AppendChild($n) }; if($value){ $n.InnerText=$value }
  }

  $pg = $projectNode.SelectSingleNode('PropertyGroup'); if(-not $pg){ $pg = Ensure-Child $xml $projectNode 'PropertyGroup' }
  Ensure-Prop $xml $pg 'TargetFramework' 'net8.0-windows'
  Ensure-Prop $xml $pg 'Nullable' 'enable'
  Ensure-Prop $xml $pg 'ImplicitUsings' 'enable'
  Ensure-Prop $xml $pg 'AssemblyName' $InternalName
  Ensure-Prop $xml $pg 'RootNamespace' $InternalName
  Ensure-Prop $xml $pg 'DalamudManifest' "$InternalName.yaml"

  $itemGroup = $projectNode.SelectSingleNode("ItemGroup[@Label='NunuAuto']")
  if(-not $itemGroup){
    $itemGroup = $xml.CreateElement('ItemGroup'); $itemGroup.SetAttribute('Label','NunuAuto'); [void]$projectNode.AppendChild($itemGroup)
  }
  $n = $itemGroup.SelectSingleNode("None[@Include='$InternalName.yaml']"); if(-not $n){ $n=$xml.CreateElement('None'); $n.SetAttribute('Include',"$InternalName.yaml"); [void]$itemGroup.AppendChild($n) }
  $n.SetAttribute('CopyToOutputDirectory','Always')

  $xml.Save($CsprojPath)
  Note "csproj set to Dalamud.NET.Sdk."
}

# --- helper: patch csproj for fallback (no SDK; direct refs) ---
function Use-FallbackRefs {
  param([string]$CsprojPath)
  # discover Dalamud assemblies under %AppData%\XIVLauncher (common install)
  $base = Join-Path $env:AppData 'XIVLauncher'
  $candidates = Get-ChildItem -LiteralPath $base -Recurse -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
  $asmDir = $null
  foreach($d in $candidates){
    # IMPORTANT: wrap Test-Path calls in () so -and is an operator (not a parameter)
    if( (Test-Path (Join-Path $d 'Dalamud.dll')) -and (Test-Path (Join-Path $d 'Dalamud.Interface.dll')) -and (Test-Path (Join-Path $d 'ImGui.NET.dll')) ){
      $asmDir = $d; break
    }
  }
  if(-not $asmDir){ throw "Could not find Dalamud assemblies under $base. Launch Dalamud once, or specify the path manually." }

  [xml]$xml = Get-Content -LiteralPath $CsprojPath
  $projectNode = $xml.SelectSingleNode('/Project'); if(-not $projectNode){ $projectNode = $xml.CreateElement('Project'); $xml.AppendChild($projectNode) | Out-Null }
  $projectNode.SetAttribute('Sdk','Microsoft.NET.Sdk')

  function Ensure-Child([System.Xml.XmlDocument]$doc,[System.Xml.XmlNode]$parent,[string]$name){
    $n = $parent.SelectSingleNode($name); if(-not $n){ $n=$doc.CreateElement($name); [void]$parent.AppendChild($n) }; $n
  }
  function Ensure-Prop([System.Xml.XmlDocument]$doc,[System.Xml.XmlNode]$pg,[string]$name,[string]$value){
    $n=$pg.SelectSingleNode($name); if(-not $n){ $n=$doc.CreateElement($name); [void]$pg.AppendChild($n) }; if($value){ $n.InnerText=$value }
  }

  $pg = $projectNode.SelectSingleNode('PropertyGroup'); if(-not $pg){ $pg = Ensure-Child $xml $projectNode 'PropertyGroup' }
  Ensure-Prop $xml $pg 'TargetFramework' 'net8.0-windows'
  Ensure-Prop $xml $pg 'Nullable' 'enable'
  Ensure-Prop $xml $pg 'ImplicitUsings' 'enable'
  Ensure-Prop $xml $pg 'AssemblyName' $InternalName
  Ensure-Prop $xml $pg 'RootNamespace' $InternalName

  $refs = @('Dalamud.dll','Dalamud.Interface.dll','ImGui.NET.dll')
  $ig = $projectNode.SelectSingleNode("ItemGroup[@Label='DalamudRefs']")
  if(-not $ig){ $ig = $xml.CreateElement('ItemGroup'); $ig.SetAttribute('Label','DalamudRefs'); [void]$projectNode.AppendChild($ig) }
  foreach($r in $refs){
    $refName = [IO.Path]::GetFileNameWithoutExtension($r)
    $node = $ig.SelectSingleNode("Reference[@Include='$refName']")
    if(-not $node){
      $node = $xml.CreateElement('Reference')
      $node.SetAttribute('Include', $refName)
      $hp = $xml.CreateElement('HintPath'); $hp.InnerText = (Join-Path $asmDir $r); [void]$node.AppendChild($hp)
      [void]$ig.AppendChild($node)
    }
  }

  # keep manifest copy rule
  $ig2 = $projectNode.SelectSingleNode("ItemGroup[@Label='NunuAuto']")
  if(-not $ig2){ $ig2 = $xml.CreateElement('ItemGroup'); $ig2.SetAttribute('Label','NunuAuto'); [void]$projectNode.AppendChild($ig2) }
  $n2 = $ig2.SelectSingleNode("None[@Include='$InternalName.yaml']"); if(-not $n2){ $n2=$xml.CreateElement('None'); $n2.SetAttribute('Include',"$InternalName.yaml"); [void]$ig2.AppendChild($n2) }
  $n2.SetAttribute('CopyToOutputDirectory','Always')

  $xml.Save($CsprojPath)
  Note "csproj switched to Microsoft.NET.Sdk with direct Dalamud references."
}

# --- try SDK build first ---
$useFallback = $false
try {
  Use-DalamudSdk -CsprojPath $csproj.FullName

  # pin SDKs at repo root for consistency
  $sdks = (& dotnet --list-sdks) 2>$null
  $dotnet8 = ($sdks | Select-String '^\s*(8\.\d+\.\d+)').Matches.Value | Select-Object -First 1
  if(-not $dotnet8){ $dotnet8 = '8.0.100' }
  $globalJson = @{ sdk = @{ version = $dotnet8; rollForward = 'latestFeature' }; 'msbuild-sdks' = @{ 'Dalamud.NET.Sdk' = '13.1.0' } } | ConvertTo-Json -Depth 5
  Set-Content -LiteralPath (Join-Path $RepoRoot 'global.json') -Value $globalJson -Encoding UTF8
  @'
<?xml version="1.0" encoding="utf-8"?>
<configuration><packageSources><clear /><add key="nuget.org" value="https://api.nuget.org/v3/index.json" /></packageSources></configuration>
'@ | Set-Content -LiteralPath (Join-Path $RepoRoot 'NuGet.config') -Encoding UTF8

  Note "dotnet restore (SDK)…"
  dotnet restore $csproj.FullName /nologo /v:minimal *> $restoreLog
  if($LASTEXITCODE -ne 0){ throw "restore failed" }

  Note "dotnet build ($Configuration, SDK)…"
  dotnet build $csproj.FullName -c $Configuration /nologo -bl:$binlog `
    -p:TargetFramework=net8.0-windows `
    -p:AssemblyName=$InternalName `
    -p:RootNamespace=$InternalName `
    -p:DalamudManifest="$InternalName.yaml" *> $buildLog
  if($LASTEXITCODE -ne 0){
    $sdkNotFound = Select-String -Path $buildLog -Pattern 'MSB4236|SDK .* Dalamud\.NET\.Sdk .* could not be found' -Quiet
    if($sdkNotFound){ $useFallback = $true } else { throw "build failed" }
  }
}
catch { $useFallback = $true }

if($useFallback){
  Note "Switching to fallback: Microsoft.NET.Sdk + direct references."
  Use-FallbackRefs -CsprojPath $csproj.FullName

  Note "dotnet restore (fallback)…"
  dotnet restore $csproj.FullName /nologo /v:minimal *> $restoreLog
  if($LASTEXITCODE -ne 0){
    Write-Host "`n--- restore log tail ---"; Get-Content $restoreLog | Select-Object -Last 120
    throw "dotnet restore failed (fallback)."
  }

  Note "dotnet build ($Configuration, fallback)…"
  dotnet build $csproj.FullName -c $Configuration /nologo -bl:$binlog *> $buildLog
  if($LASTEXITCODE -ne 0){
    Write-Host "`n--- build log tail ---"; Get-Content $buildLog | Select-Object -Last 120
    throw "dotnet build failed (fallback)."
  }
}

# --- locate output & deploy ---
$binRoot = Join-Path $ProjDir 'bin'
$outDll = Get-ChildItem -LiteralPath $binRoot -Recurse -File -Filter "$InternalName.dll" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
if(-not $outDll){ throw "Build output not found for $InternalName.dll under $binRoot." }
$outDir = $outDll.Directory.FullName
Note "Output: $outDir"

Ensure-Dir $DeployDir
$copy = @($outDll.FullName)
$yamlOut = Join-Path $outDir "$InternalName.yaml"
if(Test-Path -LiteralPath $yamlOut){ $copy += $yamlOut } else { $copy += $ManifestPath }
$iconOut = Join-Path $outDir 'icon.png'
if(Test-Path -LiteralPath $iconOut){ $copy += $iconOut }

foreach($f in $copy){
  Copy-Item -LiteralPath $f -Destination $DeployDir -Force
  Note "Deployed: $(Split-Path $f -Leaf)"
}

Write-Host "`n=== Build + Deploy complete ==="
Write-Host "Drop: $DeployDir"
Write-Host "Logs: $restoreLog, $buildLog"
Write-Host "Binlog: $binlog"
