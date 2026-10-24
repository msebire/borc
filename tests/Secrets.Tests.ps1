BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  $script:HelperPath = Join-Path $script:RepoRoot 'src\Borc\Get-BorcSecret.ps1'
  # Every credential written here uses this prefix and is removed afterwards.
  $script:Prefix = 'borc-test:'
  $script:Name = 'T' + [guid]::NewGuid().ToString('N').Substring(0, 10)
}

AfterAll {
  InModuleScope Borc -Parameters @{ N = $script:Name; P = $script:Prefix } { param($N, $P) Remove-BorcStoredSecret -Name $N -Prefix $P }
}

Describe 'Get-BorcSecret' {
  It 'reads back a stored secret under PowerShell 7' {
    InModuleScope Borc -Parameters @{ N = $script:Name; P = $script:Prefix } {
      param($N, $P)
      Set-BorcStoredSecret -Name $N -Value (ConvertTo-SecureString 'v@lue with ü' -AsPlainText -Force) -Prefix $P
      Test-BorcStoredSecret -Name $N -Prefix $P | Should -BeTrue
    }
    Get-BorcSecret -Name $script:Name -Prefix $script:Prefix | Should -BeExactly 'v@lue with ü'
  }

  It 'reads the same secret under Windows PowerShell 5.1 by dot-sourcing the helper' {
    $command = ". '$script:HelperPath'; Get-BorcSecret -Name '$script:Name' -Prefix '$script:Prefix'"
    $output = powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $command
    $LASTEXITCODE | Should -Be 0
    $output | Should -BeExactly 'v@lue with ü'
  }

  It 'throws a clear error for a missing secret' {
    { Get-BorcSecret -Name 'NOPE_NOT_THERE' -Prefix $script:Prefix } | Should -Throw '*Secret NOPE_NOT_THERE not found*borc apply*'
  }
}

Describe 'Asking for missing secrets' {
  It 'asks only for missing secrets and never logs the value' {
    InModuleScope Borc {
      $folder = Join-Path ([IO.Path]::GetTempPath()) ('borc-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
      Mock Write-Host {}
      Mock Test-BorcStoredSecret { $Name -eq 'HAVE' }
      Mock Read-BorcSecretInput { ConvertTo-SecureString 'super-secret-value' -AsPlainText -Force }
      Mock Set-BorcStoredSecret {}
      $log = Start-BorcLog -Directory $folder -Command 'test'
      Request-BorcMissingSecrets -Secrets ([ordered]@{ HAVE = 'present'; NEED = 'missing one' })
      Should -Invoke Read-BorcSecretInput -Times 1 -Exactly -ParameterFilter { $Prompt -eq 'Secret NEED (missing one)' }
      Should -Invoke Set-BorcStoredSecret -Times 1 -Exactly -ParameterFilter { $Name -eq 'NEED' }
      [IO.File]::ReadAllText($log) | Should -Not -Match 'super-secret-value'
      [IO.File]::ReadAllText($log) | Should -Match 'Stored NEED'
      Stop-BorcLog
      Remove-Item -LiteralPath $folder -Recurse -Force
    }
  }
}
