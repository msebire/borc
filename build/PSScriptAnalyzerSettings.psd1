@{
  Severity = @('Error', 'Warning')
  ExcludeRules = @(
    # borc is an interactive command line tool: it talks to the user through the host.
    'PSAvoidUsingWriteHost',
    # Internal helpers are not cmdlets; -WhatIf/-Confirm would only add noise.
    'PSUseShouldProcessForStateChangingFunctions',
    # Names such as Get-BorcPaths and Read-BorcSecrets read better in the plural.
    'PSUseSingularNouns'
  )
}
