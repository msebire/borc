<#
  What borc adds to each new PowerShell 7 terminal. The borc block of the
  profile dot-sources this file from the engine clone, so self-update changes
  it without touching the profile. Windows PowerShell 5.1 can dot-source it
  too.

  It runs at every terminal start, so it stays quick and quiet: one git
  status, and nothing printed when the config repo is clean.
#>

. (Join-Path $PSScriptRoot 'completion.ps1')

# Uncommitted changes (untracked files included, .gitignore respected) and
# commits not pushed, from the last fetch. $null when it cannot tell.
function Get-BorcSettingsStatus {
  param([string] $Path = $env:BORC_SETTINGS)
  if (-not $Path -or -not (Test-Path -LiteralPath (Join-Path $Path '.git'))) { return $null }
  if (-not (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)) { return $null }
  # --no-optional-locks: never block, or be blocked by, Git running elsewhere.
  $lines = @(& git --no-optional-locks -C $Path status --porcelain=v1 --branch 2>$null)
  if ($LASTEXITCODE -ne 0) { return $null }
  $branch = "$($lines | Where-Object { $_ -like '## *' } | Select-Object -First 1)"
  $ahead = if ($branch -match '\[ahead (\d+)') { [int]$Matches[1] } else { 0 }
  # "## main" without "...origin/main" is a branch that was never pushed.
  $unpushed = $branch -notmatch '\.\.\.' -and $branch -notmatch '^## No commits yet'
  [pscustomobject]@{
    Path = $Path
    Changes = @($lines | Where-Object { $_ -and $_ -notlike '## *' }).Count
    Ahead = $ahead
    NoUpstream = $unpushed
  }
}

# One line, only when there is something to commit or push.
function Format-BorcSettingsStatus {
  param($Status)
  if (-not $Status) { return $null }
  $parts = @(
    if ($Status.Changes -gt 0) { "$($Status.Changes) uncommitted $(if ($Status.Changes -eq 1) { 'change' } else { 'changes' })" }
    if ($Status.Ahead -gt 0) { "$($Status.Ahead) $(if ($Status.Ahead -eq 1) { 'commit' } else { 'commits' }) not pushed" }
    if ($Status.NoUpstream) { 'a branch never pushed' }
  )
  if ($parts.Count -eq 0) { return $null }
  "borc: $($parts -join ', ') in $($Status.Path) (git -C $($Status.Path) status)"
}

function Show-BorcSettingsStatus {
  $line = Format-BorcSettingsStatus -Status (Get-BorcSettingsStatus)
  if (-not $line) { return }
  if ($env:NO_COLOR) { Write-Host $line } else { Write-Host $line -ForegroundColor DarkYellow }
}

Show-BorcSettingsStatus
