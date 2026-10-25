# Entry point of the borc command: reads the arguments, shows help pages and
# runs one command. Returns the process exit code.

$script:BorcCommands = [ordered]@{
  'help' = @{ Options = @(); MinArgs = 0; MaxArgs = 1; Log = $false }
  'apply' = @{ Options = @('--what-if', '--check', '--debug'); MinArgs = 0; MaxArgs = 0; Log = $true }
  'upgrade' = @{ Options = @(); MinArgs = 0; MaxArgs = 0; Log = $true }
  'install' = @{ Options = @(); MinArgs = 1; MaxArgs = 1; Log = $true }
  'uninstall' = @{ Options = @(); MinArgs = 1; MaxArgs = 1; Log = $true }
  'search' = @{ Options = @(); MinArgs = 1; MaxArgs = 1; Log = $true }
  'self-update' = @{ Options = @(); MinArgs = 0; MaxArgs = 0; Log = $true }
}

function Get-BorcHelpText {
  param([string] $Command = 'index')
  [IO.File]::ReadAllText((Join-Path $script:BorcModuleRoot "help\$Command.txt")).TrimEnd("`n")
}

function Invoke-Borc {
  [CmdletBinding()]
  [OutputType([int])]
  param([string[]] $Arguments = @())
  $Arguments = @($Arguments | Where-Object { $null -ne $_ })
  if ($Arguments.Count -eq 0 -or $Arguments[0] -in '-h', '--help') {
    Write-Host (Get-BorcHelpText)
    return 0
  }
  $command, $rest = $Arguments[0], @($Arguments | Select-Object -Skip 1)
  if (-not $script:BorcCommands.Contains($command)) {
    Write-Host "Unknown command '$command'. Run borc help for the list of commands."
    return 2
  }
  if ($rest | Where-Object { $_ -in '-h', '--help' }) {
    Write-Host (Get-BorcHelpText -Command $command)
    return 0
  }
  $spec = $script:BorcCommands[$command]
  $options = @($rest | Where-Object { $_ -like '-*' })
  $positional = @($rest | Where-Object { $_ -notlike '-*' })
  foreach ($option in $options) {
    if ($option -notin $spec.Options) {
      Write-Host "Unknown option '$option' for borc $command. Run borc help $command."
      return 2
    }
  }
  if ($command -eq 'apply' -and '--check' -in $options -and '--what-if' -notin $options) {
    Write-Host '--check only works with --what-if: run borc apply --what-if --check.'
    return 2
  }
  if ($positional.Count -lt $spec.MinArgs -or $positional.Count -gt $spec.MaxArgs) {
    Write-Host (Get-BorcHelpText -Command $command)
    return 2
  }
  if ($command -eq 'help') { return Show-BorcHelp -Topic ($positional | Select-Object -First 1) }
  Invoke-BorcCommand -Command $command -Options $options -Positional $positional
}

function Show-BorcHelp {
  param([string] $Topic)
  if (-not $Topic) { Write-Host (Get-BorcHelpText); return 0 }
  if (-not $script:BorcCommands.Contains($Topic)) {
    Write-Host "Unknown command '$Topic'. Run borc help for the list of commands."
    return 2
  }
  Write-Host (Get-BorcHelpText -Command $Topic)
  0
}

# Runs one command with its log; any error ends the run with exit code 1.
function Invoke-BorcCommand {
  param([string] $Command, [string[]] $Options, [string[]] $Positional)
  $paths = Get-BorcPaths
  Start-BorcLog -Directory $paths.Logs -Command $Command | Out-Null
  $code = 1
  try {
    $result = switch ($Command) {
      'apply' { Invoke-BorcApply -Paths $paths -Preview:('--what-if' -in $Options) -Check:('--check' -in $Options) -OneByOne:('--debug' -in $Options) }
      'upgrade' { Invoke-BorcUpgrade -Paths $paths }
      'install' { Invoke-BorcInstall -Paths $paths -App $Positional[0] }
      'uninstall' { Invoke-BorcUninstall -Paths $paths -App $Positional[0] }
      'search' { Invoke-BorcSearch -Paths $paths -Term $Positional[0] }
      'self-update' { Invoke-BorcSelfUpdate -Paths $paths }
    }
    $code = [int](@($result)[-1])
  } catch {
    Write-BorcLog -Message $_.Exception.Message -Level Error
  } finally {
    Complete-BorcRun -ExitCode $code
    Stop-BorcLog
  }
  $code
}

function Assert-BorcSettings {
  param([Parameter(Mandatory)] $Paths)
  if (-not $Paths.Settings) { throw 'BORC_SETTINGS is not set. Run the borc installer first.' }
  if (-not (Test-Path -LiteralPath (Join-Path $Paths.Settings 'borc\borc.yaml'))) {
    throw "No borc.yaml in $($Paths.Settings)\borc. Is BORC_SETTINGS the config repo?"
  }
}

function Write-BorcPlanErrors {
  param([Parameter(Mandatory)] [string[]] $Errors)
  Write-BorcLog -Message 'borc.yaml or a recipe has problems; nothing was run:' -Level Error
  foreach ($message in $Errors) { Write-BorcLog -Message "  $message" }
}

# winget, msstore or recipe, by the form of the argument.
function Get-BorcAppKind {
  param([Parameter(Mandatory)] [string] $App)
  if ($App.Contains('/')) {
    if ($App -notmatch $script:BorcRecipeIdPattern) { throw "'$App' is not a recipe reference. Use repo/recipe or @local/<name>." }
    return 'recipe'
  }
  if (-not $App.Contains('.')) { return 'msstore' }
  'winget'
}
