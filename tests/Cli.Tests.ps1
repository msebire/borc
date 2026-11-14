BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

  function Invoke-TestBorc {
    param([string[]] $Arguments)
    InModuleScope borc -Parameters @{ A = $Arguments } {
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

  It 'shows the version, commit and branch with --version, without a log' {
    $root = Split-Path -Parent $script:FixturesRoot | Split-Path -Parent
    $version = (Import-PowerShellDataFile -LiteralPath (Join-Path $root 'src\borc\borc.psd1')).ModuleVersion
    $commit = git -C $root log -1 --format=%h
    $result = Invoke-TestBorc -Arguments @('--version')
    $result.Code | Should -Be 0
    $result.Output | Should -Match "^BORC $([regex]::Escape($version)) \($commit, \d{4}-\d{2}-\d{2}, branch "
    InModuleScope borc {
      Mock Write-Host {}
      Mock Start-BorcLog { throw 'must not start a log' }
      Invoke-Borc -Arguments @('--version') | Should -Be 0
    }
  }

  It 'shows only the version outside a Git clone' {
    InModuleScope borc {
      Mock Test-BorcGitRepo { $false }
      Get-BorcVersionText | Should -Match '^BORC \d+\.\d+\.\d+$'
    }
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
    InModuleScope borc -Parameters @{ A = $App } { param($A) Get-BorcAppKind -App $A } | Should -Be $Kind
  }

  It 'rejects a malformed recipe reference' {
    { InModuleScope borc { Get-BorcAppKind -App 'a/b/c' } } | Should -Throw '*not a recipe reference*'
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
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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

    It 'repeats the update notice in the result, where it does not scroll away' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Sync-BorcRecipeRepo {}
        Mock Show-BorcUpdateNotice { 'A newer BORC is available. Run borc self-update.' }
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Test-BorcStoredSecret { $true }
        Mock Test-BorcRestartPending { $false }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('apply') | Should -Be 0
        ($script:Shown -join "`n") | Should -Match '  update:\s+A newer BORC is available\. Run borc self-update\.'
      }
    }

    It 'says so when borc.yaml declares no secret' {
      InModuleScope borc {
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-BorcLog { $script:Shown.Add($Message) }
        Mock Get-BorcMissingSecrets { throw 'nothing to look up' }
        Show-BorcPreviewSecrets -Plan ([pscustomobject]@{ Config = [pscustomobject]@{ Secrets = [ordered]@{} } }) | Should -BeNullOrEmpty
        $script:Shown | Should -Be @('  None: borc.yaml declares no secret.')
      }
    }

    It 'decodes winget as UTF-8, then puts the console encoding back' {
      InModuleScope borc {
        Mock Write-Host {}
        $saved = [Console]::OutputEncoding
        try {
          [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(437)
          $before = [Console]::OutputEncoding.WebName
          $script:During = $null
          Mock winget { $script:During = [Console]::OutputEncoding.WebName; $global:LASTEXITCODE = 0 }
          Invoke-BorcWingetQuiet -Arguments @('--version') | Out-Null
          $script:During | Should -Be 'utf-8'
          [Console]::OutputEncoding.WebName | Should -Be $before
          $script:During = $null
          Invoke-BorcWinget -Arguments @('--version') | Should -Be 0
          $script:During | Should -Be 'utf-8'
          [Console]::OutputEncoding.WebName | Should -Be $before
        } finally {
          [Console]::OutputEncoding = $saved
        }
      }
    }

    It 'stops before the main run and asks for a restart after the reboot run' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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

    It 'names a winget of another minor version after a failure: <Output>' -ForEach @(
      @{ Output = 'v1.30.1'; Hint = $true }
      @{ Output = 'v1.28.5'; Hint = $true }
      @{ Output = 'v1.29.999'; Hint = $false }
      @{ Output = 'unreadable'; Hint = $false }
    ) {
      InModuleScope borc -Parameters @{ O = $Output; H = $Hint } {
        param($O, $H)
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 0; Output = @($O) } }
        Write-BorcWingetVersionHint
        $matched = ($script:Shown -join "`n") -match 'verified with winget 1\.29\.380.*troubleshooting'
        $matched | Should -Be $H
      }
    }

    It 'says nothing about the winget version after a success' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Test-BorcRestartPending { $false }
        Mock Write-BorcWingetVersionHint {}
        Mock Invoke-BorcWinget { 0 }
        Invoke-BorcConfigureRun -Document ([ordered]@{ resources = @() }) -Name 'test' | Should -Be 0
        Should -Invoke Write-BorcWingetVersionHint -Times 0 -Exactly
      }
    }

    It 'asks for missing secrets before running' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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
      (Get-Content $path -Raw).Replace("  - recipe: recipes/idea`n", "  - recipe: recipes/idea`n    parameters:`n      ideaHome: $script:SystemDrive\idea`n") | Set-Content $path -NoNewline
      git -C $script:Settings -c user.name=borc-test -c user.email=borc-test@example.invalid commit --quiet -am param
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('apply') | Should -Be 1
        ($script:Shown -join "`n") | Should -Match 'uncommitted changes'
        ($script:Shown -join "`n") | Should -Match 'Result: nothing was applied: commit or discard the local changes listed above\.\n  tip: borc apply --no-pull applies your working copy as it is, without pulling'
        Should -Invoke Invoke-BorcWinget -Times 0 -Exactly
      }
    }

    It 'suggests --no-pull when the pull itself fails' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Sync-BorcConfigRepo { throw 'git failed to pull the config repo (exit code 1).' }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('apply') | Should -Be 1
        ($script:Shown -join "`n") | Should -Match 'Result: nothing was applied: the pull failed \(see the git error above\)\.\n  tip: borc apply --no-pull'
        Should -Invoke Invoke-BorcWinget -Times 0 -Exactly
      }
    }

    It 'applies the working copy as it is with --no-pull, uncommitted changes included' {
      $path = Join-Path $script:Settings 'borc\borc.yaml'
      (Get-Content $path -Raw).Replace("secrets:", "  - winget: Not.Committed`nsecrets:") | Set-Content $path -NoNewline
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Sync-BorcConfigRepo { throw 'must not pull' }
        Mock Sync-BorcRecipeRepo {}
        Mock Show-BorcUpdateNotice { throw 'must not check for updates' }
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Test-BorcStoredSecret { $true }
        Mock Test-BorcRestartPending { $false }
        $script:Configured = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-BorcWinget { $script:Configured.Add([IO.File]::ReadAllText($Arguments[2])); 0 }
        Invoke-Borc -Arguments @('apply', '--no-pull') | Should -Be 0
        $script:Configured[-1] | Should -Match 'winget: Not\.Committed'
        $text = $script:Shown -join "`n"
        $text | Should -Match '==> \[1/5\] Using the config repo as it is'
        $text | Should -Match '  pulled:\s+skipped \(--no-pull\)'
      }
    }

    It 'previews the working copy with --what-if --no-pull, without fetching' {
      $path = Join-Path $script:Settings 'borc\borc.yaml'
      (Get-Content $path -Raw).Replace("secrets:", "  - winget: Not.Committed`nsecrets:") | Set-Content $path -NoNewline
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Get-BorcIncoming { throw 'must not fetch' }
        Mock Invoke-BorcWinget { throw 'winget must not run' }
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Test-BorcStoredSecret { $true }
        Invoke-Borc -Arguments @('apply', '--what-if', '--no-pull') | Should -Be 0
        $text = $script:Shown -join "`n"
        $text | Should -Match '==> \[1/4\] Reading the config repo and recipe repos as they are \(--no-pull\)'
        $text | Should -Match '  winget  Not\.Committed\s+would be installed'
        $text | Should -Match '  pull:\s+recipe repo recipes would be cloned; skipped \(--no-pull\)'
      }
    }

    It 'runs one recipe at a time with --one-by-one and names the failing one' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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
        Invoke-Borc -Arguments @('apply', '--one-by-one') | Should -Be 1
        $script:Count | Should -Be 3
        ($script:Shown -join "`n") | Should -Match 'The failing recipe is recipes/npm-auth'
      }
    }

    It 'tests the recipe units once with --what-if --check and gives definite verdicts' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Invoke-BorcWinget { throw 'winget must not apply anything' }
        Mock Test-BorcStoredSecret { $true }
        # winget answers from the units in the file BORC wrote: npm cache would change.
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
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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

    It 'ends install and uninstall with a Result: <Name>' -ForEach @(
      @{ Name = 'new app'; Arguments = @('install', 'New.App'); ExitList = 1; Code = 0; Expected = 'Result: installed New\.App\.\n  borc\.yaml: line added, not committed' }
      @{ Name = 'already installed'; Arguments = @('install', 'Git.Git'); ExitList = 0; Code = 0; Expected = 'Result: Git\.Git was already installed\.\n  borc\.yaml: already listed' }
      @{ Name = 'unknown ID'; Arguments = @('install', 'No.Such.App'); ExitList = 1; ExitShow = 1; Code = 1; Expected = 'Result: nothing was installed: winget has no package with the ID No\.Such\.App\.' }
      @{ Name = 'uninstalled'; Arguments = @('uninstall', 'Git.Git'); ExitList = 0; Code = 0; Expected = 'Result: uninstalled Git\.Git\.\n  borc\.yaml: line removed, not committed' }
      @{ Name = 'not installed, not listed'; Arguments = @('uninstall', 'Other.App'); ExitList = 1; Code = 0; Expected = 'Result: Other\.App was not installed\.\n  borc\.yaml: no line to remove' }
      @{ Name = 'recipe'; Arguments = @('uninstall', 'recipes/node'); ExitList = 1; Code = 0; Expected = 'Result: removed recipes/node from borc\.yaml\.\n  borc\.yaml:\s+line removed, not committed\n  left in place: everything the recipe set up' }
      @{ Name = 'recipe not listed'; Arguments = @('uninstall', 'recipes/none'); ExitList = 1; Code = 1; Expected = 'Result: nothing changed: recipes/none is not listed in borc\.yaml\.' }
    ) {
      InModuleScope borc -Parameters @{ P = $script:Paths; T = $_ } {
        param($P, $T)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        $script:Test = $T
        Mock Invoke-BorcWingetQuiet {
          $exit = if ($Arguments[0] -eq 'show') { if ($script:Test.ContainsKey('ExitShow')) { $script:Test.ExitShow } else { 0 } } else { $script:Test.ExitList }
          [pscustomobject]@{ ExitCode = $exit; Output = @() }
        }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments $T.Arguments | Should -Be $T.Code
        ($script:Shown -join "`n") | Should -Match $T.Expected
      }
    }

    It 'ends a recipe install with what ran, or with what failed' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Test-BorcRestartPending { $false }
        Mock Test-BorcStoredSecret { $true }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('install', 'recipes/npm-auth') | Should -Be 0
        ($script:Shown -join "`n") | Should -Match 'Result: ran recipes/npm-auth\.\n  recipe:\s+winget does not say which of its settings changed\n  also ran:\s+recipes/node\n  borc\.yaml: already listed'
        $script:Shown.Clear()
        Mock Invoke-BorcWinget { -1978286078 }
        Invoke-Borc -Arguments @('install', 'recipes/npm-auth') | Should -Be 1
        ($script:Shown -join "`n") | Should -Match "Result: recipes/node failed; winget's errors are shown above\."
      }
    }

    It 'installs a listed app at the version borc.yaml fixes' {
      $path = Join-Path $script:Settings 'borc\borc.yaml'
      (Get-Content $path -Raw).Replace("  - winget: Git.Git`n", "  - winget: Git.Git`n    version: '2.45.1'`n") | Set-Content $path -NoNewline
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('install', 'Git.Git') | Should -Be 0
        Should -Invoke Invoke-BorcWinget -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'install' -and ($Arguments -join ' ') -match '--version 2\.45\.1' }
      }
    }

    It 'moves an installed app to the fixed version with a configure unit, as apply does' {
      $path = Join-Path $script:Settings 'borc\borc.yaml'
      (Get-Content $path -Raw).Replace("  - winget: Git.Git`n", "  - winget: Git.Git`n    version: '2.45.1'`n") | Set-Content $path -NoNewline
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Test-BorcRestartPending { $false }
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 0; Output = @('Name  Id       Version  Source', '-----------------------------', 'Git   Git.Git  2.50.0   winget') } }
        $script:Configured = $null
        Mock Invoke-BorcWinget { $script:Configured = [IO.File]::ReadAllText($Arguments[2]); 0 }
        Invoke-Borc -Arguments @('install', 'Git.Git') | Should -Be 0
        Should -Invoke Invoke-BorcWinget -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq 'install' }
        Should -Invoke Invoke-BorcWinget -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'configure' }
        $script:Configured | Should -Match "version: 2\.45\.1|version: '2\.45\.1'"
        ($script:Shown -join "`n") | Should -Match 'Git\.Git is at 2\.50\.0; borc\.yaml fixes it at 2\.45\.1\.'
        ($script:Shown -join "`n") | Should -Match 'Result: Git\.Git is now at 2\.45\.1\.'
        $script:Shown.Clear()
        Mock Invoke-BorcWinget { -1978286078 }
        Invoke-Borc -Arguments @('install', 'Git.Git') | Should -Be 1
        ($script:Shown -join "`n") | Should -Match "Result: Git\.Git was not moved to 2\.45\.1; winget's errors are shown above\."
      }
    }

    It 'leaves a listed app alone when it is at the fixed version' {
      $path = Join-Path $script:Settings 'borc\borc.yaml'
      (Get-Content $path -Raw).Replace("  - winget: Git.Git`n", "  - winget: Git.Git`n    version: '2.45.1'`n") | Set-Content $path -NoNewline
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 0; Output = @('Name  Id       Version  Source', '-----------------------------', 'Git   Git.Git  2.45.1   winget') } }
        Mock Invoke-BorcWinget { 0 }
        Invoke-Borc -Arguments @('install', 'Git.Git') | Should -Be 0
        Should -Invoke Invoke-BorcWinget -Times 0 -Exactly
      }
    }

    It 'explains a name it read as a Store ID when winget cannot install it' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Invoke-BorcWinget { -1978335212 }
        Invoke-Borc -Arguments @('install', 'vim') | Should -Be 1
        ($script:Shown -join "`n") | Should -Match 'BORC read vim as a Microsoft Store ID.*borc search vim'
        ($script:Shown -join "`n") | Should -Match "Result: vim was not installed; winget's errors are shown above\.\n  tip: BORC read vim as a Microsoft Store ID; find a winget ID with borc search vim"
      }
    }

    It 'runs the recipes a recipe requires first' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Test-BorcRestartPending { $false }
        Mock Test-BorcStoredSecret { $true }
        $script:Configured = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-BorcWinget { $script:Configured.Add([IO.File]::ReadAllText($Arguments[2])); 0 }
        Invoke-Borc -Arguments @('install', 'recipes/npm-auth') | Should -Be 0
        $script:Configured.Count | Should -Be 2
        $script:Configured[0] | Should -Match 'recipes/node: '
        $script:Configured[1] | Should -Match 'recipes/npm-auth: '
      }
    }

    It 'stops when a required recipe fails' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        Mock Write-Host {}
        Mock Test-BorcRestartPending { $false }
        Mock Test-BorcStoredSecret { $true }
        Mock Invoke-BorcWinget { -1978286078 }
        Invoke-Borc -Arguments @('install', 'recipes/npm-auth') | Should -Be 1
        Should -Invoke Invoke-BorcWinget -Times 1 -Exactly
      }
    }

    It 'runs a recipe on its own and adds it' {
      $path = Join-Path $script:Settings 'borc\borc.yaml'
      (Get-Content $path -Raw).Replace("  - recipe: recipes/idea`n", '') | Set-Content $path -NoNewline
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        $script:Upgraded = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-BorcWinget { $script:Upgraded.Add($Arguments[2]); if ($Arguments[2] -eq 'Canonical.Ubuntu.2404') { $script:WingetNoPackageFound } else { $script:WingetNoApplicableUpgrade } }
        Invoke-Borc -Arguments @('upgrade') | Should -Be 0
        $script:Upgraded | Should -Be @('Git.Git', '9NBLGGH4NNS1', 'OpenJS.NodeJS.LTS', 'JetBrains.IntelliJIDEA.Community', 'Canonical.Ubuntu.2404')
        Should -Invoke Invoke-BorcWinget -ParameterFilter { $Arguments[0] -ne 'upgrade' } -Times 0 -Exactly
        ($script:Shown -join "`n") | Should -Match 'Result: done; nothing to upgrade\.\n  not installed: Canonical\.Ubuntu\.2404; borc apply installs them'
      }
    }

    It 'ends upgrade with what changed version and what failed' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        $script:Calls = 0
        # The list before the upgrades has Git.Git at 1.0, the one after has it at 2.0.
        Mock Update-BorcInstalledList {
          $script:Calls++
          $script:BorcInstalledList = @('Name  Id       Version  Source', '-----------------------------', "Git   Git.Git  $(if ($script:Calls -eq 1) { '1.0' } else { '2.0' })      winget")
        }
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        Mock Invoke-BorcWinget { if ($Arguments[2] -eq '9NBLGGH4NNS1') { 1 } else { 0 } }
        Invoke-Borc -Arguments @('upgrade') | Should -Be 1
        $text = $script:Shown -join "`n"
        $text | Should -Match "Result: some upgrades failed; winget's errors are shown above\."
        $text | Should -Match '  upgraded:\s+Git\.Git \(1\.0 -> 2\.0\)'
        $text | Should -Match '  failed:\s+9NBLGGH4NNS1'
      }
    }

    It 'ends upgrade with changes when only a version moved' {
      InModuleScope borc {
        Mock Set-BorcResult {}
        Set-BorcUpgradeResult -Upgraded @('Git.Git (1.0 -> 2.0)')
        Should -Invoke Set-BorcResult -Times 1 -Exactly -ParameterFilter { $Headline -eq 'done, with changes.' }
      }
    }

    It 'leaves a package with a fixed version alone, and says so' {
      $path = Join-Path $script:Settings 'borc\borc.yaml'
      (Get-Content $path -Raw).Replace("  - winget: Git.Git`n", "  - winget: Git.Git`n    version: '2.45.1'`n") | Set-Content $path -NoNewline
      InModuleScope borc -Parameters @{ P = $script:Paths } {
        param($P)
        Mock Get-BorcPaths { $P }
        $script:Shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:Shown.Add("$Object") }
        Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        $script:Upgraded = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-BorcWinget { $script:Upgraded.Add($Arguments[2]); 0 }
        Invoke-Borc -Arguments @('upgrade') | Should -Be 0
        $script:Upgraded | Should -Not -Contain 'Git.Git'
        $script:Upgraded | Should -Contain '9NBLGGH4NNS1'
        ($script:Shown -join "`n") | Should -Match 'Git\.Git is not installed, and borc\.yaml fixes it at 2\.45\.1\.'
        ($script:Shown -join "`n") | Should -Match '  fixed version:\s+Git\.Git at 2\.45\.1 \(not installed\)'
      }
    }

    It 'says what is installed next to a fixed version' {
      InModuleScope borc {
        $package = [pscustomobject]@{ Id = 'jqlang.jq'; Version = '1.7.1'; Origin = 'borc.yaml' }
        Format-BorcFixedNotice -Package $package -Installed '1.7.1' | Should -Be 'jqlang.jq stays at 1.7.1, the version fixed in borc.yaml.'
        Format-BorcFixedNotice -Package $package -Installed '1.8.2' | Should -Be 'jqlang.jq is at 1.8.2, and borc.yaml fixes it at 1.7.1. upgrade leaves it alone; borc apply sets that version.'
        Format-BorcFixedDetail -Package $package -Installed '1.7.1' | Should -Be 'jqlang.jq at 1.7.1'
        Format-BorcFixedDetail -Package $package -Installed '1.8.2' | Should -Be 'jqlang.jq at 1.7.1 (1.8.2 installed)'
      }
    }

    It 'searches recipe names and descriptions, then winget' {
      InModuleScope borc -Parameters @{ P = $script:Paths } {
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

  It 'updates the engine to its remote branch, then lets the updated engine refresh its files and profile block' {
    InModuleScope borc -Parameters @{ P = $script:Paths } {
      param($P)
      Mock Get-BorcPaths { $P }
      Mock Write-Host {}
      Mock Test-BorcGitRepo { $true }
      Mock Invoke-BorcGit { [pscustomobject]@{ ExitCode = 0; Output = @('my-branch') } }
      Mock Invoke-BorcEngineRefresh { 0 }
      Invoke-Borc -Arguments @('self-update') | Should -Be 0
      Should -Invoke Invoke-BorcGit -Times 1 -Exactly -ParameterFilter { 'fetch' -in $Arguments }
      Should -Invoke Invoke-BorcGit -Times 1 -Exactly -ParameterFilter { 'reset' -in $Arguments -and 'origin/my-branch' -in $Arguments }
      Should -Invoke Invoke-BorcGit -Times 0 -Exactly -ParameterFilter { 'pull' -in $Arguments }
      Should -Invoke Invoke-BorcEngineRefresh -Times 1 -Exactly
    }
  }

  It 'takes a rewritten branch, with a real clone' {
    $root = New-TestFolder
    try {
      $remote = Join-Path $root 'remote.git'
      $seed = Join-Path $root 'seed'
      $clone = Join-Path $root 'engine'
      $git = @('-c', 'user.name=borc-test', '-c', 'user.email=borc-test@example.invalid', '-c', 'init.defaultBranch=main', '-c', 'core.autocrlf=false')
      git @git init --quiet --bare $remote
      git @git clone --quiet $remote $seed 2>$null
      Set-Content -Path (Join-Path $seed 'file.txt') -Value 'one'
      git @git -C $seed add -A
      git @git -C $seed commit --quiet -m one
      git @git -C $seed push --quiet origin HEAD:refs/heads/main 2>$null
      git @git clone --quiet --branch main $remote $clone 2>$null
      Set-Content -Path (Join-Path $seed 'file.txt') -Value 'rewritten'
      git @git -C $seed commit --quiet --amend -am rewritten
      git @git -C $seed push --quiet --force origin HEAD:refs/heads/main 2>$null
      InModuleScope borc -Parameters @{ C = $clone } {
        param($C)
        Mock Write-Host {}
        Update-BorcEngineClone -Path $C
      }
      Get-Content (Join-Path $clone 'file.txt') | Should -Be 'rewritten'
    } finally {
      Remove-Item -LiteralPath $root -Recurse -Force
    }
  }

  It 'fails when the updated engine cannot refresh' {
    InModuleScope borc -Parameters @{ P = $script:Paths } {
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
    InModuleScope borc -Parameters @{ P = $script:Paths } {
      param($P)
      $script:Shown = [System.Collections.Generic.List[string]]::new()
      Mock Write-Host { $script:Shown.Add("$Object") }
      Mock Test-BorcGitRepo { $true }
      Mock Invoke-BorcGit { [pscustomobject]@{ ExitCode = 0; Output = @('my-branch') } } -ParameterFilter { 'symbolic-ref' -in $Arguments }
      Mock Invoke-BorcGit { [pscustomobject]@{ ExitCode = 0; Output = @('aaa111') } } -ParameterFilter { 'rev-parse' -in $Arguments }
      Mock Invoke-BorcGit { [pscustomobject]@{ ExitCode = 0; Output = @("bbb222`trefs/heads/my-branch") } } -ParameterFilter { 'ls-remote' -in $Arguments }
      Show-BorcUpdateNotice -Paths $P | Should -Be 'The BORC branch my-branch has changed. Run borc self-update.'
      Should -Invoke Invoke-BorcGit -Times 1 -Exactly -ParameterFilter { 'ls-remote' -in $Arguments -and 'refs/heads/my-branch' -in $Arguments }
      ($script:Shown -join "`n") | Should -Match 'The BORC branch my-branch has changed. Run borc self-update.'
    }
  }

  It 'says only what it knows about recipes when the run did not finish' {
    InModuleScope borc {
      Format-BorcRecipesDetail -Recipes 4 -ExitCode 0 | Should -Be '4 run; winget does not say which of their settings changed'
      Format-BorcRecipesDetail -Recipes 4 -ExitCode 3010 | Should -Be '4 listed; those not run yet run after the restart'
      Format-BorcRecipesDetail -Recipes 4 -ExitCode 1 | Should -Be "4 listed; winget's errors above say which units failed"
    }
  }

  It 'names the missing VC++ runtime after a failed run, and stays quiet when it is there' {
    InModuleScope borc {
      $script:Shown = [System.Collections.Generic.List[string]]::new()
      Mock Write-BorcLog { $script:Shown.Add($Message) }
      Mock Test-BorcVcRuntime { $true }
      Write-BorcVcRuntimeHint
      $script:Shown.Count | Should -Be 0
      Mock Test-BorcVcRuntime { $false }
      Write-BorcVcRuntimeHint
      $script:Shown[0] | Should -Match 'vcruntime140_1\.dll.*winget install --id Microsoft\.VCRedist\.2015\+'
    }
  }

  It 'says to enable winget configure when it ran nothing for that reason, and gives no other hint' {
    InModuleScope borc {
      $script:Shown = [System.Collections.Generic.List[string]]::new()
      Mock Write-BorcLog { $script:Shown.Add($Message) }
      Mock Write-BorcDocument {}
      Mock Get-BorcRunFilePath { 'x.winget.yaml' }
      Mock Test-BorcRestartPending { $false }
      Mock Write-BorcVcRuntimeHint { throw 'no other hint' }
      Mock Write-BorcWingetVersionHint { throw 'no other hint' }
      Mock Invoke-BorcWinget { $script:WingetConfigureNotEnabled }
      Invoke-BorcConfigureRun -Document @{} -Name 'main' | Should -Be 1
      $script:Shown | Should -Contain 'winget configure ran nothing: its extended features are not enabled. Run winget configure --enable, then borc apply again.'
      0x8A150069 | Should -Be -1978335127
    }
  }

  It 'says when a failed run left Windows waiting for a restart, and only then' {
    InModuleScope borc {
      $script:Shown = [System.Collections.Generic.List[string]]::new()
      Mock Write-BorcLog { $script:Shown.Add($Message) }
      Mock Write-BorcDocument {}
      Mock Get-BorcRunFilePath { 'x.winget.yaml' }
      Mock Write-BorcVcRuntimeHint {}
      Mock Write-BorcWingetVersionHint {}
      Mock Invoke-BorcWinget { -1978286075 }
      $script:Checks = 0
      Mock Test-BorcRestartPending { $script:Checks++; $script:Checks -gt 1 }
      Invoke-BorcConfigureRun -Document @{} -Name 'reboot' | Should -Be 1
      $script:Shown | Should -Contain 'Windows needs a restart, which may be why units failed. Restart, then run borc apply again.'
      $script:Shown.Clear()
      Mock Test-BorcRestartPending { $true }
      Invoke-BorcConfigureRun -Document @{} -Name 'reboot' | Should -Be 1
      $script:Shown | Should -Not -Contain 'Windows needs a restart, which may be why units failed. Restart, then run borc apply again.'
    }
  }

  It 'does not call the plain packages a recipe in --one-by-one' {
    InModuleScope borc {
      $script:Shown = [System.Collections.Generic.List[string]]::new()
      Mock Write-BorcLog { $script:Shown.Add($Message) }
      Mock New-BorcSingleDocuments { [pscustomobject]@{ Name = $script:BorcPlainPackagesName; Reboot = $false; Document = @{} } }
      Mock Invoke-BorcConfigureRun { 1 }
      Invoke-BorcRunsOneByOne -Plan ([pscustomobject]@{}) | Should -Be 1
      $script:Shown | Should -Contain 'Running the plain packages.'
      $script:Shown | Should -Contain "One of the plain packages failed; winget's errors above name it."
    }
  }

  It 'runs the refresh with the module of the updated engine clone' {
    InModuleScope borc -Parameters @{ P = $script:Paths } {
      param($P)
      Mock Write-Host {}
      $script:Command = $null
      Mock pwsh { $script:Command = $args[-1]; $global:LASTEXITCODE = 0 }
      Invoke-BorcEngineRefresh -Paths $P | Should -Be 0
      $script:Command | Should -Match ([regex]::Escape("Import-Module -Name '$($P.Engine)\src\borc\borc.psd1'"))
      $script:Command | Should -Match 'Update-BorcRuntime'
    }
  }

  It 'refreshes the runtime files and only the BORC block of the profile' {
    $profilePath = Join-Path $script:Root 'profile.ps1'
    Set-Content -Path $profilePath -Value "Set-Alias g git`n# >>> borc >>>`nold block`n# <<< borc <<<" -NoNewline
    InModuleScope borc -Parameters @{ P = $script:Paths; F = $profilePath } {
      param($P, $F)
      Mock Write-Host {}
      Mock Get-BorcPaths { $P }
      Mock Get-BorcProfilePath { $F }
      Update-BorcRuntime
      Update-BorcRuntime
      Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like 'Updated the BORC block*' }
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
