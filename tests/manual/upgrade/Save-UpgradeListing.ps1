<#
.SYNOPSIS
  Saves what winget reports about available upgrades, for manual check V1.

.DESCRIPTION
  Read-only: runs winget list and winget upgrade without an ID, which install
  nothing, and writes each output to <Path>\<name>.txt in UTF-8, as BORC reads it.
  The files list the apps of this machine: copy only the lines a test fixture needs.
#>
param([Parameter(Mandatory)] [string] $Path)

$ErrorActionPreference = 'Stop'
$common = @('--accept-source-agreements', '--disable-interactivity')
$commands = [ordered]@{
  'version' = @('--version')
  'list' = @('list') + $common
  'list-upgrade-available' = @('list', '--upgrade-available') + $common
  'list-upgrade-available-include-unknown' = @('list', '--upgrade-available', '--include-unknown') + $common
  'list-upgrade-available-include-pinned' = @('list', '--upgrade-available', '--include-pinned') + $common
  'upgrade' = @('upgrade') + $common
  'upgrade-include-unknown' = @('upgrade', '--include-unknown') + $common
}
New-Item -ItemType Directory -Path $Path -Force | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$saved = [Console]::OutputEncoding
try {
  [Console]::OutputEncoding = $utf8
  foreach ($name in $commands.Keys) {
    $arguments = $commands[$name]
    $output = & winget @arguments 2>&1 | ForEach-Object { "$_" }
    $text = @("> winget $($arguments -join ' ')", "exit code: $LASTEXITCODE", '') + $output
    [IO.File]::WriteAllText((Join-Path $Path "$name.txt"), (($text -join "`n") + "`n"), $utf8)
  }
} finally {
  [Console]::OutputEncoding = $saved
}
Write-Host "Saved $($commands.Count) files in $Path"
