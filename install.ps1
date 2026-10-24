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
$WingetAlreadyFine = @{ -1978335189 = 'no upgrade available'; -1978335135 = 'already installed' } # 0x8A15002B, 0x8A150061

# The same look as the borc command: numbered steps, a start and an end line
# around each external command, colours (off with NO_COLOR) and a summary.
# Command output is not indented here: winget draws its progress in place.
$InstallSteps = @{ List = New-Object System.Collections.ArrayList; Total = 5; Current = $null }

function Write-InstallLine {
  param([Parameter(Mandatory = $true)] [AllowEmptyString()] [string] $Text, [string] $Color)
  if ($Color -and -not $env:NO_COLOR) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}

function Format-InstallDuration {
  param([Parameter(Mandatory = $true)] [TimeSpan] $Duration)
  if ($Duration.TotalSeconds -lt 60) { return '{0}s' -f [int][Math]::Floor($Duration.TotalSeconds) }
  '{0}m {1:00}s' -f [int][Math]::Floor($Duration.TotalMinutes), $Duration.Seconds
}

function Complete-InstallStep {
  param([string] $Status = 'done')
  $step = $InstallSteps.Current
  if (-not $step) { return }
  $step.Status = $Status
  $step.Duration = (Get-Date) - $step.Started
  $InstallSteps.Current = $null
}

function Start-InstallStep {
  param([Parameter(Mandatory = $true)] [string] $Name)
  Complete-InstallStep
  $label = '[{0}/{1}] {2}' -f ($InstallSteps.List.Count + 1), $InstallSteps.Total, $Name
  $step = New-Object psobject -Property @{ Label = $label; Started = Get-Date; Status = $null; Duration = $null }
  [void]$InstallSteps.List.Add($step)
  $InstallSteps.Current = $step
  Write-InstallLine -Text ''
  Write-InstallLine -Text "==> $label" -Color Cyan
}

function Write-InstallSummary {
  if ($InstallSteps.List.Count -eq 0) { return }
  $colors = @{ done = 'Green'; failed = 'Red'; restart = 'Yellow' }
  $width = ($InstallSteps.List | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum
  Write-InstallLine -Text ''
  Write-InstallLine -Text 'Installer summary:'
  foreach ($step in $InstallSteps.List) {
    $line = '  {0,-8} {1}  {2}' -f $step.Status, $step.Label.PadRight($width), (Format-InstallDuration -Duration $step.Duration)
    Write-InstallLine -Text $line -Color $colors[$step.Status]
  }
  if ($InstallSteps.List.Count -lt $InstallSteps.Total) {
    Write-InstallLine -Text "  Stopped after step $($InstallSteps.List.Count) of $($InstallSteps.Total)."
  }
}

function Format-InstallExitCode {
  param([Parameter(Mandatory = $true)] [int] $Code)
  if ($Code -ge 0 -and $Code -lt 65536) { return "$Code" }
  '0x{0:X8}' -f $Code
}

# Runs an external command between a start and an end line; returns its exit
# code. Codes in OkCodes are not failures; their note says what they mean.
function Invoke-InstallCommand {
  param(
    [Parameter(Mandatory = $true)] [string] $FilePath,
    [Parameter(Mandatory = $true)] [string[]] $Arguments,
    [hashtable] $OkCodes = @{}
  )
  $started = Get-Date
  Write-InstallLine -Text "  > $FilePath $($Arguments -join ' ')"
  # Start-Process keeps the command on this console, so its output is shown as
  # it comes and never mixes with the exit code this function returns.
  $quoted = @($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } })
  $process = Start-Process -FilePath $FilePath -ArgumentList $quoted -NoNewWindow -Wait -PassThru
  $code = $process.ExitCode
  $time = Format-InstallDuration -Duration ((Get-Date) - $started)
  if ($code -eq 0 -or $OkCodes.ContainsKey($code)) {
    $note = if ($code -ne 0) { " ($($OkCodes[$code]))" } else { '' }
    Write-InstallLine -Text "  < done in $time$note" -Color Green
  } else {
    Write-InstallLine -Text "  < failed, exit code $(Format-InstallExitCode -Code $code), after $time" -Color Red
  }
  $code
}

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
    Write-InstallLine -Text '  > Install-PackageProvider NuGet'
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
  }
  # -Force answers the "untrusted repository" prompt for this install only;
  # PSGallery is not marked as trusted.
  Write-InstallLine -Text "  > Install-Module $Name"
  Install-Module -Name $Name -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
}

function Update-BorcWinget {
  try {
    Install-BorcGalleryModule -Name 'Microsoft.WinGet.Client'
    Import-Module -Name Microsoft.WinGet.Client -ErrorAction Stop
    Write-InstallLine -Text '  > Repair-WinGetPackageManager -Latest'
    $started = Get-Date
    Repair-WinGetPackageManager -Latest -ErrorAction Stop | Out-Null
    Write-InstallLine -Text "  < done in $(Format-InstallDuration -Duration ((Get-Date) - $started))" -Color Green
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
  $arguments = @('install', '--id', $Id, '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
  $code = Invoke-InstallCommand -FilePath 'winget' -Arguments $arguments -OkCodes $WingetAlreadyFine
  if ($code -ne 0 -and -not $WingetAlreadyFine.ContainsKey($code)) {
    throw "winget could not install $Id (exit code $(Format-InstallExitCode -Code $code))."
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
  $code = Invoke-InstallCommand -FilePath 'git' -Arguments $Arguments
  if ($code -ne 0) { throw "git could not $Action (exit code $code)." }
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
    Invoke-BorcEngineGit -Arguments @('-C', $Path, 'fetch', 'origin') -Action "fetch $RepoUrl"
    Invoke-BorcEngineGit -Arguments @('-C', $Path, 'switch', $Branch) -Action "switch the borc engine to the branch $Branch"
    Invoke-BorcEngineGit -Arguments @('-C', $Path, 'pull', '--ff-only') -Action 'update the borc engine'
  } else {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    Invoke-BorcEngineGit -Arguments @('clone', '--branch', $Branch, $RepoUrl, $Path) -Action "clone the branch $Branch of $RepoUrl"
  }
}

function Install-Borc {
  $ErrorActionPreference = 'Stop'
  $status = 'failed'
  try {
    Initialize-BorcSession
    Start-InstallStep -Name 'Windows version'
    Assert-BorcWindowsVersion
    Start-InstallStep -Name 'Updating winget'
    Update-BorcWinget
    Start-InstallStep -Name 'Git, PowerShell 7 and Microsoft.DSC'
    foreach ($id in @('Git.Git', 'Microsoft.PowerShell', 'Microsoft.DSC')) { Install-BorcWingetPackage -Id $id }
    Update-BorcSessionPath
    $branch = Get-BorcEngineBranch
    $engine = Join-Path $env:LOCALAPPDATA 'borc\engine'
    Start-InstallStep -Name "borc engine, branch $branch ($engine)"
    Install-BorcEngine -Path $engine -Branch $branch
    Start-InstallStep -Name 'borc setup and borc apply, under PowerShell 7'
    $code = Invoke-InstallCommand -FilePath 'pwsh.exe' -Arguments @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $engine 'src\setup.ps1')) -OkCodes @{ 3010 = 'restart needed' }
    if ($code -eq 3010) { $status = 'restart'; return } # borc apply asked for a restart.
    if ($code -ne 0) { throw "borc setup did not finish (exit code $code). The log path is shown above." }
    $status = 'done'
  } finally {
    Complete-InstallStep -Status $status
    Write-InstallSummary
  }
}

# Errors are thrown rather than exited, so running this through irm | iex in
# an open window never closes it.
Install-Borc
