# Secrets are declared in borc.yaml and stored in Windows Credential Manager as
# borc:<NAME>. Only names are ever logged or printed, never values.

function Get-BorcMissingSecrets {
  param([Parameter(Mandatory)] [System.Collections.IDictionary] $Secrets)
  @($Secrets.Keys | Where-Object { -not (Test-BorcStoredSecret -Name $_) })
}

function Request-BorcMissingSecrets {
  param([Parameter(Mandatory)] [System.Collections.IDictionary] $Secrets)
  foreach ($name in (Get-BorcMissingSecrets -Secrets $Secrets)) {
    $value = Read-BorcSecretInput -Prompt "Secret $name ($($Secrets[$name]))"
    if ($null -eq $value -or $value.Length -eq 0) { throw "No value given for the secret $name." }
    Set-BorcStoredSecret -Name $name -Value $value
    Write-BorcLog -Message "Stored $name in Windows Credential Manager as $script:BorcCredentialPrefix$name."
  }
}
