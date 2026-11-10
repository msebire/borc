$script:BorcRestartExitCode = 3010

function Invoke-BorcApply {
  param([Parameter(Mandatory)] $Paths, [switch] $Preview, [switch] $Check, [switch] $OneByOne, [switch] $NoPull)
  Assert-BorcSettings -Paths $Paths
  if ($Preview) { return Invoke-BorcApplyPreview -Paths $Paths -Check:$Check -NoPull:$NoPull }

  Start-BorcSteps -Total 5
  $heads = Get-BorcRepoHeads -Paths $Paths
  $updateNotice = $null
  if ($NoPull) {
    Start-BorcStep -Name "Using the config repo as it is ($($Paths.Settings), --no-pull)"
    Write-BorcLog -Message 'Not pulling: BORC applies the working copy, uncommitted changes included.'
    Start-BorcStep -Name 'Using the recipe repos as they are (--no-pull)'
    Sync-BorcRecipeRepos -Paths $Paths -MissingOnly
  } else {
    Start-BorcStep -Name "Pulling the config repo ($($Paths.Settings))"
    try {
      Sync-BorcConfigRepo -Path $Paths.Settings
      Start-BorcStep -Name 'Pulling recipe repos'
      Sync-BorcRecipeRepos -Paths $Paths
    } catch {
      Add-BorcNoPullTip
      throw
    }
    $updateNotice = Show-BorcUpdateNotice -Paths $Paths
  }
  $pulls = Get-BorcPulls -Before $heads -After (Get-BorcRepoHeads -Paths $Paths)

  Start-BorcStep -Name 'Checking borc.yaml and the recipes'
  $plan = Get-BorcPlan -SettingsRoot $Paths.Settings -RecipesRoot $Paths.Recipes
  if ($plan.Errors.Count -gt 0) { Write-BorcPlanErrors -Errors $plan.Errors; return 1 }
  Write-BorcPlanCounts -Plan $plan
  Start-BorcStep -Name 'Secrets'
  $stored = @(Request-BorcMissingSecrets -Secrets $plan.Config.Secrets)

  Start-BorcStep -Name 'Applying the configuration'
  $packages = @(Get-BorcListedPackages -Plan $plan)
  $before = Get-BorcPackageVersions -Packages $packages
  $code = if ($OneByOne) { Invoke-BorcRunsOneByOne -Plan $plan } else { Invoke-BorcRuns -Plan $plan }
  $after = Get-BorcPackageVersions -Packages $packages
  Set-BorcApplyResult -ExitCode $code -Pulls $pulls -Before $before -After $after -Recipes $plan.Order.Count -Secrets $stored -NoPull:$NoPull
  if ($updateNotice) { $script:BorcResult.Details['update'] = $updateNotice }
  $code
}

# When the pull is refused or fails, the result points at --no-pull, which
# applies the working copy as it is.
function Add-BorcNoPullTip {
  $tip = 'borc apply --no-pull applies your working copy as it is, without pulling'
  if (-not $script:BorcResult) {
    Set-BorcResult -Headline 'nothing was applied: the pull failed (see the git error above).' -Color Red
  }
  $script:BorcResult.Details['tip'] = $tip
}

# The commit each repo is at: the config repo and every recipe clone.
function Get-BorcRepoHeads {
  param([Parameter(Mandatory)] $Paths)
  $heads = [ordered]@{ 'config repo' = [pscustomobject]@{ Path = $Paths.Settings; Head = Get-BorcHead -Path $Paths.Settings } }
  $config = ConvertTo-BorcConfig -Text (Read-BorcTextFile -Path (Join-Path $Paths.Settings 'borc\borc.yaml'))
  foreach ($repo in $config.Recipes) {
    $clone = Join-Path $Paths.Recipes $repo.Name
    $head = if (Test-BorcGitRepo -Path $clone) { Get-BorcHead -Path $clone } else { $null }
    $heads["recipe repo $($repo.Name)"] = [pscustomobject]@{ Path = $clone; Head = $head }
  }
  $heads
}

function Get-BorcHead {
  param([Parameter(Mandatory)] [string] $Path)
  $result = Invoke-BorcGit -Arguments @('-C', $Path, 'rev-parse', 'HEAD') -Quiet
  if ($result.ExitCode -ne 0) { return $null }
  $result.Output | Select-Object -First 1
}

# What the pulls brought, per repo: "2 commits pulled" or "cloned".
function Get-BorcPulls {
  param([System.Collections.IDictionary] $Before, [System.Collections.IDictionary] $After)
  $pulls = [ordered]@{}
  foreach ($repo in $After.Keys) {
    $old = if ($Before.Contains($repo)) { $Before[$repo].Head } else { $null }
    $new = $After[$repo].Head
    if (-not $new -or $old -eq $new) { continue }
    if (-not $old) { $pulls[$repo] = 'cloned'; continue }
    $count = (Invoke-BorcGit -Arguments @('-C', $After[$repo].Path, 'rev-list', '--count', "$old..$new") -Quiet).Output | Select-Object -First 1
    $pulls[$repo] = "$count $(if ($count -eq '1') { 'commit' } else { 'commits' }) pulled"
  }
  $pulls
}

# Installed version of each package (or $null), from one winget list call.
function Get-BorcPackageVersions {
  param([object[]] $Packages = @())
  $versions = [ordered]@{}
  if ($Packages.Count -eq 0) { return $versions }
  Update-BorcInstalledList
  foreach ($package in $Packages) { $versions[$package.Id] = Get-BorcInstalledVersion -Id $package.Id }
  Clear-BorcInstalledList
  $versions
}

# Packages installed both before and after, at another version: "Id (1 -> 2)".
function Get-BorcVersionChanges {
  param([System.Collections.IDictionary] $Before, [System.Collections.IDictionary] $After)
  $After.Keys | Where-Object { $After[$_] -and $Before[$_] -and $After[$_] -ne $Before[$_] } | ForEach-Object { "$_ ($($Before[$_]) -> $($After[$_]))" }
}

# What apply did, as far as BORC can know: winget prints "Unit successfully
# applied." whether a unit changed or was already in place, so recipe settings
# are reported as run, not as changed.
function Set-BorcApplyResult {
  param(
    [int] $ExitCode,
    [System.Collections.IDictionary] $Pulls,
    [System.Collections.IDictionary] $Before,
    [System.Collections.IDictionary] $After,
    [int] $Recipes,
    [string[]] $Secrets = @(),
    [switch] $NoPull
  )
  $installed = @($After.Keys | Where-Object { $After[$_] -and -not $Before[$_] })
  $upgraded = @(Get-BorcVersionChanges -Before $Before -After $After)
  $details = [ordered]@{}
  $pulledText = @($Pulls.Keys | ForEach-Object { "$_ $($Pulls[$_])" }) -join ', '
  $details['pulled'] = if ($NoPull) { (@($pulledText) + 'skipped (--no-pull)' | Where-Object { $_ }) -join '; ' } elseif ($pulledText) { $pulledText } else { 'nothing new' }
  $details['installed'] = if ($installed.Count -gt 0) { $installed -join ', ' } else { 'nothing new' }
  if ($upgraded.Count -gt 0) { $details['version changed'] = $upgraded -join ', ' }
  if ($Recipes -gt 0) { $details['recipes'] = Format-BorcRecipesDetail -Recipes $Recipes -ExitCode $ExitCode }
  if ($Secrets.Count -gt 0) { $details['secrets'] = "stored $($Secrets -join ', ')" }
  $changed = $Pulls.Count -gt 0 -or $installed.Count -gt 0 -or $upgraded.Count -gt 0 -or $Secrets.Count -gt 0
  switch ($ExitCode) {
    0 {
      if ($changed) { Set-BorcResult -Headline 'done, with changes.' -Details $details -Color Green }
      else { Set-BorcResult -Headline 'done; nothing new was pulled or installed.' -Details $details -Color Green }
    }
    $script:BorcRestartExitCode { Set-BorcResult -Headline 'Windows needs a restart. Restart, then run borc apply again.' -Details $details -Color Yellow }
    default { Set-BorcResult -Headline 'winget reported a failure; its errors are shown above.' -Details $details -Color Red }
  }
}

# "run" only when the whole run finished: a failure or a restart can leave some not run.
function Format-BorcRecipesDetail {
  param([int] $Recipes, [int] $ExitCode)
  if ($ExitCode -eq 0) { return "$Recipes run; winget does not say which of their settings changed" }
  if ($ExitCode -eq $script:BorcRestartExitCode) { return "$Recipes listed; those not run yet run after the restart" }
  "$Recipes listed; winget's errors above say which units failed"
}

function Write-BorcPlanCounts {
  param([Parameter(Mandatory)] $Plan)
  $plain = @($Plan.Config.Apps | Where-Object Kind -NE 'recipe').Count
  Write-BorcLog -Message "No problem found: $plain plain app(s) and $($Plan.Order.Count) recipe(s)."
}

function Sync-BorcRecipeRepos {
  param([Parameter(Mandatory)] $Paths, [switch] $MissingOnly)
  $text = Read-BorcTextFile -Path (Join-Path $Paths.Settings 'borc\borc.yaml')
  $config = ConvertTo-BorcConfig -Text $text
  if ($config.Recipes.Count -eq 0) { Write-BorcLog -Message 'borc.yaml lists no recipe repo.' }
  foreach ($repo in $config.Recipes) {
    $clone = Join-Path $Paths.Recipes $repo.Name
    # --no-pull still clones a missing repo: its recipes could not run otherwise.
    if ($MissingOnly -and (Test-BorcGitRepo -Path $clone)) { Write-BorcLog -Message "recipe repo $($repo.Name): used as it is."; continue }
    Sync-BorcRecipeRepo -Url $repo.Url -Path $clone
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
    $isPackages = $single.Name -eq $script:BorcPlainPackagesName
    Write-BorcLog -Message $(if ($isPackages) { 'Running the plain packages.' } else { "Running $($single.Name) on its own." })
    $code = Invoke-BorcConfigureRun -Document $single.Document -Name ($single.Name -replace '[^A-Za-z0-9._-]', '_')
    if ($code -ne 0) {
      if ($code -ne $script:BorcRestartExitCode) {
        Write-BorcLog -Message $(if ($isPackages) { "One of the plain packages failed; winget's errors above name it." } else { "The failing recipe is $($single.Name)." }) -Level Error
      }
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
    Write-BorcVcRuntimeHint
    Write-BorcWingetVersionHint
    return 1
  }
  if (-not $restartBefore -and (Test-BorcRestartPending)) {
    Write-BorcLog -Message 'Windows needs a restart. Restart, then run borc apply again.' -Level Warning
    return $script:BorcRestartExitCode
  }
  0
}

# Without this runtime, winget only reports an internal error with a number. The
# installer installs it; a machine can still lose it, or have been set up before.
function Write-BorcVcRuntimeHint {
  if (Test-BorcVcRuntime) { return }
  Write-BorcLog -Message "Windows has no $script:BorcVcRuntimeFile, which winget configure needs for elevated units. To install it, run: winget install --id $(Get-BorcVcRedistId)"
}

# The installer takes the latest winget, and a new one may read configuration
# files differently. Only said after a failure: on every run it would be noise,
# and it would stay there for good once winget moves on. The minor version is
# what matters, as winget changes its build number with every release.
function Write-BorcWingetVersionHint {
  $result = Invoke-BorcWingetQuiet -Arguments @('--version')
  if ($result.ExitCode -ne 0 -or "$($result.Output)" -notmatch '(\d+)\.(\d+)\.(\d+)') { return }
  $version = [version]$Matches[0]
  Write-BorcLog -Message "winget version: $version." -LogOnly
  $verified = $script:WingetVerifiedVersion
  if ($version.Major -eq $verified.Major -and $version.Minor -eq $verified.Minor) { return }
  Write-BorcLog -Message "This is winget $version, and BORC's configuration files were verified with winget $verified. If the error is about the file itself, see `"winget rejects a configuration file`" in the troubleshooting page."
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
      $what = if ($branch -eq $script:BorcBranch) { 'A newer BORC is available' } else { "The BORC branch $branch has changed" }
      Write-BorcLog -Message "$what. Run borc self-update."
      "$what. Run borc self-update."
    }
  } catch {
    Write-BorcLog -Message "Update check skipped: $($_.Exception.Message)" -LogOnly
  }
}
