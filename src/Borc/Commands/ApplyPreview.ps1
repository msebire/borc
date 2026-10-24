# borc apply --what-if: fetches without merging and reads borc.yaml and the
# recipes as they would be after the pull. Changes nothing.

function Invoke-BorcApplyPreview {
  param([Parameter(Mandatory)] $Paths)
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
  Show-BorcPreviewApps -Plan $plan
  Show-BorcPreviewSecrets -Plan $plan
  if ($errors.Count -gt 0) { Write-BorcPlanErrors -Errors $errors; return 1 }
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

function Show-BorcPreviewApps {
  param([Parameter(Mandatory)] $Plan)
  if (-not $Plan.Config) { return }
  Write-BorcLog -Message 'Apps:'
  foreach ($app in $Plan.Config.Apps) {
    if ($app.Kind -eq 'recipe') { continue }
    $state = if (Test-BorcPackageInstalled -Id $app.Id) { 'installed' } else { 'would be installed' }
    Write-BorcLog -Message "  $($app.Kind) $($app.Id): $state"
  }
  foreach ($id in $Plan.Order) {
    $note = if ($Plan.Recipes[$id].Reboot) { ' (runs first, may need a restart)' } else { '' }
    Write-BorcLog -Message "  recipe ${id}: would be applied$note"
  }
  if ($Plan.Errors.Count -eq 0) {
    foreach ($message in (New-BorcRunDocuments -Plan $Plan).Dropped) { Write-BorcLog -Message "  $message" }
  }
}

function Show-BorcPreviewSecrets {
  param([Parameter(Mandatory)] $Plan)
  if (-not $Plan.Config) { return }
  $missing = @(Get-BorcMissingSecrets -Secrets $Plan.Config.Secrets)
  if ($missing.Count -eq 0) { Write-BorcLog -Message 'Secrets: none would be asked for.'; return }
  Write-BorcLog -Message "Secrets that would be asked for: $($missing -join ', ')"
}
