# winget package operations used by the commands. All go through Invoke-BorcWinget.

# One winget list of everything installed, so checking many packages costs one
# call. Only a hit is trusted: a package missing from it (Store apps are often
# listed under another ID) is still asked about on its own.
$script:BorcInstalledList = $null

function Update-BorcInstalledList {
  $result = Invoke-BorcWingetQuiet -Arguments @('list', '--accept-source-agreements', '--disable-interactivity')
  $script:BorcInstalledList = if ($result.ExitCode -eq 0) { @($result.Output) } else { @() }
}

function Clear-BorcInstalledList {
  $script:BorcInstalledList = $null
}

function Get-BorcListedVersion {
  param([Parameter(Mandatory)] [string] $Id)
  if (-not $script:BorcInstalledList) { return $null }
  ConvertFrom-WingetListVersion -Id $Id -Lines $script:BorcInstalledList
}

function Test-BorcPackageInstalled {
  param([Parameter(Mandatory)] [string] $Id)
  if (Get-BorcListedVersion -Id $Id) { return $true }
  $result = Invoke-BorcWingetQuiet -Arguments @('list', '--id', $Id, '--exact', '--accept-source-agreements', '--disable-interactivity')
  $result.ExitCode -eq 0
}

# The installed version of a package, or $null when it is not installed.
function Get-BorcInstalledVersion {
  param([Parameter(Mandatory)] [string] $Id)
  $listed = Get-BorcListedVersion -Id $Id
  if ($listed) { return $listed }
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
