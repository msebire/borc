# Thin wrappers over Borc.CredentialStore (defined in Get-BorcSecret.ps1), so
# tests can mock Credential Manager. Values never reach the log.
function Test-BorcStoredSecret {
  param([Parameter(Mandatory)] [string] $Name, [string] $Prefix = $script:BorcCredentialPrefix)
  $null -ne [Borc.CredentialStore]::Read("$Prefix$Name")
}

function Set-BorcStoredSecret {
  param(
    [Parameter(Mandatory)] [string] $Name,
    [Parameter(Mandatory)] [securestring] $Value,
    [string] $Prefix = $script:BorcCredentialPrefix
  )
  $plain = [System.Net.NetworkCredential]::new('', $Value).Password
  [Borc.CredentialStore]::Write("$Prefix$Name", $plain)
}

function Remove-BorcStoredSecret {
  param([Parameter(Mandatory)] [string] $Name, [string] $Prefix = $script:BorcCredentialPrefix)
  [Borc.CredentialStore]::Delete("$Prefix$Name")
}
