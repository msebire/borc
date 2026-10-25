BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

  function Invoke-TestBorc {
    param([string[]] $Arguments)
    InModuleScope Borc -Parameters @{ A = $Arguments } {
      param($A)
      $script:Shown = [System.Collections.Generic.List[string]]::new()
      Mock Write-Host { $script:Shown.Add("$Object") }
      $code = Invoke-Borc -Arguments $A
      [pscustomobject]@{ Code = $code; Output = ($script:Shown -join "`n") }
    }
  }
}

Describe 'Help' {
  It 'lists the commands for <Arguments>' -ForEach @(
    @{ Arguments = @() }, @{ Arguments = @('help') }, @{ Arguments = @('--help') }, @{ Arguments = @('-h') }
  ) {
    $result = Invoke-TestBorc -Arguments $Arguments
    $result.Code | Should -Be 0
    foreach ($command in 'help', 'apply', 'upgrade', 'install', 'uninstall', 'search', 'self-update') {
      $result.Output | Should -Match "(?m)^  $command\b"
    }
  }

  It 'shows the page of <Command> with help, --help and -h' -ForEach @(
    @{ Command = 'help' }, @{ Command = 'apply' }, @{ Command = 'upgrade' }, @{ Command = 'install' }
    @{ Command = 'uninstall' }, @{ Command = 'search' }, @{ Command = 'self-update' }
  ) {
    $page = (Invoke-TestBorc -Arguments @('help', $Command)).Output
    $page | Should -Match "^Usage: borc $Command"
    (Invoke-TestBorc -Arguments @($Command, '--help')).Output | Should -BeExactly $page
    (Invoke-TestBorc -Arguments @($Command, '-h')).Output | Should -BeExactly $page
  }

  It 'refuses --check without --what-if' {
    $result = Invoke-TestBorc -Arguments @('apply', '--check')
    $result.Code | Should -Be 2
    $result.Output | Should -Match 'only works with --what-if'
  }

  It 'rejects an unknown command or option' {
    (Invoke-TestBorc -Arguments @('frobnicate')).Code | Should -Be 2
    (Invoke-TestBorc -Arguments @('help', 'frobnicate')).Code | Should -Be 2
    $result = Invoke-TestBorc -Arguments @('apply', '--force')
    $result.Code | Should -Be 2
    $result.Output | Should -Match "Unknown option '--force'"
  }

  It 'shows the page when an argument is missing' {
    $result = Invoke-TestBorc -Arguments @('install')
    $result.Code | Should -Be 2
    $result.Output | Should -Match '^Usage: borc install <app>'
  }
}

Describe 'Reading the install argument' {
  It 'reads <App> as <Kind>' -ForEach @(
    @{ App = 'recipes/node'; Kind = 'recipe' }
    @{ App = '@local/wsl-ubuntu'; Kind = 'recipe' }
    @{ App = '9NBLGGH4NNS1'; Kind = 'msstore' }
    @{ App = 'Git.Git'; Kind = 'winget' }
  ) {
    InModuleScope Borc -Parameters @{ A = $App } { param($A) Get-BorcAppKind -App $A } | Should -Be $Kind
  }

  It 'rejects a malformed recipe reference' {
    { InModuleScope Borc { Get-BorcAppKind -App 'a/b/c' } } | Should -Throw '*not a recipe reference*'
  }
}

Describe 'Commands with winget mocked' {
  BeforeAll {
    $script:Root = New-TestFolder
    $script:Settings = Join-Path $script:Root 'settings'
    $script:Paths = [pscustomobject]@{
      Internal = Join-Path $script:Root 'internal'
      Engine = Join-Path $script:Root 'internal\engine'
      Recipes = Join-Path $script:FixturesRoot 'recipes'
      Logs = Join-Path $script:Root 'internal\logs'
      Bin = Join-Path $script:Root 'internal\bin'
      Settings = $script:Settings
      Home = Join-Path $script:Root 'home'
    }
  }
  AfterAll { Remove-Item -LiteralPath $script:Root -Recurse -Force }

  BeforeEach {
    Remove-Item -LiteralPath $script:Settings -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath (Join-Path $script:FixturesRoot 'settings') -Destination $script:Settings -Recurse
    git init --quiet --initial-branch home $script:Settings
    git -C $script:Settings config core.autocrlf false
    git -C $script:Settings add -A
    git -C $script:Settings -c user.name=borc-test -c user.email=borc-test@example.invalid commit --quiet -m seed
  }

  Context 'apply' {
    It 'runs the reboot recipes first, then one merged run, and reports success' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Sync-BorcRecipeRepo {}
        Mock Show-BorcUpdateNotice {}
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Test-BorcStoredSecret { $true }
        Mock Test-BorcRestartPending { $false }
        $script:Configured = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-BorcWinget { $script:Configured.Add([IO.File]::ReadAllText($Arguments[2])); 0 }
        Invoke-Borc -Arguments @('apply') | Should -Be 0
        $script:Configured.Count | Should -Be 2
        $script:Configured[0] | Should -Match 'recipes/wsl: wsl feature'
        $script:Configured[0] | Should -Not -Match 'Git.Git'
        $script:Configured[1] | Should -Match 'winget: Git.Git'
        $script:Configured[1] | Should -Not -Match 'NPM_TOKEN:|borc:'
        Should -Invoke Invoke-BorcWinget -Times 2 -Exactly -ParameterFilter { $Arguments[0] -eq 'configure' -and '--accept-configuration-agreements' -in $Arguments }
        Should -Invoke Write-Host -ParameterFilter { $Object -eq 'Result: done; nothing new was pulled or installed.' }
        Should -Invoke Write-Host -ParameterFilter { $Object -match '^  recipes:\s+5 run; winget does not say which of their settings changed$' }
      }
    }

    It 'stops before the main run and asks for a restart after the reboot run' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Sync-BorcRecipeRepo {}
        Mock Show-BorcUpdateNotice {}
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Test-BorcStoredSecret { $true }
        $script:RunCount = 0
        Mock Invoke-BorcWinget { $script:RunCount++; 0 }
        Mock Test-BorcRestartPending { $script:RunCount -ge 1 }
        Invoke-Borc -Arguments @('apply') | Should -Be 3010
        $script:RunCount | Should -Be 1
        Should -Invoke Write-Host -ParameterFilter { $Object -match 'Restart, then run borc apply again' }
      }
    }

    It 'exits 1 when winget reports a failure' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Sync-BorcRecipeRepo {}
        Mock Show-BorcUpdateNotice {}
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Test-BorcStoredSecret { $true }
        Mock Test-BorcRestartPending { $false }
        Mock Invoke-BorcWinget { -1978286078 }
        Invoke-Borc -Arguments @('apply') | Should -Be 1
        Should -Invoke Invoke-BorcWinget -Times 1 -Exactly
      }
    }

    It 'asks for missing secrets before running' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Sync-BorcRecipeRepo {}
        Mock Show-BorcUpdateNotice {}
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Test-BorcStoredSecret { $false }
        Mock Read-BorcSecretInput { ConvertTo-SecureString 'x' -AsPlainText -Force }
        Mock Set-BorcStoredSecret {}
        Mock Test-BorcRestartPending { $false }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('apply') | Should -Be 0
        Should -Invoke Set-BorcStoredSecret -Times 1 -Exactly -ParameterFilter { $Name -eq 'NPM_TOKEN' }
      }
    }

    It 'refuses to run with an unknown parameter, before anything runs' {
      $path = Join-Path $script:Settings 'borc\borc.yaml'
      (Get-Content $path -Raw).Replace("  - recipe: recipes/idea`n", "  - recipe: recipes/idea`n    parameters:`n      ideaHome: D:\idea`n") | Set-Content $path -NoNewline
      git -C $script:Settings -c user.name=borc-test -c user.email=borc-test@example.invalid commit --quiet -am param
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Sync-BorcRecipeRepo {}
        Mock Show-BorcUpdateNotice {}
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Invoke-BorcWinget { 0 }
        Mock Read-BorcSecretInput {}
        Invoke-Borc -Arguments @('apply') | Should -Be 1
        ($script:Shown -join "`n") | Should -Match "recipe recipes/idea has no parameter 'ideaHome'"
        Should -Invoke Invoke-BorcWinget -Times 0 -Exactly
        Should -Invoke Read-BorcSecretInput -Times 0 -Exactly
      }
    }

    It 'refuses to pull over a dirty tracked file' {
      Add-Content -Path (Join-Path $script:Settings 'borc\borc.yaml') -Value '# local edit'
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('apply') | Should -Be 1
        ($script:Shown -join "`n") | Should -Match 'uncommitted changes'
        Should -Invoke Invoke-BorcWinget -Times 0 -Exactly
      }
    }

    It 'runs one recipe at a time with --debug and names the failing one' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Sync-BorcRecipeRepo {}
        Mock Show-BorcUpdateNotice {}
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Test-BorcStoredSecret { $true }
        Mock Test-BorcRestartPending { $false }
        $script:Count = 0
        Mock Invoke-BorcWinget { $script:Count++; if ($script:Count -eq 3) { 1 } else { 0 } }
        Invoke-Borc -Arguments @('apply', '--debug') | Should -Be 1
        $script:Count | Should -Be 3
        ($script:Shown -join "`n") | Should -Match 'The failing recipe is recipes/npm-auth'
      }
    }

    It 'tests the recipe units once with --what-if --check and gives definite verdicts' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Invoke-BorcWinget { throw 'winget must not apply anything' }
        Mock Test-BorcStoredSecret { $true }
        # winget answers from the units in the file borc wrote: npm cache would change.
        Mock Invoke-BorcWingetQuiet {
          if ($Arguments[0] -ne 'configure') { return [pscustomobject]@{ ExitCode = 0; Output = @() } }
          $document = ConvertFrom-BorcYaml -Text ([IO.File]::ReadAllText($Arguments[3]))
          $lines = foreach ($unit in $document.resources) {
            "$($unit.type) [$($unit.name)]"
            if ($unit.name -eq 'recipes/node: npm cache') { '  System is not in the described configuration state.' } else { '  System is in the described configuration state.' }
          }
          [pscustomobject]@{ ExitCode = 1; Output = @($lines) }
        }
        Invoke-Borc -Arguments @('apply', '--what-if', '--check') | Should -Be 0
        Should -Invoke Invoke-BorcWingetQuiet -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'configure' -and $Arguments[1] -eq 'test' -and '--suppress-initial-details' -in $Arguments }
        $text = $script:Shown -join "`n"
        $text | Should -Match '==> \[2/5\] Testing the recipes'' units'
        $text | Should -Match '< done in \d+s \(\d+ unit\(s\) tested\)'
        $text | Should -Match '  recipe  recipes/node\s+would be applied\n\s+units: 1 of 2 in place\n\s+would change: npm cache\n\s+skipped: 1 \(no value for npmPrefix\)'
        $text | Should -Match '  recipe  recipes/idea\s+in place'
        $text | Should -Match 'expect one UAC prompt'
        $text | Should -Not -Match '"may be applied"'
      }
    }

    It 'changes nothing with --what-if' {
      $before = git -C $script:Settings rev-parse HEAD
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Invoke-BorcWinget { throw 'winget must not run' }
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = $(if ($Arguments[2] -eq 'Git.Git') { 0 } else { 1 }); Output = @() } }
        Mock Test-BorcStoredSecret { $false }
        Mock Set-BorcStoredSecret { throw 'no secret may be stored' }
        Mock Read-BorcSecretInput { throw 'no secret may be asked' }
        Invoke-Borc -Arguments @('apply', '--what-if') | Should -Be 0
        $text = $script:Shown -join "`n"
        $text | Should -Match '  winget  Git\.Git\s+installed'
        $text | Should -Match '  msstore 9NBLGGH4NNS1\s+would be installed'
        $text | Should -Match '  recipe  recipes/wsl\s+may be applied \(runs first, may need a restart\)'
        $text | Should -Match '  recipe  recipes/node\s+would be applied\n\s+packages: 0 of 1 installed \(OpenJS\.NodeJS\.LTS\)\n\s+settings: 1 unit, not checked; 1 skipped \(no value for npmPrefix\)'
        $text | Should -Match '  recipe  recipes/npm-auth\s+may be applied\n\s+packages: none\n\s+settings: 1 unit, not checked'
        $text | Should -Match '  4 would be installed or applied, 2 may be applied, 1 in place\.'
        $text | Should -Match '"may be applied": no package is missing'
        $text | Should -Match 'Result: there are changes to apply\.\n  pull:\s+recipe repo recipes would be cloned\n  apps and recipes: 4 would be installed or applied, 2 may be applied, 1 in place\n  secrets:\s+1 would be asked for \(NPM_TOKEN\)'
        # The reboot recipe is listed first, as it runs first.
        $text.IndexOf('recipe  recipes/wsl ') | Should -BeLessThan $text.IndexOf('recipe  recipes/node ')
        $text | Should -Match '==> \[3/4\] Secrets that would be asked for'
        $text | Should -Match '  NPM_TOKEN \(token for the company npm registry\)'
        $text | Should -Match 'Nothing was changed'
      }
      git -C $script:Settings rev-parse HEAD | Should -Be $before
      git -C $script:Settings status --porcelain | Should -BeNullOrEmpty
    }
  }

  Context 'install and uninstall' {
    It 'installs a missing winget app and adds it to borc.yaml, keeping comments' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = $(if ($Arguments[0] -eq 'show') { 0 } else { 1 }); Output = @() } }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('install', 'Microsoft.VisualStudioCode') | Should -Be 0
        Should -Invoke Invoke-BorcWinget -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'install' -and $Arguments[2] -eq 'Microsoft.VisualStudioCode' }
      }
      $text = Get-Content (Join-Path $script:Settings 'borc\borc.yaml') -Raw
      $text | Should -Match '# Test fixture: uses every feature.'
      $text | Should -Match "  - recipe: recipes/wsl`n  - winget: Microsoft.VisualStudioCode`nsecrets:"
      git -C $script:Settings log --oneline | Should -HaveCount 1
    }

    It 'refuses an unknown winget ID' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('install', 'No.Such.App') | Should -Be 1
        Should -Invoke Invoke-BorcWinget -Times 0 -Exactly
      }
    }

    It 'only installs a listed app when it is missing, and leaves borc.yaml alone' {
      $before = Get-Content (Join-Path $script:Settings 'borc\borc.yaml') -Raw
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 0; Output = @() } }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('install', 'Git.Git') | Should -Be 0
        Should -Invoke Invoke-BorcWinget -Times 0 -Exactly
      }
      Get-Content (Join-Path $script:Settings 'borc\borc.yaml') -Raw | Should -BeExactly $before
    }

    It 'runs a recipe on its own and adds it' {
      $path = Join-Path $script:Settings 'borc\borc.yaml'
      (Get-Content $path -Raw).Replace("  - recipe: recipes/idea`n", '') | Set-Content $path -NoNewline
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Test-BorcRestartPending { $false }
        $script:Configured = $null
        Mock Invoke-BorcWinget { $script:Configured = [IO.File]::ReadAllText($Arguments[2]); 0 }
        Invoke-Borc -Arguments @('install', 'recipes/idea') | Should -Be 0
        $script:Configured | Should -Match 'recipes/idea: idea package'
        $script:Configured | Should -Not -Match 'Git.Git'
      }
      Get-Content $path -Raw | Should -Match "  - recipe: recipes/idea`nsecrets:"
    }

    It 'uninstalls a winget app and removes its line' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 0; Output = @() } }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('uninstall', 'Git.Git') | Should -Be 0
        Should -Invoke Invoke-BorcWinget -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'uninstall' }
      }
      Get-Content (Join-Path $script:Settings 'borc\borc.yaml') -Raw | Should -Not -Match 'Git.Git'
    }

    It 'still uninstalls an app borc.yaml does not list' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 0; Output = @() } }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('uninstall', 'Other.App') | Should -Be 0
        Should -Invoke Invoke-BorcWinget -Times 1 -Exactly
        ($script:Shown -join "`n") | Should -Match 'no line to remove'
      }
    }

    It 'only removes the line of a recipe and lists its packages' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('uninstall', 'recipes/node') | Should -Be 0
        Should -Invoke Invoke-BorcWinget -Times 0 -Exactly
        ($script:Shown -join "`n") | Should -Match 'borc uninstall OpenJS.NodeJS.LTS'
      }
      $text = Get-Content (Join-Path $script:Settings 'borc\borc.yaml') -Raw
      $text | Should -Not -Match 'recipes/node'
      $text | Should -Not -Match 'npmCache'
    }
  }

  Context 'upgrade and search' {
    It 'upgrades only what borc.yaml lists and skips apps that are not installed' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        $script:Upgraded = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-BorcWinget { $script:Upgraded.Add($Arguments[2]); if ($Arguments[2] -eq 'Canonical.Ubuntu.2404') { $script:WingetNoPackageFound } else { $script:WingetNoApplicableUpgrade } }
        Invoke-Borc -Arguments @('upgrade') | Should -Be 0
        $script:Upgraded | Should -Be @('Git.Git', '9NBLGGH4NNS1', 'OpenJS.NodeJS.LTS', 'JetBrains.IntelliJIDEA.Community', 'Canonical.Ubuntu.2404')
        Should -Invoke Invoke-BorcWinget -ParameterFilter { $Arguments[0] -ne 'upgrade' } -Times 0 -Exactly
      }
    }

    It 'leaves a package with a fixed version alone, and says so' {
      $path = Join-Path $script:Settings 'borc\borc.yaml'
      (Get-Content $path -Raw).Replace("  - winget: Git.Git`n", "  - winget: Git.Git`n    version: '2.45.1'`n") | Set-Content $path -NoNewline
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        $script:Upgraded = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-BorcWinget { $script:Upgraded.Add($Arguments[2]); 0 }
        Invoke-Borc -Arguments @('upgrade') | Should -Be 0
        $script:Upgraded | Should -Not -Contain 'Git.Git'
        $script:Upgraded | Should -Contain '9NBLGGH4NNS1'
        ($script:Shown -join "`n") | Should -Match 'Git\.Git stays at 2\.45\.1, the version fixed in borc\.yaml\.'
      }
    }

    It 'searches recipe names and descriptions, then winget' {
      InModuleScope Borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('search', 'linux') | Should -Be 0
        $text = $script:Shown -join "`n"
        $text | Should -Match 'recipes/wsl\s+Windows Subsystem for Linux'
        $text | Should -Not -Match 'recipes/node'
        Should -Invoke Invoke-BorcWinget -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'search' -and $Arguments[1] -eq 'linux' }
      }
    }
  }
}

Describe 'self-update' {
  BeforeAll {
    $script:Root = New-TestFolder
    $script:Paths = [pscustomobject]@{
      Internal = $script:Root
      Engine = Join-Path $script:Root 'engine'
      Recipes = Join-Path $script:Root 'recipes'
      Logs = Join-Path $script:Root 'logs'
      Bin = Join-Path $script:Root 'bin'
      Settings = $null
      Home = $null
    }
  }
  AfterAll { Remove-Item -LiteralPath $script:Root -Recurse -Force }

  It 'pulls the engine, then lets the updated engine refresh its files and profile block' {
    InModuleScope Borc -Parameters @{ P = $script:Paths } {
      param($P)
      Mock Get-BorcPaths { $P }
      Mock Write-Host {}
      Mock Test-BorcGitRepo { $true }
      Mock Invoke-BorcGit { [pscustomobject]@{ ExitCode = 0; Output = @('abc1234 2026-10-24') } }
      Mock Invoke-BorcEngineRefresh { 0 }
      Invoke-Borc -Arguments @('self-update') | Should -Be 0
      Should -Invoke Invoke-BorcGit -Times 1 -Exactly -ParameterFilter { 'pull' -in $Arguments -and '--ff-only' -in $Arguments }
      Should -Invoke Invoke-BorcEngineRefresh -Times 1 -Exactly
    }
  }

  It 'fails when the updated engine cannot refresh' {
    InModuleScope Borc -Parameters @{ P = $script:Paths } {
      param($P)
      Mock Get-BorcPaths { $P }
      Mock Write-Host {}
      Mock Test-BorcGitRepo { $true }
      Mock Invoke-BorcGit { [pscustomobject]@{ ExitCode = 0; Output = @() } }
      Mock Invoke-BorcEngineRefresh { 1 }
      Invoke-Borc -Arguments @('self-update') | Should -Be 1
    }
  }

  It 'compares the update notice with the branch the engine is on' {
    InModuleScope Borc -Parameters @{ P = $script:Paths } {
      param($P)
      $script:Shown = [System.Collections.Generic.List[string]]::new()
      Mock Write-Host { $script:Shown.Add("$Object") }
      Mock Test-BorcGitRepo { $true }
      Mock Invoke-BorcGit { [pscustomobject]@{ ExitCode = 0; Output = @('my-branch') } } -ParameterFilter { 'symbolic-ref' -in $Arguments }
      Mock Invoke-BorcGit { [pscustomobject]@{ ExitCode = 0; Output = @('aaa111') } } -ParameterFilter { 'rev-parse' -in $Arguments }
      Mock Invoke-BorcGit { [pscustomobject]@{ ExitCode = 0; Output = @("bbb222`trefs/heads/my-branch") } } -ParameterFilter { 'ls-remote' -in $Arguments }
      Show-BorcUpdateNotice -Paths $P
      Should -Invoke Invoke-BorcGit -Times 1 -Exactly -ParameterFilter { 'ls-remote' -in $Arguments -and 'refs/heads/my-branch' -in $Arguments }
      ($script:Shown -join "`n") | Should -Match 'The borc branch my-branch has newer commits. Run borc self-update.'
    }
  }

  It 'runs the refresh with the module of the updated engine clone' {
    InModuleScope Borc -Parameters @{ P = $script:Paths } {
      param($P)
      Mock Write-Host {}
      $script:Command = $null
      Mock pwsh { $script:Command = $args[-1]; $global:LASTEXITCODE = 0 }
      Invoke-BorcEngineRefresh -Paths $P | Should -Be 0
      $script:Command | Should -Match ([regex]::Escape("Import-Module -Name '$($P.Engine)\src\Borc\Borc.psd1'"))
      $script:Command | Should -Match 'Update-BorcRuntime'
    }
  }

  It 'refreshes the runtime files and only the borc block of the profile' {
    $profilePath = Join-Path $script:Root 'profile.ps1'
    Set-Content -Path $profilePath -Value "Set-Alias g git`n# >>> borc >>>`nold block`n# <<< borc <<<" -NoNewline
    InModuleScope Borc -Parameters @{ P = $script:Paths; F = $profilePath } {
      param($P, $F)
      Mock Write-Host {}
      Mock Get-BorcPaths { $P }
      Mock Get-BorcProfilePath { $F }
      Update-BorcRuntime
      Update-BorcRuntime
      Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like 'Updated the borc block*' }
    }
    $text = Read-TestText -Path $profilePath
    $text | Should -Match '^Set-Alias g git'
    $text | Should -Not -Match 'old block'
    $text | Should -Match 'borc\\scripts'
    Test-Path (Join-Path $script:Root 'bin\borc.cmd') | Should -BeTrue
    Test-Path (Join-Path $script:Root 'Get-BorcSecret.ps1') | Should -BeTrue
  }
}

Describe 'Entry points' {
  It 'are UTF-8 without BOM for borc.cmd and call the engine clone' {
    $cmd = [IO.File]::ReadAllText((Join-Path $script:RepoRoot 'src\borc.cmd'))
    $cmd | Should -Match ([regex]::Escape('"%LOCALAPPDATA%\borc\engine\src\borc.ps1" %*'))
  }
}
