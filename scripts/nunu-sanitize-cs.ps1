# nunu-sanitize-cs.ps1 — scrub fancy punctuation and invisible chars from C# files
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = 'C:\NunuCompanionApp V2.0'
function Note([string]$m){ Write-Host "[Nunu] $m" }

$map = @{
  [char]0x2018 = "'"; [char]0x2019 = "'"; [char]0x201B = "'";
  [char]0x201C = '"'; [char]0x201D = '"'; [char]0x201F = '"';
  [char]0x00AB = '"'; [char]0x00BB = '"';
  [char]0x2013 = "-";  [char]0x2014 = "-";
  [char]0x2026 = "...";
  [char]0x00A0 = " ";  [char]0x200B = ""; [char]0x200C = ""; [char]0x200D = ""; [char]0xFEFF = ""
}

$files = Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Filter *.cs -File -ErrorAction SilentlyContinue
if(-not $files){ throw "No .cs files found under $ProjectRoot" }

$changed = 0
foreach($f in $files){
  $text = Get-Content -LiteralPath $f.FullName -Raw
  foreach($k in $map.Keys){ $text = $text -replace [Regex]::Escape([string]$k), [string]$map[$k] }
  $lines = $text -split "`r?`n"
  for($i=0;$i -lt $lines.Count;$i++){ $lines[$i] = $lines[$i].TrimStart([char]0xFEFF, [char]0x200B, [char]0x200C, [char]0x200D) }
  $new = ($lines -join "`r`n")
  if($new -ne $text){ Set-Content -LiteralPath $f.FullName -Value $new -Encoding UTF8; $changed++; Note "Sanitized: $($f.FullName)" }
}
Note "Sanitized $changed file(s)."
