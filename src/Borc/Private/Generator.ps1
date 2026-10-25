# Builds the WinGet Configuration documents borc runs: recipes marked
# reboot: true in a first run, then everything else in one merged run.

function New-BorcRunDocuments {
  param([Parameter(Mandatory)] $Plan)
  $dropped = [System.Collections.Generic.List[string]]::new()
  $rebootIds = @($Plan.Order | Where-Object { $Plan.Recipes[$_].Reboot })
  $mainIds = @($Plan.Order | Where-Object { -not $Plan.Recipes[$_].Reboot })

  $rebootUnits = @(Get-BorcRunUnits -Plan $Plan -Ids $rebootIds -Dropped $dropped)
  $mainUnits = @(Get-BorcPackageUnits -Config $Plan.Config) + @(Get-BorcRunUnits -Plan $Plan -Ids $mainIds -Dropped $dropped)

  [pscustomobject]@{
    Reboot = New-BorcDocument -Units $rebootUnits
    Main = New-BorcDocument -Units $mainUnits
    Dropped = @($dropped)
  }
}

# One document per recipe, then one for the plain packages: used by
# apply --debug and by install. requires becomes run order instead of dependsOn.
function New-BorcSingleDocuments {
  param([Parameter(Mandatory)] $Plan, [string[]] $Ids = $Plan.Order, [switch] $IncludePackages)
  $dropped = [System.Collections.Generic.List[string]]::new()
  $ordered = @($Plan.Order | Where-Object { $_ -in $Ids -and $Plan.Recipes[$_].Reboot }) + @($Plan.Order | Where-Object { $_ -in $Ids -and -not $Plan.Recipes[$_].Reboot })
  foreach ($id in $ordered) {
    [pscustomobject]@{ Name = $id; Reboot = $Plan.Recipes[$id].Reboot; Document = New-BorcDocument -Units @(Get-BorcRunUnits -Plan $Plan -Ids @($id) -Dropped $dropped) }
  }
  if ($IncludePackages) {
    [pscustomobject]@{ Name = 'plain packages'; Reboot = $false; Document = New-BorcDocument -Units @(Get-BorcPackageUnits -Config $Plan.Config) }
  }
}

function New-BorcDocument {
  param([object[]] $Units = @())
  if ($Units.Count -eq 0) { return $null }
  $document = New-WingetDocumentHeader
  $document['resources'] = [System.Collections.Generic.List[object]]::new()
  foreach ($unit in $Units) { $document['resources'].Add($unit) }
  $document
}

function Get-BorcPackageUnits {
  param([Parameter(Mandatory)] $Config)
  foreach ($app in $Config.Apps) {
    if ($app.Kind -in 'winget', 'msstore') { New-WingetPackageUnit -Source $app.Kind -Id $app.Id -Version $app.Version }
  }
}

# Units of the given recipes, in order. Each recipe's units depend on the kept
# units of the recipes it requires, when those are part of the same run.
function Get-BorcRunUnits {
  param([Parameter(Mandatory)] $Plan, [string[]] $Ids, [Parameter(Mandatory)] [AllowEmptyCollection()] $Dropped)
  $kept = @{}
  foreach ($id in $Ids) {
    $recipe = $Plan.Recipes[$id]
    $app = $Plan.Config.Apps | Where-Object { $_.Kind -eq 'recipe' -and $_.Id -eq $id } | Select-Object -First 1
    $parameters = if ($app) { $app.Parameters } else { [ordered]@{} }
    $requiredUnits = @(foreach ($required in $recipe.Requires) { if ($kept.ContainsKey($required)) { $kept[$required] } })
    $units = @(ConvertTo-BorcRecipeUnits -Recipe $recipe -Parameters $parameters -RequiredUnits $requiredUnits -Dropped $Dropped)
    $kept[$id] = @($units | ForEach-Object { [pscustomobject]@{ Type = $_['type']; Name = $_['name'] } })
    $units
  }
}

function ConvertTo-BorcRecipeUnits {
  param(
    [Parameter(Mandatory)] $Recipe,
    [Parameter(Mandatory)] [System.Collections.IDictionary] $Parameters,
    [object[]] $RequiredUnits = @(),
    [Parameter(Mandatory)] [AllowEmptyCollection()] $Dropped
  )
  $droppedNames = @{}
  foreach ($resource in $Recipe.Resources) {
    $missing = @(Get-BorcMissingParameters -Resource $resource -Parameters $Parameters)
    if ($missing.Count -gt 0) {
      $droppedNames[$resource['name']] = $true
      $Dropped.Add("$($Recipe.Id): '$($resource['name'])' skipped, no value for $($missing -join ', ')")
    }
  }
  $ownNames = @($Recipe.Resources | ForEach-Object { $_['name'] })

  foreach ($resource in $Recipe.Resources) {
    if ($droppedNames.ContainsKey($resource['name'])) { continue }
    $unit = Copy-BorcYamlNode $resource
    if ((Test-BorcMap $unit['properties']) -and $unit['properties'].Contains('input')) {
      $unit['properties']['input'] = Expand-BorcPlaceholders -Node $unit['properties']['input'] -Parameters $Parameters
    }
    $unit['name'] = Format-WingetResourceName -RecipeId $Recipe.Id -Name $resource['name']
    $dependsOn = @(Get-BorcUnitDependsOn -Unit $unit -RecipeId $Recipe.Id -OwnNames $ownNames -DroppedNames $droppedNames -RequiredUnits $RequiredUnits)
    $unit.Remove('dependsOn')
    if ($dependsOn.Count -gt 0) { $unit = Add-BorcDependsOn -Unit $unit -DependsOn $dependsOn }
    $unit
  }
}

function Get-BorcMissingParameters {
  param([Parameter(Mandatory)] $Resource, [Parameter(Mandatory)] [System.Collections.IDictionary] $Parameters)
  $properties = $Resource['properties']
  if (-not (Test-BorcMap $properties)) { return }
  Get-BorcPlaceholders -Node $properties['input'] | Where-Object { -not $Parameters.Contains($_) }
}

function Expand-BorcPlaceholders {
  param($Node, [Parameter(Mandatory)] [System.Collections.IDictionary] $Parameters)
  if ($Node -is [string]) {
    return [regex]::Replace($Node, $script:BorcPlaceholderPattern, { param($match) $Parameters[$match.Groups[1].Value] })
  }
  if (Test-BorcMap $Node) {
    $copy = [ordered]@{}
    foreach ($key in $Node.Keys) { $copy[$key] = Expand-BorcPlaceholders -Node $Node[$key] -Parameters $Parameters }
    return $copy
  }
  if (Test-BorcList $Node) {
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Node) { $items.Add((Expand-BorcPlaceholders -Node $item -Parameters $Parameters)) }
    return , $items
  }
  $Node
}

# The recipe's own dependsOn entries, renamed to the prefixed names (entries on
# dropped units are removed), followed by every kept unit of required recipes.
# Recipe checks guarantee that every own entry names a unit of the recipe.
function Get-BorcUnitDependsOn {
  param($Unit, [string] $RecipeId, [string[]] $OwnNames, [hashtable] $DroppedNames, [object[]] $RequiredUnits)
  foreach ($entry in @($Unit['dependsOn'] | Where-Object { $null -ne $_ })) {
    $name = ConvertFrom-WingetDependsOn -Value "$entry"
    if ($name -notin $OwnNames -or $DroppedNames.ContainsKey($name)) { continue }
    Format-WingetDependsOn -Name (Format-WingetResourceName -RecipeId $RecipeId -Name $name)
  }
  foreach ($required in $RequiredUnits) {
    Format-WingetDependsOn -Name $required.Name
  }
}

# Puts dependsOn right after type, where DSC documents usually have it.
function Add-BorcDependsOn {
  param([Parameter(Mandatory)] $Unit, [Parameter(Mandatory)] [string[]] $DependsOn)
  $result = [ordered]@{}
  foreach ($key in $Unit.Keys) {
    $result[$key] = $Unit[$key]
    if ($key -eq 'type') { $result['dependsOn'] = [System.Collections.Generic.List[object]]::new([object[]]$DependsOn) }
  }
  if (-not $result.Contains('dependsOn')) { $result['dependsOn'] = [System.Collections.Generic.List[object]]::new([object[]]$DependsOn) }
  $result
}

function Write-BorcDocument {
  param([Parameter(Mandatory)] $Document, [Parameter(Mandatory)] [string] $Path)
  $yaml = (ConvertTo-BorcYaml -Data $Document) -replace "`r`n", "`n"
  [IO.File]::WriteAllText($Path, $yaml, [Text.UTF8Encoding]::new($false))
}
