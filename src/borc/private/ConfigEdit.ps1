# install and uninstall edit the apps list of borc.yaml as text, so comments
# and formatting survive. The YAML serializer is never used on borc.yaml.

function Split-BorcLines {
  param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
  $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
  $lines = [System.Collections.Generic.List[string]]::new()
  if ($Text.Length -gt 0) { $lines.AddRange([string[]]($Text -split '\r?\n')) }
  # A final newline leaves an empty last element; it is restored on join.
  $endsWithNewline = $Text.EndsWith("`n")
  if ($endsWithNewline) { $lines.RemoveAt($lines.Count - 1) }
  [pscustomobject]@{ Lines = $lines; Newline = $newline }
}

function Join-BorcLines {
  param([Parameter(Mandatory)] $Split)
  if ($Split.Lines.Count -eq 0) { return '' }
  ($Split.Lines -join $Split.Newline) + $Split.Newline
}

# Finds the top-level apps: key and the lines of its block.
function Find-BorcAppsBlock {
  param([Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [System.Collections.Generic.List[string]] $Lines)
  $start = -1
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match '^apps\s*:') { $start = $i; break }
  }
  if ($start -lt 0) { return $null }
  $end = $Lines.Count
  for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match '^[^\s#\-]') { $end = $i; break }
  }
  [pscustomobject]@{ Start = $start; End = $end }
}

function Format-BorcYamlScalar {
  param([Parameter(Mandatory)] [string] $Value)
  if ($Value -match "^[@&*!|>'`"%,\[\]{}#?:-]" -or $Value -match ': | #|:$') {
    return "'" + $Value.Replace("'", "''") + "'"
  }
  $Value
}

function Add-BorcAppEntry {
  param(
    [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
    [Parameter(Mandatory)] [ValidateSet('winget', 'msstore', 'recipe')] [string] $Kind,
    [Parameter(Mandatory)] [string] $Id
  )
  $split = Split-BorcLines -Text $Text
  $lines = $split.Lines
  $block = Find-BorcAppsBlock -Lines $lines
  $value = Format-BorcYamlScalar -Value $Id

  if ($null -eq $block) {
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim()) { $lines.Add('') }
    $lines.Add('apps:')
    $lines.Add("  - ${Kind}: $value")
    return Join-BorcLines -Split $split
  }
  if ($lines[$block.Start] -match '^apps\s*:\s*\[\s*\]\s*(#.*)?$') {
    $lines[$block.Start] = 'apps:' + $(if ($Matches[1]) { " $($Matches[1])" } else { '' })
  }

  $indent = '  '
  $insertAt = $block.Start + 1
  for ($i = $block.Start + 1; $i -lt $block.End; $i++) {
    $line = $lines[$i]
    if ($line -match '^(\s*)-\s') {
      if ($insertAt -eq $block.Start + 1) { $indent = $Matches[1] }
      $insertAt = $i + 1
    } elseif ($line.Trim() -and $line -notmatch '^\s*#' -and $insertAt -gt $block.Start + 1) {
      # Continuation of the previous item, such as its parameters.
      $insertAt = $i + 1
    }
  }
  $lines.Insert($insertAt, "$indent- ${Kind}: $value")
  Join-BorcLines -Split $split
}

# Returns the new text, or $null when the entry is not listed.
function Remove-BorcAppEntry {
  param(
    [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
    [Parameter(Mandatory)] [ValidateSet('winget', 'msstore', 'recipe')] [string] $Kind,
    [Parameter(Mandatory)] [string] $Id
  )
  $split = Split-BorcLines -Text $Text
  $lines = $split.Lines
  $block = Find-BorcAppsBlock -Lines $lines
  if ($null -eq $block) { return $null }
  $pattern = '^(\s*)-\s+' + [regex]::Escape($Kind) + '\s*:\s*(''|"|)' + [regex]::Escape($Id) + '\2\s*(#.*)?$'
  for ($i = $block.Start + 1; $i -lt $block.End; $i++) {
    if ($lines[$i] -notmatch $pattern) { continue }
    $dashIndent = $Matches[1].Length
    $count = 1
    while ($i + $count -lt $block.End) {
      $next = $lines[$i + $count]
      if (-not $next.Trim() -or ($next -match '^(\s*)' -and $Matches[1].Length -le $dashIndent)) { break }
      $count++
    }
    $lines.RemoveRange($i, $count)
    return Join-BorcLines -Split $split
  }
  $null
}
