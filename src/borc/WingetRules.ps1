# Everything BORC knows about the WinGet Configuration file format lives here,
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
# found, even with a simple name. BORC's prefixed names (with @, /, : and
# spaces) work, for PowerShellScript and Microsoft.WinGet/Package targets.
# A Microsoft.WinGet/Package unit with id and source: winget applies too.
# With version, verified on 2026-10-25: jqlang.jq version 1.7.1 installed 1.7.1
# while 1.8.2 was available, and a second apply left it at 1.7.1.
#
# Environment, seen on 2026-11-08: units do not inherit the caller's process. With
# LOCALAPPDATA redirected in the process running winget configure, a unit wrote to
# the real %LOCALAPPDATA%. So a process-level variable cannot sandbox a real run,
# and a value a unit needs has to be a user variable.
#
# Packages, seen on 2026-11-09 on Windows 11: a Microsoft.WinGet/Package unit with
# source: msstore fails with "Package agreements were not agreed to" unless it sets
# acceptAgreements: true, and then applies. --accept-configuration-agreements does not
# reach it. A unit with version also goes down to an older version, which winget
# install refuses (0x8A15002B).
#
# Elevated units, seen the same day: without the current VC++ runtime
# (vcruntime140_1.dll missing), winget's elevated process cannot load
# WindowsPackageManager.dll, and every unit of the file fails with an internal
# error, the non-elevated ones too. In winget configure test, an elevated unit has a
# shield icon and two spaces between its type and its name.

# The winget these rules were verified with. A failed run compares against it.
$script:WingetVerifiedVersion = [version]'1.29.380'

$script:WingetSchemaUrl ='https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json'
$script:WingetProcessor = 'dscv3'
$script:WingetPowerShellScriptType = 'Microsoft.DSC.Transitional/PowerShellScript'
$script:WingetWindowsPowerShellScriptType = 'Microsoft.DSC.Transitional/WindowsPowerShellScript'
$script:WingetPackageType = 'Microsoft.WinGet/Package'

$script:WingetConfigureArguments = @('--accept-configuration-agreements', '--disable-interactivity')
$script:WingetAgreementArguments = @('--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')

# winget configure test, as read by apply --what-if --check. Seen on winget
# 1.29.380 (English UI): after each "<type> [<name>]" line, one line gives the
# unit's state; a failed test adds the script's error below. The exit code is
# not 0 as soon as one unit is not in place, so BORC reads the lines instead.
# Any other line is reported as "could not check", never guessed.
$script:WingetTestArguments = @('--accept-configuration-agreements', '--disable-interactivity', '--suppress-initial-details')
$script:WingetTestUnitPattern = '^(?<type>[\w.]+/[\w.]+)\S*\s+\[(?<name>.+)\]$'
$script:WingetTestInState = 'System is in the described configuration state.'
$script:WingetTestNotInState = 'System is not in the described configuration state.'
$script:WingetTestFailed = 'The configuration unit failed while attempting to test the current system state.'

# winget configure with its extended features off, seen on 2026-11-10 on a new
# Windows 11 machine: it prints "Extended features are not enabled. Run `winget
# configure --enable` to enable them." and runs nothing. winget error names this
# code APPINSTALLER_CLI_ERROR_PACKAGE_IS_STUB, which is not what happened here.
$script:WingetConfigureNotEnabled = 0x8A150069

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
  $properties['acceptAgreements'] = $true
  [ordered]@{
    name = Format-WingetPackageName -Source $Source -Id $Id
    type = $script:WingetPackageType
    properties = $properties
  }
}

# A package unit from a recipe accepts agreements too, unless the recipe says otherwise.
function Add-WingetPackageAgreement {
  param([Parameter(Mandatory)] $Unit)
  if ($Unit['type'] -ne $script:WingetPackageType -or $Unit['properties'] -isnot [System.Collections.IDictionary]) { return }
  if (-not $Unit['properties'].Contains('acceptAgreements')) { $Unit['properties']['acceptAgreements'] = $true }
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
