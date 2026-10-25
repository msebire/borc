# The marked block borc keeps in the PowerShell 7 profile (CurrentUserAllHosts).
# Only the text between the markers is ever rewritten.

function Get-BorcProfileBlock {
  @(
    $script:BorcProfileBegin
    '# Managed by borc: changes inside this block are overwritten.'
    'if ($env:BORC_SETTINGS) {'
    '  $borcScripts = @(Get-ChildItem -Path (Join-Path $env:BORC_SETTINGS ''borc\scripts'') -Filter ''*.ps1'' -File -ErrorAction SilentlyContinue | Sort-Object Name)'
    '  foreach ($borcScript in $borcScripts) {'
    '    try { . $borcScript.FullName } catch { Write-Warning "borc: $($borcScript.Name) failed to load: $_" }'
    '  }'
    '  Remove-Variable -Name borcScripts, borcScript -ErrorAction SilentlyContinue'
    '}'
    '$borcCompletion = Join-Path $env:LOCALAPPDATA ''borc\engine\src\completion.ps1'''
    'if (Test-Path -LiteralPath $borcCompletion) { . $borcCompletion }'
    'Remove-Variable -Name borcCompletion -ErrorAction SilentlyContinue'
    'if ($env:BORC_HOME -and (Test-Path -LiteralPath $env:BORC_HOME) -and (Get-Location).Path.TrimEnd(''\'') -eq $HOME.TrimEnd(''\'')) {'
    '  Set-Location -LiteralPath $env:BORC_HOME'
    '}'
    $script:BorcProfileEnd
  ) -join "`n"
}

# Returns the profile text with the borc block added or replaced.
function Update-BorcProfileText {
  param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
  $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
  $block = (Get-BorcProfileBlock) -replace "`n", $newline
  $pattern = '(?s)' + [regex]::Escape($script:BorcProfileBegin) + '.*?' + [regex]::Escape($script:BorcProfileEnd)
  if ($Text -match $pattern) {
    return [regex]::Replace($Text, $pattern, { $block }, 'None', [TimeSpan]::FromSeconds(5))
  }
  if ($Text.Length -eq 0) { return $block + $newline }
  $separator = if ($Text.EndsWith("`n")) { $newline } else { $newline + $newline }
  $Text + $separator + $block + $newline
}

function Set-BorcProfileBlock {
  param([Parameter(Mandatory)] [string] $Path)
  $exists = Test-Path -LiteralPath $Path
  $text = if ($exists) { [IO.File]::ReadAllText($Path) } else { '' }
  $updated = Update-BorcProfileText -Text $text
  if ($exists -and $updated -ceq $text) { return $false }
  New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
  # Keep a BOM if the profile had one; Windows PowerShell needs it for non-ASCII text.
  $hadBom = $false
  if ($exists) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hadBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  }
  [IO.File]::WriteAllText($Path, $updated, [Text.UTF8Encoding]::new($hadBom))
  $true
}
