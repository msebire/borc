<#
.SYNOPSIS
  Creates a throwaway config repo for the manual checks in REPORT.md.

.DESCRIPTION
  Copies tests/manual/settings to <Path>\settings, makes it a Git repo with one
  commit, and creates <Path>\localappdata. Point BORC_SETTINGS and LOCALAPPDATA
  at them, at process level, so borc's logs and clones stay inside <Path>.
  This is a test helper: borc itself never commits.
#>
param([Parameter(Mandatory)] [string] $Path)

$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Path) { throw "$Path already exists. Remove it or choose another path." }
$settings = Join-Path $Path 'settings'
New-Item -ItemType Directory -Path $Path, (Join-Path $Path 'localappdata') | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'settings') -Destination $settings -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bad-parameter.borc.yaml') -Destination $Path
git init --quiet --initial-branch check $settings
git -C $settings config core.autocrlf false
git -C $settings add -A
git -C $settings -c user.name=borc-check -c user.email=borc-check@example.invalid commit --quiet -m 'Manual check repo'
Write-Host "Created $settings"
