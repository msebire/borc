<#
.SYNOPSIS
  Stand-in for the planned Write-BorcVersion helper, for manual checks V3 and V4.

.DESCRIPTION
  Copy it to %LOCALAPPDATA%\borc-check. Units dot-source it from there and call
  Write-CheckVersion, which writes one JSON file to %LOCALAPPDATA%\borc-check\versions
  and prints nothing, so a testScript still outputs exactly one boolean. Each report
  also records who wrote it, so the check shows which profile an elevated unit used.
#>

function Write-CheckVersion {
  param([Parameter(Mandatory)] [string] $App, [string] $Installed = '', [string] $Available = '', [string] $Note = '')
  try {
    $folder = Join-Path $env:LOCALAPPDATA 'borc-check\versions'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $report = [ordered]@{
      App = $App
      Installed = $Installed
      Available = $Available
      Note = $Note
      User = $identity.Name
      Elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
      PowerShell = "$($PSVersionTable.PSVersion)"
      LocalAppData = $env:LOCALAPPDATA
      Time = (Get-Date).ToString('o')
    }
    $file = Join-Path $folder "$App-$([guid]::NewGuid().ToString('N')).json"
    [IO.File]::WriteAllText($file, ($report | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  } catch {
    # A report must never fail the unit, so a failure writes and prints nothing.
    $null = $_
  }
}
