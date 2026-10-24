# Secrets are declared in borc.yaml and stored in Windows Credential Manager as
# borc:<NAME>. Only names are ever logged or printed, never values.

function Get-BorcMissingSecrets {
  param([Parameter(Mandatory)] [System.Collections.IDictionary] $Secrets)
  @($Secrets.Keys | Where-Object { -not (Test-BorcStoredSecret -Name $_) })
}

function Request-BorcMissingSecrets {
  param([Parameter(Mandatory)] [System.Collections.IDictionary] $Secrets)
  $missing = @(Get-BorcMissingSecrets -Secrets $Secrets)
  if ($missing.Count -eq 0) {
    Write-BorcLog -Message $(if ($Secrets.Count -eq 0) { 'No secret is declared.' } else { "All $($Secrets.Count) declared secret(s) are in Windows Credential Manager." })
    return
  }
  foreach ($name in $missing) {
    $value = Read-BorcSecretInput -Prompt "Secret $name ($($Secrets[$name]))"
    if ($null -eq $value -or $value.Length -eq 0) { throw "No value given for the secret $name." }
    Set-BorcStoredSecret -Name $name -Value $value
    Write-BorcLog -Message "Stored $name in Windows Credential Manager as $script:BorcCredentialPrefix$name."
  }
}
