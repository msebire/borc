# borc upgrade, install and uninstall.

function Invoke-BorcUpgrade {
  param([Parameter(Mandatory)] $Paths)
  Assert-BorcSettings -Paths $Paths
  Start-BorcSteps -Total 2
  Start-BorcStep -Name 'Checking borc.yaml and the recipes'
  $plan = Get-BorcPlan -SettingsRoot $Paths.Settings -RecipesRoot $Paths.Recipes
  if ($plan.Errors.Count -gt 0) { Write-BorcPlanErrors -Errors $plan.Errors; return 1 }
  $listed = @(Get-BorcListedPackages -Plan $plan)
  $fixed = @($listed | Where-Object Version)
  $fixedVersions = Get-BorcPackageVersions -Packages $fixed
  foreach ($package in $fixed) {
    Write-BorcLog -Message (Format-BorcFixedNotice -Package $package -Installed $fixedVersions[$package.Id])
  }
  $fixedDetails = @($fixed | ForEach-Object { Format-BorcFixedDetail -Package $_ -Installed $fixedVersions[$_.Id] })
  $packages = @($listed | Where-Object { -not $_.Version })
  Start-BorcStep -Name "Upgrading $($packages.Count) package(s)"
  $before = Get-BorcPackageVersions -Packages $packages
  $okCodes = @{ $script:WingetNoApplicableUpgrade = 'no upgrade available'; $script:WingetNoPackageFound = 'not installed; borc apply installs it' }
  $failed = [System.Collections.Generic.List[string]]::new()
  $notInstalled = [System.Collections.Generic.List[string]]::new()
  foreach ($package in $packages) {
    $code = Invoke-BorcWinget -Arguments (Get-BorcPackageArguments -Verb 'upgrade' -Source $package.Source -Id $package.Id) -OkCodes $okCodes
    if ($code -eq $script:WingetNoPackageFound) { $notInstalled.Add($package.Id) }
    elseif (-not $okCodes.ContainsKey($code) -and $code -ne 0) {
      Write-BorcLog -Message "winget could not upgrade $($package.Id), exit code $(Format-BorcExitCode -Code $code)." -Level Error
      $failed.Add($package.Id)
    }
  }
  $after = Get-BorcPackageVersions -Packages $packages
  Set-BorcUpgradeResult -Upgraded @(Get-BorcVersionChanges -Before $before -After $after) -Failed @($failed) -NotInstalled @($notInstalled) -Fixed $fixedDetails
  if ($failed.Count -gt 0) { return 1 }
  0
}

# upgrade leaves a fixed package alone, so what is installed may not be that version.
function Format-BorcFixedNotice {
  param([Parameter(Mandatory)] $Package, [string] $Installed)
  if ($Installed -eq $Package.Version) { return "$($Package.Id) stays at $($Package.Version), the version fixed in $($Package.Origin)." }
  $where = if ($Installed) { "is at $Installed" } else { 'is not installed' }
  "$($Package.Id) $where, and $($Package.Origin) fixes it at $($Package.Version). upgrade leaves it alone; borc apply sets that version."
}

function Format-BorcFixedDetail {
  param([Parameter(Mandatory)] $Package, [string] $Installed)
  $text = "$($Package.Id) at $($Package.Version)"
  if ($Installed -eq $Package.Version) { return $text }
  if ($Installed) { return "$text ($Installed installed)" }
  "$text (not installed)"
}

function Set-BorcUpgradeResult {
  param([string[]] $Upgraded = @(), [string[]] $Failed = @(), [string[]] $NotInstalled = @(), [string[]] $Fixed = @())
  $details = [ordered]@{}
  if ($Upgraded.Count -gt 0) { $details['upgraded'] = $Upgraded -join ', ' }
  if ($Failed.Count -gt 0) { $details['failed'] = $Failed -join ', ' }
  if ($NotInstalled.Count -gt 0) { $details['not installed'] = "$($NotInstalled -join ', '); borc apply installs them" }
  if ($Fixed.Count -gt 0) { $details['fixed version'] = $Fixed -join ', ' }
  if ($Failed.Count -gt 0) { Set-BorcResult -Headline "some upgrades failed; winget's errors are shown above." -Details $details -Color Red }
  elseif ($Upgraded.Count -gt 0) { Set-BorcResult -Headline 'done, with changes.' -Details $details -Color Green }
  else { Set-BorcResult -Headline 'done; nothing to upgrade.' -Details $details -Color Green }
}

function Invoke-BorcInstall {
  param([Parameter(Mandatory)] $Paths, [Parameter(Mandatory)] [string] $App)
  Assert-BorcSettings -Paths $Paths
  $kind = Get-BorcAppKind -App $App
  $configPath = Join-Path $Paths.Settings 'borc\borc.yaml'
  $config = ConvertTo-BorcConfig -Text (Read-BorcTextFile -Path $configPath)
  $entry = $config.Apps | Where-Object { $_.Kind -eq $kind -and $_.Id -eq $App } | Select-Object -First 1
  $listed = [bool]$entry

  Start-BorcSteps -Total 3
  $code = if ($kind -eq 'recipe') { Install-BorcRecipe -Paths $Paths -Id $App -Config $config } else { Install-BorcPlainApp -Kind $kind -Id $App -Listed $listed -Version $(if ($entry) { "$($entry.Version)" }) }
  if ($code -ne 0) { return $code }
  Start-BorcStep -Name 'Updating borc.yaml'
  if ($listed) {
    Write-BorcLog -Message "$App is already listed in $configPath."
    $script:BorcResult.Details['borc.yaml'] = 'already listed'
    return 0
  }
  Set-BorcConfigText -Path $configPath -Text (Add-BorcAppEntry -Text (Read-BorcTextFile -Path $configPath) -Kind $kind -Id $App)
  Write-BorcLog -Message "Added $App to $configPath. Review the change and commit it when you are ready."
  $script:BorcResult.Details['borc.yaml'] = 'line added, not committed'
  0
}

function Install-BorcPlainApp {
  param([Parameter(Mandatory)] [string] $Kind, [Parameter(Mandatory)] [string] $Id, [bool] $Listed, [string] $Version = '')
  Start-BorcStep -Name "Checking $Id"
  if ($Kind -eq 'winget' -and -not $Listed -and -not (Test-BorcWingetPackageExists -Id $Id)) {
    Write-BorcLog -Message "winget has no package with the ID $Id. Try borc search." -Level Error
    Set-BorcResult -Headline "nothing was installed: winget has no package with the ID $Id." -Color Red
    return 1
  }
  $state = Get-BorcPackageState -Id $Id -Version $Version
  Start-BorcStep -Name "Installing $Id"
  if ($state.Matches) {
    Write-BorcLog -Message "$Id is already installed$(if ($Version) { " at $Version" })."
    Set-BorcResult -Headline "$Id was already installed." -Color Green
    return 0
  }
  if ($state.Installed) {
    Write-BorcLog -Message "$Id is at $($state.InstalledVersion); borc.yaml fixes it at $Version."
    return Set-BorcFixedVersion -Kind $Kind -Id $Id -Version $Version
  }
  $code = Invoke-BorcWinget -Arguments (Get-BorcPackageArguments -Verb 'install' -Source $Kind -Id $Id -Version $Version)
  if ($code -ne 0) {
    Write-BorcLog -Message "winget could not install $Id, exit code $(Format-BorcExitCode -Code $code)." -Level Error
    # A name with no dot is read as a Store ID, which is rarely what was meant.
    $details = [ordered]@{}
    if ($Kind -eq 'msstore') {
      Write-BorcLog -Message "BORC read $Id as a Microsoft Store ID. A winget ID has a dot, such as Git.Git: find it with borc search $Id."
      $details['tip'] = "BORC read $Id as a Microsoft Store ID; find a winget ID with borc search $Id"
    }
    Set-BorcResult -Headline "$Id was not installed; winget's errors are shown above." -Details $details -Color Red
    return 1
  }
  Set-BorcResult -Headline "installed $Id." -Color Green
  0
}

# Moves an installed package to the fixed version with a configure unit, as
# borc apply does: winget install refuses to go down to an older version.
function Set-BorcFixedVersion {
  param([Parameter(Mandatory)] [string] $Kind, [Parameter(Mandatory)] [string] $Id, [Parameter(Mandatory)] [string] $Version)
  $document = New-BorcDocument -Units @(New-WingetPackageUnit -Source $Kind -Id $Id -Version $Version)
  $code = Invoke-BorcConfigureRun -Document $document -Name ($Id -replace '[^A-Za-z0-9._-]', '_')
  if ($code -eq $script:BorcRestartExitCode) {
    Set-BorcResult -Headline "Windows needs a restart. Restart, then run borc install $Id again." -Color Yellow
    return $code
  }
  if ($code -ne 0) {
    Set-BorcResult -Headline "$Id was not moved to $Version; winget's errors are shown above." -Color Red
    return 1
  }
  Set-BorcResult -Headline "$Id is now at $Version." -Color Green
  0
}

# The recipe and every recipe it requires, directly or not.
function Get-BorcRecipeWithRequired {
  param([Parameter(Mandatory)] $Plan, [Parameter(Mandatory)] [string] $Id, [System.Collections.Generic.HashSet[string]] $Seen = [System.Collections.Generic.HashSet[string]]::new())
  if (-not $Seen.Add($Id)) { return }
  $Id
  foreach ($required in $Plan.Recipes[$Id].Requires) { Get-BorcRecipeWithRequired -Plan $Plan -Id $required -Seen $Seen }
}

function Install-BorcRecipe {
  param([Parameter(Mandatory)] $Paths, [Parameter(Mandatory)] [string] $Id, [Parameter(Mandatory)] $Config)
  Start-BorcStep -Name "Checking $Id and its secrets"
  $repoName = ($Id -split '/')[0]
  $repo = $Config.Recipes | Where-Object Name -EQ $repoName
  if ($repo -and -not (Test-Path -LiteralPath (Join-Path $Paths.Recipes $repo.Name))) {
    Sync-BorcRecipeRepo -Url $repo.Url -Path (Join-Path $Paths.Recipes $repo.Name)
  }
  $app = [pscustomobject]@{ Kind = 'recipe'; Id = $Id; Parameters = [ordered]@{} }
  $plan = Get-BorcPlan -SettingsRoot $Paths.Settings -RecipesRoot $Paths.Recipes -ExtraApps @($app)
  if ($plan.Errors.Count -gt 0) { Write-BorcPlanErrors -Errors $plan.Errors; return 1 }

  $ids = @(Get-BorcRecipeWithRequired -Plan $plan -Id $Id)
  $secrets = [ordered]@{}
  foreach ($recipeId in $ids) {
    foreach ($name in $plan.Recipes[$recipeId].Secrets) { $secrets[$name] = $plan.Config.Secrets[$name] }
  }
  $null = Request-BorcMissingSecrets -Secrets $secrets

  Start-BorcStep -Name "Installing $Id"
  # New-BorcSingleDocuments keeps the plan's order, so required recipes run first.
  foreach ($single in @(New-BorcSingleDocuments -Plan $plan -Ids $ids)) {
    if (-not $single.Document) {
      Write-BorcLog -Message "$($single.Name) has nothing to run with the parameters borc.yaml gives it."
      continue
    }
    if ($single.Name -ne $Id) { Write-BorcLog -Message "Running $($single.Name) first: $Id requires it." }
    $code = Invoke-BorcConfigureRun -Document $single.Document -Name ($single.Name -replace '[^A-Za-z0-9._-]', '_')
    if ($code -eq $script:BorcRestartExitCode) {
      Set-BorcResult -Headline "Windows needs a restart. Restart, then run borc install $Id again." -Color Yellow
      return $code
    }
    if ($code -ne 0) {
      Set-BorcResult -Headline "$($single.Name) failed; winget's errors are shown above." -Color Red
      return $code
    }
  }
  $details = [ordered]@{ recipe = 'winget does not say which of its settings changed' }
  $required = @($ids | Where-Object { $_ -ne $Id })
  if ($required.Count -gt 0) { $details['also ran'] = $required -join ', ' }
  Set-BorcResult -Headline "ran $Id." -Details $details -Color Green
  0
}

function Invoke-BorcUninstall {
  param([Parameter(Mandatory)] $Paths, [Parameter(Mandatory)] [string] $App)
  Assert-BorcSettings -Paths $Paths
  $kind = Get-BorcAppKind -App $App
  $configPath = Join-Path $Paths.Settings 'borc\borc.yaml'
  $text = Read-BorcTextFile -Path $configPath
  Start-BorcSteps -Total 2

  if ($kind -eq 'recipe') {
    Start-BorcStep -Name 'Updating borc.yaml'
    $updated = Remove-BorcAppEntry -Text $text -Kind $kind -Id $App
    if ($null -eq $updated) {
      Write-BorcLog -Message "$App is not listed in $configPath." -Level Error
      Set-BorcResult -Headline "nothing changed: $App is not listed in borc.yaml." -Color Red
      return 1
    }
    Set-BorcConfigText -Path $configPath -Text $updated
    Write-BorcLog -Message "Removed $App from $configPath. Review the change and commit it when you are ready."
    Start-BorcStep -Name 'Packages the recipe installed'
    Show-BorcRecipeLeftovers -Paths $Paths -Id $App
    Set-BorcResult -Headline "removed $App from borc.yaml." -Details ([ordered]@{ 'borc.yaml' = 'line removed, not committed'; 'left in place' = 'everything the recipe set up' }) -Color Green
    return 0
  }

  Start-BorcStep -Name "Uninstalling $App"
  $headline = "$App was not installed."
  if (Test-BorcPackageInstalled -Id $App) {
    $code = Invoke-BorcWinget -Arguments (Get-BorcPackageArguments -Verb 'uninstall' -Source $kind -Id $App)
    if ($code -ne 0) {
      Write-BorcLog -Message "winget could not uninstall $App, exit code $(Format-BorcExitCode -Code $code). borc.yaml was left as it is." -Level Error
      Set-BorcResult -Headline "$App was not uninstalled; winget's errors are shown above." -Details ([ordered]@{ 'borc.yaml' = 'left as it is' }) -Color Red
      return 1
    }
    $headline = "uninstalled $App."
  } else {
    Write-BorcLog -Message "$App is not installed."
  }
  Start-BorcStep -Name 'Updating borc.yaml'
  $updated = Remove-BorcAppEntry -Text $text -Kind $kind -Id $App
  if ($null -eq $updated) {
    Write-BorcLog -Message "$App is not listed in $configPath; there was no line to remove."
    Set-BorcResult -Headline $headline -Details ([ordered]@{ 'borc.yaml' = 'no line to remove' }) -Color Green
    return 0
  }
  Set-BorcConfigText -Path $configPath -Text $updated
  Write-BorcLog -Message "Removed $App from $configPath. Review the change and commit it when you are ready."
  Set-BorcResult -Headline $headline -Details ([ordered]@{ 'borc.yaml' = 'line removed, not committed' }) -Color Green
  0
}

# BORC does not undo a recipe; it lists what the recipe installed instead.
function Show-BorcRecipeLeftovers {
  param([Parameter(Mandatory)] $Paths, [Parameter(Mandatory)] [string] $Id)
  $path = Resolve-BorcRecipePath -Id $Id -RecipesRoot $Paths.Recipes -SettingsRoot $Paths.Settings
  $text = Read-BorcTextFile -Path $path
  if ($null -eq $text) { return }
  $packages = @(Get-BorcRecipePackages -Recipe (ConvertTo-BorcRecipe -Text $text -Id $Id))
  if ($packages.Count -eq 0) {
    Write-BorcLog -Message 'The recipe installed no winget package. Anything else it set up stays in place.'
    return
  }
  Write-BorcLog -Message 'The recipe installed these winget packages, which stay installed. Anything else it set up stays in place too:'
  foreach ($package in $packages) { Write-BorcLog -Message "  borc uninstall $($package.Id)" }
}
