<#
  borc installer. Runs under Windows PowerShell 5.1:

    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/msebire/borc/main/install.ps1 | iex"

  It updates winget, installs Git, PowerShell 7 and Microsoft.DSC, clones the
  borc engine into %LOCALAPPDATA%\borc\engine, then hands over to the engine
  (src\setup.ps1, under PowerShell 7) for the rest: the questions, the config
  repo, the environment variables, the borc command, the profile block and
  borc apply. Every step checks first, so it can be run again safely.

  To test an unreleased branch, set BORC_BRANCH for that one command (from a
  PowerShell prompt; the backtick keeps the outer shell from expanding it):

    powershell -NoProfile -ExecutionPolicy Bypass -Command "`$env:BORC_BRANCH='my-branch'; irm https://raw.githubusercontent.com/msebire/borc/main/install.ps1 | iex"
#>

# Copy of $BorcRepoUrl in src\Borc\Constants.ps1: this file is downloaded
# alone. The tests check that both match.
$BorcRepoUrl = 'https://github.com/msebire/borc'
$BorcReleaseBranch = 'main'

# winget exit codes that mean "already there" rather than a failure.
$WingetAlreadyFine = @(0, -1978335189, -1978335135) # 0x8A15002B no upgrade, 0x8A150061 already installed

function Assert-BorcWindowsVersion {
  param([int] $Build = [Environment]::OSVersion.Version.Build)
  if ($Build -ge 22000) { return }
  if ($Build -ge 19045) {
    Write-Warning 'This is Windows 10 22H2. borc targets Windows 11; it continues, on a best effort basis.'
    return
  }
  throw "borc needs Windows 11, or Windows 10 22H2 (build 19045). This machine runs build $Build."
}

function Initialize-BorcSession {
  # Process scope only: the machine and user execution policies stay as they are.
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Install-BorcGalleryModule {
  param([Parameter(Mandatory = $true)] [string] $Name)
  if (Get-Module -ListAvailable -Name $Name) { return }
  $nuget = Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' }
  if (-not $nuget) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
  }
  # -Force answers the "untrusted repository" prompt for this install only;
  # PSGallery is not marked as trusted.
  Install-Module -Name $Name -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
}

function Update-BorcWinget {
  Write-Host 'Updating winget to its latest version.'
  try {
    Install-BorcGalleryModule -Name 'Microsoft.WinGet.Client'
    Import-Module -Name Microsoft.WinGet.Client -ErrorAction Stop
    Repair-WinGetPackageManager -Latest -ErrorAction Stop | Out-Null
  } catch {
    throw "winget could not be updated: $($_.Exception.Message)`nUpdate App Installer from the Microsoft Store, then run the borc installer again."
  }
}

function Update-BorcSessionPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$machine;$user"
}

function Install-BorcWingetPackage {
  param([Parameter(Mandatory = $true)] [string] $Id)
  Write-Host "Installing or upgrading $Id."
  & winget install --id $Id --exact --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
  if ($WingetAlreadyFine -notcontains $LASTEXITCODE) {
    throw "winget could not install $Id (exit code $LASTEXITCODE)."
  }
}

# The engine branch: main, unless BORC_BRANCH is set for this process to test
# an unreleased branch. Never stored: rerunning without it goes back to main.
function Get-BorcEngineBranch {
  if ($env:BORC_BRANCH) {
    Write-Warning "BORC_BRANCH is set: installing the borc engine from the branch $env:BORC_BRANCH, not from the release branch $BorcReleaseBranch."
    return $env:BORC_BRANCH
  }
  $BorcReleaseBranch
}

function Invoke-BorcEngineGit {
  param([Parameter(Mandatory = $true)] [string[]] $Arguments, [Parameter(Mandatory = $true)] [string] $Action)
  & git @Arguments
  if ($LASTEXITCODE -ne 0) { throw "git could not $Action (exit code $LASTEXITCODE)." }
}

# Clones the engine on the branch, or brings an existing clone to the latest
# commit of that branch.
function Install-BorcEngine {
  param(
    [Parameter(Mandatory = $true)] [string] $Path,
    [Parameter(Mandatory = $true)] [string] $Branch,
    [string] $RepoUrl = $BorcRepoUrl
  )
  if (Test-Path -LiteralPath (Join-Path $Path '.git')) {
    Write-Host "Updating the borc engine (branch $Branch)."
    Invoke-BorcEngineGit -Arguments @('-C', $Path, 'fetch', 'origin') -Action "fetch $RepoUrl"
    Invoke-BorcEngineGit -Arguments @('-C', $Path, 'switch', $Branch) -Action "switch the borc engine to the branch $Branch"
    Invoke-BorcEngineGit -Arguments @('-C', $Path, 'pull', '--ff-only') -Action 'update the borc engine'
  } else {
    Write-Host "Cloning the borc engine (branch $Branch) into $Path."
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    Invoke-BorcEngineGit -Arguments @('clone', '--branch', $Branch, $RepoUrl, $Path) -Action "clone the branch $Branch of $RepoUrl"
  }
}

function Install-Borc {
  $ErrorActionPreference = 'Stop'
  Initialize-BorcSession
  Assert-BorcWindowsVersion
  Update-BorcWinget
  foreach ($id in @('Git.Git', 'Microsoft.PowerShell', 'Microsoft.DSC')) { Install-BorcWingetPackage -Id $id }
  Update-BorcSessionPath
  $engine = Join-Path $env:LOCALAPPDATA 'borc\engine'
  Install-BorcEngine -Path $engine -Branch (Get-BorcEngineBranch)
  & pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'src\setup.ps1')
  if ($LASTEXITCODE -eq 3010) { return } # borc apply asked for a restart.
  if ($LASTEXITCODE -ne 0) { throw "borc setup did not finish (exit code $LASTEXITCODE). The log path is shown above." }
}

# Errors are thrown rather than exited, so running this through irm | iex in
# an open window never closes it.
Install-Borc
