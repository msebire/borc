# Git operations on the config repo, recipe repos and the engine clone.
# borc never commits or pushes: nothing here runs commit, push or merge.

function Invoke-BorcGit {
  param([Parameter(Mandatory)] [string[]] $Arguments, [switch] $Quiet)
  $ErrorActionPreference = 'Continue'
  Write-BorcLog -Message "git $($Arguments -join ' ')" -LogOnly
  $lines = [System.Collections.Generic.List[string]]::new()
  & git @Arguments 2>&1 | ForEach-Object {
    $line = "$_"
    $lines.Add($line)
    if ($Quiet) { Write-BorcLog -Message $line -LogOnly } else { Write-BorcOutputLine -Line $line }
  }
  [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($lines) }
}

function Assert-BorcGit {
  param([Parameter(Mandatory)] $Result, [Parameter(Mandatory)] [string] $Action)
  if ($Result.ExitCode -ne 0) { throw "git failed to $Action (exit code $($Result.ExitCode))." }
}

function Test-BorcGitRepo {
  param([Parameter(Mandatory)] [string] $Path)
  Test-Path -LiteralPath (Join-Path $Path '.git')
}

function Get-BorcGitRemoteUrl {
  param([Parameter(Mandatory)] [string] $Path)
  $result = Invoke-BorcGit -Arguments @('-C', $Path, 'remote', 'get-url', 'origin') -Quiet
  if ($result.ExitCode -ne 0) { return $null }
  $result.Output | Select-Object -First 1
}

# Tracked files with uncommitted changes. Untracked and ignored files never count.
function Get-BorcDirtyFiles {
  param([Parameter(Mandatory)] [string] $Path)
  $result = Invoke-BorcGit -Arguments @('-C', $Path, 'status', '--porcelain', '--untracked-files=no') -Quiet
  Assert-BorcGit -Result $result -Action "read the status of $Path"
  @($result.Output | Where-Object { $_ } | ForEach-Object { $_.Substring(3) })
}

function Get-BorcUpstream {
  param([Parameter(Mandatory)] [string] $Path)
  $result = Invoke-BorcGit -Arguments @('-C', $Path, 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}') -Quiet
  if ($result.ExitCode -ne 0) { return $null }
  $result.Output | Select-Object -First 1
}

function Get-BorcCurrentBranch {
  param([Parameter(Mandatory)] [string] $Path)
  $result = Invoke-BorcGit -Arguments @('-C', $Path, 'symbolic-ref', '--short', 'HEAD') -Quiet
  $result.Output | Select-Object -First 1
}

function Format-BorcDirtyMessage {
  param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string[]] $Files)
  $list = ($Files | ForEach-Object { "  $_" }) -join "`n"
  "These tracked files in $Path have uncommitted changes:`n$list`nCommit or discard them, then run borc apply again. borc does not pull over local changes."
}

# Pulls the config repo. Refuses when tracked files have uncommitted changes.
# A branch with no upstream (a new local repo) is applied as it is.
function Sync-BorcConfigRepo {
  param([Parameter(Mandatory)] [string] $Path)
  $dirty = @(Get-BorcDirtyFiles -Path $Path)
  if ($dirty.Count -gt 0) { throw (Format-BorcDirtyMessage -Path $Path -Files $dirty) }
  if (-not (Get-BorcUpstream -Path $Path)) {
    Write-BorcLog -Message "The branch $(Get-BorcCurrentBranch -Path $Path) has no upstream yet; using the local copy. Push it with git push -u origin <branch> when ready."
    return
  }
  Assert-BorcGit -Result (Invoke-BorcGit -Arguments @('-C', $Path, 'pull', '--ff-only')) -Action "pull $Path"
}

function Sync-BorcRecipeRepo {
  param([Parameter(Mandatory)] [string] $Url, [Parameter(Mandatory)] [string] $Path)
  if (Test-BorcGitRepo -Path $Path) {
    Assert-BorcGit -Result (Invoke-BorcGit -Arguments @('-C', $Path, 'pull', '--ff-only')) -Action "pull $Url"
  } else {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    Assert-BorcGit -Result (Invoke-BorcGit -Arguments @('clone', $Url, $Path)) -Action "clone $Url"
  }
}

# Fetches without merging and returns what a pull would bring.
function Get-BorcIncoming {
  param([Parameter(Mandatory)] [string] $Path)
  if (-not (Get-BorcUpstream -Path $Path)) { return [pscustomobject]@{ Ref = $null; Commits = @(); Files = @() } }
  Assert-BorcGit -Result (Invoke-BorcGit -Arguments @('-C', $Path, 'fetch') -Quiet) -Action "fetch $Path"
  $commits = Invoke-BorcGit -Arguments @('-C', $Path, 'log', '--oneline', 'HEAD..@{u}') -Quiet
  $files = Invoke-BorcGit -Arguments @('-C', $Path, 'diff', '--stat', 'HEAD...@{u}') -Quiet
  [pscustomobject]@{ Ref = '@{u}'; Commits = @($commits.Output | Where-Object { $_ }); Files = @($files.Output | Where-Object { $_ }) }
}

# A file as it is at a ref, or $null when it does not exist there.
function Read-BorcGitFile {
  param([Parameter(Mandatory)] [string] $Repo, [Parameter(Mandatory)] [string] $Ref, [Parameter(Mandatory)] [string] $RelativePath)
  $result = Invoke-BorcGit -Arguments @('-C', $Repo, 'show', "${Ref}:$($RelativePath -replace '\\', '/')") -Quiet
  if ($result.ExitCode -ne 0) { return $null }
  ($result.Output -join "`n") + "`n"
}

function Get-BorcRemoteBranches {
  param([Parameter(Mandatory)] [string] $Url)
  $result = Invoke-BorcGit -Arguments @('ls-remote', '--heads', $Url) -Quiet
  Assert-BorcGit -Result $result -Action "reach $Url"
  @($result.Output | Where-Object { $_ -match "\trefs/heads/(.+)$" } | ForEach-Object { $Matches[1] })
}

function ConvertTo-BorcComparableUrl {
  param([AllowEmptyString()] [string] $Url)
  if (-not $Url) { return '' }
  ($Url.Trim().TrimEnd('/', '\') -replace '\.git$', '').ToLowerInvariant()
}

# Missing, Empty, SameRepo or Other. An empty URL matches a repo with no origin.
function Get-BorcSettingsFolderState {
  param([Parameter(Mandatory)] [string] $Path, [AllowEmptyString()] [string] $Url = '')
  if (-not (Test-Path -LiteralPath $Path)) { return 'Missing' }
  if (-not (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)) { return 'Empty' }
  if (Test-BorcGitRepo -Path $Path) {
    $origin = Get-BorcGitRemoteUrl -Path $Path
    if ((ConvertTo-BorcComparableUrl $origin) -eq (ConvertTo-BorcComparableUrl $Url)) { return 'SameRepo' }
  }
  'Other'
}

function Copy-BorcTemplate {
  param([Parameter(Mandatory)] [string] $Destination)
  $template = Join-Path $script:BorcModuleRoot 'template'
  Get-ChildItem -LiteralPath $template -Force | Copy-Item -Destination $Destination -Recurse -Force
}

# Creates BORC_SETTINGS: a clone of the config repo on the given branch, or the
# starter template for an empty URL or an empty remote. Never commits.
function Initialize-BorcSettings {
  param(
    [Parameter(Mandatory)] [string] $Path,
    [AllowEmptyString()] [string] $Url = '',
    [Parameter(Mandatory)] [string] $Branch,
    # Receives the remote branches and the wanted branch, and returns the branch to start from, or $null.
    [Parameter(Mandatory)] [scriptblock] $ChooseBase
  )
  $state = Get-BorcSettingsFolderState -Path $Path -Url $Url
  switch ($state) {
    'SameRepo' { Write-BorcLog -Message "$Path is already set up; leaving it as it is."; return }
    'Other' { throw "$Path is not empty and is not a clone of $(if ($Url) { $Url } else { 'a local borc repo' }). Choose another folder or empty this one, then run the installer again." }
  }
  if (-not $Url) {
    Assert-BorcGit -Result (Invoke-BorcGit -Arguments @('init', '--initial-branch', $Branch, $Path) -Quiet) -Action "create $Path"
    Copy-BorcTemplate -Destination $Path
    Write-BorcLog -Message "Created a new config repo in $Path from the starter template. Commit it, add a remote and push when you are ready."
    return
  }
  $branches = @(Get-BorcRemoteBranches -Url $Url)
  if ($branches.Count -eq 0) {
    Assert-BorcGit -Result (Invoke-BorcGit -Arguments @('clone', $Url, $Path)) -Action "clone $Url"
    Assert-BorcGit -Result (Invoke-BorcGit -Arguments @('-C', $Path, 'symbolic-ref', 'HEAD', "refs/heads/$Branch") -Quiet) -Action "set the branch $Branch"
    Copy-BorcTemplate -Destination $Path
    Write-BorcLog -Message "$Url is empty: filled $Path from the starter template on branch $Branch. Commit and push when you are ready."
    return
  }
  if ($Branch -in $branches) {
    Assert-BorcGit -Result (Invoke-BorcGit -Arguments @('clone', '--branch', $Branch, $Url, $Path)) -Action "clone $Url"
    return
  }
  $base = & $ChooseBase $branches $Branch
  if (-not $base) { throw "The branch $Branch does not exist on $Url and no branch was chosen to create it from." }
  Assert-BorcGit -Result (Invoke-BorcGit -Arguments @('clone', '--branch', $base, $Url, $Path)) -Action "clone $Url"
  Assert-BorcGit -Result (Invoke-BorcGit -Arguments @('-C', $Path, 'switch', '--no-track', '--create', $Branch) -Quiet) -Action "create the branch $Branch"
  Write-BorcLog -Message "Created the branch $Branch from $base. Push it with git push -u origin $Branch when you are ready."
}
