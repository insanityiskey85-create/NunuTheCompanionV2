# nunu-fix-imgui-v12.ps1 — migrate v13 ImGui bindings back to ImGuiNET for API 12
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = 'C:\NunuCompanionApp V2.0'
function Note([string]$m){ Write-Host "[Nunu] $m" }

$files = Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Filter *.cs -File -ErrorAction SilentlyContinue
if(-not $files){ throw "No .cs files found under $ProjectRoot" }

$changed = 0
foreach($f in $files){
  $t = Get-Content -LiteralPath $f.FullName -Raw
  $o = $t
  $t = $t -replace '^\s*using\s+Dalamud\.Bindings\.ImGui\s*;\s*', 'using ImGuiNET;', 'Multiline'
  $t = $t -replace '^\s*using\s+Dalamud\.Bindings\.ImPlot\s*;\s*', 'using ImPlotNET;', 'Multiline'
  $t = $t -replace '^\s*using\s+Dalamud\.Bindings\.ImGuizmo\s*;\s*', 'using ImGuizmoNET;', 'Multiline'
  if($t -ne $o){ Set-Content -LiteralPath $f.FullName -Value $t -Encoding UTF8; $changed++; Note "Patched: $($f.FullName)" }
}
Note "Patched $changed file(s)."
