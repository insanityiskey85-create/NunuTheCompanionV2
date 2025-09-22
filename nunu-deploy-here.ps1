# nunu-build-modern.ps1 — Dalamud SDK build & deploy (no Hooks hunting)
# Builds with Dalamud.NET.Sdk (API 13 / .NET 9) and copies outputs to your drop folder.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# === PATHS ===
$RepoRoot  = 'C:\NunuCompanionApp V2.0'  # folder that contains the .csproj somewhere beneath
$DeployDir = 'C:\NunuCompanionApp V2.0\Nunu Companion App V2.0\Dployed NunuCompanionAppV2.0'

# === PROJECT IDENTITY ===
$InternalName = 'NunuCompanionAppV2'     # AssemblyName + RootNamespace
$DisplayName  = 'Nunu Companion App V2.0'
$Author       = 'The Nunu'

# === BUILD FLAVOR ===
$Configuration   = 'Release'              # Debug or Release
$TargetFramework = 'net9.0'               # Dalamud API 13 uses .NET 9
$SdkVersion      = ''                     # e.g. '13.1.0' to pin; '' uses latest installed

function Note([string]$m){ Write-Host "[Nunu] $m" }
function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }

# 1) Find the .csproj (prefer one matching InternalName)
$csproj = Get-ChildItem -LiteralPath $RepoRoot -Recurse -Filter *.csproj -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } |
          Sort-Object FullName
if(-not $csproj){ throw "No .csproj found under $RepoRoot." }
$csproj = ($csproj | Where-Object { $_.BaseName -ieq $InternalName } | Select-Object -First 1) `
          ?? ($csproj | Select-Object -First 1)
$ProjDir = $csproj.Directory.FullName
Note "Project: $($csproj.FullName)"

# 2) Ensure a YAML manifest (packager reads this; runtime JSON is generated)
$ManifestPath = Join-Path $ProjDir "$InternalName.yaml"
if(-not (Test-Path -LiteralPath $ManifestPath)){
$manifest = @"
name: $DisplayName
author: $Author
punchline: Persona + chat companion (V2).
description: |-
  Nunu Companion App (V2) — persona lives in plugin config; one-DLL drop.
tags: [utility, chat, nunu]
"@
Set-Content -LiteralPath $ManifestPath -Value $manifest -Encoding UTF8
Note "Manifest created: $ManifestPath"
} else { Note "Manifest ensured: $ManifestPath" }

# 3) Patch the .csproj to use Dalamud.NET.Sdk (no direct refs to Dalamud/ImGui)
[xml]$xml = Get-Content -LiteralPath $csproj.FullName
$projectNode = $xml.SelectSingleNode('/Project'); if(-not $projectNode){ throw "Invalid .csproj XML." }

$desiredSdk = if([string]::IsNullOrWhiteSpace($SdkVersion)) { 'Dalamud.NET.Sdk' } else { "Dalamud.NET.Sdk/$SdkVersion" }
$projectNode.SetAttribute('Sdk', $desiredSdk)

function Ensure-Child([System.Xml.XmlDocument]$doc,[System.Xml.XmlNode]$parent,[string]$name){
    $n = $parent.SelectSingleNode($name); if(-not $n){ $n = $doc.CreateElement($name); [void]$parent.AppendChild($n) }; $n
}
function Ensure-Prop([System.Xml.XmlDocument]$doc,[System.Xml.XmlNode]$pg,[string]$name,[string]$value){
    $n = $pg.SelectSingleNode($name); if(-not $n){ $n = $doc.CreateElement($name); [void]$pg.AppendChild($n) }
    if($value){ $n.InnerText = $value }
}

$pg = $projectNode.SelectSingleNode('PropertyGroup'); if(-not $pg){ $pg = Ensure-Child $xml $projectNode 'PropertyGroup' }
Ensure-Prop $xml $pg 'TargetFramework' $TargetFramework
Ensure-Prop $xml $pg 'Platforms' 'x64'
Ensure-Prop $xml $pg 'Nullable' 'enable'
Ensure-Prop $xml $pg 'ImplicitUsings' 'enable'
Ensure-Prop $xml $pg 'LangVersion' 'latest'
Ensure-Prop $xml $pg 'AllowUnsafeBlocks' 'true'
Ensure-Prop $xml $pg 'AssemblyName' $InternalName
Ensure-Prop $xml $pg 'RootNamespace' $InternalName

# Remove any legacy <Reference Include="Dalamud*"> or "ImGui*"
$allRefNodes = $xml.SelectNodes('//ItemGroup/Reference')
foreach($ref in @($allRefNodes)){
    $inc = $ref.GetAttribute('Include')
    if($inc -match '^(Dalamud(\.|$)|ImGui)'){ $ref.ParentNode.RemoveChild($ref) | Out-Null }
}
# Remove old groups labeled DalamudRefs
$legacyGroups = $xml.SelectNodes("//ItemGroup[@Label='DalamudRefs']")
foreach($grp in @($legacyGroups)){ $grp.ParentNode.RemoveChild($grp) | Out-Null }

# Ensure packager for Release zips
$itemGroup = $xml.SelectSingleNode('//ItemGroup[PackageReference]'); if(-not $itemGroup){ $itemGroup = $xml.CreateElement('ItemGroup'); [void]$projectNode.AppendChild($itemGroup) }
$pr = $itemGroup.SelectSingleNode("PackageReference[@Include='DalamudPackager']")
if(-not $pr){
    $pr = $xml.CreateElement('PackageReference'); $pr.SetAttribute('Include','DalamudPackager'); $pr.SetAttribute('Version','13.1.0')
    $pv = $xml.CreateElement('PrivateAssets'); $pv.InnerText = 'All'; [void]$pr.AppendChild($pv)
    [void]$itemGroup.AppendChild($pr)
}

# Ensure YAML is copied to output
$assetsGroup = $xml.SelectSingleNode("//ItemGroup[@Label='NunuAuto']")
if(-not $assetsGroup){ $assetsGroup = $xml.CreateElement('ItemGroup'); $assetsGroup.SetAttribute('Label','NunuAuto'); [void]$projectNode.AppendChild($assetsGroup) }
$noneNode = $assetsGroup.SelectSingleNode("None[@Include='$InternalName.yaml']")
if(-not $noneNode){ $noneNode = $xml.CreateElement('None'); $noneNode.SetAttribute('Include',"$InternalName.yaml"); [void]$assetsGroup.AppendChild($noneNode) }
$noneNode.SetAttribute('CopyToOutputDirectory','Always')

$xml.Save($csproj.FullName)
Note "csproj set to $desiredSdk."

# 4) Restore & Build
Push-Location $ProjDir
try {
    Note "dotnet restore (SDK)…"
    & dotnet restore | Out-Host
    if($LASTEXITCODE -ne 0){ throw "restore failed ($LASTEXITCODE)" }

    $extraProps = @()
    if($Configuration -ieq 'Release'){ $extraProps += '/p:MakeZip=true' }

    Note "dotnet build ($Configuration, SDK)…"
    & dotnet build -c $Configuration @extraProps | Out-Host
    if($LASTEXITCODE -ne 0){ throw "build failed ($LASTEXITCODE)" }
}
finally { Pop-Location }

# 5) Gather outputs (no Hooks files)
$outDir = Join-Path $ProjDir "bin\$Configuration\$TargetFramework"
if(-not (Test-Path -LiteralPath $outDir)){ throw "Build output not found: $outDir" }

# If packager created <AssemblyName> subfolder, prefer it
$packSub = Join-Path $outDir $InternalName
if(Test-Path -LiteralPath $packSub){ $outDir = $packSub }

$pluginDll = Join-Path $outDir "$InternalName.dll"
if(-not (Test-Path -LiteralPath $pluginDll)){
    # fallback: find the newest dll
    $pluginDll = Get-ChildItem -LiteralPath (Join-Path $ProjDir "bin\$Configuration") -Recurse -Filter "$InternalName.dll" -File -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -Expand FullName -First 1
    if(-not $pluginDll){ throw "$InternalName.dll not found under bin\$Configuration." }
    $outDir = Split-Path -Parent $pluginDll
}

# Collect artifacts to deploy
$toCopy = @($pluginDll)
$pdb = [IO.Path]::ChangeExtension($pluginDll,'.pdb'); if(Test-Path -LiteralPath $pdb){ $toCopy += $pdb }

$yamlOut = Join-Path $outDir "$InternalName.yaml"
if(Test-Path -LiteralPath $yamlOut){ $toCopy += $yamlOut } else { $toCopy += $ManifestPath }

$manifestJson = Join-Path $outDir 'manifest.json'; if(Test-Path -LiteralPath $manifestJson){ $toCopy += $manifestJson }
$latestZip    = Join-Path $outDir 'latest.zip';     if(Test-Path -LiteralPath $latestZip){ $toCopy += $latestZip }
$icon         = Join-Path $outDir 'icon.png';       if(Test-Path -LiteralPath $icon){ $toCopy += $icon }

# 6) Deploy
Ensure-Dir $DeployDir
foreach($f in $toCopy){
    Copy-Item -LiteralPath $f -Destination $DeployDir -Force
    Note "Deployed: $(Split-Path $f -Leaf)"
}

Write-Host "`n=== Build + Deploy complete ==="
Write-Host "Output Root: $outDir"
Write-Host "Drop Folder: $DeployDir"
