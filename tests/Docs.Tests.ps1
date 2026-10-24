BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  $script:DocsRoot = Join-Path $script:RepoRoot 'docs'
  $script:ExamplesRoot = Join-Path $script:DocsRoot 'examples'
  $script:Pages = @(Get-ChildItem -Path $script:DocsRoot -Filter '*.md' -File) + @(Get-Item (Join-Path $script:RepoRoot 'README.md'))

  # Fenced blocks of a page, each with the marker comment right above it, if any.
  function Get-FencedBlocks {
    param([string] $Path)
    $text = Read-TestText -Path $Path
    $pattern = '(?ms)(?:^<!-- (?<kind>example|help): (?<target>\S+) -->\n)?^```(?<lang>[\w-]*)\n(?<body>.*?)^```$'
    foreach ($match in [regex]::Matches($text, $pattern)) {
      [pscustomobject]@{
        Page = Split-Path -Leaf $Path
        Kind = $match.Groups['kind'].Value
        Target = $match.Groups['target'].Value
        Language = $match.Groups['lang'].Value
        Body = $match.Groups['body'].Value
      }
    }
  }
  $script:Blocks = @(foreach ($page in $script:Pages) { Get-FencedBlocks -Path $page.FullName })
}

Describe 'Documentation examples' {
  It 'gives every YAML block a real example file' {
    $orphans = $script:Blocks | Where-Object { $_.Language -eq 'yaml' -and $_.Kind -ne 'example' } | ForEach-Object Page
    $orphans | Should -BeNullOrEmpty
  }

  It 'shows each example file exactly as it is' {
    $bad = foreach ($block in $script:Blocks | Where-Object Kind -EQ 'example') {
      $path = Join-Path $script:DocsRoot $block.Target
      if (-not (Test-Path $path) -or (Read-TestText -Path $path) -cne $block.Body) { "$($block.Page): $($block.Target)" }
    }
    $bad | Should -BeNullOrEmpty
  }

  It 'has example files that borc accepts, with no problem reported' {
    $plan = InModuleScope Borc -Parameters @{ S = (Join-Path $script:ExamplesRoot 'settings'); R = (Join-Path $script:ExamplesRoot 'recipes') } {
      param($S, $R)
      Get-BorcPlan -SettingsRoot $S -RecipesRoot $R
    }
    $plan.Errors | Should -BeNullOrEmpty
    $runs = InModuleScope Borc -Parameters @{ Plan = $plan } { param($Plan) New-BorcRunDocuments -Plan $Plan }
    $runs.Reboot.resources.name | Should -Be @('@local/wsl-ubuntu: wsl features', '@local/wsl-ubuntu: ubuntu package')
    $runs.Main.resources.name | Should -Contain 'recipes/node: npm cache'
  }

  It 'has borc.yaml snippets that borc accepts' {
    foreach ($file in Get-ChildItem -Path $script:ExamplesRoot -Filter '*.borc.yaml') {
      $config = InModuleScope Borc -Parameters @{ T = (Read-TestText -Path $file.FullName) } { param($T) ConvertTo-BorcConfig -Text $T }
      $config.Errors | Should -BeNullOrEmpty -Because $file.Name
    }
  }

  It 'has a borc header example that borc accepts' {
    $header = Read-TestText -Path (Join-Path $script:ExamplesRoot 'recipe-header.yaml')
    $text = $header + "`$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json`nmetadata:`n  winget:`n    processor: dscv3`n"
    $recipe = InModuleScope Borc -Parameters @{ T = $text } { param($T) ConvertTo-BorcRecipe -Text $T -Id 'recipes/node' }
    $recipe.Errors | Should -BeNullOrEmpty
    $recipe.Secrets | Should -Be @('NPM_TOKEN')
  }

  It 'has fragments that are valid YAML, and the exact WinGet header' {
    foreach ($file in Get-ChildItem -Path (Join-Path $script:ExamplesRoot 'fragments') -Filter '*.yaml') {
      { InModuleScope Borc -Parameters @{ T = (Read-TestText -Path $file.FullName) } { param($T) ConvertFrom-BorcYaml -Text $T } } | Should -Not -Throw -Because $file.Name
    }
    $header = InModuleScope Borc -Parameters @{ T = (Read-TestText -Path (Join-Path $script:ExamplesRoot 'fragments\winget-header.yaml')) } { param($T) ConvertFrom-BorcYaml -Text $T }
    InModuleScope Borc -Parameters @{ H = $header } { param($H) Test-WingetDocumentHeader -Document $H } | Should -BeTrue
  }

  It 'uses the verified WinGet header in every recipe example' {
    foreach ($file in Get-ChildItem -Path $script:ExamplesRoot -Filter '*.yaml' -Recurse | Where-Object { (Read-TestText $_.FullName) -match '(?m)^resources:' }) {
      Read-TestText -Path $file.FullName | Should -Match ([regex]::Escape('$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json'))
    }
  }
}

Describe 'Manual check repo' {
  It 'is accepted by borc, and its bad variant reports both errors' {
    $root = Join-Path $script:RepoRoot 'tests\manual'
    $plan = InModuleScope Borc -Parameters @{ S = (Join-Path $root 'settings') } { param($S) Get-BorcPlan -SettingsRoot $S -RecipesRoot $S }
    $plan.Errors | Should -BeNullOrEmpty
    $plan.Order | Should -Be @('@local/borc-check-param', '@local/borc-check-requires', '@local/borc-check-secret', '@local/borc-check-reboot')

    $bad = Read-TestText -Path (Join-Path $root 'bad-parameter.borc.yaml')
    $reader = { param($Path) if ($Path -like '*\borc\borc.yaml') { $bad } elseif (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } }.GetNewClosure()
    $plan = InModuleScope Borc -Parameters @{ S = (Join-Path $root 'settings'); Reader = $reader } { param($S, $Reader) Get-BorcPlan -SettingsRoot $S -RecipesRoot $S -ReadFile $Reader }
    ($plan.Errors -join "`n") | Should -Match "has no parameter 'greting'"
    ($plan.Errors -join "`n") | Should -Match 'uses the secret BORC_CHECK_SECRET, which is not declared'
  }
}

Describe 'Command reference' {
  It 'shows every help page word for word' {
    $helpFiles = Get-ChildItem -Path (Join-Path $script:RepoRoot 'src\Borc\help') -Filter '*.txt'
    $shown = @($script:Blocks | Where-Object { $_.Page -eq 'commands.md' -and $_.Kind -eq 'help' })
    $shown.Target | Sort-Object | Should -Be ($helpFiles.BaseName | Sort-Object)
    foreach ($block in $shown) {
      $block.Body | Should -BeExactly (Read-TestText -Path (Join-Path $script:RepoRoot "src\Borc\help\$($block.Target).txt"))
    }
  }
}

Describe 'Engine repository URL' {
  BeforeAll {
    $script:RepoUrl = InModuleScope Borc { $script:BorcRepoUrl }
    $script:RepoPath = ([uri]$script:RepoUrl).AbsolutePath.Trim('/')
  }

  It 'is the only borc repository the docs, template and install.ps1 point at' {
    $files = @($script:Pages.FullName) + @(
      (Join-Path $script:RepoRoot 'install.ps1')
      (Join-Path $script:RepoRoot 'src\Borc\template\borc\borc.yaml')
    )
    $bad = foreach ($file in $files) {
      $text = [IO.File]::ReadAllText($file)
      foreach ($match in [regex]::Matches($text, '(?:github\.com|raw\.githubusercontent\.com)/([\w.-]+/[\w.-]+)')) {
        $path = $match.Groups[1].Value -replace '\.git$', ''
        $isExample = $path -match '^(someone|acme|you|PowerShell)/'
        if (-not $isExample -and $path -ne $script:RepoPath) { "$(Split-Path -Leaf $file): $($match.Value)" }
      }
    }
    $bad | Should -BeNullOrEmpty
  }

  It 'gives the one-liner in the README' {
    $oneLiner = InModuleScope Borc { Get-BorcOneLiner }
    [IO.File]::ReadAllText((Join-Path $script:RepoRoot 'README.md')) | Should -Match ([regex]::Escape($oneLiner))
  }
}
