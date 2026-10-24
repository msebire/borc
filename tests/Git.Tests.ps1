BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  $env:GIT_TERMINAL_PROMPT = '0'

  function Invoke-TestGit {
    # Plain $args: an advanced function would read -C as one of its own parameters.
    $output = & git -c user.name=borc-test -c user.email=borc-test@example.invalid -c init.defaultBranch=main -c core.autocrlf=false @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $args failed: $output" }
  }

  # A bare remote with the branches given, each holding a borc.yaml.
  function New-TestRemote {
    param([string] $Root, [string[]] $Branches = @())
    $remote = Join-Path $Root 'remote.git'
    Invoke-TestGit init --bare $remote
    if ($Branches.Count -gt 0) {
      $work = Join-Path $Root 'seed'
      Invoke-TestGit clone $remote $work
      New-Item -ItemType Directory -Path (Join-Path $work 'borc') | Out-Null
      Set-Content -Path (Join-Path $work 'borc\borc.yaml') -Value "apps:`n  - winget: Git.Git"
      Invoke-TestGit -C $work add -A
      Invoke-TestGit -C $work commit -m seed
      Invoke-TestGit -C $work branch -M $Branches[0]
      foreach ($branch in $Branches) { Invoke-TestGit -C $work push origin "HEAD:refs/heads/$branch" }
    }
    $remote
  }

  function Initialize-TestSettings {
    param([string] $Path, [string] $Url, [string] $Branch, [scriptblock] $ChooseBase = { param($b) $null })
    InModuleScope Borc -Parameters @{ P = $Path; U = $Url; B = $Branch; C = $ChooseBase } {
      param($P, $U, $B, $C)
      Mock Write-Host {}
      Initialize-BorcSettings -Path $P -Url $U -Branch $B -ChooseBase $C
    }
  }
}

Describe 'BORC_SETTINGS folder check' {
  BeforeEach { $script:Root = New-TestFolder }
  AfterEach { Remove-Item -LiteralPath $script:Root -Recurse -Force }

  It 'sees a missing, an empty and a foreign folder' {
    InModuleScope Borc -Parameters @{ R = $script:Root } {
      param($R)
      Get-BorcSettingsFolderState -Path (Join-Path $R 'nope') -Url 'https://x/y.git' | Should -Be 'Missing'
      Get-BorcSettingsFolderState -Path $R -Url 'https://x/y.git' | Should -Be 'Empty'
      Set-Content -Path (Join-Path $R 'file.txt') -Value 'x'
      Get-BorcSettingsFolderState -Path $R -Url 'https://x/y.git' | Should -Be 'Other'
    }
  }

  It 'recognises a clone of the same repo, whatever the URL spelling' {
    $remote = New-TestRemote -Root $script:Root -Branches @('main')
    $clone = Join-Path $script:Root 'settings'
    Invoke-TestGit clone $remote $clone
    InModuleScope Borc -Parameters @{ C = $clone; U = $remote } {
      param($C, $U)
      Get-BorcSettingsFolderState -Path $C -Url $U | Should -Be 'SameRepo'
      Get-BorcSettingsFolderState -Path $C -Url ($U.ToUpperInvariant() -replace '\.git$', '/') | Should -Be 'SameRepo'
      Get-BorcSettingsFolderState -Path $C -Url 'https://github.com/other/repo.git' | Should -Be 'Other'
    }
  }

  It 'stops on a foreign folder' {
    Set-Content -Path (Join-Path $script:Root 'file.txt') -Value 'x'
    { Initialize-TestSettings -Path $script:Root -Url 'https://x/y.git' -Branch 'home' } | Should -Throw '*is not empty and is not a clone*'
  }
}

Describe 'Creating BORC_SETTINGS' {
  BeforeEach {
    $script:Root = New-TestFolder
    $script:Settings = Join-Path $script:Root 'settings'
  }
  AfterEach { Remove-Item -LiteralPath $script:Root -Recurse -Force }

  It 'creates a local repo from the starter template for an empty URL, without committing' {
    Initialize-TestSettings -Path $script:Settings -Url '' -Branch 'home'
    Test-Path (Join-Path $script:Settings 'borc\borc.yaml') | Should -BeTrue
    Test-Path (Join-Path $script:Settings '.gitignore') | Should -BeTrue
    Test-Path (Join-Path $script:Settings 'borc\scripts') | Should -BeTrue
    Test-Path (Join-Path $script:Settings 'borc\cookbook') | Should -BeTrue
    git -C $script:Settings symbolic-ref --short HEAD | Should -Be 'home'
    git -C $script:Settings rev-parse --verify --quiet HEAD | Should -BeNullOrEmpty
  }

  It 'leaves the local repo alone when run again with an empty URL' {
    Initialize-TestSettings -Path $script:Settings -Url '' -Branch 'home'
    Set-Content -Path (Join-Path $script:Settings 'borc\borc.yaml') -Value 'apps: []'
    Initialize-TestSettings -Path $script:Settings -Url '' -Branch 'home'
    Get-Content (Join-Path $script:Settings 'borc\borc.yaml') | Should -Be 'apps: []'
  }

  It 'clones an existing branch' {
    $remote = New-TestRemote -Root $script:Root -Branches @('work', 'home')
    Initialize-TestSettings -Path $script:Settings -Url $remote -Branch 'home'
    git -C $script:Settings symbolic-ref --short HEAD | Should -Be 'home'
  }

  It 'offers the existing branches and creates a missing branch from the chosen one' {
    $remote = New-TestRemote -Root $script:Root -Branches @('work', 'home')
    $script:Offered = $null
    Initialize-TestSettings -Path $script:Settings -Url $remote -Branch 'laptop' -ChooseBase { param($branches) $script:Offered = $branches; 'work' }
    $script:Offered | Sort-Object | Should -Be @('home', 'work')
    git -C $script:Settings symbolic-ref --short HEAD | Should -Be 'laptop'
    git -C $script:Settings ls-remote --heads origin laptop | Should -BeNullOrEmpty
  }

  It 'stops when no branch is chosen' {
    $remote = New-TestRemote -Root $script:Root -Branches @('work')
    { Initialize-TestSettings -Path $script:Settings -Url $remote -Branch 'laptop' } | Should -Throw '*no branch was chosen*'
  }

  It 'fills an empty remote from the starter template, without committing or pushing' {
    $remote = New-TestRemote -Root $script:Root
    Initialize-TestSettings -Path $script:Settings -Url $remote -Branch 'home'
    Test-Path (Join-Path $script:Settings 'borc\borc.yaml') | Should -BeTrue
    git -C $script:Settings symbolic-ref --short HEAD | Should -Be 'home'
    git -C $script:Settings rev-parse --verify --quiet HEAD | Should -BeNullOrEmpty
    git ls-remote --heads $remote | Should -BeNullOrEmpty
  }

  It 'asks for the URL, the branch and the base branch during setup' {
    $remote = New-TestRemote -Root $script:Root -Branches @('work')
    InModuleScope Borc -Parameters @{ S = $script:Settings; U = $remote } {
      param($S, $U)
      Mock Write-Host {}
      $script:Answers = [System.Collections.Generic.Queue[string]]::new([string[]]@($U, 'laptop', '1'))
      Mock Read-BorcInput { $script:Answers.Dequeue() }
      Initialize-BorcSettingsInteractive -Path $S
    }
    git -C $script:Settings symbolic-ref --short HEAD | Should -Be 'laptop'
  }

  It 'leaves a clone of the same repo as it is' {
    $remote = New-TestRemote -Root $script:Root -Branches @('home')
    Initialize-TestSettings -Path $script:Settings -Url $remote -Branch 'home'
    Initialize-TestSettings -Path $script:Settings -Url $remote -Branch 'home'
    git -C $script:Settings symbolic-ref --short HEAD | Should -Be 'home'
  }
}

Describe 'Pulling the config repo' {
  BeforeEach {
    $script:Root = New-TestFolder
    $script:Remote = New-TestRemote -Root $script:Root -Branches @('home')
    $script:Settings = Join-Path $script:Root 'settings'
    Invoke-TestGit clone --branch home $script:Remote $script:Settings
  }
  AfterEach { Remove-Item -LiteralPath $script:Root -Recurse -Force }

  It 'refuses to pull while a tracked file has uncommitted changes' {
    Add-Content -Path (Join-Path $script:Settings 'borc\borc.yaml') -Value '# local edit'
    $settings = $script:Settings
    { InModuleScope Borc -Parameters @{ S = $settings } { param($S) Mock Write-Host {}; Sync-BorcConfigRepo -Path $S } } |
      Should -Throw '*borc/borc.yaml*Commit or discard them*'
  }

  It 'pulls when only untracked or ignored files changed' {
    Set-Content -Path (Join-Path $script:Settings 'untracked.txt') -Value 'x'
    $seed = Join-Path $script:Root 'seed'
    Add-Content -Path (Join-Path $seed 'borc\borc.yaml') -Value '  - winget: A.B'
    Invoke-TestGit -C $seed commit -am more
    Invoke-TestGit -C $seed push origin HEAD:refs/heads/home
    InModuleScope Borc -Parameters @{ S = $script:Settings } { param($S) Mock Write-Host {}; Sync-BorcConfigRepo -Path $S }
    Get-Content (Join-Path $script:Settings 'borc\borc.yaml') | Should -Contain '  - winget: A.B'
  }

  It 'shows what a pull would bring without merging it' {
    $seed = Join-Path $script:Root 'seed'
    Add-Content -Path (Join-Path $seed 'borc\borc.yaml') -Value '  - winget: A.B'
    Invoke-TestGit -C $seed commit -am 'add A.B'
    Invoke-TestGit -C $seed push origin HEAD:refs/heads/home
    $incoming = InModuleScope Borc -Parameters @{ S = $script:Settings } { param($S) Get-BorcIncoming -Path $S }
    $incoming.Commits | Should -Match 'add A.B'
    Get-Content (Join-Path $script:Settings 'borc\borc.yaml') | Should -Not -Contain '  - winget: A.B'
    $text = InModuleScope Borc -Parameters @{ S = $script:Settings } { param($S) Read-BorcGitFile -Repo $S -Ref '@{u}' -RelativePath 'borc\borc.yaml' }
    $text | Should -Match 'A\.B'
  }

  It 'applies the local copy of a branch with no upstream' {
    Invoke-TestGit -C $script:Settings switch -c laptop --no-track
    InModuleScope Borc -Parameters @{ S = $script:Settings } { param($S) Mock Write-Host {}; Sync-BorcConfigRepo -Path $S }
  }
}
