# Everything borc knows about the WinGet Configuration file format lives here,
# so a future winget change means editing this one file.
#
# Verified on 2026-10-24 with winget 1.29.380, DSC 3.2.2 and Windows 10 22H2:
# the schema URL, the processor, the two script resource types, input with one
# param, testScript returning one boolean, and securityContext: elevated.
# winget 1.29 rejects the aka.ms/dsc/schemas/v3/... URLs from the DSC docs.
#
# Not verified yet: the dependsOn form, the prefixed resource names inside it,
# and the Microsoft.WinGet/Package properties borc uses for plain packages.

$script:WingetSchemaUrl = 'https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json'
$script:WingetProcessor = 'dscv3'
$script:WingetPowerShellScriptType = 'Microsoft.DSC.Transitional/PowerShellScript'
$script:WingetWindowsPowerShellScriptType = 'Microsoft.DSC.Transitional/WindowsPowerShellScript'
$script:WingetPackageType = 'Microsoft.WinGet/Package'

$script:WingetConfigureArguments = @('--accept-configuration-agreements', '--disable-interactivity')
$script:WingetAgreementArguments = @('--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')

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

function Format-WingetDependsOn {
  param([Parameter(Mandatory)] [string] $Type, [Parameter(Mandatory)] [string] $Name)
  "[resourceId('$Type','$Name')]"
}

# Reads back the type and name of a dependsOn entry, or $null when it has another form.
function ConvertFrom-WingetDependsOn {
  param([Parameter(Mandatory)] [string] $Value)
  if ($Value -match "^\[resourceId\(\s*'([^']*)'\s*,\s*'([^']*)'\s*\)\]$") {
    return [pscustomobject]@{ Type = $Matches[1]; Name = $Matches[2] }
  }
  $null
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
  param([Parameter(Mandatory)] [string] $Source, [Parameter(Mandatory)] [string] $Id)
  [ordered]@{
    name = Format-WingetPackageName -Source $Source -Id $Id
    type = $script:WingetPackageType
    properties = [ordered]@{ id = $Id; source = $Source }
  }
}
