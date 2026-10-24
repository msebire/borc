# The only place borc runs winget. Output is streamed to the host and the log
# as it comes; the function returns winget's exit code.
function Invoke-BorcWinget {
  param([Parameter(Mandatory)] [string[]] $Arguments)
  Write-BorcLog -Message "winget $($Arguments -join ' ')" -LogOnly
  & winget @Arguments 2>&1 | ForEach-Object { Write-BorcOutputLine -Line "$_" }
  $LASTEXITCODE
}

# Runs winget without showing its output; used for quiet checks such as "is it installed".
function Invoke-BorcWingetQuiet {
  param([Parameter(Mandatory)] [string[]] $Arguments)
  Write-BorcLog -Message "winget $($Arguments -join ' ')" -LogOnly
  $output = & winget @Arguments 2>&1 | ForEach-Object { "$_" }
  [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
}
