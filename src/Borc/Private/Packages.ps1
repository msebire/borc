# winget package operations used by the commands. All go through Invoke-BorcWinget.

function Test-BorcPackageInstalled {
  param([Parameter(Mandatory)] [string] $Id)
  $result = Invoke-BorcWingetQuiet -Arguments @('list', '--id', $Id, '--exact', '--accept-source-agreements', '--disable-interactivity')
  $result.ExitCode -eq 0
}

# The installed version of a package, or $null when it is not installed.
function Get-BorcInstalledVersion {
  param([Parameter(Mandatory)] [string] $Id)
  $result = Invoke-BorcWingetQuiet -Arguments @('list', '--id', $Id, '--exact', '--accept-source-agreements', '--disable-interactivity')
  if ($result.ExitCode -ne 0) { return $null }
  $version = ConvertFrom-WingetListVersion -Id $Id -Lines $result.Output
  if ($version) { $version } else { 'unknown' }
}

# Installed, missing, or installed in another version than the fixed one.
function Get-BorcPackageState {
  param([Parameter(Mandatory)] [string] $Id, [string] $Version = '')
  if (-not $Version) {
    $installed = Test-BorcPackageInstalled -Id $Id
    return [pscustomobject]@{ Installed = $installed; Matches = $installed; InstalledVersion = $null }
  }
  $current = Get-BorcInstalledVersion -Id $Id
  [pscustomobject]@{ Installed = [bool]$current; Matches = ($current -eq $Version); InstalledVersion = $current }
}

function Test-BorcWingetPackageExists {
  param([Parameter(Mandatory)] [string] $Id)
  $result = Invoke-BorcWingetQuiet -Arguments @('show', '--id', $Id, '--exact', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
  $result.ExitCode -eq 0
}

function Get-BorcPackageArguments {
  param([Parameter(Mandatory)] [string] $Verb, [Parameter(Mandatory)] [string] $Source, [Parameter(Mandatory)] [string] $Id)
  $arguments = @($Verb, '--id', $Id, '--exact', '--source', $Source)
  if ($Verb -eq 'uninstall') { return $arguments + @('--accept-source-agreements', '--disable-interactivity') }
  $arguments + $script:WingetAgreementArguments
}

# Every package borc.yaml lists: plain IDs, then the packages of listed recipes.
# A package listed twice keeps the first entry, but a version fixed by either
# entry wins, so borc upgrade never moves it past that version.
function Get-BorcListedPackages {
  param([Parameter(Mandatory)] $Plan)
  $seen = [ordered]@{}
  $packages = @(
    foreach ($app in $Plan.Config.Apps) {
      if ($app.Kind -in 'winget', 'msstore') { [pscustomobject]@{ Source = $app.Kind; Id = $app.Id; Version = "$($app.Version)"; Origin = 'borc.yaml' } }
    }
    foreach ($id in $Plan.Order) { Get-BorcRecipePackages -Recipe $Plan.Recipes[$id] }
  )
  foreach ($package in $packages) {
    $key = "$($package.Source)|$($package.Id)".ToLowerInvariant()
    if (-not $seen.Contains($key)) { $seen[$key] = $package; continue }
    if ($package.Version -and -not $seen[$key].Version) { $seen[$key] = $package }
  }
  $seen.Values
}

# Writes borc.yaml back, keeping a BOM if it had one.
function Set-BorcConfigText {
  param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
  $bytes = [IO.File]::ReadAllBytes($Path)
  $hadBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($hadBom))
}
