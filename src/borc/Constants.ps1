# The engine repository. This is the only place the URL is defined; install.ps1
# keeps a copy (it is downloaded alone) and the tests check that they match.
$script:BorcRepoUrl = 'https://github.com/msebire/borc'
# The release branch. A maintainer can install another one with BORC_BRANCH
# (see install.ps1); the engine clone then stays on it.
$script:BorcBranch = 'main'

# What src\setup.ps1 exits with when BORC is installed but its first borc apply
# failed. install.ps1 keeps a copy, and the tests check that they match.
$script:BorcFirstApplyFailedExitCode = 4

$script:BorcCredentialPrefix = 'borc:'
$script:BorcLogsToKeep = 20
$script:BorcProfileBegin = '# >>> borc >>>'
$script:BorcProfileEnd = '# <<< borc <<<'

function Get-BorcRawUrl {
  param([Parameter(Mandatory)] [string] $Path)
  $repoPath = ([uri]$script:BorcRepoUrl).AbsolutePath.Trim('/')
  "https://raw.githubusercontent.com/$repoPath/$script:BorcBranch/$Path"
}

function Get-BorcOneLiner {
  $url = Get-BorcRawUrl -Path 'install.ps1'
  "irm $url | iex"
}
