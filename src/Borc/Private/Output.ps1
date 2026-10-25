# How borc presents a run: numbered step headers, a start and an end line
# around each external command, and a summary at the end. The same lines go to
# the log, with the time and without colours.

$script:BorcSteps = [System.Collections.Generic.List[object]]::new()
$script:BorcStepTotal = 0
$script:BorcCurrentStep = $null
$script:BorcResult = $null

# Colours are for the console only, and NO_COLOR turns them off. The text
# always says the result too, so nothing depends on the colour alone.
function Write-BorcConsole {
  param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text, [ConsoleColor] $Color)
  if ($PSBoundParameters.ContainsKey('Color') -and -not $env:NO_COLOR) {
    Write-Host $Text -ForegroundColor $Color
  } else {
    Write-Host $Text
  }
}

function Format-BorcDuration {
  param([Parameter(Mandatory)] [TimeSpan] $Duration)
  if ($Duration.TotalSeconds -lt 60) { return '{0}s' -f [int][Math]::Floor($Duration.TotalSeconds) }
  '{0}m {1:00}s' -f [int][Math]::Floor($Duration.TotalMinutes), $Duration.Seconds
}

function Start-BorcSteps {
  param([Parameter(Mandatory)] [int] $Total)
  $script:BorcSteps = [System.Collections.Generic.List[object]]::new()
  $script:BorcStepTotal = $Total
  $script:BorcCurrentStep = $null
  $script:BorcResult = $null
}

# What the run did or would do, shown under the steps: a headline, then one
# line per topic. The last thing read answers "is there anything to apply?".
function Set-BorcResult {
  param(
    [Parameter(Mandatory)] [string] $Headline,
    [System.Collections.IDictionary] $Details = [ordered]@{},
    [string] $Color
  )
  $script:BorcResult = [pscustomobject]@{ Headline = $Headline; Details = $Details; Color = $Color }
}

# Ends the previous step, if any, then shows the header of the next one.
function Start-BorcStep {
  param([Parameter(Mandatory)] [string] $Name)
  Complete-BorcStep
  $number = $script:BorcSteps.Count + 1
  $label = "[$number/$script:BorcStepTotal] $Name"
  $script:BorcCurrentStep = [pscustomobject]@{ Label = $label; Started = Get-Date; Status = $null; Duration = $null }
  $script:BorcSteps.Add($script:BorcCurrentStep)
  Write-BorcConsole -Text ''
  Write-BorcConsole -Text "==> $label" -Color Cyan
  Add-BorcLogLine -Line ''
  Add-BorcLogLine -Line "==> $label"
}

function Complete-BorcStep {
  param([ValidateSet('done', 'failed', 'restart')] [string] $Status = 'done')
  if (-not $script:BorcCurrentStep) { return }
  $script:BorcCurrentStep.Status = $Status
  $script:BorcCurrentStep.Duration = (Get-Date) - $script:BorcCurrentStep.Started
  $script:BorcCurrentStep = $null
}

# One line per step reached, with its result and duration.
function Write-BorcSummary {
  if ($script:BorcSteps.Count -eq 0) { return }
  $colors = @{ done = 'Green'; failed = 'Red'; restart = 'Yellow' }
  $width = ($script:BorcSteps | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum
  Write-BorcConsole -Text ''
  Write-BorcConsole -Text 'Summary:'
  Add-BorcLogLine -Line ''
  Add-BorcLogLine -Line 'Summary:'
  foreach ($step in $script:BorcSteps) {
    $line = '  {0,-8} {1}  {2}' -f $step.Status, $step.Label.PadRight($width), (Format-BorcDuration -Duration $step.Duration)
    Write-BorcConsole -Text $line -Color $colors[$step.Status]
    Add-BorcLogLine -Line $line
  }
  if ($script:BorcSteps.Count -lt $script:BorcStepTotal) {
    $line = "  Stopped after step $($script:BorcSteps.Count) of $script:BorcStepTotal."
    Write-BorcConsole -Text $line
    Add-BorcLogLine -Line $line
  }
  Write-BorcResult
  $script:BorcSteps = [System.Collections.Generic.List[object]]::new()
}

function Write-BorcResult {
  $result = $script:BorcResult
  if (-not $result) { return }
  Write-BorcConsole -Text ''
  Add-BorcLogLine -Line ''
  $headline = "Result: $($result.Headline)"
  if ($result.Color) { Write-BorcConsole -Text $headline -Color $result.Color } else { Write-BorcConsole -Text $headline }
  Add-BorcLogLine -Line $headline
  $width = ($result.Details.Keys | ForEach-Object { "$_".Length } | Measure-Object -Maximum).Maximum
  foreach ($label in $result.Details.Keys) {
    $line = '  {0} {1}' -f "${label}:".PadRight($width + 1), $result.Details[$label]
    Write-BorcConsole -Text $line
    Add-BorcLogLine -Line $line
  }
  $script:BorcResult = $null
}

# Ends the steps of a command from its exit code, then shows the summary.
function Complete-BorcRun {
  param([Parameter(Mandatory)] [int] $ExitCode)
  $status = switch ($ExitCode) { 0 { 'done' } 3010 { 'restart' } default { 'failed' } }
  Complete-BorcStep -Status $status
  Write-BorcSummary
}

function Write-BorcCommandStart {
  param([Parameter(Mandatory)] [string] $Command)
  Write-BorcConsole -Text "  > $Command"
  Add-BorcLogLine -Line "  > $Command"
}

# The end line of a command. Codes listed in OkCodes are not failures; their
# note says what they mean, such as "no upgrade available".
function Write-BorcCommandEnd {
  param([Parameter(Mandatory)] [int] $ExitCode, [Parameter(Mandatory)] [TimeSpan] $Duration, [hashtable] $OkCodes = @{})
  $time = Format-BorcDuration -Duration $Duration
  if ($ExitCode -eq 0 -or $OkCodes.ContainsKey($ExitCode)) {
    $note = if ($ExitCode -ne 0 -and $OkCodes[$ExitCode]) { " ($($OkCodes[$ExitCode]))" } else { '' }
    $line = "  < done in $time$note"
    Write-BorcConsole -Text $line -Color Green
  } else {
    $line = "  < failed, exit code $(Format-BorcExitCode -Code $ExitCode), after $time"
    Write-BorcConsole -Text $line -Color Red
  }
  Add-BorcLogLine -Line $line
}

function Format-BorcExitCode {
  param([Parameter(Mandatory)] [int] $Code)
  if ($Code -ge 0 -and $Code -lt 65536) { return "$Code" }
  '0x{0:X8}' -f $Code
}
