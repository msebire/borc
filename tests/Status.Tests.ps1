BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  $script:SavedSettings = $env:BORC_SETTINGS
  # Loading profile.ps1 runs the start-up check; with no BORC_SETTINGS it prints nothing.
  $env:BORC_SETTINGS = $null
  . (Join-Path $script:RepoRoot 'src\profile.ps1')

  $script:Git = @('-c', 'user.name=borc-test', '-c', 'user.email=borc-test@example.invalid', '-c', 'init.defaultBranch=main', '-c', 'core.autocrlf=false')
  function New-TestRepo {
    param([switch] $Pushed)
    $root = New-TestFolder
    $repo = Join-Path $root 'settings'
    git @script:Git init --quiet $repo
    Set-Content -Path (Join-Path $repo 'tracked.txt') -Value 'one'
    Set-Content -Path (Join-Path $repo '.gitignore') -Value 'cache/'
    git @script:Git -C $repo add -A
    git @script:Git -C $repo commit --quiet -m seed
    if ($Pushed) {
      git @script:Git init --quiet --bare (Join-Path $root 'remote.git')
      git @script:Git -C $repo remote add origin (Join-Path $root 'remote.git')
      git @script:Git -C $repo push --quiet -u origin main 2>$null
    }
    [pscustomobject]@{ Root = $root; Repo = $repo }
  }
}

AfterAll {
  $env:BORC_SETTINGS = $script:SavedSettings
}

Describe 'Welcome banner of the starter template' {
  BeforeAll {
    $script:Welcome = Join-Path $script:RepoRoot 'src\borc\template\borc\scripts\welcome.ps1'

    # A child process: the banner is loaded the way the profile block loads it.
    function Invoke-Welcome {
      param([string] $After = '', [string] $NoColor = '1')
      $command = "`$env:BORC_SETTINGS = 'D:\settings'; `$env:NO_COLOR = '$NoColor'; . '$script:Welcome'; $After"
      @(pwsh -NoProfile -NonInteractive -Command $command)
    }
  }

  It 'replaces the .gitkeep of the scripts folder' {
    Test-Path $script:Welcome | Should -BeTrue
    Test-Path (Join-Path (Split-Path $script:Welcome) '.gitkeep') | Should -BeFalse
  }

  It 'shows the configuration folder and the next steps' {
    $text = (Invoke-Welcome) -join "`n"
    $text | Should -Match 'Your configuration is in D:\\settings'
    $text | Should -Match 'Commands and tips: README\.md'
    $text | Should -Match '1\. Add apps\s+borc install <id>, or edit borc\\borc\.yaml'
    $text | Should -Match '2\. Apply them\s+borc apply'
    $text | Should -Match '3\. Save them\s+commit in D:\\settings, add a remote and push'
    $text | Should -Match 'delete borc\\scripts\\welcome\.ps1'
  }

  It 'suggests hello-borc only while the example recipe exists' {
    $root = New-TestFolder
    try {
      $command = "`$env:BORC_SETTINGS = '$root'; `$env:NO_COLOR = '1'; . '$script:Welcome'"
      (@(pwsh -NoProfile -NonInteractive -Command $command) -join "`n") | Should -Not -Match 'hello-borc'
      New-Item -ItemType Directory -Path (Join-Path $root 'borc\cookbook') | Out-Null
      Set-Content -Path (Join-Path $root 'borc\cookbook\hello-borc.yaml') -Value 'x'
      (@(pwsh -NoProfile -NonInteractive -Command $command) -join "`n") | Should -Match 'Try it: hello-borc, from the example recipe in borc\\cookbook'
    } finally {
      Remove-Item -LiteralPath $root -Recurse -Force
    }
  }

  It 'writes only to the host, so it never ends up in captured output' {
    $command = "`$env:BORC_SETTINGS = 'D:\settings'; `$captured = @(. '$script:Welcome' 6>`$null); `$captured.Count"
    pwsh -NoProfile -NonInteractive -Command $command | Should -Be '0'
  }

  It 'leaves no function or variable behind in the terminal' {
    $output = Invoke-Welcome -After "'left: ' + [bool](Get-Command Write-Segments -ErrorAction SilentlyContinue) + ' ' + [bool](Get-Variable settings -ErrorAction SilentlyContinue)"
    $output[-1] | Should -Be 'left: False False'
  }

  It 'uses colours, and drops them with NO_COLOR' {
    $command = "`$env:BORC_SETTINGS = 'D:\settings'; `$env:NO_COLOR = '{0}'; . '$script:Welcome' 6>&1 | ForEach-Object {{ `$_.MessageData.ForegroundColor }} | Where-Object {{ `$null -ne `$_ }} | Select-Object -Unique"
    @(pwsh -NoProfile -NonInteractive -Command ($command -f '')) | Should -Contain 'Cyan'
    @(pwsh -NoProfile -NonInteractive -Command ($command -f '1')) | Should -Not -Contain 'Cyan'
  }
}

Describe 'Start-up status of the config repo' {
  AfterEach { if ($script:Test) { Remove-Item -LiteralPath $script:Test.Root -Recurse -Force } }

  It 'says nothing when everything is committed and pushed' {
    $script:Test = New-TestRepo -Pushed
    Format-BorcSettingsStatus -Status (Get-BorcSettingsStatus -Path $script:Test.Repo) | Should -BeNullOrEmpty
  }

  It 'counts modified and untracked files, but not ignored ones' {
    $script:Test = New-TestRepo -Pushed
    Set-Content -Path (Join-Path $script:Test.Repo 'tracked.txt') -Value 'two'
    Set-Content -Path (Join-Path $script:Test.Repo 'new.txt') -Value 'x'
    New-Item -ItemType Directory -Path (Join-Path $script:Test.Repo 'cache') | Out-Null
    Set-Content -Path (Join-Path $script:Test.Repo 'cache\ignored.txt') -Value 'x'
    $status = Get-BorcSettingsStatus -Path $script:Test.Repo
    $status.Changes | Should -Be 2
    Format-BorcSettingsStatus -Status $status | Should -Be "BORC: 2 uncommitted changes in $($script:Test.Repo) (git -C $($script:Test.Repo) status)"
  }

  It 'counts every new file of a new folder, not the folder' {
    $script:Test = New-TestRepo -Pushed
    New-Item -ItemType Directory -Path (Join-Path $script:Test.Repo 'app') | Out-Null
    Set-Content -Path (Join-Path $script:Test.Repo 'app\one.txt') -Value 'x'
    Set-Content -Path (Join-Path $script:Test.Repo 'app\two.txt') -Value 'x'
    (Get-BorcSettingsStatus -Path $script:Test.Repo).Changes | Should -Be 2
  }

  It 'counts commits not pushed' {
    $script:Test = New-TestRepo -Pushed
    git @script:Git -C $script:Test.Repo commit --quiet --allow-empty -m one
    git @script:Git -C $script:Test.Repo commit --quiet --allow-empty -m two
    Format-BorcSettingsStatus -Status (Get-BorcSettingsStatus -Path $script:Test.Repo) | Should -Match '^BORC: 2 commits not pushed in '
  }

  It 'notices a branch that was never pushed' {
    $script:Test = New-TestRepo
    Format-BorcSettingsStatus -Status (Get-BorcSettingsStatus -Path $script:Test.Repo) | Should -Match '^BORC: a branch never pushed in '
  }

  It 'says nothing for a folder that is not a Git repo, or no folder at all' {
    $script:Test = [pscustomobject]@{ Root = New-TestFolder }
    Get-BorcSettingsStatus -Path $script:Test.Root | Should -BeNullOrEmpty
    Get-BorcSettingsStatus -Path '' | Should -BeNullOrEmpty
  }
}
