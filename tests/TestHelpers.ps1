# Shared by every test file: loads the module fresh and exposes common paths.
$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:ModulePath = Join-Path $script:RepoRoot 'src\Borc\Borc.psd1'
$script:FixturesRoot = Join-Path $PSScriptRoot 'fixtures'

Get-Module -Name Borc | Remove-Module -Force
Import-Module -Name $script:ModulePath -Force

function New-TestFolder {
  $path = Join-Path ([IO.Path]::GetTempPath()) ("borc-test-" + [guid]::NewGuid().ToString('N').Substring(0, 12))
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  $path
}

function Read-TestText {
  param([Parameter(Mandatory)] [string] $Path)
  [IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
}
