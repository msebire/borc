BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

  # A recipe from its resources, as Get-BorcPlan would load it.
  function New-TestPlan {
    param([string] $Resources, [hashtable] $Parameters = @{}, [string] $Header = '')
    $text = $Header + "`$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json`nmetadata:`n  winget:`n    processor: dscv3`nresources:`n" + $Resources
    InModuleScope Borc -Parameters @{ T = $text; P = $Parameters } {
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
    InModuleScope Borc -Parameters @{ Plan = $Plan; Installed = $Installed } {
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
    InModuleScope Borc -Parameters @{ L = $lines } { param($L) ConvertFrom-WingetListVersion -Id 'jqlang.jq' -Lines $L } | Should -Be '1.7.1'
  }

  It 'counts a plain app as installed only in its fixed version' {
    InModuleScope Borc {
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
    InModuleScope Borc {
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
    $results = InModuleScope Borc -Parameters @{ L = $lines } { param($L) ConvertFrom-BorcConfigureTest -Lines $L }
    $results.Keys | Should -Be @('@local/x: in place', '@local/x: would change', 'winget: Git.Git', '@local/x: broken test', '@local/x: after in place')
    $results['@local/x: in place'].State | Should -Be 'in'
    $results['@local/x: would change'].State | Should -Be 'out'
    $results['@local/x: broken test'].State | Should -Be 'unknown'
    $results['@local/x: broken test'].Message | Should -Be 'test failed: tool not installed'
  }

  It 'never guesses on a line it does not know' {
    $results = InModuleScope Borc { ConvertFrom-BorcConfigureTest -Lines @('Microsoft.WinGet/Package [@local/x: app]', '  Le système est dans un état inconnu.') }
    $results['@local/x: app'].State | Should -Be 'unknown'
    $results['@local/x: app'].Message | Should -Match '^winget said: Le syst'
  }
}

Describe 'Checked recipe verdicts' {
  BeforeAll {
    function Get-CheckedVerdict {
      # IDictionary, not hashtable: a hashtable would lose the unit order.
      param([System.Collections.IDictionary] $States, [string[]] $Dropped = @())
      InModuleScope Borc -Parameters @{ S = $States; D = $Dropped } {
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
    $result = InModuleScope Borc -Parameters @{ P = $Pulls; V = $Verdicts; S = $Secrets; C = $Checked } {
      param($P, $V, $S, $C)
      $pulls = [ordered]@{}; foreach ($key in $P.Keys) { $pulls[$key] = $P[$key] }
      $rows = @($V | ForEach-Object { [pscustomobject]@{ Verdict = $_ } })
      Set-BorcPreviewResult -Pulls $pulls -Rows $rows -Secrets $S -Checked:$C
      $script:BorcResult
    }
    $result.Headline | Should -Be $Expected
  }

  It 'lists the pulls, the counts and the secrets' {
    $result = InModuleScope Borc {
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
    $result = InModuleScope Borc {
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
    $result = InModuleScope Borc -Parameters @{ C = $Code } {
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
    InModuleScope Borc {
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
    $lines = InModuleScope Borc {
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
    $lines = InModuleScope Borc {
      $script:Lines = [System.Collections.Generic.List[string]]::new()
      Mock Write-Host { $script:Lines.Add("$Object") }
      Write-BorcPreviewSummary -Rows @([pscustomobject]@{ Verdict = 'may be applied' }) -Checked
      $script:Lines
    }
    ($lines -join "`n") | Should -Match 'winget could not test some of its units'
  }
}
