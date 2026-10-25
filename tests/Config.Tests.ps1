BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'borc.yaml parsing' {
  It 'reads recipes, apps, parameters and secrets' {
    $text = [IO.File]::ReadAllText((Join-Path $script:FixturesRoot 'settings\borc\borc.yaml'))
    $config = InModuleScope Borc -Parameters @{ Text = $text } { param($Text) ConvertTo-BorcConfig -Text $Text }
    $config.Errors | Should -BeNullOrEmpty
    $config.Recipes.Name | Should -Be @('recipes')
    $config.Apps.Kind | Should -Be @('winget', 'msstore', 'recipe', 'recipe', 'recipe', 'recipe', 'recipe')
    ($config.Apps | Where-Object Id -EQ 'recipes/node').Parameters['npmCache'] | Should -Be 'D:\caches\npm'
    $config.Secrets['NPM_TOKEN'] | Should -Be 'token for the company npm registry'
  }

  It 'names recipe repos by Git repo name or alias' {
    $text = @'
recipes:
  - repo: https://github.com/someone/recipes.git
  - repo: https://github.com/acme/recipes.git
    alias: acme
'@
    $config = InModuleScope Borc -Parameters @{ Text = $text } { param($Text) ConvertTo-BorcConfig -Text $Text }
    $config.Errors | Should -BeNullOrEmpty
    $config.Recipes.Name | Should -Be @('recipes', 'acme')
  }

  It 'accepts an empty file' {
    $config = InModuleScope Borc { ConvertTo-BorcConfig -Text '' }
    $config.Errors | Should -BeNullOrEmpty
    $config.Apps.Count | Should -Be 0
  }

  It 'reports <Case>' -ForEach @(
    @{ Case = 'a YAML syntax error'; Text = "apps: [`n"; Expected = 'invalid YAML' }
    @{ Case = 'an unknown top-level key'; Text = "app:`n  - winget: Git.Git"; Expected = "unknown key 'app'" }
    @{ Case = 'two repos with the same name'; Text = "recipes:`n  - repo: https://a/x/recipes`n  - repo: https://b/y/recipes.git"; Expected = 'Give one of them an alias' }
    @{ Case = 'an entry with two kinds'; Text = "apps:`n  - winget: A.B`n    msstore: 9X"; Expected = 'exactly one of winget, msstore or recipe' }
    @{ Case = 'an unknown key in an app'; Text = "apps:`n  - winget: A.B`n    parameters:`n      x: y"; Expected = "unknown key 'parameters' in the apps entry for A.B" }
    @{ Case = 'a malformed recipe reference'; Text = "apps:`n  - recipe: node"; Expected = "'node' is not a recipe reference" }
    @{ Case = 'an unknown recipe repo'; Text = "apps:`n  - recipe: nope/node"; Expected = "refers to the repo 'nope'" }
    @{ Case = 'a parameter that is not a string'; Text = "recipes:`n  - repo: https://x/recipes`napps:`n  - recipe: recipes/node`n    parameters:`n      port: 8080"; Expected = 'parameter port of recipes/node must be a string' }
    @{ Case = 'an app listed twice'; Text = "apps:`n  - winget: Git.Git`n  - winget: Git.Git"; Expected = 'listed twice' }
    @{ Case = 'an invalid secret name'; Text = "secrets:`n  NPM-TOKEN: x"; Expected = 'not a valid secret name' }
  ) {
    $config = InModuleScope Borc -Parameters @{ Text = $Text } { param($Text) ConvertTo-BorcConfig -Text $Text }
    ($config.Errors -join "`n") | Should -Match ([regex]::Escape($Expected))
  }

  It 'accepts a quoted number as a parameter value' {
    $text = "recipes:`n  - repo: https://x/recipes`napps:`n  - recipe: recipes/node`n    parameters:`n      port: '8080'"
    $config = InModuleScope Borc -Parameters @{ Text = $text } { param($Text) ConvertTo-BorcConfig -Text $Text }
    $config.Errors | Should -BeNullOrEmpty
    $config.Apps[0].Parameters['port'] | Should -Be '8080'
  }

  It 'accepts a fixed version on a winget app, quoted' {
    $config = InModuleScope Borc { ConvertTo-BorcConfig -Text "apps:`n  - winget: jqlang.jq`n    version: '1.7'" }
    $config.Errors | Should -BeNullOrEmpty
    $config.Apps[0].Version | Should -Be '1.7'
  }

  It 'refuses an unquoted version that YAML reads as a number, and a version on a Store app' {
    $config = InModuleScope Borc { ConvertTo-BorcConfig -Text "apps:`n  - winget: jqlang.jq`n    version: 1.7`n  - msstore: 9X`n    version: '1'" }
    ($config.Errors -join "`n") | Should -Match "version of jqlang.jq must be a string. Quote it"
    ($config.Errors -join "`n") | Should -Match "unknown key 'version' in the apps entry for 9X"
  }

  It 'accepts @local recipes without a recipes entry' {
    $config = InModuleScope Borc { ConvertTo-BorcConfig -Text "apps:`n  - recipe: '@local/tool'" }
    $config.Errors | Should -BeNullOrEmpty
    $config.Apps[0].Id | Should -Be '@local/tool'
  }
}

Describe 'Recipe parsing' {
  It 'reads the borc header' {
    $text = [IO.File]::ReadAllText((Join-Path $script:FixturesRoot 'recipes\recipes\npm-auth.yaml'))
    $recipe = InModuleScope Borc -Parameters @{ Text = $text } { param($Text) ConvertTo-BorcRecipe -Text $Text -Id 'recipes/npm-auth' }
    $recipe.Errors | Should -BeNullOrEmpty
    $recipe.Description | Should -Be 'Logs npm in to the company registry'
    $recipe.Requires | Should -Be @('recipes/node')
    $recipe.Secrets | Should -Be @('NPM_TOKEN')
    $recipe.Reboot | Should -BeFalse
  }

  It 'reports <Case>' -ForEach @(
    @{ Case = 'the aka.ms schema URL'; Body = "`$schema: https://aka.ms/dsc/schemas/v3/bundled/config/document.json`nmetadata:`n  winget:`n    processor: dscv3"; Expected = 'the file must start with $schema' }
    @{ Case = 'a missing processor'; Body = "`$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json"; Expected = 'processor: dscv3' }
    @{ Case = 'an unknown header key'; Body = "borc:`n  covers: [x]`n" + $null; Expected = "unknown key 'covers' in the borc header" }
    @{ Case = 'a non-boolean reboot'; Body = "borc:`n  reboot: maybe"; Expected = 'reboot must be true or false' }
    @{ Case = 'an undeclared placeholder'; Body = "resources:`n  - name: a`n    type: T`n    properties:`n      input: '{{nope}}'"; Expected = 'uses {{nope}}, which the borc header does not declare' }
    @{ Case = 'a placeholder outside input'; Body = "borc:`n  parameters:`n    p: d`nresources:`n  - name: a`n    type: T`n    properties:`n      setScript: '{{p}}'"; Expected = 'outside input' }
    @{ Case = 'a dependsOn on another recipe'; Body = "resources:`n  - name: a`n    type: T`n    dependsOn:`n      - 'recipes/node: node package'"; Expected = "depends on 'recipes/node: node package', which is not a resource of this recipe. Use requires" }
    @{ Case = 'a dependsOn typo in the resourceId form'; Body = "resources:`n  - name: a`n    type: T`n  - name: b`n    type: T`n    dependsOn:`n      - `"[resourceId('T','aa')]`""; Expected = "depends on 'aa', which is not a resource of this recipe" }
    @{ Case = 'a dependsOn that is not a list'; Body = "resources:`n  - name: a`n    type: T`n  - name: b`n    type: T`n    dependsOn: a"; Expected = 'must be a list of resource names' }
    @{ Case = 'a unit that depends on itself'; Body = "resources:`n  - name: a`n    type: T`n    dependsOn: [a]"; Expected = "resource 'a' depends on itself" }
    @{ Case = 'two resources with one name'; Body = "resources:`n  - name: a`n    type: T`n  - name: a`n    type: T"; Expected = "two resources are named 'a'" }
  ) {
    $header = "`$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json`nmetadata:`n  winget:`n    processor: dscv3`n"
    $text = if ($Body.StartsWith('$schema')) { $Body } else { $header + $Body }
    $recipe = InModuleScope Borc -Parameters @{ Text = $text } { param($Text) ConvertTo-BorcRecipe -Text $Text -Id 'r/x' }
    ($recipe.Errors -join "`n") | Should -Match ([regex]::Escape($Expected))
  }

  It 'resolves repo recipes and @local recipes to files' {
    InModuleScope Borc {
      Resolve-BorcRecipePath -Id 'recipes/node' -RecipesRoot 'C:\r' -SettingsRoot 'D:\settings' | Should -Be 'C:\r\recipes\node.yaml'
      Resolve-BorcRecipePath -Id '@local/wsl-ubuntu' -RecipesRoot 'C:\r' -SettingsRoot 'D:\settings' | Should -Be 'D:\settings\borc\cookbook\wsl-ubuntu.yaml'
    }
  }
}

Describe 'Plan validation' {
  BeforeAll {
    $script:SettingsRoot = Join-Path $script:FixturesRoot 'settings'
    $script:RecipesRoot = Join-Path $script:FixturesRoot 'recipes'

    function Get-TestPlan {
      param([string] $ConfigText)
      $files = @{}
      if ($ConfigText) { $files[(Join-Path $script:SettingsRoot 'borc\borc.yaml')] = $ConfigText }
      $reader = {
        param($Path)
        if ($files.ContainsKey($Path)) { return $files[$Path] }
        if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path) }
        $null
      }.GetNewClosure()
      InModuleScope Borc -Parameters @{ S = $script:SettingsRoot; R = $script:RecipesRoot; Reader = $reader } {
        param($S, $R, $Reader)
        Get-BorcPlan -SettingsRoot $S -RecipesRoot $R -ReadFile $Reader
      }
    }
  }

  It 'accepts the full fixture and orders recipes by requires' {
    $plan = Get-TestPlan
    $plan.Errors | Should -BeNullOrEmpty
    $plan.Order | Should -Be @('recipes/node', 'recipes/npm-auth', 'recipes/idea', 'recipes/wsl', '@local/wsl-ubuntu')
  }

  It 'reports <Case>' -ForEach @(
    @{ Case = 'an unknown parameter'; Expected = "recipe recipes/node has no parameter 'npmCach' (it declares: npmCache, npmPrefix)"
      Config = "recipes:`n  - repo: https://x/recipes`napps:`n  - recipe: recipes/node`n    parameters:`n      npmCach: D:\x" }
    @{ Case = 'an undeclared secret'; Expected = 'uses the secret NPM_TOKEN, which is not declared under secrets'
      Config = "recipes:`n  - repo: https://x/recipes`napps:`n  - recipe: recipes/node`n  - recipe: recipes/npm-auth" }
    @{ Case = 'a required recipe that is not listed'; Expected = 'requires recipes/node, which borc.yaml does not list'
      Config = "recipes:`n  - repo: https://x/recipes`napps:`n  - recipe: recipes/npm-auth`nsecrets:`n  NPM_TOKEN: t" }
    @{ Case = 'a missing recipe file'; Expected = 'recipe recipes/nope not found'
      Config = "recipes:`n  - repo: https://x/recipes`napps:`n  - recipe: recipes/nope" }
    @{ Case = 'a missing @local recipe'; Expected = 'recipe @local/nope not found'
      Config = "apps:`n  - recipe: '@local/nope'" }
  ) {
    $plan = Get-TestPlan -ConfigText $Config
    ($plan.Errors -join "`n") | Should -Match ([regex]::Escape($Expected))
  }

  It 'reports every problem at once' {
    $plan = Get-TestPlan -ConfigText "recipes:`n  - repo: https://x/recipes`napps:`n  - recipe: recipes/npm-auth`n  - recipe: recipes/node`n    parameters:`n      bad: x"
    $plan.Errors.Count | Should -Be 2
  }

  It 'reports a missing borc.yaml' {
    $plan = InModuleScope Borc { Get-BorcPlan -SettingsRoot 'C:\nowhere' -RecipesRoot 'C:\nowhere' }
    $plan.Errors | Should -Match 'borc.yaml not found'
  }
}

Describe 'Recipe requires rules' {
  It 'refuses a reboot recipe that requires a normal recipe, and loops' {
    InModuleScope Borc {
      $recipes = [ordered]@{
        'r/a' = [pscustomobject]@{ Id = 'r/a'; Reboot = $true; Requires = @('r/b') }
        'r/b' = [pscustomobject]@{ Id = 'r/b'; Reboot = $false; Requires = @('r/a') }
      }
      $errors = [System.Collections.Generic.List[string]]::new()
      Test-BorcRequires -Recipes $recipes -Errors $errors
      Get-BorcRecipeOrder -Recipes $recipes -Errors $errors | Out-Null
      ($errors -join "`n") | Should -Match 'cannot require r/b'
      ($errors -join "`n") | Should -Match 'in a loop: r/a -> r/b -> r/a'
    }
  }
}
