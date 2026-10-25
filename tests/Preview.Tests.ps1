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
