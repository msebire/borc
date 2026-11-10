BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  $script:Template = Join-Path $script:RepoRoot 'src\borc\template'
  $script:RecipePath = Join-Path $script:Template 'borc\cookbook\hello-borc.yaml'
}

Describe 'Starter template' {
  It 'is accepted by BORC, with the example recipe listed' {
    $plan = InModuleScope borc -Parameters @{ T = $script:Template } { param($T) Get-BorcPlan -SettingsRoot $T -RecipesRoot $T }
    $plan.Errors | Should -BeNullOrEmpty
    $plan.Order | Should -Be @('@local/hello-borc')
    $runs = InModuleScope borc -Parameters @{ Plan = $plan } { param($Plan) New-BorcRunDocuments -Plan $Plan }
    $runs.Reboot | Should -BeNullOrEmpty
    $runs.Main.resources.name | Should -Contain '@local/hello-borc: hello-borc command'
  }

  It 'needs no .gitkeep' {
    @(Get-ChildItem -Path $script:Template -Recurse -Force -File -Filter '.gitkeep') | Should -BeNullOrEmpty
  }

  It 'needs no admin rights for the example recipe, so no UAC prompt on a first apply' {
    (Read-TestText -Path $script:RecipePath) -split "`n" | Where-Object { $_ -notmatch '^\s*#' -and $_ -match 'securityContext' } | Should -BeNullOrEmpty
  }
}

Describe 'Template README' {
  BeforeAll {
    $script:Readme = Read-TestText -Path (Join-Path $script:Template 'README.md')
  }

  It 'does not rely on the example recipe, which the user may delete' {
    $script:Readme | Should -Not -Match 'hello-borc'
  }

  It 'only names commands that exist' {
    $help = (Get-ChildItem -Path (Join-Path $script:RepoRoot 'src\borc\help') -Filter '*.txt').BaseName
    $named = [regex]::Matches($script:Readme, '`borc ([a-z-]+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $named | Should -Not -BeNullOrEmpty
    $named | Where-Object { $_ -notin $help } | Should -BeNullOrEmpty
  }

  It 'only names options the command has' {
    $apply = Read-TestText -Path (Join-Path $script:RepoRoot 'src\borc\help\apply.txt')
    $commands = [regex]::Matches($script:Readme, '`borc [^`]*`') | ForEach-Object Value
    $options = [regex]::Matches(($commands -join ' '), '--[a-z][a-z-]+') | ForEach-Object Value | Sort-Object -Unique
    $options | Should -Not -BeNullOrEmpty
    foreach ($option in $options) { $apply | Should -Match ([regex]::Escape($option)) }
  }

  It 'links to doc pages that exist' {
    $pages = [regex]::Matches($script:Readme, '/blob/main/(docs/[\w-]+\.md)') | ForEach-Object { $_.Groups[1].Value }
    $pages | Should -Not -BeNullOrEmpty
    foreach ($page in $pages) { Test-Path (Join-Path $script:RepoRoot $page) | Should -BeTrue -Because "$page should exist" }
  }

  It 'names the files of the template it describes' {
    foreach ($path in 'borc/borc.yaml', 'borc/cookbook/', 'borc/scripts/') {
      $script:Readme | Should -Match ([regex]::Escape($path))
      Test-Path (Join-Path $script:Template $path) | Should -BeTrue
    }
  }
}

Describe 'Example recipe' {
  It 'documents every option a recipe can use' {
    $text = Read-TestText -Path $script:RecipePath
    foreach ($word in 'Layout under BORC_SETTINGS', 'requires:', 'reboot:', 'parameters:', '{{name}}', 'secrets:', 'Microsoft.WinGet/Package', 'testScript', 'setScript', 'securityContext: elevated', 'docs/writing-recipes.md') {
      $text | Should -Match ([regex]::Escape($word)) -Because "the example recipe should explain $word"
    }
  }

  Context 'running its scripts' {
    BeforeAll {
      $script:Root = New-TestFolder
      $script:SavedLocalAppData = $env:LOCALAPPDATA
      $script:SavedSettings = $env:BORC_SETTINGS
      # Process level only: the scripts write under these temporary folders.
      $env:LOCALAPPDATA = Join-Path $script:Root 'localappdata'
      $env:BORC_SETTINGS = $script:Template
      New-Item -ItemType Directory -Path (Join-Path $env:LOCALAPPDATA 'borc\bin') | Out-Null
      $text = Read-TestText -Path $script:RecipePath
      $script:Unit = (InModuleScope borc -Parameters @{ T = $text } { param($T) ConvertTo-BorcRecipe -Text $T -Id '@local/hello-borc' }).Resources[0]
      $script:Command = Join-Path $env:LOCALAPPDATA 'borc\bin\hello-borc.cmd'
    }
    AfterAll {
      $env:LOCALAPPDATA = $script:SavedLocalAppData
      $env:BORC_SETTINGS = $script:SavedSettings
      Remove-Item -LiteralPath $script:Root -Recurse -Force
    }

    It 'says exactly one boolean: false before, true after, as winget requires' {
      $properties = $script:Unit.properties
      $before = @(& ([scriptblock]::Create($properties.testScript)) $properties.input)
      $before.Count | Should -Be 1
      $before[0] | Should -BeOfType [bool]
      $before[0] | Should -BeFalse
      @(& ([scriptblock]::Create($properties.setScript)) $properties.input) | Should -BeNullOrEmpty
      $after = @(& ([scriptblock]::Create($properties.testScript)) $properties.input)
      $after.Count | Should -Be 1
      $after[0] | Should -BeTrue
    }

    It 'adds a command that prints the message kept in the config repo' {
      $output = @(cmd.exe /c $script:Command)
      $output[0] | Should -Be 'Hello from BORC!'
      ($output -join "`n") | Should -Match 'hello-borc\\message\.txt'
    }
  }
}
