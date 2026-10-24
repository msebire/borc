# borc upgrade, install and uninstall.

function Invoke-BorcUpgrade {
  param([Parameter(Mandatory)] $Paths)
  Assert-BorcSettings -Paths $Paths
  $plan = Get-BorcPlan -SettingsRoot $Paths.Settings -RecipesRoot $Paths.Recipes
  if ($plan.Errors.Count -gt 0) { Write-BorcPlanErrors -Errors $plan.Errors; return 1 }
  $failed = 0
  foreach ($package in @(Get-BorcListedPackages -Plan $plan)) {
    $code = Invoke-BorcWinget -Arguments (Get-BorcPackageArguments -Verb 'upgrade' -Source $package.Source -Id $package.Id)
    if ($code -eq $script:WingetNoPackageFound) {
      Write-BorcLog -Message "$($package.Id) is not installed; borc apply installs it."
    } elseif ($code -ne 0 -and $code -ne $script:WingetNoApplicableUpgrade) {
      Write-BorcLog -Message "winget could not upgrade $($package.Id), exit code $(Format-BorcExitCode -Code $code)." -Level Error
      $failed++
    }
  }
  if ($failed -gt 0) { return 1 }
  0
}

function Invoke-BorcInstall {
  param([Parameter(Mandatory)] $Paths, [Parameter(Mandatory)] [string] $App)
  Assert-BorcSettings -Paths $Paths
  $kind = Get-BorcAppKind -App $App
  $configPath = Join-Path $Paths.Settings 'borc\borc.yaml'
  $config = ConvertTo-BorcConfig -Text (Read-BorcTextFile -Path $configPath)
  $listed = [bool]($config.Apps | Where-Object { $_.Kind -eq $kind -and $_.Id -eq $App })

  $code = if ($kind -eq 'recipe') { Install-BorcRecipe -Paths $Paths -Id $App -Config $config } else { Install-BorcPlainApp -Kind $kind -Id $App -Listed $listed }
  if ($code -ne 0) { return $code }
  if ($listed) { return 0 }
  Set-BorcConfigText -Path $configPath -Text (Add-BorcAppEntry -Text (Read-BorcTextFile -Path $configPath) -Kind $kind -Id $App)
  Write-BorcLog -Message "Added $App to $configPath. Review the change and commit it when you are ready."
  0
}

function Install-BorcPlainApp {
  param([Parameter(Mandatory)] [string] $Kind, [Parameter(Mandatory)] [string] $Id, [bool] $Listed)
  if ($Kind -eq 'winget' -and -not $Listed -and -not (Test-BorcWingetPackageExists -Id $Id)) {
    Write-BorcLog -Message "winget has no package with the ID $Id. Try borc search." -Level Error
    return 1
  }
  if (Test-BorcPackageInstalled -Id $Id) {
    Write-BorcLog -Message "$Id is already installed."
    return 0
  }
  $code = Invoke-BorcWinget -Arguments (Get-BorcPackageArguments -Verb 'install' -Source $Kind -Id $Id)
  if ($code -ne 0) {
    Write-BorcLog -Message "winget could not install $Id, exit code $(Format-BorcExitCode -Code $code)." -Level Error
    return 1
  }
  0
}

function Install-BorcRecipe {
  param([Parameter(Mandatory)] $Paths, [Parameter(Mandatory)] [string] $Id, [Parameter(Mandatory)] $Config)
  $repoName = ($Id -split '/')[0]
  $repo = $Config.Recipes | Where-Object Name -EQ $repoName
  if ($repo -and -not (Test-Path -LiteralPath (Join-Path $Paths.Recipes $repo.Name))) {
    Sync-BorcRecipeRepo -Url $repo.Url -Path (Join-Path $Paths.Recipes $repo.Name)
  }
  $app = [pscustomobject]@{ Kind = 'recipe'; Id = $Id; Parameters = [ordered]@{} }
  $plan = Get-BorcPlan -SettingsRoot $Paths.Settings -RecipesRoot $Paths.Recipes -ExtraApps @($app)
  if ($plan.Errors.Count -gt 0) { Write-BorcPlanErrors -Errors $plan.Errors; return 1 }

  $recipe = $plan.Recipes[$Id]
  $secrets = [ordered]@{}
  foreach ($name in $recipe.Secrets) { $secrets[$name] = $plan.Config.Secrets[$name] }
  Request-BorcMissingSecrets -Secrets $secrets

  $single = @(New-BorcSingleDocuments -Plan $plan -Ids @($Id))[0]
  if (-not $single.Document) {
    Write-BorcLog -Message "$Id has nothing to run with the parameters borc.yaml gives it."
    return 0
  }
  Invoke-BorcConfigureRun -Document $single.Document -Name ($Id -replace '[^A-Za-z0-9._-]', '_')
}

function Invoke-BorcUninstall {
  param([Parameter(Mandatory)] $Paths, [Parameter(Mandatory)] [string] $App)
  Assert-BorcSettings -Paths $Paths
  $kind = Get-BorcAppKind -App $App
  $configPath = Join-Path $Paths.Settings 'borc\borc.yaml'
  $text = Read-BorcTextFile -Path $configPath

  if ($kind -eq 'recipe') {
    $updated = Remove-BorcAppEntry -Text $text -Kind $kind -Id $App
    if ($null -eq $updated) { Write-BorcLog -Message "$App is not listed in $configPath." -Level Error; return 1 }
    Set-BorcConfigText -Path $configPath -Text $updated
    Write-BorcLog -Message "Removed $App from $configPath. Review the change and commit it when you are ready."
    Show-BorcRecipeLeftovers -Paths $Paths -Id $App
    return 0
  }

  if (Test-BorcPackageInstalled -Id $App) {
    $code = Invoke-BorcWinget -Arguments (Get-BorcPackageArguments -Verb 'uninstall' -Source $kind -Id $App)
    if ($code -ne 0) {
      Write-BorcLog -Message "winget could not uninstall $App, exit code $(Format-BorcExitCode -Code $code). borc.yaml was left as it is." -Level Error
      return 1
    }
  } else {
    Write-BorcLog -Message "$App is not installed."
  }
  $updated = Remove-BorcAppEntry -Text $text -Kind $kind -Id $App
  if ($null -eq $updated) {
    Write-BorcLog -Message "$App is not listed in $configPath; there was no line to remove."
    return 0
  }
  Set-BorcConfigText -Path $configPath -Text $updated
  Write-BorcLog -Message "Removed $App from $configPath. Review the change and commit it when you are ready."
  0
}

# borc does not undo a recipe; it lists what the recipe installed instead.
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
