BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Logs' {
  BeforeEach { $script:Folder = New-TestFolder }
  AfterEach {
    InModuleScope Borc { $script:BorcLogPath = $null }
    Remove-Item -LiteralPath $script:Folder -Recurse -Force
  }

  It 'keeps the newest 20 logs with the files of their run' {
    for ($i = 0; $i -lt 25; $i++) {
      $stem = '20260101-0000{0:00}-000-apply' -f $i
      Set-Content -Path (Join-Path $script:Folder "$stem.log") -Value x
      Set-Content -Path (Join-Path $script:Folder "$stem.main.winget.yaml") -Value x
    }
    InModuleScope Borc -Parameters @{ F = $script:Folder } { param($F) Start-BorcLog -Directory $F -Command 'apply' } | Out-Null
    $logs = @(Get-ChildItem -Path $script:Folder -Filter '*.log')
    $logs.Count | Should -Be 20
    $logs.Name | Should -Not -Contain '20260101-000005-000-apply.log'
    Test-Path (Join-Path $script:Folder '20260101-000005-000-apply.main.winget.yaml') | Should -BeFalse
    Test-Path (Join-Path $script:Folder '20260101-000024-000-apply.main.winget.yaml') | Should -BeTrue
  }

  It 'writes messages and tool output, but not progress spinners' {
    InModuleScope Borc -Parameters @{ F = $script:Folder } {
      param($F)
      Mock Write-Host {}
      $log = Start-BorcLog -Directory $F -Command 'apply'
      Write-BorcLog -Message 'hello'
      Write-BorcLog -Message 'careful' -Level Warning
      Write-BorcOutputLine -Line '  \ '
      Write-BorcOutputLine -Line 'Found Git [Git.Git]'
      $text = [IO.File]::ReadAllText($log)
      $text | Should -Match 'hello'
      $text | Should -Match 'WARNING: careful'
      $text | Should -Match 'Found Git'
      $text | Should -Not -Match '\\'
      Stop-BorcLog
      Should -Invoke Write-Host -ParameterFilter { $Object -eq "Log: $log" }
    }
  }
}
