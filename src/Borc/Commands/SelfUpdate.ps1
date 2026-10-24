function Invoke-BorcSelfUpdate {
  param([Parameter(Mandatory)] $Paths)
  if (-not (Test-BorcGitRepo -Path $Paths.Engine)) {
    throw "borc is not installed in $($Paths.Engine). Run the one-line installer again."
  }
  Start-BorcSteps -Total 2
  Start-BorcStep -Name 'Pulling the borc engine'
  Assert-BorcGit -Result (Invoke-BorcGit -Arguments @('-C', $Paths.Engine, 'pull', '--ff-only')) -Action 'update borc'
  Start-BorcStep -Name 'Refreshing borc.cmd, Get-BorcSecret.ps1 and the profile block'
  $code = Invoke-BorcEngineRefresh -Paths $Paths
  if ($code -ne 0) { throw "The updated engine could not refresh its runtime files and profile block (exit code $code)." }
  $head = (Invoke-BorcGit -Arguments @('-C', $Paths.Engine, 'log', '-1', '--format=%h %cs') -Quiet).Output | Select-Object -First 1
  $branch = Get-BorcCurrentBranch -Path $Paths.Engine
  $onBranch = if ($branch -and $branch -ne $script:BorcBranch) { ", branch $branch" } else { '' }
  Write-BorcLog -Message "borc is up to date ($head$onBranch)."
  0
}

# This process still runs the engine as it was before the pull, so the updated
# engine, in a child process, copies its own files and writes its own profile block.
function Invoke-BorcEngineRefresh {
  param([Parameter(Mandatory)] $Paths)
  $manifest = Join-Path $Paths.Engine 'src\Borc\Borc.psd1'
  $command = "`$ErrorActionPreference = 'Stop'; Import-Module -Name '$manifest'; & (Get-Module -Name Borc) { Update-BorcRuntime }"
  $started = Get-Date
  Write-BorcCommandStart -Command 'pwsh (updated engine): Update-BorcRuntime'
  & pwsh -NoLogo -NoProfile -NonInteractive -Command $command 2>&1 | ForEach-Object { Write-BorcOutputLine -Line "$_" }
  $code = $LASTEXITCODE
  Write-BorcCommandEnd -ExitCode $code -Duration ((Get-Date) - $started)
  $code
}

# Brings the files borc keeps outside the engine clone in line with it.
function Update-BorcRuntime {
  $paths = Get-BorcPaths
  Install-BorcRuntimeFiles -Paths $paths
  $profilePath = Get-BorcProfilePath
  if (Set-BorcProfileBlock -Path $profilePath) { Write-Host "Updated the borc block in $profilePath." }
}

# Copies the borc.cmd shim and Get-BorcSecret.ps1 out of the engine clone, to
# the places recipes and the PATH expect them.
function Install-BorcRuntimeFiles {
  param([Parameter(Mandatory)] $Paths)
  New-Item -ItemType Directory -Path $Paths.Bin -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $script:BorcModuleRoot) 'borc.cmd') -Destination (Join-Path $Paths.Bin 'borc.cmd') -Force
  Copy-Item -LiteralPath (Join-Path $script:BorcModuleRoot 'Get-BorcSecret.ps1') -Destination (Join-Path $Paths.Internal 'Get-BorcSecret.ps1') -Force
}
