# winget writes UTF-8 when its output is piped, whatever the console's code page.
# Returns the encoding to put back, or $null when there is no console to change.
function Enter-BorcWingetEncoding {
  try {
    $saved = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $saved
  } catch {
    $null
  }
}

function Exit-BorcWingetEncoding {
  param($Saved)
  if ($Saved) { try { [Console]::OutputEncoding = $Saved } catch { Write-BorcLog -Message "Console encoding not restored: $($_.Exception.Message)" -LogOnly } }
}

# The only place BORC runs winget. Output is streamed, indented under a start
# and an end line, to the host and the log; the function returns winget's exit code.
function Invoke-BorcWinget {
  param([Parameter(Mandatory)] [string[]] $Arguments, [hashtable] $OkCodes = @{})
  $started = Get-Date
  Write-BorcCommandStart -Command "winget $($Arguments -join ' ')"
  $encoding = Enter-BorcWingetEncoding
  try {
    & winget @Arguments 2>&1 | ForEach-Object { Write-BorcOutputLine -Line "$_" }
    $code = $LASTEXITCODE
  } finally {
    Exit-BorcWingetEncoding -Saved $encoding
  }
  Write-BorcCommandEnd -ExitCode $code -Duration ((Get-Date) - $started) -OkCodes $OkCodes
  $code
}

# Runs winget without showing its output; used for quiet checks such as "is it installed".
function Invoke-BorcWingetQuiet {
  param([Parameter(Mandatory)] [string[]] $Arguments)
  Write-BorcLog -Message "winget $($Arguments -join ' ')" -LogOnly
  $encoding = Enter-BorcWingetEncoding
  try {
    $output = & winget @Arguments 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
  } finally {
    Exit-BorcWingetEncoding -Saved $encoding
  }
  [pscustomobject]@{ ExitCode = $code; Output = @($output) }
}
