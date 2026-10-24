# Whether Windows waits for a restart. Reads the servicing keys that feature
# installs (WSL, Virtual Machine Platform) and Windows Update set.
function Test-BorcRestartPending {
  $keys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
  )
  foreach ($key in $keys) {
    if (Test-Path -LiteralPath $key) { return $true }
  }
  $false
}
