# The only place borc runs winget. Output is streamed, indented under a start
# and an end line, to the host and the log; the function returns winget's exit code.
function Invoke-BorcWinget {
  param([Parameter(Mandatory)] [string[]] $Arguments, [hashtable] $OkCodes = @{})
  $started = Get-Date
  Write-BorcCommandStart -Command "winget $($Arguments -join ' ')"
  & winget @Arguments 2>&1 | ForEach-Object { Write-BorcOutputLine -Line "$_" }
  $code = $LASTEXITCODE
  Write-BorcCommandEnd -ExitCode $code -Duration ((Get-Date) - $started) -OkCodes $OkCodes
  $code
}

# Runs winget without showing its output; used for quiet checks such as "is it installed".
function Invoke-BorcWingetQuiet {
  param([Parameter(Mandatory)] [string[]] $Arguments)
  Write-BorcLog -Message "winget $($Arguments -join ' ')" -LogOnly
  $output = & winget @Arguments 2>&1 | ForEach-Object { "$_" }
  [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
}
