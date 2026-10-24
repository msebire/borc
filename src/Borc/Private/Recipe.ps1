# Reads one recipe: the borc header, the WinGet header check and the resources.

$script:BorcPlaceholderPattern = '\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}'
$script:BorcHeaderKeys = @('description', 'requires', 'reboot', 'parameters', 'secrets')

function Resolve-BorcRecipePath {
  param(
    [Parameter(Mandatory)] [string] $Id,
    [Parameter(Mandatory)] [string] $RecipesRoot,
    [Parameter(Mandatory)] [string] $SettingsRoot
  )
  $repo, $name = $Id -split '/', 2
  if ($repo -eq '@local') {
    return Join-Path $SettingsRoot "borc\cookbook\$name.yaml"
  }
  Join-Path $RecipesRoot "$repo\$name.yaml"
}

function ConvertTo-BorcRecipe {
  param(
    [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
    [Parameter(Mandatory)] [string] $Id
  )
  $errors = [System.Collections.Generic.List[string]]::new()
  $recipe = [pscustomobject]@{
    Id = $Id
    Description = ''
    Requires = @()
    Reboot = $false
    Parameters = [ordered]@{}
    Secrets = @()
    Resources = @()
    Errors = $errors
  }
  try {
    $document = ConvertFrom-BorcYaml -Text $Text -Source "recipe $Id"
  } catch {
    $errors.Add($_.Exception.Message)
    return $recipe
  }
  if (-not (Test-BorcMap $document)) {
    $errors.Add("recipe ${Id}: expected a WinGet Configuration document.")
    return $recipe
  }
  foreach ($key in $document.Keys) {
    if ($key -notin 'borc', '$schema', 'metadata', 'resources') { $errors.Add("recipe ${Id}: unknown top-level key '$key'.") }
  }
  if (-not (Test-WingetDocumentHeader -Document $document)) {
    $errors.Add("recipe ${Id}: the file must start with `$schema: $script:WingetSchemaUrl and metadata: winget: processor: $script:WingetProcessor.")
  }
  Read-BorcRecipeHeader -Node $document['borc'] -Recipe $recipe
  Read-BorcRecipeResources -Node $document['resources'] -Recipe $recipe
  $recipe
}

function Read-BorcRecipeHeader {
  param($Node, [Parameter(Mandatory)] $Recipe)
  if ($null -eq $Node) { return }
  $id = $Recipe.Id
  if (-not (Test-BorcMap $Node)) { $Recipe.Errors.Add("recipe ${id}: the borc header must be a map."); return }
  foreach ($key in $Node.Keys) {
    if ($key -notin $script:BorcHeaderKeys) { $Recipe.Errors.Add("recipe ${id}: unknown key '$key' in the borc header.") }
  }
  if ($Node.Contains('description')) { $Recipe.Description = "$($Node['description'])" }
  if ($Node.Contains('reboot')) {
    if ($Node['reboot'] -is [bool]) { $Recipe.Reboot = $Node['reboot'] } else { $Recipe.Errors.Add("recipe ${id}: reboot must be true or false.") }
  }
  $Recipe.Requires = @(Read-BorcNameList -Node $Node['requires'] -What 'requires' -Pattern $script:BorcRecipeIdPattern -Recipe $Recipe)
  $Recipe.Secrets = @(Read-BorcNameList -Node $Node['secrets'] -What 'secrets' -Pattern $script:BorcSymbolPattern -Recipe $Recipe)
  if ($null -ne $Node['parameters']) {
    if (Test-BorcMap $Node['parameters']) {
      foreach ($name in $Node['parameters'].Keys) {
        if ($name -match $script:BorcSymbolPattern) { $Recipe.Parameters[$name] = "$($Node['parameters'][$name])" }
        else { $Recipe.Errors.Add("recipe ${id}: '$name' is not a valid parameter name (letters, digits and '_').") }
      }
    } else {
      $Recipe.Errors.Add("recipe ${id}: parameters must map each parameter name to a description.")
    }
  }
}

function Read-BorcNameList {
  param($Node, [Parameter(Mandatory)] [string] $What, [Parameter(Mandatory)] [string] $Pattern, [Parameter(Mandatory)] $Recipe)
  if ($null -eq $Node) { return }
  if (-not (Test-BorcList $Node)) { $Recipe.Errors.Add("recipe $($Recipe.Id): $What must be a list, for example $What`: [a, b]."); return }
  foreach ($item in $Node) {
    if ($item -is [string] -and $item -match $Pattern) { $item }
    else { $Recipe.Errors.Add("recipe $($Recipe.Id): '$item' is not valid in $What.") }
  }
}

function Read-BorcRecipeResources {
  param($Node, [Parameter(Mandatory)] $Recipe)
  $id = $Recipe.Id
  if ($null -eq $Node) { return }
  if (-not (Test-BorcList $Node)) { $Recipe.Errors.Add("recipe ${id}: resources must be a list."); return }
  $names = @{}
  $resources = foreach ($resource in $Node) {
    if (-not (Test-BorcMap $resource) -or -not ($resource['name'] -is [string]) -or -not ($resource['type'] -is [string])) {
      $Recipe.Errors.Add("recipe ${id}: every resource needs a name and a type.")
      continue
    }
    $name = $resource['name']
    if ($name.Contains("'")) { $Recipe.Errors.Add("recipe ${id}: resource name '$name' must not contain a single quote.") }
    if ($names.ContainsKey($name)) { $Recipe.Errors.Add("recipe ${id}: two resources are named '$name'.") }
    $names[$name] = $true
    Test-BorcResourcePlaceholders -Resource $resource -Recipe $Recipe
    $resource
  }
  $Recipe.Resources = @($resources)
}

# Placeholders are only allowed in input, and must be declared in the header.
function Test-BorcResourcePlaceholders {
  param([Parameter(Mandatory)] $Resource, [Parameter(Mandatory)] $Recipe)
  $id = $Recipe.Id
  $name = $Resource['name']
  $properties = $Resource['properties']
  $unitInput = if (Test-BorcMap $properties) { $properties['input'] } else { $null }
  foreach ($placeholder in Get-BorcPlaceholders -Node $unitInput) {
    if (-not $Recipe.Parameters.Contains($placeholder)) {
      $Recipe.Errors.Add("recipe ${id}: resource '$name' uses {{$placeholder}}, which the borc header does not declare under parameters.")
    }
  }
  $outside = Copy-BorcYamlNode $Resource
  if (Test-BorcMap $outside['properties']) { $outside['properties'].Remove('input') }
  foreach ($placeholder in Get-BorcPlaceholders -Node $outside) {
    $Recipe.Errors.Add("recipe ${id}: resource '$name' uses {{$placeholder}} outside input. Placeholders only work in input.")
  }
}

function Get-BorcPlaceholders {
  param($Node)
  $found = [System.Collections.Generic.List[string]]::new()
  Add-BorcPlaceholders -Node $Node -Found $found
  $found | Select-Object -Unique
}

function Add-BorcPlaceholders {
  param($Node, [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[string]] $Found)
  if ($Node -is [string]) {
    foreach ($match in [regex]::Matches($Node, $script:BorcPlaceholderPattern)) { $Found.Add($match.Groups[1].Value) }
  } elseif (Test-BorcMap $Node) {
    foreach ($value in $Node.Values) { Add-BorcPlaceholders -Node $value -Found $Found }
  } elseif (Test-BorcList $Node) {
    foreach ($item in $Node) { Add-BorcPlaceholders -Node $item -Found $Found }
  }
}

# Winget packages a recipe installs, as source and id pairs.
function Get-BorcRecipePackages {
  param([Parameter(Mandatory)] $Recipe)
  foreach ($resource in $Recipe.Resources) {
    if ($resource['type'] -ne $script:WingetPackageType) { continue }
    $properties = $resource['properties']
    if (-not (Test-BorcMap $properties) -or -not $properties['id']) { continue }
    $source = if ($properties['source']) { "$($properties['source'])" } else { 'winget' }
    [pscustomobject]@{ Source = $source; Id = "$($properties['id'])" }
  }
}
