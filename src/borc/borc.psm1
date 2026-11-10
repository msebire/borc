$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1.0
$script:BorcModuleRoot = $PSScriptRoot

$sourceFiles = @(
  Get-Item -Path (Join-Path $PSScriptRoot 'Constants.ps1'), (Join-Path $PSScriptRoot 'WingetRules.ps1'), (Join-Path $PSScriptRoot 'Get-BorcSecret.ps1')
  Get-ChildItem -Path (Join-Path $PSScriptRoot 'private'), (Join-Path $PSScriptRoot 'commands') -Filter '*.ps1' -File -Recurse | Sort-Object FullName
)
foreach ($sourceFile in $sourceFiles) {
  . $sourceFile.FullName
}

Export-ModuleMember -Function Invoke-Borc, Invoke-BorcSetup, Get-BorcSecret
