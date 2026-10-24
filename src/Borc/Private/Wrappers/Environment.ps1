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
    Settings = Get-BorcEnvironmentVariable -Name 'BORC_SETTINGS'
    Home = Get-BorcEnvironmentVariable -Name 'BORC_HOME'
  }
}
