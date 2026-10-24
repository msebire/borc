# The engine repository. This is the only place the URL is defined; install.ps1
# keeps a copy (it is downloaded alone) and the tests check that they match.
$script:BorcRepoUrl = 'https://github.com/msebire/borc'
$script:BorcBranch = 'main'

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
  "powershell -NoProfile -ExecutionPolicy Bypass -Command `"irm $url | iex`""
}
