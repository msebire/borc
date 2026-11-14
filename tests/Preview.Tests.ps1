BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

  # A recipe from its resources, as Get-BorcPlan would load it.
  function New-TestPlan {
    param([string] $Resources, [hashtable] $Parameters = @{}, [string] $Header = '')
    $text = $Header + "`$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json`nmetadata:`n  winget:`n    processor: dscv3`nresources:`n" + $Resources
    InModuleScope borc -Parameters @{ T = $text; P = $Parameters } {
      param($T, $P)
      $recipe = ConvertTo-BorcRecipe -Text $T -Id '@local/x'
      $recipe.Errors | Should -BeNullOrEmpty
      $parameters = [ordered]@{}
      foreach ($key in $P.Keys) { $parameters[$key] = $P[$key] }
      $config = [pscustomobject]@{ Apps = @([pscustomobject]@{ Kind = 'recipe'; Id = '@local/x'; Parameters = $parameters }) }
      [pscustomobject]@{ Config = $config; Recipes = [ordered]@{ '@local/x' = $recipe }; Order = @('@local/x'); Errors = @() }
    }
  }

  function Get-TestVerdict {
    param($Plan, [string[]] $Installed = @())
    InModuleScope borc -Parameters @{ Plan = $Plan; Installed = $Installed } {
      param($Plan, $Installed)
      Mock Test-BorcPackageInstalled { $Id -in $Installed }
      Get-BorcRecipeVerdict -Plan $Plan -Id '@local/x'
    }
  }

  $script:Package = "  - name: app`n    type: Microsoft.WinGet/Package`n    properties:`n      id: Some.App`n      source: winget`n"
  $script:Setting = "  - name: setting`n    type: Microsoft.DSC.Transitional/PowerShellScript`n    properties:`n      input: '{{value}}'`n"
}

Describe 'Recipe verdicts' {
  It 'is in place when it only installs packages and all of them are there' {
    $verdict = Get-TestVerdict -Plan (New-TestPlan -Resources $script:Package) -Installed 'Some.App'
    $verdict.Verdict | Should -Be 'in place'
    $verdict.Details | Should -Be @('packages: 1 of 1 installed, no settings')
  }

  It 'would be applied when a package is missing, and names it' {
    $verdict = Get-TestVerdict -Plan (New-TestPlan -Resources $script:Package)
    $verdict.Verdict | Should -Be 'would be applied'
    $verdict.Details | Should -Be @('packages: 0 of 1 installed (Some.App), no settings')
  }

  It 'may be applied when its packages are there but it has settings' {
    $header = "borc:`n  parameters:`n    value: a value`n"
    $verdict = Get-TestVerdict -Plan (New-TestPlan -Header $header -Resources ($script:Package + $script:Setting) -Parameters @{ value = 'x' }) -Installed 'Some.App'
    $verdict.Verdict | Should -Be 'may be applied'
    $verdict.Details | Should -Be @('packages: 1 of 1 installed', 'settings: 1 unit, not checked')
  }

  It 'counts a setting skipped for a missing parameter, without running it' {
    $header = "borc:`n  parameters:`n    value: a value`n"
    $verdict = Get-TestVerdict -Plan (New-TestPlan -Header $header -Resources ($script:Package + $script:Setting)) -Installed 'Some.App'
    $verdict.Verdict | Should -Be 'in place'
    $verdict.Details | Should -Be @('packages: 1 of 1 installed', 'settings: none to run; 1 skipped (no value for value)')
  }

  It 'notes that a reboot recipe runs first' {
    $verdict = Get-TestVerdict -Plan (New-TestPlan -Header "borc:`n  reboot: true`n" -Resources $script:Package)
    $verdict.Note | Should -Be ' (runs first, may need a restart)'
  }
}

Describe 'Fixed versions' {
  It 'reads the installed version from real winget list output, not the available one' {
    $lines = @('Name Id        Version Available Source', '-------------------------------------------', 'jq   jqlang.jq 1.7.1   1.8.2     winget')
    InModuleScope borc -Parameters @{ L = $lines } { param($L) ConvertFrom-WingetListVersion -Id 'jqlang.jq' -Lines $L } | Should -Be '1.7.1'
  }

  It 'counts a plain app as installed only in its fixed version' {
    InModuleScope borc {
      Mock Get-BorcInstalledVersion { '1.8.2' }
      $verdict = Get-BorcPlainVerdict -App ([pscustomobject]@{ Kind = 'winget'; Id = 'jqlang.jq'; Version = '1.7.1' })
      $verdict.Verdict | Should -Be 'would be installed'
      $verdict.Details | Should -Be @('version 1.7.1 fixed, 1.8.2 is installed')
      Mock Get-BorcInstalledVersion { '1.7.1' }
      $verdict = Get-BorcPlainVerdict -App ([pscustomobject]@{ Kind = 'winget'; Id = 'jqlang.jq'; Version = '1.7.1' })
      $verdict.Verdict | Should -Be 'installed'
      $verdict.Details | Should -Be @('version 1.7.1 fixed')
    }
  }

  It 'keeps a version a recipe fixes, even when borc.yaml lists the same package without one' {
    InModuleScope borc {
      $recipe = [pscustomobject]@{ Id = 'r/x'; Resources = @([ordered]@{ name = 'p'; type = 'Microsoft.WinGet/Package'; properties = [ordered]@{ id = 'Git.Git'; source = 'winget'; version = '2.45.1' } }) }
      $plan = [pscustomobject]@{
        Config = [pscustomobject]@{ Apps = @([pscustomobject]@{ Kind = 'winget'; Id = 'Git.Git'; Version = '' }) }
        Recipes = [ordered]@{ 'r/x' = $recipe }; Order = @('r/x')
      }
      $listed = @(Get-BorcListedPackages -Plan $plan)
      $listed.Count | Should -Be 1
      $listed[0].Version | Should -Be '2.45.1'
      $listed[0].Origin | Should -Be 'recipe r/x'
    }
  }
}

Describe 'Reading winget configure test' {
  It 'reads the state of every unit from real winget 1.29 output' {
    $lines = [IO.File]::ReadAllLines((Join-Path $script:FixturesRoot 'winget-configure-test.txt'))
    $results = InModuleScope borc -Parameters @{ L = $lines } { param($L) ConvertFrom-BorcConfigureTest -Lines $L }
    $results.Keys | Should -Be @('@local/x: in place', '@local/x: would change', 'winget: Git.Git', '@local/x: broken test', '@local/x: after in place')
    $results['@local/x: in place'].State | Should -Be 'in'
    $results['@local/x: would change'].State | Should -Be 'out'
    $results['@local/x: broken test'].State | Should -Be 'unknown'
    $results['@local/x: broken test'].Message | Should -Be 'test failed: tool not installed'
  }

  It 'reads an elevated unit, whose type is followed by a shield icon and two spaces' -ForEach @(
    @{ Case = 'decoded as UTF-8'; Icon = "$([char]::ConvertFromUtf32(0x1F6E1))$([char]0xFE0F)" }
    @{ Case = 'garbled by an OEM code page, as seen on winget 1.29.380'; Icon = "$([char]0x2261)$([char]0x192)$([char]0xA2)$([char]0xED)" }
  ) {
    $lines = @("Microsoft.DSC.Transitional/PowerShellScript$Icon  [@local/d-elevated: elevated no-op]", '  System is in the described configuration state.')
    $results = InModuleScope borc -Parameters @{ L = $lines } { param($L) ConvertFrom-BorcConfigureTest -Lines $L }
    $results['@local/d-elevated: elevated no-op'].State | Should -Be 'in'
  }

  It 'does not take an error line for a unit' {
    $lines = @('Microsoft.WinGet/Package [@local/x: app]', '  System is in the described configuration state.', 'Some/Path failed for this [reason]')
    $results = InModuleScope borc -Parameters @{ L = $lines } { param($L) ConvertFrom-BorcConfigureTest -Lines $L }
    @($results.Keys) | Should -Be @('@local/x: app')
  }

  It 'never guesses on a line it does not know' {
    $results = InModuleScope borc { ConvertFrom-BorcConfigureTest -Lines @('Microsoft.WinGet/Package [@local/x: app]', '  Le système est dans un état inconnu.') }
    $results['@local/x: app'].State | Should -Be 'unknown'
    $results['@local/x: app'].Message | Should -Match '^winget said: Le syst'
  }
}

Describe 'Checked recipe verdicts' {
  BeforeAll {
    function Get-CheckedVerdict {
      # IDictionary, not hashtable: a hashtable would lose the unit order.
      param([System.Collections.IDictionary] $States, [string[]] $Dropped = @())
      InModuleScope borc -Parameters @{ S = $States; D = $Dropped } {
        param($S, $D)
        $checks = [ordered]@{}
        $units = foreach ($name in $S.Keys) {
          [ordered]@{ name = "@local/x: $name"; type = 'T' }
          if ($S[$name]) { $checks["@local/x: $name"] = [pscustomobject]@{ State = $S[$name]; Message = 'test failed: boom' } }
        }
        Get-BorcCheckedRecipeVerdict -Id '@local/x' -Units @($units) -Dropped $D -Checks $checks -Note ''
      }
    }
  }

  It 'is in place when every unit is' {
    $verdict = Get-CheckedVerdict -States ([ordered]@{ a = 'in'; b = 'in' })
    $verdict.Verdict | Should -Be 'in place'
    $verdict.Details | Should -Be @('units: 2 of 2 in place')
  }

  It 'would be applied when a unit would change, and names it' {
    $verdict = Get-CheckedVerdict -States ([ordered]@{ a = 'in'; b = 'out' }) -Dropped @("@local/x: 'c' skipped, no value for p")
    $verdict.Verdict | Should -Be 'would be applied'
    $verdict.Details | Should -Be @('units: 1 of 2 in place', 'would change: b', 'skipped: 1 (no value for p)')
  }

  It 'may be applied when a unit could not be tested, with the reason' {
    $verdict = Get-CheckedVerdict -States ([ordered]@{ a = 'in'; b = 'unknown'; c = $null })
    $verdict.Verdict | Should -Be 'may be applied'
    $verdict.Details | Should -Be @('units: 1 of 3 in place', 'could not test: b (test failed: boom); c (no result from winget)')
  }
}

Describe 'what-if result' {
  It 'says <Expected> for <Case>' -ForEach @(
    @{ Case = 'a pull to bring'; Pulls = @{ 'config repo' = '2 commits to pull' }; Verdicts = @('in place'); Secrets = @(); Checked = $false; Expected = 'there are changes to apply.' }
    @{ Case = 'an app to install'; Pulls = @{}; Verdicts = @('would be installed', 'in place'); Secrets = @(); Checked = $false; Expected = 'there are changes to apply.' }
    @{ Case = 'a secret to ask'; Pulls = @{}; Verdicts = @('in place'); Secrets = @('NPM_TOKEN'); Checked = $false; Expected = 'there are changes to apply.' }
    @{ Case = 'only "may be applied"'; Pulls = @{}; Verdicts = @('may be applied', 'installed'); Secrets = @(); Checked = $false; Expected = 'probably nothing to apply; 1 recipe may be applied. Run with --check to know.' }
    @{ Case = 'units --check could not test'; Pulls = @{}; Verdicts = @('may be applied', 'may be applied'); Secrets = @(); Checked = $true; Expected = 'probably nothing to apply; 2 recipes could not be fully tested.' }
    @{ Case = 'everything in place'; Pulls = @{}; Verdicts = @('installed', 'in place'); Secrets = @(); Checked = $false; Expected = 'nothing to apply.' }
  ) {
    $result = InModuleScope borc -Parameters @{ P = $Pulls; V = $Verdicts; S = $Secrets; C = $Checked } {
      param($P, $V, $S, $C)
      $pulls = [ordered]@{}; foreach ($key in $P.Keys) { $pulls[$key] = $P[$key] }
      $rows = @($V | ForEach-Object { [pscustomobject]@{ Verdict = $_ } })
      Set-BorcPreviewResult -Pulls $pulls -Rows $rows -Secrets $S -Checked:$C
      $script:BorcResult
    }
    $result.Headline | Should -Be $Expected
  }

  It 'lists the pulls, the counts and the secrets' {
    $result = InModuleScope borc {
      Set-BorcPreviewResult -Pulls ([ordered]@{ 'config repo' = '2 commits to pull'; 'recipe repo acme' = 'would be cloned' }) -Rows @([pscustomobject]@{ Verdict = 'would be applied' }) -Secrets @('NPM_TOKEN')
      $script:BorcResult
    }
    $result.Details['pull'] | Should -Be 'config repo 2 commits to pull, recipe repo acme would be cloned'
    $result.Details['apps and recipes'] | Should -Be '1 would be installed or applied, 0 may be applied, 0 in place'
    $result.Details['secrets'] | Should -Be '1 would be asked for (NPM_TOKEN)'
  }
}

Describe 'apply result' {
  It 'names what was installed and what changed version, and says recipes are only run' {
    $result = InModuleScope borc {
      $before = [ordered]@{ 'Git.Git' = '2.55.0'; 'jqlang.jq' = $null; 'OpenJS.NodeJS.LTS' = '22.1.0' }
      $after = [ordered]@{ 'Git.Git' = '2.56.0'; 'jqlang.jq' = '1.7.1'; 'OpenJS.NodeJS.LTS' = '22.1.0' }
      Set-BorcApplyResult -ExitCode 0 -Pulls ([ordered]@{ 'config repo' = '1 commit pulled' }) -Before $before -After $after -Recipes 3 -Secrets @('NPM_TOKEN')
      $script:BorcResult
    }
    $result.Headline | Should -Be 'done, with changes.'
    $result.Details['pulled'] | Should -Be 'config repo 1 commit pulled'
    $result.Details['installed'] | Should -Be 'jqlang.jq'
    $result.Details['version changed'] | Should -Be 'Git.Git (2.55.0 -> 2.56.0)'
    $result.Details['recipes'] | Should -Be '3 run; winget does not say which of their settings changed'
    $result.Details['secrets'] | Should -Be 'stored NPM_TOKEN'
  }

  It 'says <Expected> for exit code <Code>' -ForEach @(
    @{ Code = 0; Expected = 'done; nothing new was pulled or installed.' }
    @{ Code = 3010; Expected = 'Windows needs a restart. Restart, then run borc apply again.' }
    @{ Code = 1; Expected = 'winget reported a failure; its errors are shown above.' }
  ) {
    $result = InModuleScope borc -Parameters @{ C = $Code } {
      param($C)
      Set-BorcApplyResult -ExitCode $C -Pulls ([ordered]@{}) -Before ([ordered]@{ a = '1' }) -After ([ordered]@{ a = '1' }) -Recipes 0
      $script:BorcResult
    }
    $result.Headline | Should -Be $Expected
    $result.Details.Contains('recipes') | Should -BeFalse
  }
}

Describe 'One winget list for many packages' {
  It 'answers from one list call, and asks about a single ID only when it is not in the list' {
    InModuleScope borc {
      $script:Calls = [System.Collections.Generic.List[string]]::new()
      Mock Invoke-BorcWingetQuiet {
        $script:Calls.Add($Arguments -join ' ')
        if ('--id' -notin $Arguments) { return [pscustomobject]@{ ExitCode = 0; Output = @('Name Id      Version Source', 'Git  Git.Git 2.56.0  winget') } }
        [pscustomobject]@{ ExitCode = 1; Output = @() }
      }
      Update-BorcInstalledList
      Test-BorcPackageInstalled -Id 'Git.Git' | Should -BeTrue
      Get-BorcInstalledVersion -Id 'Git.Git' | Should -Be '2.56.0'
      Test-BorcPackageInstalled -Id 'Some.Store.App' | Should -BeFalse
      Clear-BorcInstalledList
      @($script:Calls | Where-Object { $_ -like '*--id Git.Git*' }).Count | Should -Be 0
      @($script:Calls | Where-Object { $_ -like '*--id Some.Store.App*' }).Count | Should -Be 1
    }
  }
}

Describe 'Verdict summary' {
  It 'counts the verdicts, and explains "may be applied" only when one is shown' {
    $lines = InModuleScope borc {
      $script:Lines = [System.Collections.Generic.List[string]]::new()
      Mock Write-Host { $script:Lines.Add("$Object") }
      $rows = @('would be installed', 'would be applied', 'may be applied', 'installed', 'in place', 'in place') | ForEach-Object { [pscustomobject]@{ Verdict = $_ } }
      Write-BorcPreviewSummary -Rows $rows
      Write-BorcPreviewSummary -Rows @([pscustomobject]@{ Verdict = 'installed' })
      $script:Lines
    }
    $lines | Should -Contain '  2 would be installed or applied, 1 may be applied, 3 in place.'
    @($lines | Where-Object { $_ -like '*"may be applied"*' }).Count | Should -Be 1
    $lines | Should -Contain '  0 would be installed or applied, 0 may be applied, 1 in place.'
  }

  It 'explains "may be applied" differently once the units were tested' {
    $lines = InModuleScope borc {
      $script:Lines = [System.Collections.Generic.List[string]]::new()
      Mock Write-Host { $script:Lines.Add("$Object") }
      Write-BorcPreviewSummary -Rows @([pscustomobject]@{ Verdict = 'may be applied' }) -Checked
      $script:Lines
    }
    ($lines -join "`n") | Should -Match 'winget could not test some of its units'
  }
}

Describe 'Reading winget list --upgrade-available' {
  It 'reads both tables of real winget 1.29 output, explicit targeting included' {
    $lines = [IO.File]::ReadAllLines((Join-Path $script:FixturesRoot 'winget-upgrade-available.txt'))
    $updates = InModuleScope borc -Parameters @{ L = $lines } { param($L) ConvertFrom-WingetUpgradeList -Lines $L }
    @($updates.Keys) | Should -Be @('Google.Chrome', 'Microsoft.VCRedist.2015+.x86', 'Microsoft.WSL', 'Discord.Discord')
    $updates['Microsoft.VCRedist.2015+.x86'] | Should -Be '14.52.37029.0'
    $updates['Discord.Discord'] | Should -Be '1.0.9268'
  }

  It 'reads the no-match line as no update, and anything else as unreadable' {
    InModuleScope borc {
      $none = ConvertFrom-WingetUpgradeList -Lines @('No installed package found matching input criteria.')
      $none.Count | Should -Be 0
      $null -eq $none | Should -BeFalse
      $null -eq (ConvertFrom-WingetUpgradeList -Lines @('Aucun package installé ne correspond aux critères.')) | Should -BeTrue
    }
  }

  It 'finds an ID winget cut short with an ellipsis' {
    InModuleScope borc {
      $updates = [ordered]@{ ("Microsoft.VisualStudio.2022.Commun" + [char]0x2026) = '17.14.1' }
      Find-BorcAvailableUpdate -Updates $updates -Id 'Microsoft.VisualStudio.2022.Community' | Should -Be '17.14.1'
      Find-BorcAvailableUpdate -Updates $updates -Id 'Git.Git' | Should -BeNullOrEmpty
    }
  }
}

Describe 'Upgrade verdicts' {
  It 'says <Expected> for <Case>' -ForEach @(
    @{ Case = 'a listed update'; Installed = '2.47.0'; Version = ''; Source = 'winget'; Store = $true; Expected = 'update available'; Cells = @('2.47.0', '2.48.1', '') }
    @{ Case = 'no listed update'; Installed = '2.47.0'; Version = ''; Source = 'winget'; Store = $true; Expected = 'up to date'; Cells = @('2.47.0', '', ''); Updates = @{} }
    @{ Case = 'a fixed version'; Installed = '2.45.1'; Version = '2.45.1'; Source = 'winget'; Store = $true; Expected = 'fixed version'; Cells = @('2.45.1', '2.48.1', 'fixed at 2.45.1 in borc.yaml') }
    @{ Case = 'a missing package'; Installed = $null; Version = ''; Source = 'winget'; Store = $true; Expected = 'not installed'; Cells = @('', '', 'borc apply installs it') }
    @{ Case = 'an unknown installed version'; Installed = 'unknown'; Version = ''; Source = 'winget'; Store = $true; Expected = 'unknown'; Cells = @('', '', 'winget does not know the installed version'); Updates = @{} }
    @{ Case = 'a Store app with no Store version'; Installed = '12.18.0'; Version = ''; Source = 'msstore'; Store = $false; Expected = 'unknown'; Cells = @('12.18.0', '', 'the Store gives no version, so winget cannot tell'); Updates = @{} }
    @{ Case = 'a Store app with a Store version'; Installed = '12.18.0'; Version = ''; Source = 'msstore'; Store = $true; Expected = 'up to date'; Cells = @('12.18.0', '', ''); Updates = @{} }
  ) {
    $updates = if ($null -ne $Updates) { $Updates } else { @{ 'Some.App' = '2.48.1' } }
    $row = InModuleScope borc -Parameters @{ I = $Installed; V = $Version; S = $Source; K = $Store; U = $updates } {
      param($I, $V, $S, $K, $U)
      Mock Get-BorcInstalledVersion { $I }
      Mock Test-BorcStoreVersionKnown { $K }
      $package = [pscustomobject]@{ Source = $S; Id = 'Some.App'; Version = $V; Origin = 'borc.yaml' }
      Get-BorcUpgradeVerdict -Package $package -Updates ([ordered]@{} + $U)
    }
    $row.State | Should -Be $Expected
    @($row.Installed, $row.Available, $row.Note) | Should -Be $Cells
  }

  It 'asks the Store for its version and reads Unknown as no version' {
    InModuleScope borc {
      Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 0; Output = @('Found Hotspot Shield [XPDNLRV08ZCH53]', 'Version: Unknown', 'Publisher: Pango Inc.') } }
      Test-BorcStoreVersionKnown -Id 'XPDNLRV08ZCH53' | Should -BeFalse
      Mock Invoke-BorcWingetQuiet { [pscustomobject]@{ ExitCode = 0; Output = @('Found Some App [9ABC]', 'Version: 1.2.3') } }
      Test-BorcStoreVersionKnown -Id '9ABC' | Should -BeTrue
      Should -Invoke Invoke-BorcWingetQuiet -ParameterFilter { $Arguments[0] -eq 'show' -and $Arguments -contains 'msstore' }
    }
  }

  It 'keeps the columns of the updates when a recipe has no version' {
    InModuleScope borc {
      Mock Set-BorcResult {}
      $rows = @(
        [pscustomobject]@{ Kind = 'package'; State = 'update available'; Id = 'Git.Git'; Installed = '1'; Available = '2'; Note = '' }
        [pscustomobject]@{ Kind = 'recipe'; State = 'update available'; Id = '@local/x'; Installed = ''; Available = ''; Note = 'would run: u' }
      )
      Set-BorcUpgradePreviewResult -Rows $rows
      Should -Invoke Set-BorcResult -ParameterFilter { ($Details['updates'] -join '|') -eq 'Git.Git   1  -> 2|@local/x           would run: u' }
    }
  }

  It 'counts the states, and answers whether borc upgrade would change anything' {
    InModuleScope borc {
      Mock Set-BorcResult {}
      $rows = @(
        [pscustomobject]@{ Kind = 'package'; State = 'update available'; Id = 'Git.Git'; Installed = '1'; Available = '2'; Note = '' }
        [pscustomobject]@{ Kind = 'package'; State = 'up to date'; Id = 'jqlang.jq'; Installed = '1.8'; Available = ''; Note = '' }
        [pscustomobject]@{ Kind = 'package'; State = 'unknown'; Id = '9X'; Installed = '3'; Available = ''; Note = 'why' }
      )
      Format-BorcUpgradeCounts -Rows $rows | Should -Be '1 update available, 1 up to date, 0 fixed, 0 not installed, 1 unknown'
      Set-BorcUpgradePreviewResult -Rows $rows
      Should -Invoke Set-BorcResult -ParameterFilter { $Headline -eq 'borc upgrade would upgrade 1 package.' -and $Details['updates'] -eq 'Git.Git  1  -> 2' -and $Details['unknown'] -eq '9X  3  why' -and -not $Details.Contains('up to date') }
      Set-BorcUpgradePreviewResult -Rows $rows[1..2]
      Should -Invoke Set-BorcResult -ParameterFilter { $Headline -eq 'probably nothing to upgrade; 1 could not be checked.' }
      Set-BorcUpgradePreviewResult -Rows $rows[1]
      Should -Invoke Set-BorcResult -ParameterFilter { $Headline -eq 'nothing to upgrade.' }
    }
  }
}
