# Shared by every test file: loads the module fresh and exposes common paths.
$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:ModulePath = Join-Path $script:RepoRoot 'src\borc\borc.psd1'
$script:FixturesRoot = Join-Path $PSScriptRoot 'fixtures'
# The drive Windows runs from, which every machine has. Tests build every example
# path on it rather than naming a drive, so they never depend on the drives of the
# machine that runs them. Repository.Tests.ps1 checks that no test names one.
$script:SystemDrive = [IO.Path]::GetPathRoot([Environment]::SystemDirectory).TrimEnd('\')

Get-Module -Name borc | Remove-Module -Force
Import-Module -Name $script:ModulePath -Force
# powershell-yaml, from where BORC finds it on this machine. It is loaded before any
# test mocks Get-BorcPaths, which would hide BORC's own modules folder.
InModuleScope borc { Import-BorcYamlModule }

function New-TestFolder {
  $path = Join-Path ([IO.Path]::GetTempPath()) ("borc-test-" + [guid]::NewGuid().ToString('N').Substring(0, 12))
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  $path
}

function Read-TestText {
  param([Parameter(Mandatory)] [string] $Path)
  [IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
}
