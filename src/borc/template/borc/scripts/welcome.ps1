# Welcome banner of the BORC starter template, and an example of what this
# folder is for: every *.ps1 here is loaded in each new PowerShell 7 terminal.
# Delete this file when you no longer need the banner.

# Inside a script block, so nothing here stays behind in your terminal.
& {
  $settings = $env:BORC_SETTINGS

  # Prints one line from text and colour pairs. NO_COLOR turns the colours off.
  function Write-Segments {
    param([object[]] $Segments = @())
    for ($i = 0; $i -lt $Segments.Count; $i += 2) {
      if ($env:NO_COLOR) { Write-Host $Segments[$i] -NoNewline }
      else { Write-Host $Segments[$i] -NoNewline -ForegroundColor $Segments[$i + 1] }
    }
    Write-Host ''
  }

  function Write-Step {
    param([string] $Number, [string] $Label, [string] $Action)
    Write-Segments @("  $Number. ", 'Cyan', $Label.PadRight(12), 'White', $Action, 'Gray')
  }

  Write-Host ''
  Write-Segments @('  BORC', 'Cyan', '  Blank to Operational, Rejoin the Collective.', 'DarkGray')
  Write-Segments @('  Your configuration is in ', 'Gray', $settings, 'White')
  Write-Host ''
  if ($settings -and (Test-Path -LiteralPath (Join-Path $settings 'borc\cookbook\hello-borc.yaml'))) {
    Write-Segments @('  Try it: ', 'Gray', 'hello-borc', 'White', ', from the example recipe in borc\cookbook', 'Gray')
    Write-Host ''
  }
  Write-Step -Number '1' -Label 'Add apps' -Action 'borc install <id>, or edit borc\borc.yaml'
  Write-Step -Number '2' -Label 'Apply them' -Action 'borc apply'
  Write-Step -Number '3' -Label 'Save them' -Action "commit in $settings, add a remote and push"
  Write-Host ''
  Write-Segments @('  Commands and tips: README.md in that folder', 'DarkGray')
  Write-Segments @('  Docs: https://github.com/msebire/borc/tree/main/docs', 'DarkGray')
  Write-Segments @('  To remove this message, delete borc\scripts\welcome.ps1', 'DarkGray')
  Write-Host ''
}
