# Loads borc.yaml and every recipe it lists, then checks them against each
# other. The result holds every problem found, so nothing runs on a broken plan.

function Read-BorcTextFile {
  param([Parameter(Mandatory)] [string] $Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  [IO.File]::ReadAllText($Path)
}

function Get-BorcPlan {
  param(
    [Parameter(Mandatory)] [string] $SettingsRoot,
    [Parameter(Mandatory)] [string] $RecipesRoot,
    # Reads a file by path and returns $null when it does not exist; --what-if
    # passes a reader that looks at the fetched commits instead of the disk.
    [scriptblock] $ReadFile = { param($Path) Read-BorcTextFile -Path $Path },
    # Extra apps entries, as install adds them before editing borc.yaml.
    [object[]] $ExtraApps = @()
  )
  $configPath = Join-Path $SettingsRoot 'borc\borc.yaml'
  $text = & $ReadFile $configPath
  if ($null -eq $text) {
    return [pscustomobject]@{ Config = $null; Recipes = [ordered]@{}; Order = @(); Errors = @("borc.yaml not found: $configPath") }
  }
  $config = ConvertTo-BorcConfig -Text $text -Source 'borc.yaml'
  foreach ($app in $ExtraApps) {
    if (-not ($config.Apps | Where-Object { $_.Kind -eq $app.Kind -and $_.Id -eq $app.Id })) { $config.Apps.Add($app) }
  }
  $errors = [System.Collections.Generic.List[string]]::new()
  foreach ($message in $config.Errors) { $errors.Add($message) }

  $recipes = [ordered]@{}
  foreach ($app in @($config.Apps | Where-Object Kind -EQ 'recipe')) {
    $path = Resolve-BorcRecipePath -Id $app.Id -RecipesRoot $RecipesRoot -SettingsRoot $SettingsRoot
    $recipeText = & $ReadFile $path
    if ($null -eq $recipeText) {
      $errors.Add("recipe $($app.Id) not found: $path")
      continue
    }
    $recipe = ConvertTo-BorcRecipe -Text $recipeText -Id $app.Id
    $recipe | Add-Member -NotePropertyName Path -NotePropertyValue $path
    foreach ($message in $recipe.Errors) { $errors.Add($message) }
    Test-BorcAppAgainstRecipe -App $app -Recipe $recipe -Config $config -Errors $errors
    $recipes[$app.Id] = $recipe
  }
  Test-BorcRequires -Recipes $recipes -Errors $errors
  $order = @(Get-BorcRecipeOrder -Recipes $recipes -Errors $errors)

  [pscustomobject]@{ Config = $config; Recipes = $recipes; Order = $order; Errors = @($errors) }
}

function Test-BorcAppAgainstRecipe {
  param([Parameter(Mandatory)] $App, [Parameter(Mandatory)] $Recipe, [Parameter(Mandatory)] $Config, [Parameter(Mandatory)] [AllowEmptyCollection()] $Errors)
  foreach ($name in $App.Parameters.Keys) {
    if (-not $Recipe.Parameters.Contains($name)) {
      $declared = if ($Recipe.Parameters.Count) { $Recipe.Parameters.Keys -join ', ' } else { 'none' }
      $Errors.Add("borc.yaml: recipe $($App.Id) has no parameter '$name' (it declares: $declared).")
    }
  }
  foreach ($secret in $Recipe.Secrets) {
    if (-not $Config.Secrets.Contains($secret)) {
      $Errors.Add("borc.yaml: recipe $($App.Id) uses the secret $secret, which is not declared under secrets.")
    }
  }
}

function Test-BorcRequires {
  param([Parameter(Mandatory)] $Recipes, [Parameter(Mandatory)] [AllowEmptyCollection()] $Errors)
  foreach ($recipe in $Recipes.Values) {
    foreach ($required in $recipe.Requires) {
      if (-not $Recipes.Contains($required)) {
        $Errors.Add("recipe $($recipe.Id) requires $required, which borc.yaml does not list under apps.")
      } elseif ($recipe.Reboot -and -not $Recipes[$required].Reboot) {
        $Errors.Add("recipe $($recipe.Id) is marked reboot: true and runs first, so it cannot require $required, which is not.")
      }
    }
  }
}

# Recipes in an order where each one comes after the recipes it requires;
# otherwise the borc.yaml order is kept.
function Get-BorcRecipeOrder {
  param([Parameter(Mandatory)] $Recipes, [Parameter(Mandatory)] [AllowEmptyCollection()] $Errors)
  $state = @{}
  $order = [System.Collections.Generic.List[string]]::new()
  foreach ($id in $Recipes.Keys) {
    Add-BorcRecipeInOrder -Id $id -Recipes $Recipes -State $state -Order $order -Errors $Errors -Path @()
  }
  $order
}

function Add-BorcRecipeInOrder {
  param($Id, $Recipes, $State, $Order, $Errors, [string[]] $Path)
  if ($State[$Id] -eq 'done' -or -not $Recipes.Contains($Id)) { return }
  if ($State[$Id] -eq 'visiting') {
    $Errors.Add("recipes require each other in a loop: $((@($Path) + $Id) -join ' -> ').")
    return
  }
  $State[$Id] = 'visiting'
  foreach ($required in $Recipes[$Id].Requires) {
    Add-BorcRecipeInOrder -Id $required -Recipes $Recipes -State $State -Order $Order -Errors $Errors -Path (@($Path) + $Id)
  }
  $State[$Id] = 'done'
  $Order.Add($Id)
}
