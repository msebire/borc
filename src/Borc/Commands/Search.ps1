function Invoke-BorcSearch {
  param([Parameter(Mandatory)] $Paths, [Parameter(Mandatory)] [string] $Term)
  $roots = [ordered]@{}
  if ($Paths.Settings) {
    $configText = Read-BorcTextFile -Path (Join-Path $Paths.Settings 'borc\borc.yaml')
    if ($null -ne $configText) {
      foreach ($repo in (ConvertTo-BorcConfig -Text $configText).Recipes) { $roots[$repo.Name] = Join-Path $Paths.Recipes $repo.Name }
    }
    $roots['@local'] = Join-Path $Paths.Settings 'borc\cookbook'
  }

  Start-BorcSteps -Total 2
  Start-BorcStep -Name "Recipes matching '$Term'"
  $found = 0
  foreach ($repo in $roots.Keys) {
    if (-not (Test-Path -LiteralPath $roots[$repo])) {
      if ($repo -ne '@local') { Write-BorcLog -Message "  ($repo is not cloned yet; run borc apply)" }
      continue
    }
    foreach ($match in @(Find-BorcRecipes -Repo $repo -Folder $roots[$repo] -Term $Term)) {
      Write-BorcLog -Message ("  {0,-30} {1}" -f $match.Id, $match.Description)
      $found++
    }
  }
  if ($found -eq 0) { Write-BorcLog -Message '  No recipe matches.' }

  Start-BorcStep -Name "winget packages matching '$Term'"
  $code = Invoke-BorcWinget -Arguments @('search', $Term, '--accept-source-agreements', '--disable-interactivity') -OkCodes @{ $script:WingetNoPackageFound = 'no match' }
  if ($code -ne 0 -and $code -ne $script:WingetNoPackageFound) { return 1 }
  0
}

function Find-BorcRecipes {
  param([Parameter(Mandatory)] [string] $Repo, [Parameter(Mandatory)] [string] $Folder, [Parameter(Mandatory)] [string] $Term)
  foreach ($file in Get-ChildItem -LiteralPath $Folder -Filter '*.yaml' -File | Sort-Object Name) {
    $id = "$Repo/$($file.BaseName)"
    $recipe = ConvertTo-BorcRecipe -Text ([IO.File]::ReadAllText($file.FullName)) -Id $id
    if ($id -like "*$Term*" -or $recipe.Description -like "*$Term*") {
      [pscustomobject]@{ Id = $id; Description = $recipe.Description }
    }
  }
}
