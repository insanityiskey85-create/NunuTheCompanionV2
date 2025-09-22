# nunu-build-net8.ps1 — Dalamud SDK build & deploy (API 12 / .NET 8)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# CONFIGURE
$RepoRoot     = 'C:\NunuCompanionApp V2.0'
$DeployDir    = 'C:\NunuCompanionApp V2.0\Drop'
$InternalName = 'NunuCompanionAppV2'
$DisplayName  = 'Nunu Companion App V2.0'
$Author       = 'The Nunu'
$Configuration = 'Release'
$DefaultTFM    = 'net8.0'
$SdkVersion    = '12.3.0'  # pin API 12 SDK

function Note([string]$m){ Write-Host "[Nunu] $m" }
function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }

# .NET 8 sanity
$sdks = & dotnet --list-sdks 2>$null
if(-not $sdks){ throw ".NET SDK not found. Install .NET 8 SDK (x64)." }
if(-not ($sdks | Select-String -Pattern '^\s*8\.' -SimpleMatch:$false)){ Write-Host $sdks; throw "Missing .NET 8 SDK." }

# Find project
Ensure-Dir $RepoRoot
$cslist = Get-ChildItem -LiteralPath $RepoRoot -Recurse -Filter *.csproj -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } | Sort-Object FullName
if(-not $cslist){ throw "No .csproj found under $RepoRoot." }
$csproj = ($cslist | Where-Object { $_.BaseName -ieq $InternalName } | Select-Object -First 1) ?? ($cslist | Select-Object -First 1)
$ProjDir = $csproj.Directory.FullName
Note "Project: $($csproj.FullName)"

$RestoreLog = Join-Path $ProjDir 'nunu-restore.log'
$BuildLog   = Join-Path $ProjDir 'nunu-build.log'

# Ensure YAML manifest
$ManifestPath = Join-Path $ProjDir "$InternalName.yaml"
if(-not (Test-Path -LiteralPath $ManifestPath)){
$manifest = @"
name: $DisplayName
author: $Author
punchline: Minimal chat capture window.
description: |
  Nunu Companion App (V2) — simple chat capture and viewer using Dalamud API 12.
tags: [utility, chat]
"@
  Set-Content -LiteralPath $ManifestPath -Value $manifest -Encoding UTF8
  Note "Manifest ensured: $ManifestPath"
} else { Note "Manifest ensured: $ManifestPath" }

# Patch .csproj -> Dalamud.NET.Sdk (pinned API 12)
[xml]$xml = Get-Content -LiteralPath $csproj.FullName
$projectNode = $xml.SelectSingleNode('/Project'); if(-not $projectNode){ throw "Invalid .csproj XML" }
$desiredSdk = "Dalamud.NET.Sdk/$SdkVersion"
$projectNode.SetAttribute('Sdk', $desiredSdk)

function Ensure-Child([System.Xml.XmlDocument]$doc,[System.Xml.XmlNode]$parent,[string]$name){ $n = $parent.SelectSingleNode($name); if(-not $n){ $n = $doc.CreateElement($name); [void]$parent.AppendChild($n) }; $n }
function Ensure-Prop([System.Xml.XmlDocument]$doc,[System.Xml.XmlNode]$pg,[string]$name,[string]$value){ $n = $pg.SelectSingleNode($name); if(-not $n){ $n = $doc.CreateElement($name); [void]$pg.AppendChild($n) } if($value){ $n.InnerText = $value } }

$pg = $projectNode.SelectSingleNode('PropertyGroup'); if(-not $pg){ $pg = Ensure-Child $xml $projectNode 'PropertyGroup' }
Ensure-Prop $xml $pg 'TargetFramework' $DefaultTFM
Ensure-Prop $xml $pg 'Platforms' 'x64'
Ensure-Prop $xml $pg 'Nullable' 'enable'
Ensure-Prop $xml $pg 'ImplicitUsings' 'enable'
Ensure-Prop $xml $pg 'LangVersion' 'latest'
Ensure-Prop $xml $pg 'AllowUnsafeBlocks' 'true'
Ensure-Prop $xml $pg 'AssemblyName' $InternalName
Ensure-Prop $xml $pg 'RootNamespace' $InternalName

# Remove legacy references
$allRefNodes = $xml.SelectNodes('//ItemGroup/Reference')
foreach($ref in @($allRefNodes)){
  $inc = $ref.GetAttribute('Include')
  if($inc -match '^(Dalamud(\.|$)|ImGui)'){ $ref.ParentNode.RemoveChild($ref) | Out-Null }
}
$legacyGroups = $xml.SelectNodes("//ItemGroup[@Label='DalamudRefs']")
foreach($grp in @($legacyGroups)){ $grp.ParentNode.RemoveChild($grp) | Out-Null }

# Ensure YAML copied to output
$assetsGroup = $xml.SelectSingleNode("//ItemGroup[@Label='NunuAuto']"); if(-not $assetsGroup){ $assetsGroup = $xml.CreateElement('ItemGroup'); $assetsGroup.SetAttribute('Label','NunuAuto'); [void]$projectNode.AppendChild($assetsGroup) }
$noneNode = $assetsGroup.SelectSingleNode("None[@Include='$InternalName.yaml']"); if(-not $noneNode){ $noneNode = $xml.CreateElement('None'); $noneNode.SetAttribute('Include',"$InternalName.yaml"); [void]$assetsGroup.AppendChild($noneNode) }
$noneNode.SetAttribute('CopyToOutputDirectory','Always')

$xml.Save($csproj.FullName)
Note "csproj set to $desiredSdk"

# Restore & Build
Note "dotnet restore..."
& dotnet restore "$($csproj.FullName)" > $RestoreLog 2>&1
if($LASTEXITCODE -ne 0){ Write-Host "[Nunu] Restore failed. Last 60 lines:"; Get-Content $RestoreLog -Tail 60; throw "restore failed ($LASTEXITCODE)" }

$extraProps = @(); if($Configuration -ieq 'Release'){ $extraProps += '/p:MakeZip=true' }
Note "dotnet build ($Configuration)..."
& dotnet build "$($csproj.FullName)" -c $Configuration @extraProps -v m "/clp:Summary;ErrorsOnly" > $BuildLog 2>&1
if($LASTEXITCODE -ne 0){ Write-Host "[Nunu] Build failed. Last 120 lines:"; Get-Content $BuildLog -Tail 120; throw "build failed ($LASTEXITCODE)" }

# Locate output
[xml]$xml2 = Get-Content -LiteralPath $csproj.FullName
$tfmNode = $xml2.SelectSingleNode('/Project/PropertyGroup/TargetFramework')
$TFM = if($tfmNode -and $tfmNode.InnerText){ $tfmNode.InnerText } else { $DefaultTFM }

$outDir = Join-Path $ProjDir "bin\$Configuration\$TFM"
if(-not (Test-Path -LiteralPath $outDir)){
  $candDll = Get-ChildItem -LiteralPath (Join-Path $ProjDir "bin\$Configuration") -Recurse -Filter "$InternalName.dll" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $candDll){ throw "Build output not found for $InternalName.dll in bin\$Configuration." }
  $outDir = $candDll.Directory.FullName
}
$packSub = Join-Path $outDir $InternalName; if(Test-Path -LiteralPath $packSub){ $outDir = $packSub }
Note "Output Root: $outDir"

# Deploy
Ensure-Dir $DeployDir
$pluginDll = Join-Path $outDir "$InternalName.dll"; if(-not (Test-Path -LiteralPath $pluginDll)){ throw "$InternalName.dll not found in $outDir" }

$toCopy = @($pluginDll)
$pdb = [IO.Path]::ChangeExtension($pluginDll,'.pdb'); if(Test-Path -LiteralPath $pdb){ $toCopy += $pdb }
$yamlOut = Join-Path $outDir "$InternalName.yaml"; if(Test-Path -LiteralPath $yamlOut){ $toCopy += $yamlOut } else { $toCopy += $ManifestPath }
$manifestJson = Join-Path $outDir 'manifest.json'; if(Test-Path -LiteralPath $manifestJson){ $toCopy += $manifestJson }
$latestZip    = Join-Path $outDir 'latest.zip';     if(Test-Path -LiteralPath $latestZip){ $toCopy += $latestZip }
$icon         = Join-Path $outDir 'icon.png';       if(Test-Path -LiteralPath $icon){ $toCopy += $icon }

foreach($f in $toCopy){ Copy-Item -LiteralPath $f -Destination $DeployDir -Force; Note "Deployed: $(Split-Path $f -Leaf)" }

Write-Host "`n=== Build + Deploy complete ==="
Write-Host "Logs: $RestoreLog ; $BuildLog"
Write-Host "Drop Folder: $DeployDir"
