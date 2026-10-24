BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

  $script:TrackedFiles = @(git -C $script:RepoRoot ls-files --cached --others --exclude-standard) |
    Where-Object { $_ -and (Test-Path (Join-Path $script:RepoRoot $_)) -and $_ -ne 'LICENSE' } |
    ForEach-Object { Join-Path $script:RepoRoot $_ }
}

Describe 'Repository conventions' {
  It 'uses LF line endings and ends every file with a newline' {
    $bad = foreach ($file in $script:TrackedFiles) {
      $text = [IO.File]::ReadAllText($file)
      if ($text.Contains("`r`n") -or ($text.Length -gt 0 -and -not $text.EndsWith("`n"))) { $file }
    }
    $bad | Should -BeNullOrEmpty
  }

  It 'uses a UTF-8 BOM for PowerShell files only' {
    $bad = foreach ($file in $script:TrackedFiles) {
      $bytes = [IO.File]::ReadAllBytes($file)
      $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
      $wantBom = [IO.Path]::GetExtension($file) -in '.ps1', '.psm1', '.psd1'
      if ($hasBom -ne $wantBom) { $file }
    }
    $bad | Should -BeNullOrEmpty
  }

  It 'has no tabs or trailing whitespace outside Markdown' {
    $bad = foreach ($file in $script:TrackedFiles) {
      if ([IO.Path]::GetExtension($file) -eq '.md') { continue }
      $lines = [IO.File]::ReadAllLines($file)
      for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '\t' -or $lines[$i] -match '\s$') { "${file}:$($i + 1)" }
      }
    }
    $bad | Should -BeNullOrEmpty
  }
}

Describe 'Module' {
  It 'imports and exports Get-BorcSecret' {
    $commands = (Get-Module -Name Borc).ExportedFunctions.Keys
    $commands | Should -Contain 'Get-BorcSecret'
  }

  It 'has a version, which is set when a release is cut' {
    [version](Import-PowerShellDataFile -Path $script:ModulePath).ModuleVersion | Should -BeOfType [version]
  }
}
