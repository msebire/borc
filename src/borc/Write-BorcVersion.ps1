<#
  Reports a version to borc upgrade from an upgrade unit. Works under PowerShell 7
  and Windows PowerShell 5.1. BORC copies this file to
  %LOCALAPPDATA%\borc\Write-BorcVersion.ps1; upgrade units dot-source it:

    . "$env:LOCALAPPDATA\borc\Write-BorcVersion.ps1"
    Write-BorcVersion -App CodeAlta -Installed $installed -Available $latest

  Each call writes one small file to %LOCALAPPDATA%\borc\versions, which BORC
  reads after the run. It prints nothing, so a testScript still outputs exactly
  one boolean, and it never throws: a report must not fail a unit.
#>

function Write-BorcVersion {
  param([string] $App, [string] $Installed, [string] $Available)
  try {
    if (-not $App) { return }
    $folder = Join-Path $env:LOCALAPPDATA 'borc\versions'
    # Stop, so a failure goes to catch rather than to the unit's error stream.
    New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop | Out-Null
    $report = [ordered]@{ App = $App; Installed = $Installed; Available = $Available; Ticks = [DateTime]::UtcNow.Ticks }
    $path = Join-Path $folder ([guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $report -Compress), [Text.UTF8Encoding]::new($false))
  } catch {
    # Nothing is reported, and the unit goes on.
    $null = $_
  }
}
