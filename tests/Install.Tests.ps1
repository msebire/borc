BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  $script:InstallPath = Join-Path $script:RepoRoot 'install.ps1'

  # Loads the functions and top-level variables of install.ps1 without running it.
  $tokens = $null
  $parseErrors = $null
  $script:InstallAst = [System.Management.Automation.Language.Parser]::ParseFile($script:InstallPath, [ref]$tokens, [ref]$parseErrors)
  foreach ($function in $script:InstallAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($function.Extent.Text))
  }
  foreach ($statement in $script:InstallAst.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.AssignmentStatementAst] }) {
    . ([scriptblock]::Create($statement.Extent.Text))
  }

  function Invoke-TestGit {
    # Plain $args: an advanced function would read -C as one of its own parameters.
    $output = & git -c user.name=borc-test -c user.email=borc-test@example.invalid -c init.defaultBranch=main -c core.autocrlf=false @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $args failed: $output" }
  }
}

Describe 'install.ps1' {
  It 'parses under Windows PowerShell 5.1' {
    $command = "`$e = `$null; [System.Management.Automation.Language.Parser]::ParseFile('$script:InstallPath', [ref]`$null, [ref]`$e) | Out-Null; `$e.Count"
    powershell.exe -NoProfile -NonInteractive -Command $command | Should -Be '0'
  }

  It 'has no BOM and only ASCII characters, so irm | iex reads it unchanged' {
    $bytes = [IO.File]::ReadAllBytes($script:InstallPath)
    ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    @($bytes | Where-Object { $_ -gt 0x7F }).Count | Should -Be 0
  }

  It 'parses under Windows PowerShell 5.1 when decoded as irm would decode it' {
    # irm returns the raw text: no BOM is skipped, and the charset may be guessed.
    $command = @"
`$bytes = [IO.File]::ReadAllBytes('$script:InstallPath')
foreach (`$encoding in 'utf-8', 'windows-1252') {
  `$errors = `$null
  [System.Management.Automation.Language.Parser]::ParseInput([Text.Encoding]::GetEncoding(`$encoding).GetString(`$bytes), [ref]`$null, [ref]`$errors) | Out-Null
  `$errors.Count
}
"@
    powershell.exe -NoProfile -NonInteractive -Command $command | Should -Be @('0', '0')
  }

  It 'accepts Windows 11, warns on Windows 10 22H2 and refuses older builds' {
    { Assert-BorcWindowsVersion -Build 22631 } | Should -Not -Throw
    Assert-BorcWindowsVersion -Build 19045 3>&1 | Should -Match 'Windows 10 22H2'
    { Assert-BorcWindowsVersion -Build 19044 } | Should -Throw '*build 19044*'
  }

  It 'changes the execution policy for the process only' {
    $script:InstallAst.Extent.Text | Should -Match 'Set-ExecutionPolicy -Scope Process'
    $script:InstallAst.Extent.Text | Should -Not -Match 'Set-ExecutionPolicy (?!-Scope Process)'
    $script:InstallAst.Extent.Text | Should -Not -Match 'Set-PSRepository|InstallationPolicy'
  }

  It 'never exits the host, so irm | iex keeps the window open' {
    $script:InstallAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true) | Should -BeNullOrEmpty
  }

  It 'keeps the same repo URL as Constants.ps1' {
    $url = InModuleScope Borc { $script:BorcRepoUrl }
    [IO.File]::ReadAllText($script:InstallPath) | Should -Match ([regex]::Escape("`$BorcRepoUrl = '$url'"))
  }

  It 'shows the one-liner the docs give' {
    $oneLiner = InModuleScope Borc { Get-BorcOneLiner }
    [IO.File]::ReadAllText($script:InstallPath) | Should -Match ([regex]::Escape($oneLiner))
  }
}

Describe 'Installer output' {
  BeforeEach {
    $script:SavedNoColor = $env:NO_COLOR
    $env:NO_COLOR = $null
    $InstallSteps.List.Clear()
    $InstallSteps.Current = $null
    $script:Shown = New-Object System.Collections.ArrayList
    Mock Write-Host { [void]$script:Shown.Add([pscustomobject]@{ Text = "$Object"; Color = $ForegroundColor }) }
  }
  AfterEach { $env:NO_COLOR = $script:SavedNoColor }

  It 'shows numbered steps and a summary that marks the failing step' {
    Start-InstallStep -Name 'Windows version'
    Start-InstallStep -Name 'Updating winget'
    Complete-InstallStep -Status 'failed'
    Write-InstallSummary
    $texts = $script:Shown.Text
    $texts | Should -Contain '==> [1/5] Windows version'
    $texts | Should -Contain '==> [2/5] Updating winget'
    ($texts -join "`n") | Should -Match 'done     \[1/5\] Windows version'
    ($texts -join "`n") | Should -Match 'failed   \[2/5\] Updating winget'
    $texts | Should -Contain '  Stopped after step 2 of 5.'
    ($script:Shown | Where-Object Text -Like '==>*').Color | Should -Be @('Cyan', 'Cyan')
  }

  It 'frames an external command and treats the given codes as fine' {
    Invoke-InstallCommand -FilePath 'git' -Arguments @('--version') | Should -Be 0
    $script:Shown[0].Text | Should -Be '  > git --version'
    $script:Shown[-1].Text | Should -Match '^  < done in \d+s$'
    $script:Shown[-1].Color | Should -Be 'Green'
  }

  It 'ends a failing command with its exit code' {
    Invoke-InstallCommand -FilePath 'git' -Arguments @('-C', 'Z:\no\such\folder', 'status') 2>$null | Should -Not -Be 0
    $script:Shown[-1].Text | Should -Match '^  < failed, exit code \d+, after \d+s$'
    $script:Shown[-1].Color | Should -Be 'Red'
  }

  It 'drops colours with NO_COLOR' {
    $env:NO_COLOR = '1'
    Start-InstallStep -Name 'Windows version'
    $script:Shown.Color | Where-Object { $_ } | Should -BeNullOrEmpty
  }
}

Describe 'Engine branch' {
  BeforeEach { $script:SavedBranch = $env:BORC_BRANCH }
  AfterEach { $env:BORC_BRANCH = $script:SavedBranch }

  It 'is main unless BORC_BRANCH is set for the process, with a warning when it is' {
    $env:BORC_BRANCH = $null
    Get-BorcEngineBranch 3>$null | Should -Be 'main'
    $env:BORC_BRANCH = 'my-branch'
    Get-BorcEngineBranch 3>$null | Should -Be 'my-branch'
    Get-BorcEngineBranch 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | Should -Match 'BORC_BRANCH is set'
  }
}

Describe 'Engine clone' {
  BeforeAll {
    $script:Root = New-TestFolder
    $script:Remote = Join-Path $script:Root 'borc.git'
    $script:Seed = Join-Path $script:Root 'seed'
    $script:Engine = Join-Path $script:Root 'localappdata\borc\engine'
    Invoke-TestGit init --bare $script:Remote
    Invoke-TestGit clone $script:Remote $script:Seed
    Set-Content -Path (Join-Path $script:Seed 'version.txt') -Value 'main 1'
    Invoke-TestGit -C $script:Seed add -A
    Invoke-TestGit -C $script:Seed commit -m 'main 1'
    Invoke-TestGit -C $script:Seed push origin HEAD:refs/heads/main
    Invoke-TestGit -C $script:Seed switch -c my-branch
    Set-Content -Path (Join-Path $script:Seed 'version.txt') -Value 'branch 1'
    Invoke-TestGit -C $script:Seed commit -am 'branch 1'
    Invoke-TestGit -C $script:Seed push origin HEAD:refs/heads/my-branch

    function Install-TestEngine { param([string] $Branch) Install-BorcEngine -Path $script:Engine -Branch $Branch -RepoUrl $script:Remote 6>$null *>$null }
    function Get-TestEngineVersion { (Get-Content -LiteralPath (Join-Path $script:Engine 'version.txt')) }
  }
  AfterAll { Remove-Item -LiteralPath $script:Root -Recurse -Force }

  It 'clones the branch it is given' {
    Install-TestEngine -Branch 'my-branch'
    git -C $script:Engine symbolic-ref --short HEAD | Should -Be 'my-branch'
    Get-TestEngineVersion | Should -Be 'branch 1'
  }

  It 'pulls new commits of that branch when run again' {
    Set-Content -Path (Join-Path $script:Seed 'version.txt') -Value 'branch 2'
    Invoke-TestGit -C $script:Seed commit -am 'branch 2'
    Invoke-TestGit -C $script:Seed push origin HEAD:refs/heads/my-branch
    Install-TestEngine -Branch 'my-branch'
    Get-TestEngineVersion | Should -Be 'branch 2'
  }

  It 'goes back to main when run without the branch' {
    Install-TestEngine -Branch 'main'
    git -C $script:Engine symbolic-ref --short HEAD | Should -Be 'main'
    Get-TestEngineVersion | Should -Be 'main 1'
  }

  It 'stops with a clear error for a branch that does not exist' {
    { Install-TestEngine -Branch 'no-such-branch' } | Should -Throw '*switch the borc engine to the branch no-such-branch*'
  }
}

Describe 'Setup steps' {
  It 'accepts only full paths with a drive letter for the folders' {
    InModuleScope Borc {
      Test-BorcFolderPath -Path 'D:\settings\' | Should -BeTrue
      Test-BorcFolderPath -Path 'settings\' | Should -BeFalse
      Test-BorcFolderPath -Path '\\server\share\' | Should -BeFalse
    }
  }

  It 'reuses a folder variable that is already set' {
    InModuleScope Borc {
      Mock Write-Host {}
      Mock Get-BorcEnvironmentVariable { 'D:\settings' } -ParameterFilter { $Name -eq 'BORC_SETTINGS' -and $Scope -eq 'User' }
      Mock Read-BorcInput { throw 'must not ask' }
      Get-BorcFolderSetting -Name 'BORC_SETTINGS' -Purpose 'x' -Example 'D:\settings' | Should -Be 'D:\settings'
    }
  }

  It 'asks again until the folder is a full path' {
    InModuleScope Borc {
      Mock Write-Host {}
      Mock Get-BorcEnvironmentVariable { $null }
      $script:Answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('settings', '"D:\settings\"'))
      Mock Read-BorcInput { $script:Answers.Dequeue() }
      Get-BorcFolderSetting -Name 'BORC_SETTINGS' -Purpose 'x' -Example 'D:\settings' | Should -Be 'D:\settings'
    }
  }

  It 'adds the bin folder to the user PATH once, keeping unexpanded entries' {
    InModuleScope Borc {
      Mock Write-Host {}
      $script:UserPath = '%USERPROFILE%\tools;C:\other'
      Mock Get-BorcUserPath { $script:UserPath }
      Mock Set-BorcUserPath { $script:UserPath = $Value }
      $processPath = $env:Path
      try {
        Add-BorcUserPath -Folder 'C:\Users\x\AppData\Local\borc\bin'
        Add-BorcUserPath -Folder 'C:\Users\x\AppData\Local\borc\bin\'
      } finally {
        $env:Path = $processPath
      }
      $script:UserPath | Should -Be '%USERPROFILE%\tools;C:\other;C:\Users\x\AppData\Local\borc\bin'
      Should -Invoke Set-BorcUserPath -Times 1 -Exactly
    }
  }

  It 'offers the existing branches by number' {
    InModuleScope Borc {
      Mock Write-Host {}
      Mock Read-BorcInput { '2' }
      Select-BorcBaseBranch -Branch 'laptop' -Branches @('home', 'work') | Should -Be 'work'
      Mock Read-BorcInput { '' }
      Select-BorcBaseBranch -Branch 'laptop' -Branches @('home', 'work') | Should -BeNullOrEmpty
    }
  }

  It 'copies the shim and Get-BorcSecret.ps1 to the runtime folders' {
    $root = New-TestFolder
    try {
      $paths = [pscustomobject]@{ Internal = $root; Bin = Join-Path $root 'bin' }
      InModuleScope Borc -Parameters @{ P = $paths } { param($P) Install-BorcRuntimeFiles -Paths $P }
      Test-Path (Join-Path $root 'bin\borc.cmd') | Should -BeTrue
      Test-Path (Join-Path $root 'Get-BorcSecret.ps1') | Should -BeTrue
    } finally {
      Remove-Item -LiteralPath $root -Recurse -Force
    }
  }
}
