<#
.SYNOPSIS
  Reports the window of the app check V2 started, then closes it.

.DESCRIPTION
  Run it after v2-start-app.winget.yaml. It reads the process ID the unit wrote to
  %LOCALAPPDATA%\borc-check\v2.txt, waits up to 20 seconds for its window, and
  says whether the process still runs, the window's title, and whether Windows
  shows it. Then it closes the window, unless -Keep is given.
#>
param([switch] $Keep)

$ErrorActionPreference = 'Stop'
Add-Type -Namespace BorcCheck -Name Window -MemberDefinition '[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);'
$id = [int](Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'borc-check\v2.txt'))
$deadline = (Get-Date).AddSeconds(20)
do {
  $process = Get-Process -Id $id -ErrorAction SilentlyContinue
  if (-not $process -or $process.MainWindowHandle -ne [IntPtr]::Zero) { break }
  Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $deadline)

if (-not $process) {
  Write-Host "Process $id is not running."
  return
}
$handle = $process.MainWindowHandle
[pscustomobject]@{
  ProcessId = $id
  Running = $true
  SessionId = $process.SessionId
  WindowTitle = $process.MainWindowTitle
  HasWindow = $handle -ne [IntPtr]::Zero
  Visible = $handle -ne [IntPtr]::Zero -and [BorcCheck.Window]::IsWindowVisible($handle)
}
if (-not $Keep -and $handle -ne [IntPtr]::Zero) { $null = $process.CloseMainWindow() }
