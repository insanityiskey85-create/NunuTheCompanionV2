# build-nunu.ps1  (PowerShell 7 x64)
$ErrorActionPreference = 'Stop'

$root = 'C:\NunuCompanionApp V2.0\Nunu Companion App V2.0'
$proj = Join-Path $root 'NunuCompanionAppV2.csproj'
$drop = Join-Path $root 'Dployed NunuCompanionAppV2.0'
$dev  = Join-Path $env:AppData 'XIVLauncher\devPlugins\NunuCompanionAppV2'

Write-Host "[Nunu] Using dotnet:" (& dotnet --version)

# clean bin/obj (fixes the Filter error)
foreach($d in 'bin','obj'){
  $p = Join-Path $root $d
  if(Test-Path $p){ Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
}

# restore & build
& dotnet restore $proj
& dotnet build   $proj -c Release -p:Platform=x64 -clp:Summary

# find the newest compiled dll under bin\Release (handles net8/net9, -windows, etc.)
$rel = Join-Path $root 'bin\Release'
$dll = Get-ChildItem -Path $rel -Recurse -Filter 'NunuCompanionAppV2.dll' `
       | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if(-not $dll){ throw "Could not locate build output under $rel. Build likely failed." }
$out = $dll.DirectoryName
Write-Host "[Nunu] Build output: $out"

# prep deploy dirs
foreach($d in @($drop,$dev)){
  if(Test-Path $d){ Remove-Item $d -Recurse -Force }
  New-Item -ItemType Directory -Path $d | Out-Null
}

# payload: dll/pdb from output + yaml/icon from output or project root
$payloadNames = @('NunuCompanionAppV2.dll','NunuCompanionAppV2.pdb','NunuCompanionAppV2.yaml','icon.png')
$payload = foreach($name in $payloadNames){
  $p1 = Join-Path $out  $name
  $p2 = Join-Path $root $name
  if(Test-Path $p1){ $p1 }
  elseif(Test-Path $p2){ $p2 }
}

# copy to both targets
foreach($d in @($drop,$dev)){
  Copy-Item $payload -Destination $d -Force
  # persona folder (keep your structure)
  $personaSrc = Join-Path $root 'Persona\Persona.json'
  if(Test-Path $personaSrc){
    $personaDstDir = Join-Path $d 'Persona'
    New-Item -ItemType Directory -Path $personaDstDir -Force | Out-Null
    Copy-Item $personaSrc $personaDstDir -Force
  }
}

Write-Host "[Nunu] Drop -> $drop"
Get-ChildItem $drop | Select Name,Length,LastWriteTime | Format-Table -AutoSize

Write-Host "[Nunu] Dev  -> $dev"
Get-ChildItem $dev  | Select Name,Length,LastWriteTime | Format-Table -AutoSize
