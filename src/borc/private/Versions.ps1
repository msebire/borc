# The versions upgrade units report with Write-BorcVersion.ps1, which writes them
# to %LOCALAPPDATA%\borc\versions. Units ignore the caller's environment, so a
# folder at a fixed path is how they reach BORC, as Get-BorcSecret.ps1 does.

$script:BorcReportedTextMaxLength = 50

function Get-BorcVersionFolder {
  param([Parameter(Mandatory)] $Paths)
  Join-Path $Paths.Internal 'versions'
}

# Empties the folder before a run, so only that run's reports are read.
function Clear-BorcVersionReports {
  param([Parameter(Mandatory)] $Paths)
  $folder = Get-BorcVersionFolder -Paths $Paths
  if (-not (Test-Path -LiteralPath $folder)) { return }
  foreach ($file in Get-ChildItem -LiteralPath $folder -Filter '*.json' -File) { Remove-Item -LiteralPath $file.FullName -Force }
}

# The reports of the run, oldest first. A file BORC cannot read is left out with
# a warning, so its app is reported as if it had sent nothing.
function Read-BorcVersionReports {
  param([Parameter(Mandatory)] $Paths)
  $folder = Get-BorcVersionFolder -Paths $Paths
  if (-not (Test-Path -LiteralPath $folder)) { return @() }
  $reports = foreach ($file in Get-ChildItem -LiteralPath $folder -Filter '*.json' -File) {
    try {
      $data = [IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
      $app = Format-BorcReportedText -Text $data.App
      if (-not $app) { throw 'the report names no app' }
      [pscustomobject]@{ App = $app; Installed = Format-BorcReportedText -Text $data.Installed; Available = Format-BorcReportedText -Text $data.Available; Ticks = [long]$data.Ticks }
    } catch {
      Write-BorcLog -Message "Could not read the version report $($file.Name), which is left out: $($_.Exception.Message)" -Level Warning
    }
  }
  @($reports | Sort-Object Ticks)
}

# One short line of plain text: reports come from recipe code and end up in the summary.
function Format-BorcReportedText {
  param($Text)
  $clean = ("$Text" -replace '\p{C}', '').Trim()
  if ($clean.Length -gt $script:BorcReportedTextMaxLength) { $clean = $clean.Substring(0, $script:BorcReportedTextMaxLength) }
  $clean
}

# What the reports say about each app. A testScript reports the installed and the
# newest version, then the setScript, if it runs, the version it installed:
#   upgraded    the installed version changed between the reports
#   available   a newer version than the last installed one is reported: before
#               an upgrade, as with --check, or after one that did not move it
#   up to date  the version did not change, or the newest is reported installed
#   reported    anything else: the version is known, not whether it is the newest
function Get-BorcReportedVersions {
  param([object[]] $Reports = @())
  $apps = [ordered]@{}
  foreach ($report in $Reports) {
    if (-not $apps.Contains($report.App)) { $apps[$report.App] = [pscustomobject]@{ App = $report.App; Before = ''; After = ''; Available = ''; Count = 0 } }
    $entry = $apps[$report.App]
    if ($report.Installed) {
      if (-not $entry.Before) { $entry.Before = $report.Installed }
      $entry.After = $report.Installed
    }
    if ($report.Available) { $entry.Available = $report.Available }
    $entry.Count++
  }
  foreach ($entry in $apps.Values) {
    $state, $text = if ($entry.Before -and $entry.After -ne $entry.Before) { 'upgraded', "$($entry.App) ($($entry.Before) -> $($entry.After))" }
    elseif ($entry.Available -and $entry.Available -ne $entry.After) { 'available', "$($entry.App) ($($entry.After) -> $($entry.Available))" }
    elseif ($entry.Count -ge 2 -or $entry.Available) { 'up to date', "$($entry.App) $($entry.After)" }
    else { 'reported', "$($entry.App) $($entry.After)" }
    [pscustomobject]@{ App = $entry.App; State = $state; Text = $text }
  }
}
