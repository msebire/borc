BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

  # Runs a script block in the module with Write-Host captured as text and colour.
  function Get-HostLines {
    param([Parameter(Mandatory)] [scriptblock] $Script, [hashtable] $Parameters = @{})
    InModuleScope Borc -Parameters @{ S = $Script; P = $Parameters } {
      param($S, $P)
      $script:Lines = [System.Collections.Generic.List[object]]::new()
      Mock Write-Host { $script:Lines.Add([pscustomobject]@{ Text = "$Object"; Color = $ForegroundColor }) }
      # Recreated here so it runs in the module's scope, not the test file's.
      & ([scriptblock]::Create($S.ToString())) @P | Out-Null
      $script:Lines
    }
  }
}

Describe 'Durations' {
  It 'shows <Seconds> seconds as <Text>' -ForEach @(
    @{ Seconds = 0.4; Text = '0s' }, @{ Seconds = 14.9; Text = '14s' }, @{ Seconds = 125; Text = '2m 05s' }
  ) {
    InModuleScope Borc -Parameters @{ S = $Seconds } { param($S) Format-BorcDuration -Duration ([TimeSpan]::FromSeconds($S)) } | Should -Be $Text
  }

  It 'shows exit codes in decimal when small and in hex otherwise' {
    InModuleScope Borc { Format-BorcExitCode -Code 1 } | Should -Be '1'
    InModuleScope Borc { Format-BorcExitCode -Code -1978335212 } | Should -Be '0x8A150014'
  }
}

Describe 'Steps and summary' {
  BeforeEach { $script:SavedNoColor = $env:NO_COLOR; $env:NO_COLOR = $null }
  AfterEach { $env:NO_COLOR = $script:SavedNoColor }

  It 'numbers the steps, separates them with a blank line, and colours the headers' {
    $lines = Get-HostLines {
      Start-BorcSteps -Total 3
      Start-BorcStep -Name 'First'
      Start-BorcStep -Name 'Second'
    }
    $lines.Text | Should -Be @('', '==> [1/3] First', '', '==> [2/3] Second')
    ($lines | Where-Object Text -Like '==>*').Color | Should -Be @('Cyan', 'Cyan')
  }

  It 'summarises each step reached with its result, and says where it stopped' {
    $lines = Get-HostLines {
      Start-BorcSteps -Total 3
      Start-BorcStep -Name 'Pull'
      Start-BorcStep -Name 'Check'
      Complete-BorcRun -ExitCode 1
    }
    $summary = @($lines | Select-Object -Skip 5)
    $summary[0].Text | Should -Be 'Summary:'
    $summary[1].Text | Should -Match '^  done     \[1/3\] Pull \s+0s$'
    $summary[1].Color | Should -Be 'Green'
    $summary[2].Text | Should -Match '^  failed   \[2/3\] Check\s+0s$'
    $summary[2].Color | Should -Be 'Red'
    $summary[3].Text | Should -Be '  Stopped after step 2 of 3.'
  }

  It 'marks the last step as restart for exit code 3010' {
    $lines = Get-HostLines { Start-BorcSteps -Total 1; Start-BorcStep -Name 'Apply'; Complete-BorcRun -ExitCode 3010 }
    ($lines | Where-Object Text -Match 'restart').Color | Should -Be 'Yellow'
  }

  It 'shows no summary for a command without steps' {
    $lines = Get-HostLines { Start-BorcSteps -Total 0; Complete-BorcRun -ExitCode 0 }
    $lines | Should -BeNullOrEmpty
  }

  It 'drops every colour when NO_COLOR is set, and keeps the words' {
    $env:NO_COLOR = '1'
    $lines = Get-HostLines {
      Start-BorcSteps -Total 1
      Start-BorcStep -Name 'Only'
      Write-BorcLog -Message 'careful' -Level Warning
      Complete-BorcRun -ExitCode 1
    }
    $lines.Color | Where-Object { $_ } | Should -BeNullOrEmpty
    $lines.Text | Should -Contain 'Warning: careful'
    ($lines.Text -join "`n") | Should -Match 'failed   \[1/1\] Only'
  }
}

Describe 'External commands' {
  BeforeEach { $script:SavedNoColor = $env:NO_COLOR; $env:NO_COLOR = $null }
  AfterEach { $env:NO_COLOR = $script:SavedNoColor }

  It 'frames a git command with a start line, indented output and a green end line' {
    $lines = Get-HostLines { Invoke-BorcGit -Arguments @('--version') }
    $lines[0].Text | Should -Be '  > git --version'
    $lines[1].Text | Should -Match '^  \|   git version'
    $lines[1].Color | Should -Be 'DarkGray'
    $lines[-1].Text | Should -Match '^  < done in \d+s$'
    $lines[-1].Color | Should -Be 'Green'
  }

  It 'ends a failing command with a red line and its exit code' {
    $folder = New-TestFolder
    try {
      $lines = Get-HostLines { param($F) Invoke-BorcGit -Arguments @('-C', $F, 'status') } -Parameters @{ F = $folder }
      $lines[-1].Text | Should -Match '^  < failed, exit code 128, after \d+s$'
      $lines[-1].Color | Should -Be 'Red'
    } finally {
      Remove-Item -LiteralPath $folder -Recurse -Force
    }
  }

  It 'keeps quiet git calls off the console' {
    Get-HostLines { Invoke-BorcGit -Arguments @('--version') -Quiet } | Should -BeNullOrEmpty
  }

  It 'treats the codes a command passes as fine, with their meaning' {
    $lines = Get-HostLines {
      Write-BorcCommandEnd -ExitCode -1978335189 -Duration ([TimeSpan]::FromSeconds(2)) -OkCodes @{ -1978335189 = 'no upgrade available' }
    }
    $lines[0].Text | Should -Be '  < done in 2s (no upgrade available)'
    $lines[0].Color | Should -Be 'Green'
  }
}

Describe 'Log file' {
  It 'gets the same lines with the time and without colour codes' {
    $folder = New-TestFolder
    try {
      $log = InModuleScope Borc -Parameters @{ F = $folder } {
        param($F)
        Mock Write-Host {}
        $log = Start-BorcLog -Directory $F -Command 'test'
        Start-BorcSteps -Total 1
        Start-BorcStep -Name 'Only'
        Invoke-BorcGit -Arguments @('--version') | Out-Null
        Complete-BorcRun -ExitCode 0
        Stop-BorcLog
        $log
      }
      $text = Read-TestText -Path $log
      $text | Should -Match '(?m)^\d\d:\d\d:\d\d ==> \[1/1\] Only$'
      $text | Should -Match '(?m)^\d\d:\d\d:\d\d   > git --version$'
      $text | Should -Match '(?m)^\d\d:\d\d:\d\d   < done in \d+s$'
      $text | Should -Match '(?m)^\d\d:\d\d:\d\d   done     \[1/1\] Only'
      $text | Should -Not -Match "`e\["
    } finally {
      Remove-Item -LiteralPath $folder -Recurse -Force
    }
  }
}

Describe 'A command run' {
  It 'shows the steps of apply and a summary that points at the failing step' {
    $root = New-TestFolder
    try {
      $settings = Join-Path $root 'settings'
      New-Item -ItemType Directory -Path (Join-Path $settings 'borc') -Force | Out-Null
      Set-Content -Path (Join-Path $settings 'borc\borc.yaml') -Value "apps:`n  - recipe: '@local/missing'"
      git init --quiet --initial-branch home $settings
      git -C $settings config core.autocrlf false
      git -C $settings add -A
      git -C $settings -c user.name=borc-test -c user.email=borc-test@example.invalid commit --quiet -m seed
      $paths = [pscustomobject]@{ Internal = $root; Engine = Join-Path $root 'engine'; Recipes = Join-Path $root 'recipes'; Logs = Join-Path $root 'logs'; Bin = Join-Path $root 'bin'; Settings = $settings; Home = $root }
      $lines = Get-HostLines { param($P) Mock Get-BorcPaths { $P }; Invoke-Borc -Arguments @('apply') } -Parameters @{ P = $paths }
      $text = $lines.Text -join "`n"
      $text | Should -Match '==> \[1/5\] Pulling the config repo'
      $text | Should -Match '==> \[3/5\] Checking borc.yaml and the recipes'
      $text | Should -Match 'done     \[1/5\]'
      $text | Should -Match 'failed   \[3/5\] Checking borc.yaml and the recipes'
      $text | Should -Match 'Stopped after step 3 of 5.'
      $text | Should -Match 'Log: '
    } finally {
      Remove-Item -LiteralPath $root -Recurse -Force
    }
  }
}
