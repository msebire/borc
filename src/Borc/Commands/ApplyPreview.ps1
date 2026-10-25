# borc apply --what-if: fetches without merging and reads borc.yaml and the
# recipes as they would be after the pull. Changes nothing.

function Invoke-BorcApplyPreview {
  param([Parameter(Mandatory)] $Paths)
  # The check comes last, so a failure in the summary points at it.
  Start-BorcSteps -Total 4
  Start-BorcStep -Name 'Fetching the config repo and recipe repos (no merge)'
  $dirty = @(Get-BorcDirtyFiles -Path $Paths.Settings)
  if ($dirty.Count -gt 0) { Write-BorcLog -Message (Format-BorcDirtyMessage -Path $Paths.Settings -Files $dirty) -Level Warning }

  $refs = @{ $Paths.Settings = (Show-BorcIncoming -Path $Paths.Settings -Label 'config repo') }
  $localConfig = ConvertTo-BorcConfig -Text (Read-BorcTextFile -Path (Join-Path $Paths.Settings 'borc\borc.yaml'))
  $notCloned = @()
  foreach ($repo in $localConfig.Recipes) {
    $clone = Join-Path $Paths.Recipes $repo.Name
    if (Test-BorcGitRepo -Path $clone) { $refs[$clone] = Show-BorcIncoming -Path $clone -Label "recipe repo $($repo.Name)" }
    else { $notCloned += $repo.Name; Write-BorcLog -Message "recipe repo $($repo.Name): not cloned yet; borc apply will clone $($repo.Url)." }
  }

  $plan = Get-BorcPlan -SettingsRoot $Paths.Settings -RecipesRoot $Paths.Recipes -ReadFile (New-BorcPreviewReader -Refs $refs)
  $errors = @($plan.Errors | Where-Object { -not (Test-BorcNotClonedError -Message $_ -Repos $notCloned) })
  Start-BorcStep -Name 'What would be installed'
  Show-BorcPreviewApps -Plan $plan
  Start-BorcStep -Name 'Secrets that would be asked for'
  Show-BorcPreviewSecrets -Plan $plan
  Start-BorcStep -Name 'Checking borc.yaml and the recipes'
  if ($errors.Count -gt 0) { Write-BorcPlanErrors -Errors $errors; return 1 }
  Write-BorcPlanCounts -Plan $plan
  Write-BorcLog -Message 'Nothing was changed (--what-if).'
  0
}

function Show-BorcIncoming {
  param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Label)
  $incoming = Get-BorcIncoming -Path $Path
  if ($incoming.Commits.Count -eq 0) {
    Write-BorcLog -Message "${Label}: up to date."
  } else {
    Write-BorcLog -Message "${Label}: the pull would bring $($incoming.Commits.Count) commit(s):"
    foreach ($line in $incoming.Commits + $incoming.Files) { Write-BorcLog -Message "  $line" }
  }
  $incoming.Ref
}

# Reads files from the fetched commits of the repo that holds them; a repo with
# no upstream is read from the disk. The refs live in module scope because the
# reader is called from Get-BorcPlan.
function New-BorcPreviewReader {
  param([Parameter(Mandatory)] [hashtable] $Refs)
  $script:BorcPreviewRefs = $Refs
  { param($Path) Read-BorcPreviewFile -Path $Path }
}

function Read-BorcPreviewFile {
  param([Parameter(Mandatory)] [string] $Path)
  foreach ($repo in $script:BorcPreviewRefs.Keys) {
    if (-not $script:BorcPreviewRefs[$repo]) { continue }
    $prefix = $repo.TrimEnd('\') + '\'
    if ($Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
      return Read-BorcGitFile -Repo $repo -Ref $script:BorcPreviewRefs[$repo] -RelativePath $Path.Substring($prefix.Length)
    }
  }
  Read-BorcTextFile -Path $Path
}

function Test-BorcNotClonedError {
  param([Parameter(Mandatory)] [string] $Message, [string[]] $Repos)
  foreach ($repo in $Repos) {
    if ($Message -like "recipe $repo/* not found:*") { return $true }
  }
  $false
}

# A verdict per app and recipe, from what borc can know without running any
# recipe code: winget list for packages. A recipe's settings units are only
# checked by borc apply, so a recipe whose packages are all there "may be applied".
function Show-BorcPreviewApps {
  param([Parameter(Mandatory)] $Plan)
  if (-not $Plan.Config) { return }
  $rows = @(
    foreach ($app in $Plan.Config.Apps) { if ($app.Kind -ne 'recipe') { Get-BorcPlainVerdict -App $app } }
    $rebootFirst = @($Plan.Order | Where-Object { $Plan.Recipes[$_].Reboot }) + @($Plan.Order | Where-Object { -not $Plan.Recipes[$_].Reboot })
    foreach ($id in $rebootFirst) { Get-BorcRecipeVerdict -Plan $Plan -Id $id }
  )
  if ($rows.Count -eq 0) { Write-BorcLog -Message '  borc.yaml lists no app.'; return }
  $width = ($rows | ForEach-Object { $_.Id.Length } | Measure-Object -Maximum).Maximum
  $colors = @{ 'installed' = 'Green'; 'in place' = 'Green'; 'would be installed' = 'Yellow'; 'would be applied' = 'Yellow' }
  $previousKind = $null
  foreach ($row in $rows) {
    if ($previousKind -and $previousKind -ne 'recipe' -and $row.Kind -eq 'recipe') { Write-BorcPreviewLine -Text '' }
    $previousKind = $row.Kind
    $verdict = $row.Verdict + $row.Note
    Write-BorcPreviewLine -Text ('  {0,-7} {1}  {2}' -f $row.Kind, $row.Id.PadRight($width), $verdict) -Color $colors[$row.Verdict]
    foreach ($detail in $row.Details) { Write-BorcPreviewLine -Text "          $detail" }
  }
  Write-BorcPreviewSummary -Rows $rows
}

function Write-BorcPreviewLine {
  param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text, [object] $Color)
  if ($Color) { Write-BorcConsole -Text $Text -Color $Color } else { Write-BorcConsole -Text $Text }
  Add-BorcLogLine -Line $Text
}

function Write-BorcPreviewSummary {
  param([Parameter(Mandatory)] [object[]] $Rows)
  $would = @($Rows | Where-Object Verdict -Like 'would be *').Count
  $may = @($Rows | Where-Object Verdict -EQ 'may be applied').Count
  $inPlace = @($Rows | Where-Object Verdict -In 'installed', 'in place').Count
  Write-BorcPreviewLine -Text ''
  Write-BorcPreviewLine -Text "  $would would be installed or applied, $may may be applied, $inPlace in place."
  if ($may -gt 0) {
    Write-BorcPreviewLine -Text '  "may be applied": no package is missing, but its settings are only'
    Write-BorcPreviewLine -Text '  checked when borc apply runs.'
  }
}

function Get-BorcPlainVerdict {
  param([Parameter(Mandatory)] $App)
  $verdict = if (Test-BorcPackageInstalled -Id $App.Id) { 'installed' } else { 'would be installed' }
  [pscustomobject]@{ Kind = $App.Kind; Id = $App.Id; Verdict = $verdict; Note = ''; Details = @() }
}

function Get-BorcRecipeVerdict {
  param([Parameter(Mandatory)] $Plan, [Parameter(Mandatory)] [string] $Id)
  $recipe = $Plan.Recipes[$Id]
  $app = $Plan.Config.Apps | Where-Object { $_.Kind -eq 'recipe' -and $_.Id -eq $Id } | Select-Object -First 1
  $parameters = if ($app) { $app.Parameters } else { [ordered]@{} }
  $dropped = [System.Collections.Generic.List[string]]::new()
  $units = @(ConvertTo-BorcRecipeUnits -Recipe $recipe -Parameters $parameters -Dropped $dropped)
  $packages = @($units | Where-Object { $_['type'] -eq $script:WingetPackageType })
  $missing = @($packages | Where-Object { -not (Test-BorcPackageInstalled -Id "$($_['properties']['id'])") } | ForEach-Object { "$($_['properties']['id'])" })
  $settings = $units.Count - $packages.Count

  $verdict = if ($missing.Count -gt 0) { 'would be applied' } elseif ($settings -gt 0) { 'may be applied' } else { 'in place' }
  $note = if ($recipe.Reboot) { ' (runs first, may need a restart)' } else { '' }
  [pscustomobject]@{
    Kind = 'recipe'; Id = $Id; Verdict = $verdict; Note = $note
    Details = @(Format-BorcRecipeDetails -Packages $packages.Count -Missing $missing -Settings $settings -Dropped @($dropped))
  }
}

# "packages: 1 of 1 installed" and "settings: 2 units, not checked; 1 skipped (...)".
function Format-BorcRecipeDetails {
  param([int] $Packages, [string[]] $Missing = @(), [int] $Settings, [string[]] $Dropped = @())
  $packageText = if ($Packages -eq 0) { 'packages: none' } else { "packages: $($Packages - $Missing.Count) of $Packages installed" }
  if ($Missing.Count -gt 0) { $packageText += " ($($Missing -join ', '))" }
  $reasons = @($Dropped | ForEach-Object { if ($_ -match 'no value for (.+)$') { "no value for $($Matches[1])" } } | Select-Object -Unique)
  $skipped = if ($Dropped.Count -gt 0) { "$($Dropped.Count) skipped ($($reasons -join '; '))" } else { '' }
  if ($Settings -eq 0 -and -not $skipped) { return "$packageText, no settings" }
  $packageText
  $settingsText = if ($Settings -eq 0) { 'settings: none to run' } else { "settings: $Settings $(if ($Settings -eq 1) { 'unit' } else { 'units' }), not checked" }
  if ($skipped) { $settingsText += "; $skipped" }
  $settingsText
}

function Show-BorcPreviewSecrets {
  param([Parameter(Mandatory)] $Plan)
  if (-not $Plan.Config) { return }
  $missing = @(Get-BorcMissingSecrets -Secrets $Plan.Config.Secrets)
  if ($missing.Count -eq 0) { Write-BorcLog -Message '  None: every declared secret is in Windows Credential Manager.'; return }
  foreach ($name in $missing) { Write-BorcLog -Message "  $name ($($Plan.Config.Secrets[$name]))" }
}
