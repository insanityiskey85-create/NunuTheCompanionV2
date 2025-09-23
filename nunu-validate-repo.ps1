param(
  [Parameter(Mandatory = $true)]
  [string]$RepoJsonUrl
)

$ErrorActionPreference = "Stop"

Write-Host "[Nunu] Checking repo.json at $RepoJsonUrl"
$resp = Invoke-WebRequest -Uri $RepoJsonUrl -UseBasicParsing
$plugins = $resp.Content | ConvertFrom-Json
if ($plugins -isnot [System.Collections.IEnumerable]) { $plugins = @($plugins) }

foreach ($p in $plugins) {
  Write-Host "`n[Plugin] $($p.Name)  (InternalName=$($p.InternalName))"

  foreach ($prop in @('RepoUrl','IconUrl','DownloadLinkInstall','DownloadLinkUpdate')) {
    $url = $p.$prop
    if ([string]::IsNullOrWhiteSpace($url)) { Write-Warning ("  {0,-20} is empty" -f $prop); continue }

    try {
      $h = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing
      Write-Host ("  {0,-20} HTTP {1}" -f $prop, $h.StatusCode)
    } catch {
      Write-Warning ("  {0,-20} HEAD failed: {1}" -f $prop, $_.Exception.Message)
      try {
        $g = Invoke-WebRequest -Uri $url -UseBasicParsing
        Write-Host ("  {0,-20} GET  HTTP {1}" -f $prop, $g.StatusCode)
      } catch {
        Write-Error ("  {0,-20} GET failed: {1}" -f $prop, $_.Exception.Message)
      }
    }
  }

  # Pull the install zip and inspect it
  if ($p.DownloadLinkInstall) {
    $tmpZip = Join-Path $env:TEMP ("nunu_zip_" + [guid]::NewGuid() + ".zip")
    $unzip  = Join-Path $env:TEMP ("nunu_unzip_" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $unzip | Out-Null

    Write-Host "  Downloading zip…"
    Invoke-WebRequest -Uri $p.DownloadLinkInstall -UseBasicParsing -OutFile $tmpZip

    Expand-Archive -LiteralPath $tmpZip -DestinationPath $unzip -Force

    $manifest = Get-ChildItem -LiteralPath $unzip -Recurse -Filter "manifest.json" | Select-Object -First 1
    $dll      = Get-ChildItem -LiteralPath $unzip -Recurse -Filter "$($p.InternalName)*.dll" | Select-Object -First 1

    if (-not $manifest) { Write-Error "  -> manifest.json is MISSING inside the zip" }
    if (-not $dll)      { Write-Error "  -> DLL '$($p.InternalName)*.dll' is MISSING inside the zip" }

    if ($manifest) {
      $m = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json
      Write-Host ("  manifest.InternalName     = {0}" -f $m.InternalName)
      Write-Host ("  manifest.DalamudApiLevel  = {0}" -f $m.DalamudApiLevel)
      Write-Host ("  manifest.AssemblyVersion  = {0}" -f $m.AssemblyVersion)
    }

    Remove-Item $tmpZip -Force
    Remove-Item $unzip -Recurse -Force
  }
}

Write-Host "`n[Nunu] Validation complete."
