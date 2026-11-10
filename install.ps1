<#
  BORC installer. Runs under Windows PowerShell 5.1, from a PowerShell window:

    irm https://raw.githubusercontent.com/msebire/borc/main/install.ps1 | iex

  Not through powershell -ExecutionPolicy Bypass -Command: Microsoft Defender
  blocks that command line as a Trojan. The execution policy does not apply to
  text run by iex, and the installer bypasses it for its own process only.

  It updates winget, installs Git, PowerShell 7 and Microsoft.DSC, and the VC++
  runtime if it is missing, clones the BORC engine into
  %LOCALAPPDATA%\borc\engine, then hands over to the engine
  (src\setup.ps1, under PowerShell 7) for the rest: the questions, the config
  repo, the environment variables, the borc command, the profile block and
  borc apply. Every step checks first, so it can be run again safely.

  To test an unreleased branch, set BORC_BRANCH in that window first:

    $env:BORC_BRANCH='my-branch'; irm https://raw.githubusercontent.com/msebire/borc/my-branch/install.ps1 | iex

  On a computer where winget, Git or PowerShell 7 must stay as they are (a
  managed work computer), set BORC_SKIP_UPDATES=1 the same way: the installer
  then installs only what is missing, updates nothing, and checks that winget
  can run configuration files.
#>

# Copy of $BorcRepoUrl in src\borc\Constants.ps1: this file is downloaded
# alone. The tests check that both match.
$BorcRepoUrl = 'https://github.com/msebire/borc'
$BorcReleaseBranch = 'main'

# Copy of $BorcFirstApplyFailedExitCode in src\borc\Constants.ps1: BORC is
# installed, but its first borc apply failed.
$BorcFirstApplyFailedExitCode = 4

# winget exit codes that mean "already there" rather than a failure.
$WingetAlreadyFine = @{ -1978335189 = 'no upgrade available'; -1978335135 = 'already installed' } # 0x8A15002B, 0x8A150061

# The winget version BORC's configuration file rules were verified with.
$WingetVerifiedVersion = [version]'1.29.0'

# The tools the installer needs, and the command that shows each one is there.
$BorcTools = [ordered]@{ 'Git.Git' = 'git.exe'; 'Microsoft.PowerShell' = 'pwsh.exe'; 'Microsoft.DSC' = 'dsc.exe' }

# Copy of $script:BorcVcRuntimeFile in src\borc\private\wrappers\Environment.ps1:
# without it, winget configure fails on any file with an elevated unit.
$BorcVcRuntimeFile = 'vcruntime140_1.dll'

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
  $colors = @{ done = 'Green'; failed = 'Red'; restart = 'Yellow'; partial = 'Yellow' }
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
# Codes in StopCodes are not failures either, but the work did not finish.
function Invoke-InstallCommand {
  param(
    [Parameter(Mandatory = $true)] [string] $FilePath,
    [Parameter(Mandatory = $true)] [string[]] $Arguments,
    [hashtable] $OkCodes = @{},
    [hashtable] $StopCodes = @{}
  )
  $started = Get-Date
  Write-InstallLine -Text "  > $FilePath $($Arguments -join ' ')"
  # Start-Process keeps the command on this console, so its output is shown as
  # it comes and never mixes with the exit code this function returns.
  $quoted = @($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } })
  $process = Start-Process -FilePath $FilePath -ArgumentList $quoted -NoNewWindow -Wait -PassThru
  $code = $process.ExitCode
  $time = Format-InstallDuration -Duration ((Get-Date) - $started)
  if ($StopCodes.ContainsKey($code)) {
    Write-InstallLine -Text "  < stopped after ${time}: $($StopCodes[$code])" -Color Yellow
  } elseif ($code -eq 0 -or $OkCodes.ContainsKey($code)) {
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
    Write-Warning 'This is Windows 10 22H2. BORC targets Windows 11; it continues, on a best effort basis.'
    return
  }
  throw "BORC needs Windows 11, or Windows 10 22H2 (build 19045). This machine runs build $Build."
}

function Initialize-BorcSession {
  # Process scope only: the machine and user execution policies stay as they are.
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

# BORC keeps the PowerShell Gallery modules it needs in its own folder, not in
# Documents: Documents may be redirected or protected (controlled folder
# access), and BORC installs nothing there. Returns what to give Import-Module.
function Install-BorcGalleryModule {
  param([Parameter(Mandatory = $true)] [string] $Name, [string] $Folder = (Join-Path $env:LOCALAPPDATA 'borc\modules\WindowsPowerShell'))
  $saved = Join-Path $Folder $Name
  if (Test-Path -LiteralPath $saved) { return $saved }
  if (Get-Module -ListAvailable -Name $Name) { return $Name }
  $nuget = Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' }
  if (-not $nuget) {
    Write-InstallLine -Text '  > Install-PackageProvider NuGet'
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
  }
  # PSGallery is not marked as trusted; -Force answers its prompt for this save only.
  Write-InstallLine -Text "  > Save-Module $Name -Path $Folder"
  New-Item -ItemType Directory -Path $Folder -Force | Out-Null
  Save-Module -Name $Name -Path $Folder -Repository PSGallery -Force -ErrorAction Stop
  $saved
}

function Update-BorcWinget {
  try {
    $module = Install-BorcGalleryModule -Name 'Microsoft.WinGet.Client'
    Import-Module -Name $module -ErrorAction Stop
  } catch {
    throw "Could not install the PowerShell module Microsoft.WinGet.Client, which BORC uses to update winget: $($_.Exception.Message)`nIf the PowerShell Gallery is down or blocked on this network, run the installer with BORC_SKIP_UPDATES=1: it keeps the installed winget and does not need the Gallery for it."
  }
  try {
    Write-InstallLine -Text '  > Repair-WinGetPackageManager -Latest'
    $started = Get-Date
    Repair-WinGetPackageManager -Latest -ErrorAction Stop | Out-Null
    Write-InstallLine -Text "  < done in $(Format-InstallDuration -Duration ((Get-Date) - $started))" -Color Green
  } catch {
    throw "winget could not be updated: $($_.Exception.Message)`nUpdate App Installer from the Microsoft Store, then run the BORC installer again."
  }
}

# winget configure refuses to run any file until its extended features are
# enabled, which a new machine may not have. Enabling them needs the Store; a
# failure does not stop the installer, and borc apply then says what to run.
function Enable-BorcWingetConfigure {
  $code = Invoke-InstallCommand -FilePath 'winget' -Arguments @('configure', '--enable', '--disable-interactivity')
  if ($code -ne 0) {
    Write-Warning "winget could not enable its configuration features (exit code $(Format-InstallExitCode -Code $code)). borc apply will fail until they are: run winget configure --enable, then borc apply."
  }
}

function Update-BorcSessionPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$machine;$user"
}

# BORC_SKIP_UPDATES, read from this process only like BORC_BRANCH: install what
# is missing, update nothing.
function Test-BorcSkipUpdates {
  if ($env:BORC_SKIP_UPDATES -notmatch '^(1|true|yes)$') { return $false }
  Write-Warning 'BORC_SKIP_UPDATES is set: winget, Git, PowerShell 7 and Microsoft.DSC are installed only if missing, and never updated.'
  $true
}

function Get-BorcWingetVersion {
  $text = "$(& winget --version 2>$null)"
  if ($LASTEXITCODE -ne 0 -or $text -notmatch '(\d+)\.(\d+)\.(\d+)') { return $null }
  [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
}

# With the update skipped, winget must still be able to run configuration
# files: BORC cannot work without winget configure.
function Assert-BorcWingetConfigure {
  $version = Get-BorcWingetVersion
  if (-not $version) {
    throw "winget is not installed, and BORC_SKIP_UPDATES stops the installer from installing it. Install App Installer from the Microsoft Store, or run the installer without BORC_SKIP_UPDATES."
  }
  & winget configure --help 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "winget $version cannot run configuration files (winget configure), which BORC needs. Update App Installer from the Microsoft Store, or run the installer without BORC_SKIP_UPDATES."
  }
  if ($version -lt $WingetVerifiedVersion) {
    Write-Warning "winget $version is older than $WingetVerifiedVersion, the version BORC's configuration files were checked with. borc apply may fail on the dscv3 processor; if it does, update App Installer."
  }
  Write-InstallLine -Text "  winget $version can run configuration files; not updated (BORC_SKIP_UPDATES)."
}

function Test-BorcToolPresent {
  param([Parameter(Mandatory = $true)] [string] $Id)
  if (Get-Command -Name $BorcTools[$Id] -CommandType Application -ErrorAction SilentlyContinue) { return $true }
  & winget list --id $Id --exact --accept-source-agreements --disable-interactivity 2>$null | Out-Null
  $LASTEXITCODE -eq 0
}

function Install-BorcWingetPackage {
  param([Parameter(Mandatory = $true)] [string] $Id, [switch] $OnlyIfMissing)
  if ($OnlyIfMissing -and (Test-BorcToolPresent -Id $Id)) {
    Write-InstallLine -Text "  $Id is installed; not updated (BORC_SKIP_UPDATES)."
    return
  }
  $arguments = @('install', '--id', $Id, '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
  $code = Invoke-InstallCommand -FilePath 'winget' -Arguments $arguments -OkCodes $WingetAlreadyFine
  if ($code -ne 0 -and -not $WingetAlreadyFine.ContainsKey($code)) {
    throw "winget could not install $Id (exit code $(Format-InstallExitCode -Code $code))."
  }
}

function Test-BorcVcRuntime {
  param([string] $Folder = [Environment]::GetFolderPath('System'))
  Test-Path -LiteralPath (Join-Path $Folder $BorcVcRuntimeFile)
}

function Get-BorcVcRedistId {
  if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { return 'Microsoft.VCRedist.2015+.arm64' }
  'Microsoft.VCRedist.2015+.x64'
}

# Only when it is missing, as its installer may ask for admin rights. A failure
# does not stop BORC: configurations without elevated units still work.
function Install-BorcVcRuntime {
  if (Test-BorcVcRuntime) { return }
  $id = Get-BorcVcRedistId
  Write-InstallLine -Text "  Windows has no $BorcVcRuntimeFile, which winget configure needs for elevated units: installing $id."
  try {
    Install-BorcWingetPackage -Id $id
  } catch {
    Write-Warning "$($_.Exception.Message) Recipes with elevated units will fail until it is installed."
  }
}

# The engine branch: main, unless BORC_BRANCH is set for this process to test
# an unreleased branch. Never stored: rerunning without it goes back to main.
function Get-BorcEngineBranch {
  if ($env:BORC_BRANCH) {
    Write-Warning "BORC_BRANCH is set: installing the BORC engine from the branch $env:BORC_BRANCH, not from the release branch $BorcReleaseBranch."
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
    # Nobody works in this clone: it takes the remote branch as it is, even rewritten.
    Invoke-BorcEngineGit -Arguments @('-C', $Path, 'fetch', '--prune', 'origin') -Action "fetch $RepoUrl"
    Invoke-BorcEngineGit -Arguments @('-C', $Path, 'switch', '--force', $Branch) -Action "switch the BORC engine to the branch $Branch"
    Invoke-BorcEngineGit -Arguments @('-C', $Path, 'reset', '--hard', "origin/$Branch") -Action 'update the BORC engine'
  } else {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    Invoke-BorcEngineGit -Arguments @('clone', '--branch', $Branch, $RepoUrl, $Path) -Action "clone the branch $Branch of $RepoUrl"
  }
}

# The terminal that started the installer keeps its old environment: a process
# cannot change its parent's. This line reloads what setup saved for the user.
$BorcReloadLine = '$env:Path = [Environment]::GetEnvironmentVariable(''Path'', ''Machine'') + '';'' + [Environment]::GetEnvironmentVariable(''Path'', ''User''); $env:BORC_SETTINGS = [Environment]::GetEnvironmentVariable(''BORC_SETTINGS'', ''User''); $env:BORC_HOME = [Environment]::GetEnvironmentVariable(''BORC_HOME'', ''User'')'

function Write-BorcNewTerminalNote {
  Write-InstallLine -Text ''
  Write-InstallLine -Text 'Open a new terminal to use BORC: it loads the borc command, your borc/scripts and Tab completion.' -Color Cyan
  Write-InstallLine -Text 'To use the borc command in this PowerShell window instead, run:'
  Write-InstallLine -Text "  $BorcReloadLine"
}

# Everything is installed; only the configuration did not apply. Rerunning the
# installer is not what fixes that, so the note says what does.
function Write-BorcFirstApplyFailedNote {
  Write-InstallLine -Text ''
  Write-InstallLine -Text 'BORC is installed, but its first borc apply did not finish: see the errors above.' -Color Yellow
  Write-InstallLine -Text 'Fix the cause, then run borc apply in a new terminal, which loads the borc command.'
  Write-InstallLine -Text 'To use the borc command in this PowerShell window instead, run:'
  Write-InstallLine -Text "  $BorcReloadLine"
}

# Setup finished before the restart was asked for, so only the apply is left.
function Write-BorcRestartNote {
  Write-InstallLine -Text ''
  Write-InstallLine -Text 'BORC is installed, and Windows needs a restart before its first borc apply can finish.' -Color Yellow
  Write-InstallLine -Text 'Restart, then run borc apply in a new terminal: it applies the rest.'
}

function Install-Borc {
  $ErrorActionPreference = 'Stop'
  $status = 'failed'
  try {
    Initialize-BorcSession
    Start-InstallStep -Name 'Windows version'
    Assert-BorcWindowsVersion
    $skipUpdates = Test-BorcSkipUpdates
    if ($skipUpdates) {
      Start-InstallStep -Name 'winget: checking it can run configuration files (update skipped)'
      Assert-BorcWingetConfigure
      Start-InstallStep -Name 'Git, PowerShell 7 and Microsoft.DSC, if missing (updates skipped)'
    } else {
      Start-InstallStep -Name 'Updating winget'
      Update-BorcWinget
      Start-InstallStep -Name 'Git, PowerShell 7 and Microsoft.DSC'
    }
    Enable-BorcWingetConfigure
    Install-BorcVcRuntime
    foreach ($id in $BorcTools.Keys) { Install-BorcWingetPackage -Id $id -OnlyIfMissing:$skipUpdates }
    Update-BorcSessionPath
    $branch = Get-BorcEngineBranch
    $engine = Join-Path $env:LOCALAPPDATA 'borc\engine'
    Start-InstallStep -Name "BORC engine, branch $branch ($engine)"
    Install-BorcEngine -Path $engine -Branch $branch
    Start-InstallStep -Name 'BORC setup and borc apply, under PowerShell 7'
    $code = Invoke-InstallCommand -FilePath 'pwsh.exe' -Arguments @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $engine 'src\setup.ps1')) -StopCodes @{ 3010 = 'restart needed'; $BorcFirstApplyFailedExitCode = 'BORC is installed; its first borc apply did not finish' }
    if ($code -eq 3010) { $status = 'restart'; return } # borc apply asked for a restart.
    if ($code -eq $BorcFirstApplyFailedExitCode) { $status = 'partial'; return }
    if ($code -ne 0) { throw "BORC setup did not finish (exit code $code). The log path is shown above." }
    $status = 'done'
  } finally {
    Complete-InstallStep -Status $status
    Write-InstallSummary
    if ($status -eq 'done') { Write-BorcNewTerminalNote }
    if ($status -eq 'partial') { Write-BorcFirstApplyFailedNote }
    if ($status -eq 'restart') { Write-BorcRestartNote }
  }
}

# Errors are thrown rather than exited, so running this through irm | iex in
# an open window never closes it.
Install-Borc
