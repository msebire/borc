# Everything borc knows about the WinGet Configuration file format lives here,
# so a future winget change means editing this one file.
#
# Verified on 2026-10-24 with winget 1.29.380, DSC 3.2.2 and Windows 10 22H2:
# the schema URL, the processor, the two script resource types, input with one
# param, testScript returning one boolean, and securityContext: elevated.
# winget 1.29 rejects the aka.ms/dsc/schemas/v3/... URLs from the DSC docs.
#
# dependsOn, verified the same day with real winget configure runs (not
# `winget configure test`, which accepts anything): winget's dscv3 path matches
# each entry against unit names as plain text, and applies the named unit
# first. The [resourceId('<type>','<name>')] form from the DSC docs is never
# found, even with a simple name. borc's prefixed names (with @, /, : and
# spaces) work, for PowerShellScript and Microsoft.WinGet/Package targets.
# A Microsoft.WinGet/Package unit with id and source: winget applies too.
# With version, verified on 2026-10-25: jqlang.jq version 1.7.1 installed 1.7.1
# while 1.8.2 was available, and a second apply left it at 1.7.1.
#
# Not verified yet: Microsoft.WinGet/Package with source: msstore.

$script:WingetSchemaUrl = 'https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json'
$script:WingetProcessor = 'dscv3'
$script:WingetPowerShellScriptType = 'Microsoft.DSC.Transitional/PowerShellScript'
$script:WingetWindowsPowerShellScriptType = 'Microsoft.DSC.Transitional/WindowsPowerShellScript'
$script:WingetPackageType = 'Microsoft.WinGet/Package'

$script:WingetConfigureArguments = @('--accept-configuration-agreements', '--disable-interactivity')
$script:WingetAgreementArguments = @('--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')

# winget configure test, as read by apply --what-if --check. Seen on winget
# 1.29.380 (English UI): after each "<type> [<name>]" line, one line gives the
# unit's state; a failed test adds the script's error below. The exit code is
# not 0 as soon as one unit is not in place, so borc reads the lines instead.
# Any other line is reported as "could not check", never guessed.
$script:WingetTestArguments = @('--accept-configuration-agreements', '--disable-interactivity', '--suppress-initial-details')
$script:WingetTestUnitPattern = '^(?<type>[\w.]+/[\w.]+) \[(?<name>.+)\]$'
$script:WingetTestInState = 'System is in the described configuration state.'
$script:WingetTestNotInState = 'System is not in the described configuration state.'
$script:WingetTestFailed = 'The configuration unit failed while attempting to test the current system state.'

# winget exit codes that do not mean a failure for upgrade and uninstall.
$script:WingetNoApplicableUpgrade = 0x8A15002B
$script:WingetNoPackageFound = 0x8A150014

function New-WingetDocumentHeader {
  [ordered]@{
    '$schema' = $script:WingetSchemaUrl
    metadata = [ordered]@{ winget = [ordered]@{ processor = $script:WingetProcessor } }
  }
}

function Test-WingetDocumentHeader {
  param([Parameter(Mandatory)] $Document)
  $processor = $null
  if ($Document.metadata -is [System.Collections.IDictionary] -and $Document.metadata.winget -is [System.Collections.IDictionary]) {
    $processor = $Document.metadata.winget.processor
  }
  ($Document['$schema'] -ceq $script:WingetSchemaUrl) -and ($processor -ceq $script:WingetProcessor)
}

# A dependsOn entry as winget resolves it: the unit name itself.
function Format-WingetDependsOn {
  param([Parameter(Mandatory)] [string] $Name)
  $Name
}

# The unit name a recipe's dependsOn entry points at. Recipes may write the
# plain name or, as the DSC docs show, [resourceId('<type>','<name>')].
function ConvertFrom-WingetDependsOn {
  param([Parameter(Mandatory)] [string] $Value)
  if ($Value -match "^\[resourceId\(\s*'([^']*)'\s*,\s*'([^']*)'\s*\)\]$") { return $Matches[2] }
  $Value
}

function Format-WingetResourceName {
  param([Parameter(Mandatory)] [string] $RecipeId, [Parameter(Mandatory)] [string] $Name)
  "${RecipeId}: $Name"
}

function Format-WingetPackageName {
  param([Parameter(Mandatory)] [string] $Source, [Parameter(Mandatory)] [string] $Id)
  "${Source}: $Id"
}

function New-WingetPackageUnit {
  param([Parameter(Mandatory)] [string] $Source, [Parameter(Mandatory)] [string] $Id, [string] $Version = '')
  $properties = [ordered]@{ id = $Id; source = $Source }
  if ($Version) { $properties['version'] = $Version }
  [ordered]@{
    name = Format-WingetPackageName -Source $Source -Id $Id
    type = $script:WingetPackageType
    properties = $properties
  }
}

# The version winget list shows for an installed package: the column right
# after its ID ("Git  Git.Git 2.56.0.3 winget"). $null when it is not there.
function ConvertFrom-WingetListVersion {
  param([Parameter(Mandatory)] [string] $Id, [string[]] $Lines = @())
  foreach ($line in $Lines) {
    if ($line -match "(?i)(^|\s)$([regex]::Escape($Id))\s+(?<version>\S+)") { return $Matches['version'] }
  }
  $null
}
