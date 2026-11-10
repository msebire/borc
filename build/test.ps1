<#
.SYNOPSIS
  Runs PSScriptAnalyzer and every Pester test. Exits non-zero on any failure.
#>
[CmdletBinding()]
param(
  # Runs only the test files whose name contains this text.
  [string] $Filter = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

Import-Module -Name PSScriptAnalyzer -MinimumVersion 1.21.0
Import-Module -Name Pester -MinimumVersion 5.5.0

$failed = $false

Write-Host 'PSScriptAnalyzer' -ForegroundColor Cyan
$analyzed = @('install.ps1', 'src', 'build') | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path $_ }
$findings = @($analyzed | ForEach-Object {
  Invoke-ScriptAnalyzer -Path $_ -Recurse -Settings (Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1')
})
if ($findings.Count -gt 0) {
  $findings | Format-Table -AutoSize -Property Severity, RuleName, ScriptName, Line, Message | Out-String -Width 200 | Write-Host
  $failed = $true
} else {
  Write-Host 'No findings.'
}

Write-Host 'Pester' -ForegroundColor Cyan
$configuration = New-PesterConfiguration
$configuration.Run.Path = Get-ChildItem -Path (Join-Path $root 'tests') -Filter "*$Filter*.Tests.ps1" -File | ForEach-Object FullName
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') {
  $failed = $true
}

if ($failed) {
  Write-Host 'FAILED' -ForegroundColor Red
  exit 1
}
Write-Host 'PASSED' -ForegroundColor Green
exit 0
