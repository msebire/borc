# borc upgrade --what-if: which listed packages have an update, from what winget
# lists, and which recipes have upgrade units. Runs no recipe code unless --check
# tests those units. Changes nothing.

function Invoke-BorcUpgradePreview {
  param([Parameter(Mandatory)] $Paths, [string] $App = '', [switch] $Check)
  Assert-BorcSettings -Paths $Paths
  Start-BorcSteps -Total $(if ($Check) { 4 } else { 3 })
  Start-BorcStep -Name 'Checking borc.yaml and the recipes'
  $plan = Get-BorcPlan -SettingsRoot $Paths.Settings -RecipesRoot $Paths.Recipes
  if ($plan.Errors.Count -gt 0) { Write-BorcPlanErrors -Errors $plan.Errors; return 1 }
  $target = Select-BorcUpgradeTarget -Plan $plan -Packages @(Get-BorcListedPackages -Plan $plan) -App $App
  if (-not $target.Listed) { return Write-BorcNotListed -App $App -Headline 'nothing was checked' }
  $packages = @($target.Packages)
  $upgrade = New-BorcUpgradeDocument -Plan $plan -Ids $target.Recipes
  foreach ($message in $upgrade.Dropped) { Write-BorcLog -Message $message }
  if ($App -and $packages.Count -eq 0 -and $upgrade.Recipes.Count -eq 0) { Write-BorcLog -Message "$App has nothing borc upgrade can upgrade." }

  Start-BorcStep -Name 'Asking winget which packages have an update'
  $updates = if ($packages.Count -gt 0) { Get-BorcAvailableUpdates } else { [ordered]@{} }
  if ($null -eq $updates) {
    Set-BorcResult -Headline "nothing was checked: BORC could not read winget's list of updates, shown in the log." -Color Red
    return 1
  }
  $checks = $null
  $versions = @()
  if ($Check) {
    Start-BorcStep -Name "Testing the recipes' upgrade units (winget configure test)"
    if ($upgrade.Document) {
      Clear-BorcVersionReports -Paths $Paths
      $checks = Invoke-BorcUnitTest -Units @($upgrade.Document['resources']) -Name 'upgrade-check'
      $versions = @(Get-BorcReportedVersions -Reports (Read-BorcVersionReports -Paths $Paths))
    } else { Write-BorcLog -Message 'No recipe to check has upgrade units.'; $checks = [ordered]@{} }
  }

  Start-BorcStep -Name 'What borc upgrade would upgrade'
  Update-BorcInstalledList
  $rows = @(
    foreach ($package in $packages) { Get-BorcUpgradeVerdict -Package $package -Updates $updates }
    foreach ($id in $upgrade.Recipes) { Get-BorcUpgradeUnitsVerdict -Id $id -Units @($upgrade.Document['resources']) -Checks $checks }
  )
  Clear-BorcInstalledList
  Show-BorcUpgradeRows -Rows $rows -Versions $versions
  Write-BorcLog -Message 'Nothing was changed (--what-if).'
  Set-BorcUpgradePreviewResult -Rows $rows -Versions $versions
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
  [pscustomobject]@{ Kind = 'package'; State = $state; Id = $Package.Id; Detail = $detail }
}

# A recipe's row from its upgrade units: without --check they are not checked;
# with it, a unit not in place means an update is available.
function Get-BorcUpgradeUnitsVerdict {
  param([Parameter(Mandatory)] [string] $Id, [object[]] $Units = @(), [System.Collections.IDictionary] $Checks)
  $prefix = "${Id}: "
  $names = @($Units | ForEach-Object { [string]$_['name'] } | Where-Object { $_.StartsWith($prefix) })
  $short = { param($Name) $Name.Substring($prefix.Length) }
  $state, $detail = if ($null -eq $Checks) { 'not checked', "upgrade units: $(($names | ForEach-Object { & $short $_ }) -join ', '); --check tests them" }
  else {
    $out = @($names | Where-Object { $Checks[$_].State -eq 'out' } | ForEach-Object { & $short $_ })
    $unknown = @($names | Where-Object { $Checks[$_].State -notin 'in', 'out' } | ForEach-Object { "$(& $short $_) ($(if ($Checks[$_]) { $Checks[$_].Message } else { 'no result from winget' }))" })
    if ($out.Count -gt 0) { 'update available', "would run: $($out -join ', ')" }
    elseif ($unknown.Count -gt 0) { 'unknown', "could not test: $($unknown -join '; ')" }
    else { 'up to date', "upgrade units: $($names.Count) of $($names.Count) in place" }
  }
  [pscustomobject]@{ Kind = 'recipe'; State = $state; Id = $Id; Detail = $detail }
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

# The rows, then what the upgrade units reported with Write-BorcVersion, if any:
# a report names an app, not the recipe it belongs to.
function Show-BorcUpgradeRows {
  param([object[]] $Rows = @(), [object[]] $Versions = @())
  if ($Rows.Count -eq 0) { Write-BorcLog -Message '  No winget package to check.'; return }
  $width = ($Rows | ForEach-Object { $_.Id.Length } | Measure-Object -Maximum).Maximum
  $colors = @{ 'update available' = 'Yellow'; 'up to date' = 'Green' }
  foreach ($row in $Rows) {
    Write-BorcPreviewLine -Text ('  {0,-16}  {1}  {2}' -f $row.State, $row.Id.PadRight($width), $row.Detail) -Color $colors[$row.State]
  }
  if ($Versions.Count -gt 0) {
    Write-BorcPreviewLine -Text ''
    Write-BorcPreviewLine -Text '  Versions the upgrade units reported:'
    foreach ($version in $Versions) { Write-BorcPreviewLine -Text "    $($version.Text)$(if ($version.State -eq 'available') { ' available' })" }
  }
  Write-BorcPreviewLine -Text ''
  Write-BorcPreviewLine -Text "  $(Format-BorcUpgradeCounts -Rows $Rows)."
}

function Format-BorcUpgradeCounts {
  param([object[]] $Rows = @())
  $count = @{}
  foreach ($row in $Rows) { $count[$row.State] = [int]$count[$row.State] + 1 }
  $updates = [int]$count['update available']
  $text = "$updates $(if ($updates -eq 1) { 'update' } else { 'updates' }) available, $([int]$count['up to date']) up to date, $([int]$count['fixed version']) fixed, $([int]$count['not installed']) not installed, $([int]$count['unknown']) unknown"
  if ($count['not checked']) { $text += ", $($count['not checked']) not checked" }
  $text
}

# The answer to "would borc upgrade change anything?".
function Set-BorcUpgradePreviewResult {
  param([object[]] $Rows = @(), [object[]] $Versions = @())
  $details = [ordered]@{}
  $groups = [ordered]@{ 'updates' = 'update available'; 'fixed version' = 'fixed version'; 'not installed' = 'not installed'; 'unknown' = 'unknown'; 'not checked' = 'not checked' }
  foreach ($label in $groups.Keys) {
    $matched = @($Rows | Where-Object State -EQ $groups[$label])
    if ($matched.Count -gt 0) { $details[$label] = ($matched | ForEach-Object { "$($_.Id) ($($_.Detail))" }) -join ', ' }
  }
  if ($Versions.Count -gt 0) { $details['versions'] = ($Versions | ForEach-Object { "$($_.Text)$(if ($_.State -eq 'available') { ' available' })" }) -join ', ' }
  $details['counts'] = Format-BorcUpgradeCounts -Rows $Rows
  $updates = @($Rows | Where-Object State -EQ 'update available')
  $unknown = @($Rows | Where-Object State -EQ 'unknown').Count
  $notChecked = @($Rows | Where-Object State -EQ 'not checked').Count
  if ($updates.Count -gt 0) { Set-BorcResult -Headline "borc upgrade would upgrade $(Format-BorcUpgradeTargets -Rows $updates)." -Details $details -Color Yellow }
  elseif ($unknown -gt 0) { Set-BorcResult -Headline "probably nothing to upgrade; $unknown could not be checked." -Details $details }
  elseif ($notChecked -gt 0) { Set-BorcResult -Headline "probably nothing to upgrade; $notChecked $(if ($notChecked -eq 1) { 'recipe has' } else { 'recipes have' }) upgrade units. Run with --check to know." -Details $details }
  else { Set-BorcResult -Headline 'nothing to upgrade.' -Details $details -Color Green }
}

# "2 packages", "1 recipe", or "2 packages and 1 recipe".
function Format-BorcUpgradeTargets {
  param([Parameter(Mandatory)] [object[]] $Rows)
  $packages = @($Rows | Where-Object Kind -NE 'recipe').Count
  $recipes = @($Rows | Where-Object Kind -EQ 'recipe').Count
  $parts = @(
    if ($packages -gt 0) { "$packages $(if ($packages -eq 1) { 'package' } else { 'packages' })" }
    if ($recipes -gt 0) { "$recipes $(if ($recipes -eq 1) { 'recipe' } else { 'recipes' })" }
  )
  $parts -join ' and '
}
