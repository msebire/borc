BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  $script:Block = InModuleScope Borc { Get-BorcProfileBlock }
}

Describe 'Profile block text' {
  It 'is added to an empty profile' {
    InModuleScope Borc { Update-BorcProfileText -Text '' } | Should -BeExactly ($script:Block + "`n")
  }

  It 'is appended after the user content, which stays as it is' {
    $text = "Set-Alias g git`n"
    InModuleScope Borc -Parameters @{ T = $text } { param($T) Update-BorcProfileText -Text $T } | Should -BeExactly ("Set-Alias g git`n`n" + $script:Block + "`n")
  }

  It 'replaces only the text between the markers' {
    $text = "before`n# >>> borc >>>`nold stuff`n# <<< borc <<<`nafter`n"
    InModuleScope Borc -Parameters @{ T = $text } { param($T) Update-BorcProfileText -Text $T } | Should -BeExactly ("before`n" + $script:Block + "`nafter`n")
  }

  It 'changes nothing on a second run' {
    $once = InModuleScope Borc { Update-BorcProfileText -Text "x`n" }
    InModuleScope Borc -Parameters @{ T = $once } { param($T) Update-BorcProfileText -Text $T } | Should -BeExactly $once
  }

  It 'keeps CRLF line endings' {
    $result = InModuleScope Borc { Update-BorcProfileText -Text "x`r`n" }
    $result | Should -BeExactly ("x`r`n`r`n" + ($script:Block -replace "`n", "`r`n") + "`r`n")
  }
}

Describe 'Profile block file' {
  BeforeEach {
    $script:Folder = New-TestFolder
    $script:ProfilePath = Join-Path $script:Folder 'PowerShell\profile.ps1'
  }
  AfterEach {
    Remove-Item -LiteralPath $script:Folder -Recurse -Force
  }

  It 'creates the profile and reports no change the second time' {
    InModuleScope Borc -Parameters @{ P = $script:ProfilePath } { param($P) Set-BorcProfileBlock -Path $P } | Should -BeTrue
    InModuleScope Borc -Parameters @{ P = $script:ProfilePath } { param($P) Set-BorcProfileBlock -Path $P } | Should -BeFalse
    Read-TestText -Path $script:ProfilePath | Should -BeExactly ($script:Block + "`n")
  }

  It 'keeps a BOM the profile already had' {
    New-Item -ItemType Directory -Path (Split-Path $script:ProfilePath) | Out-Null
    [IO.File]::WriteAllText($script:ProfilePath, "# é`n", [Text.UTF8Encoding]::new($true))
    InModuleScope Borc -Parameters @{ P = $script:ProfilePath } { param($P) Set-BorcProfileBlock -Path $P } | Out-Null
    [IO.File]::ReadAllBytes($script:ProfilePath)[0] | Should -Be 0xEF
  }
}

Describe 'Profile block behaviour' {
  BeforeAll {
    $script:Folder = New-TestFolder
    $script:Scripts = Join-Path $script:Folder 'settings\borc\scripts'
    New-Item -ItemType Directory -Path $script:Scripts, (Join-Path $script:Folder 'home') | Out-Null
    Set-Content -Path (Join-Path $script:Scripts 'a.ps1') -Value 'function Get-BorcTestA { "a" }'
    Set-Content -Path (Join-Path $script:Scripts 'b.ps1') -Value 'throw "broken"'
    Set-Content -Path (Join-Path $script:Scripts 'c.ps1') -Value 'function Get-BorcTestC { "c" }'
    Set-Content -Path (Join-Path $script:Folder 'profile.ps1') -Value $script:Block
    # The block loads profile.ps1 (and through it completion.ps1) from the engine clone in LOCALAPPDATA.
    $engineSrc = Join-Path $script:Folder 'localappdata\borc\engine\src'
    New-Item -ItemType Directory -Path $engineSrc -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'src\profile.ps1'), (Join-Path $script:RepoRoot 'src\completion.ps1') -Destination $engineSrc
  }
  AfterAll {
    Remove-Item -LiteralPath $script:Folder -Recurse -Force
  }

  It 'loads scripts in order, warns once for a broken one, moves to BORC_HOME and loads completion' {
    # A child process, so the dot-sourcing and Set-Location never reach this session.
    $command = @"
`$env:BORC_SETTINGS = '$script:Folder\settings'
`$env:BORC_HOME = '$script:Folder\home'
`$env:LOCALAPPDATA = '$script:Folder\localappdata'
Set-Location -LiteralPath `$HOME
. '$script:Folder\profile.ps1' 3>&1 | ForEach-Object { "warning: `$_" }
Get-BorcTestA
Get-BorcTestC
(Get-Location).Path
(TabExpansion2 -inputScript 'borc self-' -cursorColumn 10).CompletionMatches.CompletionText
"@
    $output = @(pwsh -NoProfile -NonInteractive -Command $command)
    $output | Should -Be @(
      'warning: borc: b.ps1 failed to load: broken'
      'a'
      'c'
      (Join-Path $script:Folder 'home')
      'self-update')
    }

  It 'warns once at start-up about uncommitted changes and commits not pushed' {
    $settings = Join-Path $script:Folder 'settings'
    $git = @('-c', 'user.name=borc-test', '-c', 'user.email=borc-test@example.invalid', '-c', 'init.defaultBranch=main', '-c', 'core.autocrlf=false')
    git @git init --quiet --bare (Join-Path $script:Folder 'remote.git')
    git @git init --quiet $settings
    git @git -C $settings remote add origin (Join-Path $script:Folder 'remote.git')
    git @git -C $settings add -A
    git @git -C $settings commit --quiet -m seed
    git @git -C $settings push --quiet -u origin main 2>$null
    git @git -C $settings commit --quiet --allow-empty -m 'not pushed'
    Set-Content -Path (Join-Path $settings 'new-setting.txt') -Value 'x'
    $command = @"
`$env:BORC_SETTINGS = '$settings'
`$env:LOCALAPPDATA = '$script:Folder\localappdata'
`$env:NO_COLOR = '1'
. '$script:Folder\profile.ps1' 3>`$null 6>&1 | Where-Object { "`$_" -like 'borc:*' } | ForEach-Object { "`$_" }
"@
    $output = @(pwsh -NoProfile -NonInteractive -Command $command)
    $output | Should -Be @("borc: 1 uncommitted change, 1 commit not pushed in $settings (git -C $settings status)")
  }
}
