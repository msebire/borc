<#
  Tab completion for the borc command. The borc block of the PowerShell 7
  profile dot-sources this file; in Windows PowerShell 5.1, dot-source it by
  hand: . "$env:LOCALAPPDATA\borc\engine\src\completion.ps1"

  It runs in the shell itself, on every Tab, so it stays light: no module,
  no YAML parser, no child process except winget's own completion for
  winget IDs.
#>

$script:BorcCompletionCommands = @('help', 'apply', 'upgrade', 'install', 'uninstall', 'search', 'self-update')
$script:BorcCompletionOptions = @{ apply = @('--what-if', '--check', '--no-pull', '--debug', '--help', '-h') }

# The suggestions for the word being completed, given the words before it.
function Get-BorcCompletion {
  param([string[]] $Words = @(), [string] $WordToComplete = '')
  $word = $WordToComplete.Trim("'", '"')
  $command = $Words | Where-Object { $_ -notlike '-*' } | Select-Object -First 1
  if (-not $command) {
    if ($word -like '-*') { return @('--help', '-h') | Where-Object { $_ -like "$word*" } }
    return $script:BorcCompletionCommands | Where-Object { $_ -like "$word*" }
  }
  if ($word -like '-*') { return Get-BorcOptionCompletion -Command $command -Words $Words -Word $word }
  $positional = @($Words | Where-Object { $_ -notlike '-*' } | Select-Object -Skip 1)
  if ($positional.Count -gt 0) { return }
  switch ($command) {
    'help' { $script:BorcCompletionCommands | Where-Object { $_ -like "$word*" } }
    'install' {
      Get-BorcRecipeIds | Where-Object { $_ -like "$word*" }
      if ($word.Contains('.')) { Get-BorcWingetCompletion -Word $word }
    }
    'uninstall' { Get-BorcListedApps | Where-Object { $_ -like "$word*" } }
    'search' { Get-BorcRecipeIds | ForEach-Object { ($_ -split '/', 2)[1] } | Select-Object -Unique | Where-Object { $_ -like "$word*" } }
  }
}

function Get-BorcOptionCompletion {
  param([string] $Command, [string[]] $Words, [string] $Word)
  $options = if ($script:BorcCompletionOptions.ContainsKey($Command)) { $script:BorcCompletionOptions[$Command] } else { @('--help', '-h') }
  foreach ($option in $options) {
    if ($option -in $Words) { continue }
    if ($option -eq '--check' -and '--what-if' -notin $Words) { continue }
    if ($option -like "$Word*") { $option }
  }
}

# @local recipes from borc/cookbook/, then repo/recipe from the recipe clones.
function Get-BorcRecipeIds {
  if ($env:BORC_SETTINGS) {
    $cookbook = Join-Path $env:BORC_SETTINGS 'borc\cookbook'
    if (Test-Path -LiteralPath $cookbook) {
      Get-ChildItem -LiteralPath $cookbook -Filter '*.yaml' -File | Sort-Object Name | ForEach-Object { "@local/$($_.BaseName)" }
    }
  }
  $clones = Join-Path $env:LOCALAPPDATA 'borc\recipes'
  if (Test-Path -LiteralPath $clones) {
    foreach ($repo in Get-ChildItem -LiteralPath $clones -Directory | Sort-Object Name) {
      Get-ChildItem -LiteralPath $repo.FullName -Filter '*.yaml' -File | Sort-Object Name | ForEach-Object { "$($repo.Name)/$($_.BaseName)" }
    }
  }
}

# The apps borc.yaml lists, read as text: one "- kind: value" per line.
function Get-BorcListedApps {
  if (-not $env:BORC_SETTINGS) { return }
  $path = Join-Path $env:BORC_SETTINGS 'borc\borc.yaml'
  if (-not (Test-Path -LiteralPath $path)) { return }
  foreach ($line in [IO.File]::ReadAllLines($path)) {
    if ($line -match '^\s*-\s*(winget|msstore|recipe)\s*:\s*[''"]?(?<id>[^''"#\s]+)') { $Matches['id'] }
  }
}

function Get-BorcWingetCompletion {
  param([string] $Word)
  $line = "winget install $Word"
  @(& winget complete --word $Word --commandline $line --position $line.Length 2>$null) | Where-Object { $_ }
}

Register-ArgumentCompleter -Native -CommandName 'borc', 'borc.cmd' -ScriptBlock {
  param($wordToComplete, $commandAst, $cursorPosition)
  $before = @($commandAst.CommandElements | Select-Object -Skip 1 | Where-Object { $_.Extent.EndOffset -lt $cursorPosition -or ($_.Extent.EndOffset -eq $cursorPosition -and -not $wordToComplete) } | ForEach-Object { $_.Extent.Text })
  foreach ($suggestion in @(Get-BorcCompletion -Words $before -WordToComplete $wordToComplete)) {
    # @ starts a splat in PowerShell, so @local recipes are completed quoted.
    $text = if ($suggestion.StartsWith('@')) { "'$suggestion'" } else { $suggestion }
    [System.Management.Automation.CompletionResult]::new($text, $suggestion, 'ParameterValue', $suggestion)
  }
}
