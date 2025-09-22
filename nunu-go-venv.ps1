# nunu-go-venv.ps1 — Activate venv, then run the Python builder
# Usage examples:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\NunuCompanionApp V2.0\nunu-go-venv.ps1" -Mode auto
#   pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\NunuCompanionApp V2.0\nunu-go-venv.ps1" -Mode net9
#   pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\NunuCompanionApp V2.0\nunu-go-venv.ps1" -Mode net8

param(
  [ValidateSet('auto','net8','net9')]
  [string]$Mode = 'auto'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Note([string]$m){ Write-Host "[Nunu] $m" }

# --- Paths ---
$Root      = 'C:\NunuCompanionApp V2.0'
$PyVenv    = 'D:\Repos\Wav2Lip\.venv'
$PyExe     = Join-Path $PyVenv 'Scripts\python.exe'
$Activate  = Join-Path $PyVenv 'Scripts\Activate.ps1'
$RunnerPy  = Join-Path $Root 'nunu_one.py'
$Internal  = 'NunuCompanionAppV2'
$Drop      = Join-Path $Root 'Drop'

# --- Checks ---
if(!(Test-Path -LiteralPath $RunnerPy)){ throw "Missing: $RunnerPy" }
if(!(Test-Path -LiteralPath $Activate)){ throw "Missing venv activator: $Activate" }
if(!(Test-Path -LiteralPath $PyExe)){ throw "Missing venv python: $PyExe" }

# --- Activate venv in current session ---
Note "Activating venv: $PyVenv"
. $Activate
Note "VIRTUAL_ENV: $env:VIRTUAL_ENV"

# Verify python from venv
$pyCmd = Get-Command $PyExe -ErrorAction Stop
Note "Python: $($pyCmd.Path)"
& $PyExe --version | ForEach-Object { Note $_ }

# Ensure dotnet is visible (the Python script will also validate)
$dot = Get-Command dotnet -ErrorAction Stop
Note "dotnet: $($dot.Path)"

# --- Run the Python builder ---
Note "Running nunu_one.py (mode: $Mode)…"
& $PyExe $RunnerPy --mode $Mode --root $Root --internal $Internal --deploy $Drop
if($LASTEXITCODE -ne 0){ throw "nunu_one.py failed (exit $LASTEXITCODE)" }

Note "All steps complete. Drop: $Drop"
