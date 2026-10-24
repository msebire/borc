BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

  function Add-Entry { param($Text, $Kind, $Id) InModuleScope Borc -Parameters @{ T = $Text; K = $Kind; I = $Id } { param($T, $K, $I) Add-BorcAppEntry -Text $T -Kind $K -Id $I } }
  function Remove-Entry { param($Text, $Kind, $Id) InModuleScope Borc -Parameters @{ T = $Text; K = $Kind; I = $Id } { param($T, $K, $I) Remove-BorcAppEntry -Text $T -Kind $K -Id $I } }

  $script:Sample = @'
# My machine.
recipes:
  - repo: https://github.com/someone/recipes.git   # shared recipes

apps:
  # Basics
  - winget: Git.Git
  - recipe: recipes/node
    parameters:
      npmCache: D:\caches\npm   # keep the cache off C:
  - msstore: 9NBLGGH4NNS1
  # - recipe: recipes/idea

secrets:
  NPM_TOKEN: token for the company npm registry
'@ -replace "`r`n", "`n"
  $script:Sample += "`n"
}

Describe 'Adding an app to borc.yaml' {
  It 'appends after the last item, keeping every comment and line' {
    $result = Add-Entry $script:Sample 'winget' 'Microsoft.VisualStudioCode'
    $expected = $script:Sample.Replace("  - msstore: 9NBLGGH4NNS1`n", "  - msstore: 9NBLGGH4NNS1`n  - winget: Microsoft.VisualStudioCode`n")
    $result | Should -BeExactly $expected
  }

  It 'goes after the parameters of a last recipe item' {
    $text = "apps:`n  - recipe: recipes/node`n    parameters:`n      npmCache: D:\x`nsecrets: {}`n"
    Add-Entry $text 'winget' 'Git.Git' | Should -BeExactly "apps:`n  - recipe: recipes/node`n    parameters:`n      npmCache: D:\x`n  - winget: Git.Git`nsecrets: {}`n"
  }

  It 'quotes @local recipes' {
    Add-Entry "apps:`n  - winget: Git.Git`n" 'recipe' '@local/wsl-ubuntu' | Should -BeExactly "apps:`n  - winget: Git.Git`n  - recipe: '@local/wsl-ubuntu'`n"
  }

  It 'keeps the indentation already used' {
    Add-Entry "apps:`n- winget: Git.Git`n" 'winget' 'A.B' | Should -BeExactly "apps:`n- winget: Git.Git`n- winget: A.B`n"
    Add-Entry "apps:`n    - winget: Git.Git`n" 'winget' 'A.B' | Should -BeExactly "apps:`n    - winget: Git.Git`n    - winget: A.B`n"
  }

  It 'creates the apps key when missing' {
    Add-Entry "# empty`nsecrets: {}`n" 'msstore' '9X' | Should -BeExactly "# empty`nsecrets: {}`n`napps:`n  - msstore: 9X`n"
    Add-Entry '' 'msstore' '9X' | Should -BeExactly "apps:`n  - msstore: 9X`n"
  }

  It 'turns an empty flow list into a block' {
    Add-Entry "apps: []  # none yet`n" 'winget' 'A.B' | Should -BeExactly "apps: # none yet`n  - winget: A.B`n"
  }

  It 'adds under an apps key that only holds comments' {
    Add-Entry "apps:`n  # - winget: X.Y`n" 'winget' 'A.B' | Should -BeExactly "apps:`n  - winget: A.B`n  # - winget: X.Y`n"
  }

  It 'keeps CRLF line endings' {
    Add-Entry "apps:`r`n  - winget: Git.Git`r`n" 'winget' 'A.B' | Should -BeExactly "apps:`r`n  - winget: Git.Git`r`n  - winget: A.B`r`n"
  }

  It 'produces YAML that still parses to the same apps plus the new one' {
    $result = Add-Entry $script:Sample 'recipe' '@local/tool'
    $config = InModuleScope Borc -Parameters @{ T = $result } { param($T) ConvertTo-BorcConfig -Text $T }
    $config.Errors | Should -BeNullOrEmpty
    $config.Apps.Id | Should -Be @('Git.Git', 'recipes/node', '9NBLGGH4NNS1', '@local/tool')
  }
}

Describe 'Removing an app from borc.yaml' {
  It 'removes a plain item and nothing else' {
    $result = Remove-Entry $script:Sample 'winget' 'Git.Git'
    $result | Should -BeExactly $script:Sample.Replace("  - winget: Git.Git`n", '')
  }

  It 'removes a recipe item with its parameters and their comments' {
    $result = Remove-Entry $script:Sample 'recipe' 'recipes/node'
    $result | Should -BeExactly $script:Sample.Replace("  - recipe: recipes/node`n    parameters:`n      npmCache: D:\caches\npm   # keep the cache off C:`n", '')
  }

  It 'matches quoted values and ignores case' {
    Remove-Entry "apps:`n  - recipe: '@local/tool'`n  - winget: A.B`n" 'recipe' '@local/tool' | Should -BeExactly "apps:`n  - winget: A.B`n"
    Remove-Entry "apps:`n  - winget: git.git # vcs`n" 'winget' 'Git.Git' | Should -BeExactly "apps:`n"
  }

  It 'returns nothing when the app is not listed' {
    Remove-Entry $script:Sample 'winget' 'Not.Listed' | Should -BeNullOrEmpty
    Remove-Entry $script:Sample 'recipe' 'recipes/idea' | Should -BeNullOrEmpty
  }

  It 'does not touch an item with the same id outside apps' {
    Remove-Entry "other:`n  - winget: A.B`napps:`n  - winget: C.D`n" 'winget' 'A.B' | Should -BeNullOrEmpty
  }
}
