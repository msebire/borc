# borc upgrade --what-if: which listed packages have an update, from what winget
# lists, without running any recipe code. Changes nothing.

function Invoke-BorcUpgradePreview {
  param([Parameter(Mandatory)] $Paths, [string] $App = '')
  Assert-BorcSettings -Paths $Paths
  Start-BorcSteps -Total 3
  Start-BorcStep -Name 'Checking borc.yaml and the recipes'
  $plan = Get-BorcPlan -SettingsRoot $Paths.Settings -RecipesRoot $Paths.Recipes
  if ($plan.Errors.Count -gt 0) { Write-BorcPlanErrors -Errors $plan.Errors; return 1 }
  $packages = @(Get-BorcListedPackages -Plan $plan)
  if ($App) {
    $target = Select-BorcUpgradeTarget -Plan $plan -Packages $packages -App $App
    if (-not $target.Listed) { return Write-BorcNotListed -App $App -Headline 'nothing was checked' }
    $packages = @($target.Packages)
    if ($target.Recipe -and $packages.Count -eq 0) { Write-BorcLog -Message "$App has nothing borc upgrade can upgrade." }
  }

  Start-BorcStep -Name 'Asking winget which packages have an update'
  $updates = if ($packages.Count -gt 0) { Get-BorcAvailableUpdates } else { [ordered]@{} }
  if ($null -eq $updates) {
    Set-BorcResult -Headline "nothing was checked: BORC could not read winget's list of updates, shown in the log." -Color Red
    return 1
  }

  Start-BorcStep -Name 'What borc upgrade would upgrade'
  Update-BorcInstalledList
  $rows = @(foreach ($package in $packages) { Get-BorcUpgradeVerdict -Package $package -Updates $updates })
  Clear-BorcInstalledList
  Show-BorcUpgradeRows -Rows $rows
  Write-BorcLog -Message 'Nothing was changed (--what-if).'
  Set-BorcUpgradePreviewResult -Rows $rows
  0
}

# One winget list --upgrade-available, framed like any command: ID -> available
# version, or $null when winget failed or printed something BORC cannot read.
function Get-BorcAvailableUpdates {
  $started = Get-Date
  Write-BorcCommandStart -Command "winget $($script:WingetUpgradeListArguments -join ' ')"
  $list = Invoke-BorcWingetQuiet -Arguments $script:WingetUpgradeListArguments
  foreach ($line in $list.Output) { Add-BorcLogLine -Line "  |   $line" }
  $updates = ConvertFrom-WingetUpgradeList -Lines $list.Output
  $okCodes = if ($null -ne $updates) { @{ $list.ExitCode = "$($updates.Count) update(s) listed" } } else { @{} }
  Write-BorcCommandEnd -ExitCode $list.ExitCode -Duration ((Get-Date) - $started) -OkCodes $okCodes
  if ($null -eq $updates) {
    Write-BorcLog -Message "winget's list of updates is not in a form BORC knows, so nothing can be said about updates." -Level Error
  }
  $updates
}

# The available version winget lists for an ID, also when it cut the ID short
# with an ellipsis to fit its table.
function Find-BorcAvailableUpdate {
  param([Parameter(Mandatory)] [System.Collections.IDictionary] $Updates, [Parameter(Mandatory)] [string] $Id)
  if ($Updates.Contains($Id)) { return $Updates[$Id] }
  $ellipsis = [string][char]0x2026
  foreach ($listed in $Updates.Keys) {
    if ($listed.EndsWith($ellipsis) -and $Id.StartsWith($listed.TrimEnd([char]0x2026), [StringComparison]::OrdinalIgnoreCase)) { return $Updates[$listed] }
  }
  $null
}

# One row: update available, up to date, fixed version, not installed or unknown.
function Get-BorcUpgradeVerdict {
  param([Parameter(Mandatory)] $Package, [Parameter(Mandatory)] [System.Collections.IDictionary] $Updates)
  $installed = Get-BorcInstalledVersion -Id $Package.Id
  $available = Find-BorcAvailableUpdate -Updates $Updates -Id $Package.Id
  $state, $detail = if (-not $installed) { 'not installed', 'borc apply installs it' }
  elseif ($Package.Version) {
    $newer = if ($available) { "; $available available" } else { '' }
    'fixed version', "$installed installed, $($Package.Origin) fixes it at $($Package.Version)$newer"
  }
  elseif ($available) { 'update available', "$installed -> $available" }
  elseif ($installed -eq 'unknown') { 'unknown', 'winget does not know the installed version' }
  elseif ($Package.Source -eq 'msstore' -and -not (Test-BorcStoreVersionKnown -Id $Package.Id)) { 'unknown', "$installed installed; the Store gives no version, so winget cannot tell" }
  else { 'up to date', $installed }
  [pscustomobject]@{ State = $state; Id = $Package.Id; Detail = $detail }
}

# Whether the Store gives a version for an app, without which winget never lists
# an update for it.
function Test-BorcStoreVersionKnown {
  param([Parameter(Mandatory)] [string] $Id)
  $show = Invoke-BorcWingetQuiet -Arguments @('show', '--id', $Id, '--exact', '--source', 'msstore', '--accept-source-agreements', '--disable-interactivity')
  if ($show.ExitCode -ne 0) { return $false }
  foreach ($line in $show.Output) {
    if ("$line".Trim() -match $script:WingetShowVersionPattern) { return $Matches['version'] -ne 'Unknown' }
  }
  $false
}

function Show-BorcUpgradeRows {
  param([object[]] $Rows = @())
  if ($Rows.Count -eq 0) { Write-BorcLog -Message '  No winget package to check.'; return }
  $width = ($Rows | ForEach-Object { $_.Id.Length } | Measure-Object -Maximum).Maximum
  $colors = @{ 'update available' = 'Yellow'; 'up to date' = 'Green' }
  foreach ($row in $Rows) {
    Write-BorcPreviewLine -Text ('  {0,-16}  {1}  {2}' -f $row.State, $row.Id.PadRight($width), $row.Detail) -Color $colors[$row.State]
  }
  Write-BorcPreviewLine -Text ''
  Write-BorcPreviewLine -Text "  $(Format-BorcUpgradeCounts -Rows $Rows)."
}

function Format-BorcUpgradeCounts {
  param([object[]] $Rows = @())
  $count = @{}
  foreach ($row in $Rows) { $count[$row.State] = [int]$count[$row.State] + 1 }
  $updates = [int]$count['update available']
  "$updates $(if ($updates -eq 1) { 'update' } else { 'updates' }) available, $([int]$count['up to date']) up to date, $([int]$count['fixed version']) fixed, $([int]$count['not installed']) not installed, $([int]$count['unknown']) unknown"
}

# The answer to "would borc upgrade change anything?".
function Set-BorcUpgradePreviewResult {
  param([object[]] $Rows = @())
  $details = [ordered]@{}
  $groups = [ordered]@{ 'updates' = 'update available'; 'fixed version' = 'fixed version'; 'not installed' = 'not installed'; 'unknown' = 'unknown' }
  foreach ($label in $groups.Keys) {
    $matched = @($Rows | Where-Object State -EQ $groups[$label])
    if ($matched.Count -gt 0) { $details[$label] = ($matched | ForEach-Object { "$($_.Id) ($($_.Detail))" }) -join ', ' }
  }
  $details['counts'] = Format-BorcUpgradeCounts -Rows $Rows
  $updates = @($Rows | Where-Object State -EQ 'update available').Count
  $unknown = @($Rows | Where-Object State -EQ 'unknown').Count
  if ($updates -gt 0) { Set-BorcResult -Headline "borc upgrade would upgrade $updates $(if ($updates -eq 1) { 'package' } else { 'packages' })." -Details $details -Color Yellow }
  elseif ($unknown -gt 0) { Set-BorcResult -Headline "probably nothing to upgrade; $unknown could not be checked." -Details $details }
  else { Set-BorcResult -Headline 'nothing to upgrade.' -Details $details -Color Green }
}
