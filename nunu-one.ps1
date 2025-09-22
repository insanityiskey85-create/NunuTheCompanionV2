# nunu-one.ps1 — Clean punctuation, fix for Dalamud API 12 / .NET 8, build & deploy
# Paste-and-go for PowerShell 7 x64

param(
  [string]$Root        = 'C:\NunuCompanionApp V2.0',
  [string]$Internal    = 'NunuCompanionAppV2',
  [string]$DeployDir   = 'C:\NunuCompanionApp V2.0\Drop',
  [string]$Api12SdkVer = '12.3.0'   # pin Dalamud.NET.Sdk for API 12
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Note([string]$m){ Write-Host "[Nunu] $m" }
function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }

$rxm = [System.Text.RegularExpressions.RegexOptions]::Multiline

# 0) Sanity
Note "PowerShell: $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion) ($([Environment]::Is64BitProcess ? 'x64' : 'x86'))"
$sdks = & dotnet --list-sdks 2>$null
if(-not $sdks){ throw ".NET SDK not found. Install .NET 8 SDK (x64)." }
if(-not ($sdks | Select-String -Pattern '^\s*8\.')){ Write-Host $sdks; throw "Missing .NET 8 SDK." }

# 1) Locate project
Ensure-Dir $Root
$csproj = Get-ChildItem -LiteralPath $Root -Recurse -Filter *.csproj -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } |
          Sort-Object FullName |
          Where-Object { $_.BaseName -ieq $Internal } |
          Select-Object -First 1
if(-not $csproj){
  $csproj = Get-ChildItem -LiteralPath $Root -Recurse -Filter *.csproj -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } |
            Select-Object -First 1
}
if(-not $csproj){ throw "No .csproj found under $Root" }
$ProjDir = $csproj.Directory.FullName
Note "Project: $($csproj.FullName)"

$RestoreLog = Join-Path $ProjDir 'nunu-restore.log'
$BuildLog   = Join-Path $ProjDir 'nunu-build.log'

# 2) Sanitize C# files (punctuation + invisibles)
Note "Sanitizing C# files (quotes, dashes, ellipses, zero-width, BOM)…"
$map = @{
  [char]0x2018 = "'"; [char]0x2019 = "'"; [char]0x201B = "'";
  [char]0x201C = '"'; [char]0x201D = '"'; [char]0x201F = '"';
  [char]0x00AB = '"'; [char]0x00BB = '"';
  [char]0x2013 = "-"; [char]0x2014 = "-";
  [char]0x2026 = "...";
  [char]0x00A0 = " "; [char]0x200B = ""; [char]0x200C = ""; [char]0x200D = ""; [char]0xFEFF = ""
}
$files = Get-ChildItem -LiteralPath $Root -Recurse -Filter *.cs -File -ErrorAction SilentlyContinue
$sanCount = 0
foreach($f in $files){
  $text = Get-Content -LiteralPath $f.FullName -Raw
  $orig = $text
  foreach($k in $map.Keys){ $text = $text -replace [regex]::Escape([string]$k), [string]$map[$k] }
  $lines = $text -split "`r?`n"
  for($i=0;$i -lt $lines.Count;$i++){
    $lines[$i] = $lines[$i].TrimStart([char]0xFEFF, [char]0x200B, [char]0x200C, [char]0x200D)
  }
  $new = ($lines -join "`r`n")
  if($new -ne $orig){ Set-Content -LiteralPath $f.FullName -Value $new -Encoding UTF8; $sanCount++ }
}
Note "Sanitized $sanCount file(s)."

# 3) Patch sources for API 12 (ImGuiNET usings + common signature)
Note "Patching source for API 12 (ImGuiNET usings, Chat signature)…"
$patchCount = 0
foreach($f in $files){
  $t = Get-Content -LiteralPath $f.FullName -Raw
  $o = $t

  # Convert v13 usings -> ImGuiNET family using RegexOptions.Multiline
  $t = [regex]::Replace($t, '^\s*using\s+Dalamud\.Bindings\.ImGui\s*;\s*$', 'using ImGuiNET;', $rxm)
  $t = [regex]::Replace($t, '^\s*using\s+Dalamud\.Bindings\.ImPlot\s*;\s*$', 'using ImPlotNET;', $rxm)
  $t = [regex]::Replace($t, '^\s*using\s+Dalamud\.Bindings\.ImGuizmo\s*;\s*$', 'using ImGuizmoNET;', $rxm)

  # Fix ChatRouter senderId: int -> uint (API 12 delegate)
  if([System.IO.Path]::GetFileName($f.FullName) -ieq 'ChatRouter.cs'){
    $t = [regex]::Replace($t, '(\W)int\s+senderId(\W)', '${1}uint senderId$2')
  }

  if($t -ne $o){
    Set-Content -LiteralPath $f.FullName -Value $t -Encoding UTF8
    $patchCount++
  }
}
Note "Patched $patchCount file(s)."

# 4) Patch .csproj for Dalamud API 12 + net8.0
Note "Patching .csproj to Dalamud.NET.Sdk/$Api12SdkVer + net8.0…"
[xml]$xml = Get-Content -LiteralPath $csproj.FullName
$projectNode = $xml.SelectSingleNode('/Project'); if(-not $projectNode){ throw "Invalid .csproj XML" }
$projectNode.SetAttribute('Sdk', "Dalamud.NET.Sdk/$Api12SdkVer")

function Ensure-Child([System.Xml.XmlDocument]$doc,[System.Xml.XmlNode]$parent,[string]$name){
  $n = $parent.SelectSingleNode($name); if(-not $n){ $n = $doc.CreateElement($name); [void]$parent.AppendChild($n) }; $n
}
function Ensure-Prop([System.Xml.XmlDocument]$doc,[System.Xml.XmlNode]$pg,[string]$name,[string]$value){
  $n = $pg.SelectSingleNode($name); if(-not $n){ $n = $doc.CreateElement($name); [void]$pg.AppendChild($n) }
  if($value){ $n.InnerText = $value }
}

$pg = $projectNode.SelectSingleNode('PropertyGroup'); if(-not $pg){ $pg = Ensure-Child $xml $projectNode 'PropertyGroup' }
Ensure-Prop $xml $pg 'TargetFramework' 'net8.0'
Ensure-Prop $xml $pg 'Platforms' 'x64'
Ensure-Prop $xml $pg 'Nullable' 'enable'
Ensure-Prop $xml $pg 'ImplicitUsings' 'enable'
Ensure-Prop $xml $pg 'LangVersion' 'latest'
Ensure-Prop $xml $pg 'AllowUnsafeBlocks' 'true'
Ensure-Prop $xml $pg 'AssemblyName' $Internal
Ensure-Prop $xml $pg 'RootNamespace' $Internal

# Remove explicit Dalamud*/ImGui* references (SDK provides them)
$refNodes = $xml.SelectNodes('//ItemGroup/Reference')
foreach($ref in @($refNodes)){
  $inc = $ref.GetAttribute('Include')
  if($inc -match '^(Dalamud(\.|$)|ImGui)'){ $ref.ParentNode.RemoveChild($ref) | Out-Null }
}
# Remove old labeled groups
$legacyGroups = $xml.SelectNodes("//ItemGroup[@Label='DalamudRefs']")
foreach($grp in @($legacyGroups)){ $grp.ParentNode.RemoveChild($grp) | Out-Null }

# De-dupe DalamudPackager if present (optional)
$pkgRefs = $xml.SelectNodes("//PackageReference[@Include='DalamudPackager']")
if($pkgRefs.Count -gt 1){
  for($i=1; $i -lt $pkgRefs.Count; $i++){ $pkgRefs[$i].ParentNode.RemoveChild($pkgRefs[$i]) | Out-Null }
}

# Ensure YAML copied to output
$assetsGroup = $xml.SelectSingleNode("//ItemGroup[@Label='NunuAuto']")
if(-not $assetsGroup){ $assetsGroup = $xml.CreateElement('ItemGroup'); $assetsGroup.SetAttribute('Label','NunuAuto'); [void]$projectNode.AppendChild($assetsGroup) }
$yamlName = "$Internal.yaml"
$noneNode = $assetsGroup.SelectSingleNode("None[@Include='$yamlName']")
if(-not $noneNode){ $noneNode = $xml.CreateElement('None'); $noneNode.SetAttribute('Include', $yamlName); [void]$assetsGroup.AppendChild($noneNode) }
$noneNode.SetAttribute('CopyToOutputDirectory','Always')

$xml.Save($csproj.FullName)
Note "csproj patched."

# 5) Ensure manifest exists
$ManifestPath = Join-Path $ProjDir "$Internal.yaml"
if(-not (Test-Path -LiteralPath $ManifestPath)){
  $manifest = @"
name: Nunu Companion App V2.0
author: The Nunu
punchline: Minimal chat capture window.
description: |
  Nunu Companion App (V2) — simple chat capture and viewer using Dalamud API 12.
tags: [utility, chat]
"@
  Set-Content -LiteralPath $ManifestPath -Value $manifest -Encoding UTF8
  Note "Manifest created: $ManifestPath"
}

# 6) Restore & Build
Note "dotnet restore…"
& dotnet restore "$($csproj.FullName)" > $RestoreLog 2>&1
if($LASTEXITCODE -ne 0){
  Write-Host "[Nunu] Restore failed. Last 80 lines:"; Get-Content $RestoreLog -Tail 80
  throw "restore failed ($LASTEXITCODE)"
}

$props = @('/p:MakeZip=true')
Note "dotnet build (Release)…"
& dotnet build "$($csproj.FullName)" -c Release @props -v m "/clp:Summary;ErrorsOnly" > $BuildLog 2>&1
if($LASTEXITCODE -ne 0){
  Write-Host "[Nunu] Build failed. Last 120 lines:"; Get-Content $BuildLog -Tail 120
  throw "build failed ($LASTEXITCODE)"
}

# 7) Locate output & deploy
[xml]$xml2 = Get-Content -LiteralPath $csproj.FullName
$tfmNode = $xml2.SelectSingleNode('/Project/PropertyGroup/TargetFramework')
$TFM = if($tfmNode -and $tfmNode.InnerText){ $tfmNode.InnerText } else { 'net8.0' }

$outDir = Join-Path $ProjDir "bin\Release\$TFM"
if(-not (Test-Path -LiteralPath $outDir)){
  $candDll = Get-ChildItem -LiteralPath (Join-Path $ProjDir 'bin\Release') -Recurse -Filter "$Internal.dll" -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $candDll){ throw "Build output not found for $Internal.dll in bin\Release." }
  $outDir = $candDll.Directory.FullName
}
$packSub = Join-Path $outDir $Internal
if(Test-Path -LiteralPath $packSub){ $outDir = $packSub }

Ensure-Dir $DeployDir
$items = @()
$dll = Join-Path $outDir "$Internal.dll"
if(-not (Test-Path -LiteralPath $dll)){ throw "$Internal.dll not found in $outDir" }
$items += $dll

$pdb = [IO.Path]::ChangeExtension($dll,'.pdb'); if(Test-Path -LiteralPath $pdb){ $items += $pdb }
$yamlOut = Join-Path $outDir "$Internal.yaml"; if(Test-Path -LiteralPath $yamlOut){ $items += $yamlOut } else { $items += $ManifestPath }
$manifestJson = Join-Path $outDir 'manifest.json'; if(Test-Path -LiteralPath $manifestJson){ $items += $manifestJson }
$latestZip    = Join-Path $outDir 'latest.zip';     if(Test-Path -LiteralPath $latestZip){ $items += $latestZip }
$icon         = Join-Path $outDir 'icon.png';       if(Test-Path -LiteralPath $icon){ $items += $icon }

foreach($f in $items){
  Copy-Item -LiteralPath $f -Destination $DeployDir -Force
  Note "Deployed: $(Split-Path $f -Leaf)"
}

Write-Host "`n=== Build + Deploy complete ==="
Write-Host "Logs: $RestoreLog ; $BuildLog"
Write-Host "Drop Folder: $DeployDir"
