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
    Format-BorcSettingsStatus -Status $status | Should -Be "borc: 2 uncommitted changes in $($script:Test.Repo) (git -C $($script:Test.Repo) status)"
  }

  It 'counts commits not pushed' {
    $script:Test = New-TestRepo -Pushed
    git @script:Git -C $script:Test.Repo commit --quiet --allow-empty -m one
    git @script:Git -C $script:Test.Repo commit --quiet --allow-empty -m two
    Format-BorcSettingsStatus -Status (Get-BorcSettingsStatus -Path $script:Test.Repo) | Should -Match '^borc: 2 commits not pushed in '
  }

  It 'notices a branch that was never pushed' {
    $script:Test = New-TestRepo
    Format-BorcSettingsStatus -Status (Get-BorcSettingsStatus -Path $script:Test.Repo) | Should -Match '^borc: a branch never pushed in '
  }

  It 'says nothing for a folder that is not a Git repo, or no folder at all' {
    $script:Test = [pscustomobject]@{ Root = New-TestFolder }
    Get-BorcSettingsStatus -Path $script:Test.Root | Should -BeNullOrEmpty
    Get-BorcSettingsStatus -Path '' | Should -BeNullOrEmpty
  }
}
