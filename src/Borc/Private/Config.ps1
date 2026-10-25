# Reads borc.yaml into a config object. Problems are collected in Errors rather
# than thrown, so every problem is reported at once before anything runs.

$script:BorcNamePattern = '^[A-Za-z0-9._-]+$'
$script:BorcRecipeIdPattern = '^(@local|[A-Za-z0-9._-]+)/[A-Za-z0-9._-]+$'
$script:BorcSymbolPattern = '^[A-Za-z_][A-Za-z0-9_]*$'
$script:BorcAppKinds = @('winget', 'msstore', 'recipe')

function Get-BorcRepoName {
  param([Parameter(Mandatory)] [string] $Url)
  $last = ($Url.TrimEnd('/', '\') -split '[/\\:]')[-1]
  $last -replace '\.git$', ''
}

function ConvertTo-BorcConfig {
  param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text, [string] $Source = 'borc.yaml')
  $errors = [System.Collections.Generic.List[string]]::new()
  $config = [pscustomobject]@{
    Source = $Source
    Recipes = [System.Collections.Generic.List[object]]::new()
    Apps = [System.Collections.Generic.List[object]]::new()
    Secrets = [ordered]@{}
    Errors = $errors
  }
  try {
    $document = ConvertFrom-BorcYaml -Text $Text -Source $Source
  } catch {
    $errors.Add($_.Exception.Message)
    return $config
  }
  if ($null -eq $document) { return $config }
  if (-not (Test-BorcMap $document)) {
    $errors.Add("${Source}: expected keys recipes, apps and secrets at the top level.")
    return $config
  }
  foreach ($key in $document.Keys) {
    if ($key -notin 'recipes', 'apps', 'secrets') { $errors.Add("${Source}: unknown key '$key'. Expected recipes, apps or secrets.") }
  }
  Read-BorcConfigRecipes -Node $document['recipes'] -Config $config
  Read-BorcConfigSecrets -Node $document['secrets'] -Config $config
  Read-BorcConfigApps -Node $document['apps'] -Config $config
  $config
}

function Read-BorcConfigRecipes {
  param($Node, [Parameter(Mandatory)] $Config)
  if ($null -eq $Node) { return }
  $source = $Config.Source
  if (-not (Test-BorcList $Node)) { $Config.Errors.Add("${source}: recipes must be a list of '- repo: <url>' entries."); return }
  foreach ($entry in $Node) {
    if (-not (Test-BorcMap $entry) -or -not ($entry['repo'] -is [string]) -or -not $entry['repo']) {
      $Config.Errors.Add("${source}: each recipes entry needs a repo URL.")
      continue
    }
    foreach ($key in $entry.Keys) {
      if ($key -notin 'repo', 'alias') { $Config.Errors.Add("${source}: unknown key '$key' in the recipes entry for $($entry['repo']).") }
    }
    $name = if ($entry.Contains('alias')) { "$($entry['alias'])" } else { Get-BorcRepoName -Url $entry['repo'] }
    if ($name -notmatch $script:BorcNamePattern) {
      $Config.Errors.Add("${source}: '$name' is not a valid recipe repo name or alias (letters, digits, '.', '_' and '-').")
      continue
    }
    if (@($Config.Recipes | Where-Object Name -EQ $name).Count -gt 0) {
      $Config.Errors.Add("${source}: two recipe repos are named '$name'. Give one of them an alias.")
      continue
    }
    $Config.Recipes.Add([pscustomobject]@{ Name = $name; Url = $entry['repo'] })
  }
}

function Read-BorcConfigSecrets {
  param($Node, [Parameter(Mandatory)] $Config)
  if ($null -eq $Node) { return }
  $source = $Config.Source
  if (-not (Test-BorcMap $Node)) { $Config.Errors.Add("${source}: secrets must map each secret name to a short description."); return }
  foreach ($name in $Node.Keys) {
    if ($name -notmatch $script:BorcSymbolPattern) {
      $Config.Errors.Add("${source}: '$name' is not a valid secret name (letters, digits and '_').")
      continue
    }
    $Config.Secrets[$name] = "$($Node[$name])"
  }
}

function Read-BorcConfigApps {
  param($Node, [Parameter(Mandatory)] $Config)
  if ($null -eq $Node) { return }
  $source = $Config.Source
  if (-not (Test-BorcList $Node)) { $Config.Errors.Add("${source}: apps must be a list."); return }
  foreach ($entry in $Node) {
    $app = ConvertTo-BorcApp -Entry $entry -Config $Config
    if ($null -eq $app) { continue }
    if (@($Config.Apps | Where-Object { $_.Kind -eq $app.Kind -and $_.Id -eq $app.Id }).Count -gt 0) {
      $Config.Errors.Add("${source}: $($app.Kind) $($app.Id) is listed twice under apps.")
      continue
    }
    $Config.Apps.Add($app)
  }
}

function ConvertTo-BorcApp {
  param($Entry, [Parameter(Mandatory)] $Config)
  $source = $Config.Source
  $kinds = @(if (Test-BorcMap $Entry) { $Entry.Keys | Where-Object { $_ -in $script:BorcAppKinds } })
  if ($kinds.Count -ne 1) {
    $Config.Errors.Add("${source}: each apps entry needs exactly one of winget, msstore or recipe.")
    return $null
  }
  $kind = $kinds[0]
  $id = $Entry[$kind]
  if (-not ($id -is [string]) -or -not $id) {
    $Config.Errors.Add("${source}: the $kind entry under apps needs a value.")
    return $null
  }
  foreach ($key in $Entry.Keys) {
    if ($key -eq $kind) { continue }
    if ($key -eq 'parameters' -and $kind -eq 'recipe') { continue }
    if ($key -eq 'version' -and $kind -eq 'winget') { continue }
    $Config.Errors.Add("${source}: unknown key '$key' in the apps entry for $id.")
  }
  if ($kind -eq 'recipe' -and -not (Test-BorcRecipeReference -Id $id -Config $Config)) { return $null }
  $parameters = [ordered]@{}
  if ($kind -eq 'recipe' -and $Entry.Contains('parameters')) {
    $parameters = Read-BorcAppParameters -Node $Entry['parameters'] -RecipeId $id -Config $Config
  }
  $version = ''
  if ($kind -eq 'winget' -and $Entry.Contains('version')) {
    $value = $Entry['version']
    # YAML reads 1.7 as a number, which would come back as "1.7" or worse.
    if ($value -is [string] -and $value) { $version = $value }
    else { $Config.Errors.Add("${source}: version of $id must be a string. Quote it, for example version: '$value'.") }
  }
  [pscustomobject]@{ Kind = $kind; Id = $id; Parameters = $parameters; Version = $version }
}

function Test-BorcRecipeReference {
  param([Parameter(Mandatory)] [string] $Id, [Parameter(Mandatory)] $Config)
  $source = $Config.Source
  if ($Id -notmatch $script:BorcRecipeIdPattern) {
    $Config.Errors.Add("${source}: '$Id' is not a recipe reference. Use repo/recipe or @local/<name>.")
    return $false
  }
  $repo = ($Id -split '/')[0]
  if ($repo -ne '@local' -and @($Config.Recipes | Where-Object Name -EQ $repo).Count -eq 0) {
    $Config.Errors.Add("${source}: recipe $Id refers to the repo '$repo', which is not listed under recipes.")
    return $false
  }
  $true
}

function Read-BorcAppParameters {
  param($Node, [Parameter(Mandatory)] [string] $RecipeId, [Parameter(Mandatory)] $Config)
  $source = $Config.Source
  $parameters = [ordered]@{}
  if ($null -eq $Node) { return $parameters }
  if (-not (Test-BorcMap $Node)) {
    $Config.Errors.Add("${source}: parameters of $RecipeId must map each parameter name to a value.")
    return $parameters
  }
  foreach ($name in $Node.Keys) {
    $value = $Node[$name]
    if (-not ($value -is [string])) {
      $Config.Errors.Add("${source}: parameter $name of $RecipeId must be a string. Quote the value, for example $name`: '$value'.")
      continue
    }
    $parameters[$name] = $value
  }
  $parameters
}
