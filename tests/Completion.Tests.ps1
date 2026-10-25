BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

  $script:Root = New-TestFolder
  $script:SavedSettings = $env:BORC_SETTINGS
  $script:SavedLocalAppData = $env:LOCALAPPDATA
  $settings = Join-Path $script:Root 'settings'
  New-Item -ItemType Directory -Path (Join-Path $settings 'borc\cookbook'), (Join-Path $script:Root 'localappdata\borc\recipes\recipes') -Force | Out-Null
  Set-Content -Path (Join-Path $settings 'borc\cookbook\sysinternals.yaml') -Value 'x'
  Set-Content -Path (Join-Path $settings 'borc\cookbook\wsl-ubuntu.yaml') -Value 'x'
  Set-Content -Path (Join-Path $script:Root 'localappdata\borc\recipes\recipes\node.yaml') -Value 'x'
  Set-Content -Path (Join-Path $settings 'borc\borc.yaml') -Value "apps:`n  - winget: Git.Git # vcs`n  - msstore: 9NBLGGH4NNS1`n  - recipe: '@local/sysinternals'"
  # Process level only, restored after the tests.
  $env:BORC_SETTINGS = $settings
  $env:LOCALAPPDATA = Join-Path $script:Root 'localappdata'

  . (Join-Path $script:RepoRoot 'src\completion.ps1')
  # winget's own completion is a real winget call; answer it here instead.
  function Get-BorcWingetCompletion { param([string] $Word) @('Git.GCM', 'Git.Git') | Where-Object { $_ -like "$Word*" } }

  # What Tab offers for the text, with the cursor at its end, as a real shell sees it.
  function Get-Tab {
    param([string] $Line)
    @((TabExpansion2 -inputScript $Line -cursorColumn $Line.Length).CompletionMatches.CompletionText)
  }
}

AfterAll {
  $env:BORC_SETTINGS = $script:SavedSettings
  $env:LOCALAPPDATA = $script:SavedLocalAppData
  Remove-Item -LiteralPath $script:Root -Recurse -Force
}

Describe 'borc Tab completion' {
  It 'completes <Line> to <Expected>' -ForEach @(
    @{ Line = 'borc '; Expected = @('help', 'apply', 'upgrade', 'install', 'uninstall', 'search', 'self-update') }
    @{ Line = 'borc u'; Expected = @('upgrade', 'uninstall') }
    @{ Line = 'borc help se'; Expected = @('search', 'self-update') }
    @{ Line = 'borc apply --'; Expected = @('--what-if', '--debug', '--help') }
    @{ Line = 'borc apply --what-if --'; Expected = @('--check', '--debug', '--help') }
    @{ Line = 'borc install '; Expected = @("'@local/sysinternals'", "'@local/wsl-ubuntu'", 'recipes/node') }
    @{ Line = 'borc install @local/w'; Expected = @("'@local/wsl-ubuntu'") }
    @{ Line = "borc install '@local/s"; Expected = @("'@local/sysinternals'") }
    @{ Line = 'borc install Git.'; Expected = @('Git.GCM', 'Git.Git') }
    @{ Line = 'borc uninstall '; Expected = @('Git.Git', '9NBLGGH4NNS1', "'@local/sysinternals'") }
    @{ Line = 'borc search no'; Expected = @('node') }
    @{ Line = 'borc upgrade --'; Expected = @('--help') }
  ) {
    Get-Tab -Line $Line | Should -Be $Expected
  }

  # PowerShell then falls back to file names, as for any external command.
  It 'offers no borc suggestion once the argument is given' {
    $offered = Get-Tab -Line 'borc install Git.Git '
    $offered | Should -Not -Contain 'Git.GCM'
    $offered | Should -Not -Contain "'@local/sysinternals'"
    $offered | Should -Not -Contain 'recipes/node'
  }

  It 'never asks winget for a word without a dot' {
    function Get-BorcWingetCompletion { throw 'winget must not be asked' }
    { Get-Tab -Line 'borc install sys' } | Should -Not -Throw
  }
}
