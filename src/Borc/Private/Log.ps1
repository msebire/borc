$script:BorcLogPath = $null

# Starts a timestamped log for one run and keeps only the newest ones. Files a
# run writes next to its log (the generated configurations) share its stem.
function Start-BorcLog {
  param([Parameter(Mandatory)] [string] $Directory, [Parameter(Mandatory)] [string] $Command)
  New-Item -ItemType Directory -Path $Directory -Force | Out-Null
  $stem = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), $Command
  $script:BorcLogPath = Join-Path $Directory "$stem.log"
  [IO.File]::WriteAllText($script:BorcLogPath, "borc $Command, $(Get-Date -Format o)`n")
  Remove-BorcOldLogs -Directory $Directory -Keep $script:BorcLogsToKeep
  $script:BorcLogPath
}

function Stop-BorcLog {
  if ($script:BorcLogPath) {
    Write-Host "Log: $script:BorcLogPath"
  }
  $script:BorcLogPath = $null
}

# Path for a file that belongs to the current run, next to its log.
function Get-BorcRunFilePath {
  param([Parameter(Mandatory)] [string] $Suffix)
  if (-not $script:BorcLogPath) { return Join-Path ([IO.Path]::GetTempPath()) "borc-$Suffix" }
  $script:BorcLogPath -replace '\.log$', ".$Suffix"
}

function Remove-BorcOldLogs {
  param([Parameter(Mandatory)] [string] $Directory, [Parameter(Mandatory)] [int] $Keep)
  $logs = @(Get-ChildItem -Path $Directory -Filter '*.log' -File | Sort-Object Name -Descending)
  foreach ($old in ($logs | Select-Object -Skip $Keep)) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($old.Name)
    Get-ChildItem -Path $Directory -Filter "$stem.*" -File | Remove-Item -Force
  }
}

function Write-BorcLog {
  param(
    [Parameter(Mandatory)] [AllowEmptyString()] [string] $Message,
    [ValidateSet('Info', 'Warning', 'Error')] [string] $Level = 'Info',
    [switch] $LogOnly
  )
  if ($script:BorcLogPath) {
    $prefix = if ($Level -eq 'Info') { '' } else { "$($Level.ToUpperInvariant()): " }
    [IO.File]::AppendAllText($script:BorcLogPath, "$prefix$Message`n")
  }
  if ($LogOnly) { return }
  switch ($Level) {
    'Warning' { Write-Host "Warning: $Message" -ForegroundColor Yellow }
    'Error' { Write-Host "Error: $Message" -ForegroundColor Red }
    default { Write-Host $Message }
  }
}

# Output of a tool run by borc: shown as is, and logged unless it is only a
# progress spinner.
function Write-BorcOutputLine {
  param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Line)
  Write-Host $Line
  if ($script:BorcLogPath -and $Line -notmatch '^[\s\\|/\-]*$' -and $Line -notmatch '[█▒]') {
    [IO.File]::AppendAllText($script:BorcLogPath, "$Line`n")
  }
}
