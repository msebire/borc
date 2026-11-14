BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  $script:Helper = Join-Path $script:RepoRoot 'src\borc\Write-BorcVersion.ps1'

  # A report as Write-BorcVersion writes it, in the folder BORC reads.
  function New-TestReport {
    param([string] $Folder, [string] $App, [string] $Installed = '', [string] $Available = '', [long] $Ticks = 0, [string] $Text)
    New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    if (-not $Text) { $Text = [ordered]@{ App = $App; Installed = $Installed; Available = $Available; Ticks = $Ticks } | ConvertTo-Json -Compress }
    Set-Content -LiteralPath (Join-Path $Folder "$([guid]::NewGuid().ToString('N')).json") -Value $Text
  }
}

Describe 'Write-BorcVersion' {
  BeforeEach {
    $script:Root = New-TestFolder
    $script:SavedLocalAppData = $env:LOCALAPPDATA
    # Process level only: the helper writes under this temporary folder.
    $env:LOCALAPPDATA = $script:Root
  }
  AfterEach {
    $env:LOCALAPPDATA = $script:SavedLocalAppData
    Remove-Item -LiteralPath $script:Root -Recurse -Force
  }

  It 'writes one report where BORC reads it, and prints nothing' {
    $printed = @(& { . $script:Helper; Write-BorcVersion -App CodeAlta -Installed '4.2.0' -Available '4.4.0' })
    $printed.Count | Should -Be 0
    $paths = [pscustomobject]@{ Internal = Join-Path $script:Root 'borc' }
    $reports = @(InModuleScope borc -Parameters @{ P = $paths } { param($P) Read-BorcVersionReports -Paths $P })
    $reports.Count | Should -Be 1
    $reports[0].App | Should -Be 'CodeAlta'
    $reports[0].Installed | Should -Be '4.2.0'
    $reports[0].Available | Should -Be '4.4.0'
  }

  It 'works under Windows PowerShell 5.1 too' {
    $command = "`$env:LOCALAPPDATA = '$script:Root'; . '$script:Helper'; Write-BorcVersion -App Tool -Installed '1.0'"
    @(powershell -NoProfile -NonInteractive -Command $command).Count | Should -Be 0
    @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'borc\versions') -Filter '*.json').Count | Should -Be 1
  }

  It 'prints nothing and never throws when it cannot write, so the unit goes on' {
    Set-Content -Path (Join-Path $script:Root 'borc') -Value 'a file where the folder should be'
    $printed = @(& { . $script:Helper; Write-BorcVersion -App Tool -Installed '1.0'; 'after' } 2>&1)
    $printed | Should -Be @('after')
  }
}

Describe 'Reading version reports' {
  BeforeEach {
    $script:Root = New-TestFolder
    $script:Paths = [pscustomobject]@{ Internal = $script:Root }
    $script:Folder = Join-Path $script:Root 'versions'
  }
  AfterEach { Remove-Item -LiteralPath $script:Root -Recurse -Force }

  It 'reads them oldest first, as one short line of plain text each' {
    New-TestReport -Folder $script:Folder -App 'B' -Installed '2' -Ticks 20
    New-TestReport -Folder $script:Folder -App ('A' + [char]27 + '[31m' + [char]10) -Installed ('9' * 80) -Ticks 10
    $reports = @(InModuleScope borc -Parameters @{ P = $script:Paths } { param($P) Read-BorcVersionReports -Paths $P })
    $reports.App | Should -Be @('A[31m', 'B')
    $reports[0].Installed.Length | Should -Be 50
  }

  It 'leaves out a report it cannot read, with a warning' {
    New-TestReport -Folder $script:Folder -Text 'not json'
    New-TestReport -Folder $script:Folder -App 'A' -Installed '1'
    $result = InModuleScope borc -Parameters @{ P = $script:Paths } {
      param($P)
      $script:Warned = [System.Collections.Generic.List[string]]::new()
      Mock Write-BorcLog { if ($Level -eq 'Warning') { $script:Warned.Add($Message) } }
      [pscustomobject]@{ Reports = @(Read-BorcVersionReports -Paths $P); Warned = @($script:Warned) }
    }
    $result.Reports.App | Should -Be @('A')
    $result.Warned[0] | Should -Match '^Could not read the version report \w+\.json, which is left out'
  }

  It 'empties the folder before a run' {
    New-TestReport -Folder $script:Folder -App 'old' -Installed '1'
    InModuleScope borc -Parameters @{ P = $script:Paths } { param($P) Clear-BorcVersionReports -Paths $P; @(Read-BorcVersionReports -Paths $P).Count } | Should -Be 0
  }
}

Describe 'What the reports say' {
  It 'says <Expected> for <Case>' -ForEach @(
    @{ Case = 'a test, then an upgrade'; Reports = @(@('4.2.0', '4.4.0'), @('4.4.0', '')); Expected = 'upgraded'; Text = 'CodeAlta (4.2.0 -> 4.4.0)' }
    @{ Case = 'a test with the newest installed'; Reports = @(, @('4.4.0', '4.4.0')); Expected = 'up to date'; Text = 'CodeAlta 4.4.0' }
    @{ Case = 'a test with a newer version, as with --check'; Reports = @(, @('4.2.0', '4.4.0')); Expected = 'available'; Text = 'CodeAlta (4.2.0 -> 4.4.0)' }
    @{ Case = 'an upgrade that did not move it'; Reports = @(@('4.2.0', '4.4.0'), @('4.2.0', '')); Expected = 'available'; Text = 'CodeAlta (4.2.0 -> 4.4.0)' }
    @{ Case = 'two reports of one version'; Reports = @(@('4.4.0', ''), @('4.4.0', '')); Expected = 'up to date'; Text = 'CodeAlta 4.4.0' }
    @{ Case = 'one report of the installed version only'; Reports = @(, @('4.2.0', '')); Expected = 'reported'; Text = 'CodeAlta 4.2.0' }
  ) {
    $list = @(for ($i = 0; $i -lt $Reports.Count; $i++) { [pscustomobject]@{ App = 'CodeAlta'; Installed = $Reports[$i][0]; Available = $Reports[$i][1]; Ticks = $i } })
    $version = InModuleScope borc -Parameters @{ L = $list } { param($L) Get-BorcReportedVersions -Reports $L }
    $version.State | Should -Be $Expected
    $version.Text | Should -Be $Text
  }
}
