# The install steps that run under PowerShell 7, after install.ps1 has updated
# winget, installed Git, PowerShell 7 and Microsoft.DSC, and cloned the engine.
# Every step checks first, so the installer can be run again safely.

function Invoke-BorcSetup {
  [CmdletBinding()]
  [OutputType([int])]
  param()
  $paths = Get-BorcPaths
  Start-BorcLog -Directory $paths.Logs -Command 'install' | Out-Null
  Start-BorcSteps -Total 5
  $code = 1
  try {
    Start-BorcStep -Name 'PowerShell modules'
    Install-BorcYamlModule
    Start-BorcStep -Name 'Folders: BORC_SETTINGS and BORC_HOME'
    $settings = Get-BorcFolderSetting -Name 'BORC_SETTINGS' -Purpose 'the config repo clone, where apps read their settings' -Example 'D:\settings'
    $homeFolder = Get-BorcFolderSetting -Name 'BORC_HOME' -Purpose 'your home base, where the terminal opens' -Example 'D:\sources'
    Start-BorcStep -Name "Config repo ($settings)"
    Initialize-BorcSettingsInteractive -Path $settings
    New-Item -ItemType Directory -Path $homeFolder -Force | Out-Null
    Start-BorcStep -Name 'The borc command, PATH and environment variables'
    Install-BorcRuntimeFiles -Paths $paths
    Add-BorcUserPath -Folder $paths.Bin
    # Set last: SetEnvironmentVariable tells running apps the environment changed.
    Set-BorcUserEnvironmentVariable -Name 'BORC_SETTINGS' -Value $settings
    Set-BorcUserEnvironmentVariable -Name 'BORC_HOME' -Value $homeFolder
    Start-BorcStep -Name 'PowerShell 7 profile block'
    $written = Update-BorcProfileBlockOrExplain -Path (Get-BorcProfilePath)
    if ($written) { Write-BorcLog -Message "Added the borc block to $(Get-BorcProfilePath)." }
    elseif ($written -eq $false) { Write-BorcLog -Message 'The borc block is already up to date.' }
    $code = 0
  } catch {
    Write-BorcLog -Message $_.Exception.Message -Level Error
  } finally {
    Complete-BorcRun -ExitCode $code
    Stop-BorcLog
  }
  if ($code -ne 0) { return $code }
  Write-BorcConsole -Text ''
  Write-BorcConsole -Text 'borc is installed. Running borc apply.' -Color Cyan
  Invoke-Borc -Arguments @('apply')
}

# Saved in borc's own folder rather than Documents, which may be redirected or
# protected by controlled folder access. Import-BorcYamlModule loads it from there.
function Install-BorcYamlModule {
  $folder = (Get-BorcPaths).Modules
  if ((Test-Path -LiteralPath (Join-Path $folder 'powershell-yaml')) -or (Get-Module -ListAvailable -Name powershell-yaml)) { return }
  Write-BorcLog -Message "Saving the powershell-yaml module from the PowerShell Gallery into $folder."
  New-Item -ItemType Directory -Path $folder -Force | Out-Null
  try {
    Save-Module -Name powershell-yaml -Path $folder -Repository PSGallery -Force -ErrorAction Stop
  } catch {
    throw "Could not install the PowerShell module powershell-yaml: $($_.Exception.Message)"
  }
}

function Get-BorcProfilePath {
  $PROFILE.CurrentUserAllHosts
}

function Test-BorcFolderPath {
  param([AllowEmptyString()] [string] $Path)
  $Path -match '^[A-Za-z]:\\' -and $Path -notmatch '[<>"|?*]'
}

# Reuses the user variable when set; otherwise asks until the answer is a full path.
function Get-BorcFolderSetting {
  param([Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] [string] $Purpose, [Parameter(Mandatory)] [string] $Example)
  $current = Get-BorcEnvironmentVariable -Name $Name -Scope User
  if ($current) {
    Write-BorcLog -Message "$Name is $current."
    return $current
  }
  while ($true) {
    $answer = (Read-BorcInput -Prompt "$Name, $Purpose (for example $Example)").Trim().Trim('"').TrimEnd('\')
    if (Test-BorcFolderPath -Path "$answer\") { return $answer }
    Write-Host "Give a full path with a drive letter, for example $Example."
  }
}

function Initialize-BorcSettingsInteractive {
  param([Parameter(Mandatory)] [string] $Path)
  if (Test-BorcGitRepo -Path $Path) {
    Write-BorcLog -Message "$Path is already a Git repo; using it as it is."
    return
  }
  if ((Get-BorcSettingsFolderState -Path $Path) -eq 'Other') {
    throw "$Path is not empty and is not a Git repo. Choose another folder for BORC_SETTINGS or empty this one, then run the installer again."
  }
  $url = (Read-BorcInput -Prompt 'Config repo URL (leave empty to start from the starter template)').Trim()
  $branch = Read-BorcBranchName
  Initialize-BorcSettings -Path $Path -Url $url -Branch $branch -ChooseBase { param($branches, $wanted) Select-BorcBaseBranch -Branch $wanted -Branches $branches }
}

function Read-BorcBranchName {
  while ($true) {
    $branch = (Read-BorcInput -Prompt 'Branch for this machine (for example home or work)').Trim()
    if ($branch) {
      $check = Invoke-BorcGit -Arguments @('check-ref-format', '--branch', $branch) -Quiet
      if ($check.ExitCode -eq 0) { return $branch }
    }
    Write-Host 'Give a valid Git branch name.'
  }
}

function Select-BorcBaseBranch {
  param([Parameter(Mandatory)] [string] $Branch, [Parameter(Mandatory)] [string[]] $Branches)
  Write-Host "The branch $Branch does not exist yet. Existing branches:"
  for ($i = 0; $i -lt $Branches.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $Branches[$i]) }
  $answer = (Read-BorcInput -Prompt "Create $Branch from which branch? Number, or empty to stop").Trim()
  if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $Branches.Count) { return $Branches[[int]$answer - 1] }
  $null
}

function Add-BorcUserPath {
  param([Parameter(Mandatory)] [string] $Folder)
  $current = Get-BorcUserPath
  $entries = @($current -split ';' | Where-Object { $_ })
  if ($entries | Where-Object { $_.TrimEnd('\') -eq $Folder.TrimEnd('\') }) { return }
  Set-BorcUserPath -Value (($entries + $Folder) -join ';')
  $env:Path = "$env:Path;$Folder"
  Write-BorcLog -Message "Added $Folder to your PATH."
}
