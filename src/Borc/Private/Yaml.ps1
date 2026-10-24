function Import-BorcYamlModule {
  if (-not (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
    Import-Module -Name powershell-yaml -ErrorAction Stop
  }
}

# Parses YAML into ordered dictionaries. Throws with the file name on a syntax error.
function ConvertFrom-BorcYaml {
  param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text, [string] $Source = 'YAML')
  Import-BorcYamlModule
  try {
    ConvertFrom-Yaml -Yaml $Text -Ordered
  } catch {
    throw "${Source}: invalid YAML: $($_.Exception.Message)"
  }
}

function ConvertTo-BorcYaml {
  param([Parameter(Mandatory)] $Data)
  Import-BorcYamlModule
  ConvertTo-Yaml -Data $Data
}

function Test-BorcMap {
  param($Value)
  $Value -is [System.Collections.IDictionary]
}

function Test-BorcList {
  param($Value)
  ($Value -is [System.Collections.IList]) -and -not ($Value -is [System.Collections.IDictionary])
}

# Deep copy of parsed YAML, so the generator never mutates a loaded recipe.
function Copy-BorcYamlNode {
  param($Node)
  if (Test-BorcMap $Node) {
    $copy = [ordered]@{}
    foreach ($key in $Node.Keys) { $copy[$key] = Copy-BorcYamlNode $Node[$key] }
    return $copy
  }
  if (Test-BorcList $Node) {
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Node) { $items.Add((Copy-BorcYamlNode $item)) }
    return , $items
  }
  $Node
}
