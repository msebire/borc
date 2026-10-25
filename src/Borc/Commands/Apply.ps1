$script:BorcRestartExitCode = 3010

function Invoke-BorcApply {
  param([Parameter(Mandatory)] $Paths, [switch] $Preview, [switch] $Check, [switch] $OneByOne)
  Assert-BorcSettings -Paths $Paths
  if ($Preview) { return Invoke-BorcApplyPreview -Paths $Paths -Check:$Check }

  Start-BorcSteps -Total 5
  Start-BorcStep -Name "Pulling the config repo ($($Paths.Settings))"
  Sync-BorcConfigRepo -Path $Paths.Settings
  Start-BorcStep -Name 'Pulling recipe repos'
  Sync-BorcRecipeRepos -Paths $Paths
  Show-BorcUpdateNotice -Paths $Paths

  Start-BorcStep -Name 'Checking borc.yaml and the recipes'
  $plan = Get-BorcPlan -SettingsRoot $Paths.Settings -RecipesRoot $Paths.Recipes
  if ($plan.Errors.Count -gt 0) { Write-BorcPlanErrors -Errors $plan.Errors; return 1 }
  Write-BorcPlanCounts -Plan $plan
  Start-BorcStep -Name 'Secrets'
  Request-BorcMissingSecrets -Secrets $plan.Config.Secrets

  Start-BorcStep -Name 'Applying the configuration'
  if ($OneByOne) { return Invoke-BorcRunsOneByOne -Plan $plan }
  Invoke-BorcRuns -Plan $plan
}

function Write-BorcPlanCounts {
  param([Parameter(Mandatory)] $Plan)
  $plain = @($Plan.Config.Apps | Where-Object Kind -NE 'recipe').Count
  Write-BorcLog -Message "No problem found: $plain plain app(s) and $($Plan.Order.Count) recipe(s)."
}

function Sync-BorcRecipeRepos {
  param([Parameter(Mandatory)] $Paths)
  $text = Read-BorcTextFile -Path (Join-Path $Paths.Settings 'borc\borc.yaml')
  $config = ConvertTo-BorcConfig -Text $text
  if ($config.Recipes.Count -eq 0) { Write-BorcLog -Message 'borc.yaml lists no recipe repo.' }
  foreach ($repo in $config.Recipes) {
    Sync-BorcRecipeRepo -Url $repo.Url -Path (Join-Path $Paths.Recipes $repo.Name)
  }
}

function Invoke-BorcRuns {
  param([Parameter(Mandatory)] $Plan)
  $runs = New-BorcRunDocuments -Plan $Plan
  foreach ($message in $runs.Dropped) { Write-BorcLog -Message $message }
  if (-not $runs.Reboot -and -not $runs.Main) {
    Write-BorcLog -Message 'borc.yaml lists nothing to apply.'
    return 0
  }
  $kinds = @(
    @{ Name = 'reboot'; Document = $runs.Reboot; Label = 'Reboot run, recipes that may need a restart' }
    @{ Name = 'main'; Document = $runs.Main; Label = 'Main run' }
  )
  foreach ($run in $kinds) {
    if (-not $run.Document) { continue }
    Write-BorcLog -Message "$($run.Label): $($run.Document['resources'].Count) unit(s)."
    $code = Invoke-BorcConfigureRun -Document $run.Document -Name $run.Name
    if ($code -ne 0) { return $code }
  }
  Write-BorcLog -Message 'borc apply is done.'
  0
}

function Invoke-BorcRunsOneByOne {
  param([Parameter(Mandatory)] $Plan)
  foreach ($single in @(New-BorcSingleDocuments -Plan $Plan -IncludePackages)) {
    if (-not $single.Document) { continue }
    Write-BorcLog -Message "Running $($single.Name) on its own."
    $code = Invoke-BorcConfigureRun -Document $single.Document -Name ($single.Name -replace '[^A-Za-z0-9._-]', '_')
    if ($code -ne 0) {
      if ($code -ne $script:BorcRestartExitCode) { Write-BorcLog -Message "The failing recipe is $($single.Name)." -Level Error }
      return $code
    }
  }
  Write-BorcLog -Message 'borc apply is done.'
  0
}

# Runs one winget configure. Returns 0, winget's failure code, or 3010 when the
# run left Windows waiting for a restart.
function Invoke-BorcConfigureRun {
  param([Parameter(Mandatory)] $Document, [Parameter(Mandatory)] [string] $Name)
  $path = Get-BorcRunFilePath -Suffix "$Name.winget.yaml"
  Write-BorcDocument -Document $Document -Path $path
  $restartBefore = Test-BorcRestartPending
  $code = Invoke-BorcWinget -Arguments (@('configure', '--file', $path) + $script:WingetConfigureArguments)
  if ($code -ne 0) {
    Write-BorcLog -Message "winget configure reported a failure, exit code $(Format-BorcExitCode -Code $code). Its errors are shown above." -Level Error
    return 1
  }
  if (-not $restartBefore -and (Test-BorcRestartPending)) {
    Write-BorcLog -Message 'Windows needs a restart. Restart, then run borc apply again.' -Level Warning
    return $script:BorcRestartExitCode
  }
  0
}

# Compares the engine with the latest commit of the branch it is on: main, or
# the branch a maintainer installed with BORC_BRANCH.
function Show-BorcUpdateNotice {
  param([Parameter(Mandatory)] $Paths)
  try {
    if (-not (Test-BorcGitRepo -Path $Paths.Engine)) { return }
    $branch = Get-BorcCurrentBranch -Path $Paths.Engine
    if (-not $branch) { $branch = $script:BorcBranch }
    $local = (Invoke-BorcGit -Arguments @('-C', $Paths.Engine, 'rev-parse', 'HEAD') -Quiet).Output | Select-Object -First 1
    $remote = Invoke-BorcGit -Arguments @('ls-remote', $script:BorcRepoUrl, "refs/heads/$branch") -Quiet
    if ($remote.ExitCode -ne 0) { return }
    $latest = (($remote.Output | Select-Object -First 1) -split '\s+')[0]
    if ($latest -and $local -and $latest -ne $local) {
      $what = if ($branch -eq $script:BorcBranch) { 'A newer borc is available' } else { "The borc branch $branch has newer commits" }
      Write-BorcLog -Message "$what. Run borc self-update."
    }
  } catch {
    Write-BorcLog -Message "Update check skipped: $($_.Exception.Message)" -LogOnly
  }
}
