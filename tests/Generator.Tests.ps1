BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  $script:GoldenRoot = Join-Path $script:FixturesRoot 'golden'

  # Set BORC_UPDATE_GOLDEN=1 in the current process to rewrite the golden files.
  function Assert-Golden {
    param([Parameter(Mandatory)] $Document, [Parameter(Mandatory)] [string] $Name)
    $actual = InModuleScope Borc -Parameters @{ Document = $Document } { param($Document) (ConvertTo-BorcYaml -Data $Document) -replace "`r`n", "`n" }
    $path = Join-Path $script:GoldenRoot $Name
    if ($env:BORC_UPDATE_GOLDEN -eq '1') { [IO.File]::WriteAllText($path, $actual) }
    $actual | Should -BeExactly (Read-TestText -Path $path)
  }

  function Get-FixturePlan {
    param([string] $ConfigText)
    $settings = Join-Path $script:FixturesRoot 'settings'
    $configPath = Join-Path $settings 'borc\borc.yaml'
    $reader = {
      param($Path)
      if ($ConfigText -and $Path -eq $configPath) { return $ConfigText }
      if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path) }
      $null
    }.GetNewClosure()
    InModuleScope Borc -Parameters @{ S = $settings; R = (Join-Path $script:FixturesRoot 'recipes'); Reader = $reader } {
      param($S, $R, $Reader)
      Get-BorcPlan -SettingsRoot $S -RecipesRoot $R -ReadFile $Reader
    }
  }
}

Describe 'Merged configuration' {
  BeforeAll {
    $script:Plan = Get-FixturePlan
    $script:Plan.Errors | Should -BeNullOrEmpty
    $script:Runs = InModuleScope Borc -Parameters @{ Plan = $script:Plan } { param($Plan) New-BorcRunDocuments -Plan $Plan }
  }

  It 'matches the golden reboot run' {
    Assert-Golden -Document $script:Runs.Reboot -Name 'full.reboot.yaml'
  }

  It 'matches the golden main run' {
    Assert-Golden -Document $script:Runs.Main -Name 'full.main.yaml'
  }

  It 'uses the verified WinGet header and strips the borc header' {
    foreach ($document in $script:Runs.Reboot, $script:Runs.Main) {
      $document.Keys | Should -Be @('$schema', 'metadata', 'resources')
      $document['$schema'] | Should -Be 'https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json'
      $document.metadata.winget.processor | Should -Be 'dscv3'
    }
  }

  It 'puts only reboot recipes in the first run' {
    $script:Runs.Reboot.resources.name | Should -Be @('recipes/wsl: wsl feature')
  }

  It 'keeps elevation metadata' {
    $script:Runs.Reboot.resources[0].metadata.securityContext | Should -Be 'elevated'
  }

  It 'prefixes resource names with their recipe and puts plain packages first' {
    $script:Runs.Main.resources.name | Should -Be @(
      'winget: Git.Git', 'msstore: 9NBLGGH4NNS1',
      'recipes/node: node package', 'recipes/node: npm cache',
      'recipes/npm-auth: npm token',
      'recipes/idea: idea package', 'recipes/idea: idea config path',
      '@local/wsl-ubuntu: ubuntu package')
  }

  It 'substitutes placeholders in input' {
    ($script:Runs.Main.resources | Where-Object name -EQ 'recipes/node: npm cache').properties.input | Should -Be 'D:\caches\npm'
  }

  It 'leaves units without input untouched' {
    ($script:Runs.Main.resources | Where-Object name -EQ 'recipes/node: node package').properties.Keys | Should -Be @('id', 'source')
  }

  It 'drops the units whose parameter is missing' {
    $script:Runs.Main.resources.name | Should -Not -Contain 'recipes/node: npm prefix'
    $script:Runs.Dropped | Should -Be @("recipes/node: 'npm prefix' skipped, no value for npmPrefix")
  }

  It 'turns requires into dependsOn on the plain names of every kept unit of the required recipe' {
    ($script:Runs.Main.resources | Where-Object name -EQ 'recipes/npm-auth: npm token').dependsOn | Should -Be @(
      'recipes/node: node package',
      'recipes/node: npm cache')
  }

  It "turns a recipe's own resourceId entry into the plain prefixed name" {
    ($script:Runs.Main.resources | Where-Object name -EQ 'recipes/idea: idea config path').dependsOn | Should -Be @(
      'recipes/idea: idea package')
  }

  # winget resolves dependsOn by unit name within the file it runs; anything
  # else fails at apply time with "not found within the configuration".
  It 'only emits dependsOn entries that name a unit of the same run' {
    foreach ($document in $script:Runs.Reboot, $script:Runs.Main) {
      $names = @($document.resources | ForEach-Object { $_['name'] })
      foreach ($unit in $document.resources) {
        foreach ($entry in @($unit['dependsOn'] | Where-Object { $_ })) { $names | Should -Contain $entry }
      }
    }
  }

  It 'adds no dependsOn across runs, where run order already holds' {
    ($script:Runs.Main.resources | Where-Object name -EQ '@local/wsl-ubuntu: ubuntu package').Contains('dependsOn') | Should -BeFalse
  }

  It 'never changes the loaded recipes' {
    $script:Plan.Recipes['recipes/node'].Resources[1].properties.input | Should -Be '{{npmCache}}'
    $script:Plan.Recipes['recipes/node'].Resources[1].name | Should -Be 'npm cache'
  }
}

Describe 'Edge cases' {
  It 'has no reboot run when no recipe needs one' {
    $plan = Get-FixturePlan -ConfigText "apps:`n  - winget: Git.Git"
    $runs = InModuleScope Borc -Parameters @{ Plan = $plan } { param($Plan) New-BorcRunDocuments -Plan $Plan }
    $runs.Reboot | Should -BeNullOrEmpty
    $runs.Main.resources.Count | Should -Be 1
  }

  It 'has no run at all for an empty configuration' {
    $plan = Get-FixturePlan -ConfigText 'apps: []'
    $runs = InModuleScope Borc -Parameters @{ Plan = $plan } { param($Plan) New-BorcRunDocuments -Plan $Plan }
    $runs.Reboot | Should -BeNullOrEmpty
    $runs.Main | Should -BeNullOrEmpty
  }

  It 'removes a dependsOn entry that points at a dropped unit' {
    InModuleScope Borc {
      $text = @'
borc:
  parameters:
    p: optional
$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json
metadata:
  winget:
    processor: dscv3
resources:
  - name: a
    type: T
    properties:
      input: '{{p}}'
  - name: b
    type: T
    dependsOn:
      - "[resourceId('T','a')]"
    properties:
      input: x
'@
      $recipe = ConvertTo-BorcRecipe -Text $text -Id 'r/x'
      $dropped = [System.Collections.Generic.List[string]]::new()
      $units = @(ConvertTo-BorcRecipeUnits -Recipe $recipe -Parameters ([ordered]@{}) -Dropped $dropped)
      $units.Count | Should -Be 1
      $units[0].Contains('dependsOn') | Should -BeFalse
    }
  }

  It 'prefixes a plain-name dependsOn, the form recipes should use' {
    InModuleScope Borc {
      $text = @'
$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json
metadata:
  winget:
    processor: dscv3
resources:
  - name: sysinternals package
    type: Microsoft.WinGet/Package
    properties:
      id: Microsoft.Sysinternals.Suite
      source: winget
  - name: start menu shortcuts
    type: Microsoft.DSC.Transitional/PowerShellScript
    dependsOn:
      - sysinternals package
    properties:
      input: x
'@
      $recipe = ConvertTo-BorcRecipe -Text $text -Id '@local/sysinternals'
      $recipe.Errors | Should -BeNullOrEmpty
      $dropped = [System.Collections.Generic.List[string]]::new()
      $units = @(ConvertTo-BorcRecipeUnits -Recipe $recipe -Parameters ([ordered]@{}) -Dropped $dropped)
      $units[1]['dependsOn'] | Should -Be @('@local/sysinternals: sysinternals package')
      $units[0]['name'] | Should -Be '@local/sysinternals: sysinternals package'
    }
  }

  It 'never lets a value break the YAML' {
    InModuleScope Borc {
      $value = "C:\a: b # c`n- d"
      $expanded = Expand-BorcPlaceholders -Node 'pre {{p}}' -Parameters ([ordered]@{ p = $value })
      $document = New-BorcDocument -Units @([ordered]@{ name = 'u'; type = 'T'; properties = [ordered]@{ input = $expanded } })
      (ConvertFrom-BorcYaml -Text (ConvertTo-BorcYaml -Data $document)).resources[0].properties.input | Should -Be "pre $value"
    }
  }

  It 'builds one document per recipe for --debug, reboot recipes first' {
    $plan = Get-FixturePlan
    $singles = @(InModuleScope Borc -Parameters @{ Plan = $plan } { param($Plan) New-BorcSingleDocuments -Plan $Plan -IncludePackages })
    $singles.Name | Should -Be @('recipes/wsl', 'recipes/node', 'recipes/npm-auth', 'recipes/idea', '@local/wsl-ubuntu', 'plain packages')
    ($singles | Where-Object Name -EQ 'recipes/npm-auth').Document.resources[0].Contains('dependsOn') | Should -BeFalse
  }
}
