# Thin wrappers over environment variables and interactive input, so tests can
# mock them and never touch the user's real environment.
function Get-BorcEnvironmentVariable {
  param([Parameter(Mandatory)] [string] $Name, [ValidateSet('Process', 'User')] [string] $Scope = 'Process')
  [Environment]::GetEnvironmentVariable($Name, $Scope)
}

# Sets a user variable and the same value in the current process.
function Set-BorcUserEnvironmentVariable {
  param([Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] [string] $Value)
  [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
  [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

# The user PATH is read and written through the registry so entries such as
# %USERPROFILE%\bin stay unexpanded (REG_EXPAND_SZ).
function Get-BorcUserPath {
  $key = Get-Item -LiteralPath 'HKCU:\Environment'
  $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
}

function Set-BorcUserPath {
  param([Parameter(Mandatory)] [string] $Value)
  Set-ItemProperty -LiteralPath 'HKCU:\Environment' -Name 'Path' -Value $Value -Type ExpandString
}

# Defender's controlled folder access blocks unknown programs from writing in
# protected folders such as Documents. $false when it is off or unknown.
function Test-BorcControlledFolderAccess {
  try { [int](Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess -eq 1 } catch { $false }
}

function Read-BorcInput {
  param([Parameter(Mandatory)] [string] $Prompt)
  Read-Host -Prompt $Prompt
}

function Read-BorcSecretInput {
  param([Parameter(Mandatory)] [string] $Prompt)
  Read-Host -Prompt $Prompt -AsSecureString
}

function Get-BorcWindowsBuild {
  [Environment]::OSVersion.Version.Build
}

# Folders borc works with. Commands take paths from here so tests can redirect them.
function Get-BorcPaths {
  $internal = Join-Path (Get-BorcEnvironmentVariable -Name 'LOCALAPPDATA') 'borc'
  [pscustomobject]@{
    Internal = $internal
    Engine = Join-Path $internal 'engine'
    Recipes = Join-Path $internal 'recipes'
    Logs = Join-Path $internal 'logs'
    Bin = Join-Path $internal 'bin'
    # PowerShell Gallery modules borc saved for itself (see Install-BorcYamlModule).
    Modules = Join-Path $internal 'modules\PowerShell'
    Settings = Get-BorcEnvironmentVariable -Name 'BORC_SETTINGS'
    Home = Get-BorcEnvironmentVariable -Name 'BORC_HOME'
  }
}
