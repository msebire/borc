# winget package operations used by the commands. All go through Invoke-BorcWinget.

function Test-BorcPackageInstalled {
  param([Parameter(Mandatory)] [string] $Id)
  $result = Invoke-BorcWingetQuiet -Arguments @('list', '--id', $Id, '--exact', '--accept-source-agreements', '--disable-interactivity')
  $result.ExitCode -eq 0
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
function Get-BorcListedPackages {
  param([Parameter(Mandatory)] $Plan)
  $seen = @{}
  $packages = @(
    foreach ($app in $Plan.Config.Apps) {
      if ($app.Kind -in 'winget', 'msstore') { [pscustomobject]@{ Source = $app.Kind; Id = $app.Id } }
    }
    foreach ($id in $Plan.Order) { Get-BorcRecipePackages -Recipe $Plan.Recipes[$id] }
  )
  foreach ($package in $packages) {
    $key = "$($package.Source)|$($package.Id)".ToLowerInvariant()
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $package
  }
}

# Writes borc.yaml back, keeping a BOM if it had one.
function Set-BorcConfigText {
  param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
  $bytes = [IO.File]::ReadAllBytes($Path)
  $hadBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($hadBom))
}
