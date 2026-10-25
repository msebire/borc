# Writing recipes

This page is for someone writing recipes. A recipe is a WinGet Configuration
file for one tool: it installs the tool and wires it up, typically by
pointing the tool's settings at `BORC_SETTINGS`. Recipes hold no personal
opinions; preferences belong in the user's config repo.

A recipe lives in a recipe repo, as `<name>.yaml` at the root of the repo
(`recipes/node` is `node.yaml` in the repo `recipes`), or in
`borc/cookbook/<name>.yaml` of a config repo for `@local/<name>`.

## The layout comment

Start every recipe with a comment that says what it does and the layout it
expects under `BORC_SETTINGS`, so users know where their files go:

```
# Node.js LTS, with an optional npm cache location and the company registry
# token.
#
# Layout under BORC_SETTINGS:
#   npm/npmrc         user npm configuration, tracked in the config repo
```

## The borc header

Then comes the `borc:` header. borc reads it, then strips it before handing
the file to winget. Every key is optional.

<!-- example: examples/recipe-header.yaml -->
```yaml
borc:
  description: Node.js LTS and npm     # shown by borc search
  requires: [recipes/git]              # recipes that must run first
  reboot: false                        # true: may need a restart, runs first
  parameters:
    npmCache: npm cache location (optional)
  secrets: [NPM_TOKEN]                 # secrets the recipe reads
```

| Key | Meaning |
| --- | --- |
| `description` | One line, searched and shown by `borc search`. |
| `requires` | Recipes that must run before this one, in the same `repo/recipe` form as `borc.yaml`. The user must list them in `borc.yaml` too. |
| `reboot` | `true` for a recipe that may need a restart, such as one enabling Windows features. These recipes run in a first, separate run. A `reboot: true` recipe cannot require one that is not. |
| `parameters` | The optional parameters the recipe accepts, each with a description. |
| `secrets` | The secrets the recipe reads. Users must declare each one in `borc.yaml`. |

Recipes are always named explicitly by users, so there are no name clash
rules and no way for one recipe to replace another.

## The WinGet file rules

Below the borc header, every recipe starts with exactly this header:

<!-- example: examples/fragments/winget-header.yaml -->
```yaml
$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json
metadata:
  winget:
    processor: dscv3
```

winget 1.29 rejects the `aka.ms/dsc/schemas/v3/...` URLs from the DSC
documentation as "not known", and borc refuses a recipe whose header differs.
Then come the `resources`, the units winget runs. These rules were verified
on 2026-10-24 with winget 1.29.380, DSC 3.2.2 and Windows 10 22H2:

- Inline PowerShell uses `Microsoft.DSC.Transitional/PowerShellScript`
  (PowerShell 7) or `Microsoft.DSC.Transitional/WindowsPowerShellScript`
  (Windows PowerShell 5.1).
- A script takes its value through `input`, and declares exactly one
  parameter to receive it.
- `testScript` must output exactly one boolean; any other output fails the
  unit. Without a `testScript`, the resource reports the unit as already in
  place. A `getScript` is optional.
- A unit that needs admin rights sets `metadata: securityContext: elevated`.
  borc merges all recipes into one run, so the user sees a single UAC prompt
  however many units are elevated.
- Apps are installed with `Microsoft.WinGet/Package` units (`id` and
  `source`). `borc upgrade` upgrades these, and `borc uninstall` lists them
  when the user removes the recipe. Add `version` to install a given version
  instead of the latest; `borc upgrade` then leaves the package alone.
- `dependsOn` lists the **names** of the units to apply first. winget applies
  them first even when they come later in the file. The
  `[resourceId('<type>','<name>')]` form shown in the DSC documentation does
  not work with winget: the dependency is reported as "not found within the
  configuration". This was checked with real `winget configure` runs;
  `winget configure test` accepts every form, so it cannot tell.

Within a recipe, a unit can wait for another one by naming it in `dependsOn`:

<!-- example: examples/fragments/depends-on.yaml -->
```yaml
    dependsOn:
      - wsl features
```

- `dependsOn` may only name units of the same recipe. To wait for another
  recipe, use `requires` in the borc header.
- Write the names as they appear in the recipe; borc adds the recipe prefix
  for you (see below).
- borc also accepts `"[resourceId('<type>','<name>')]"` entries in existing
  recipes and turns them into the plain name, but new recipes should use the
  plain name.

Resource names must be unique within the recipe.

## Idempotence and testScript

`borc apply` runs again and again: on every machine, after every pull. A unit
must therefore be safe to run twice. winget runs `testScript` first and skips
`setScript` when it returns `$true`, so a good `testScript` checks exactly
the state `setScript` creates:

<!-- example: examples/fragments/idempotence.yaml -->
```yaml
      testScript: |
        param($path)
        (npm config get cache) -eq $path
      setScript: |
        param($path)
        npm config set cache $path
```

Make sure `testScript` writes nothing else to the output: a stray value from
a command makes the output more than one boolean, and the unit fails. Pipe
noisy commands to `Out-Null`.

## Parameters and placeholders

A unit uses a parameter through a `{{name}}` placeholder in its `input`.
Quote the value, since `{` starts a YAML map:

<!-- example: examples/fragments/placeholder.yaml -->
```yaml
      input: '{{npmCache}}'
```

borc substitutes the user's value before running winget. When the user does
not give the parameter, borc drops every unit whose `input` uses it, so the
tool's default stays untouched. You never have to handle a missing value in
the script.

- Placeholders only work in `input`. Anywhere else, borc reports an error.
- Every placeholder must be declared under `parameters` in the borc header.
- Values are always strings.
- A unit can use several placeholders in one `input`; it is dropped if any
  of them is missing.
- A `dependsOn` entry pointing at a dropped unit is removed.

## Secrets: Get-BorcSecret

A recipe never receives a secret through `input`, because the value would be
written into the generated configuration file. Instead, the script reads it
at run time with `Get-BorcSecret`, a helper borc installs in
`%LOCALAPPDATA%\borc`. Dot-source it first; it works under PowerShell 7 and
Windows PowerShell 5.1, in elevated units too:

<!-- example: examples/fragments/secret.yaml -->
```yaml
      setScript: |
        param($registry)
        . "$env:LOCALAPPDATA\borc\Get-BorcSecret.ps1"
        npm config set "//${registry}/:_authToken" (Get-BorcSecret NPM_TOKEN)
```

List every secret the recipe reads under `secrets` in the borc header. borc
checks that the user declared it in `borc.yaml` and asks for its value before
anything runs. `Get-BorcSecret` throws when the secret is missing.

Never write a secret to the output, a file or a log.

## Settings in BORC_SETTINGS

Scripts find the config repo through the `BORC_SETTINGS` environment
variable. Point the tool at its folder there, through the tool's own
configuration (an environment variable, a config file entry, a command-line
setting).

When an app cannot move its configuration, the recipe may create a symlink
from the default location to `BORC_SETTINGS`. This is a workaround for that
one recipe, not a general mechanism, and it usually needs an elevated unit:
creating symlinks needs admin rights unless Developer Mode is on.

<!-- example: examples/fragments/symlink.yaml -->
```yaml
  - name: app settings link
    type: Microsoft.DSC.Transitional/PowerShellScript
    metadata:
      securityContext: elevated
    properties:
      input: SomeApp
      testScript: |
        param($app)
        $link = Get-Item -LiteralPath (Join-Path $env:APPDATA $app) -ErrorAction SilentlyContinue
        [bool]($link -and $link.LinkType -eq 'SymbolicLink')
      setScript: |
        param($app)
        New-Item -ItemType SymbolicLink -Path (Join-Path $env:APPDATA $app) -Target (Join-Path $env:BORC_SETTINGS $app) | Out-Null
```

Windows features (WSL, Virtual Machine Platform) are enabled inside recipes
too, in an elevated unit of a `reboot: true` recipe, such as the `wsl-ubuntu`
recipe below.

## How borc merges recipes

borc runs one merged configuration rather than one file per recipe. Knowing
what it does helps when reading a log:

- The borc header is stripped.
- Every resource name gets its recipe as a prefix: `npm cache` in
  `recipes/node` becomes `recipes/node: npm cache`. `dependsOn` entries
  inside the recipe are renamed to match: `- npm cache` becomes
  `- 'recipes/node: npm cache'`.
- `requires` becomes a `dependsOn` from every unit of the recipe to every
  unit of the required recipes, by their prefixed names, and recipes are
  ordered so the required ones come first. A required recipe in the other run
  (the reboot run) adds no `dependsOn`: it has already run.
- Recipes marked `reboot: true` run first, in their own run. If Windows then
  needs a restart, `borc apply` stops and asks the user to restart and run it
  again.

The generated files are saved next to the log of the run, in
`%LOCALAPPDATA%\borc\logs`.

## A complete example

This recipe installs Node.js and wires npm to `BORC_SETTINGS`, with an
optional parameter and a secret:

<!-- example: examples/recipes/recipes/node.yaml -->
```yaml
# Node.js LTS, with an optional npm cache location and the company registry
# token.
#
# Layout under BORC_SETTINGS:
#   npm/npmrc         user npm configuration, tracked in the config repo
#
# The borc header. borc reads it and strips it before running winget.
borc:
  description: Node.js LTS and npm, configured from BORC_SETTINGS
  parameters:
    npmCache: npm cache location (optional; npm's default when not given)
  secrets: [NPM_TOKEN]

# The WinGet file header. Copy it exactly: winget 1.29 rejects other schema URLs.
$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json
metadata:
  winget:
    processor: dscv3

resources:
  # Installs Node.js. borc upgrade also upgrades every Microsoft.WinGet/Package
  # unit of a listed recipe.
  - name: node package
    type: Microsoft.WinGet/Package
    properties:
      id: OpenJS.NodeJS.LTS
      source: winget

  # Points npm at the user config tracked in BORC_SETTINGS. input carries one
  # value, received by the script's single param.
  - name: npm userconfig
    type: Microsoft.DSC.Transitional/PowerShellScript
    properties:
      input: npm\npmrc
      testScript: |
        param($relativePath)
        $wanted = Join-Path $env:BORC_SETTINGS $relativePath
        [Environment]::GetEnvironmentVariable('NPM_CONFIG_USERCONFIG', 'User') -eq $wanted
      setScript: |
        param($relativePath)
        $wanted = Join-Path $env:BORC_SETTINGS $relativePath
        [Environment]::SetEnvironmentVariable('NPM_CONFIG_USERCONFIG', $wanted, 'User')

  # Uses the optional parameter. Without npmCache in borc.yaml, borc drops
  # this whole unit and npm keeps its default cache.
  - name: npm cache
    type: Microsoft.DSC.Transitional/PowerShellScript
    properties:
      input: '{{npmCache}}'
      testScript: |
        param($path)
        (npm config get cache) -eq $path
      setScript: |
        param($path)
        npm config set cache $path

  # Reads a secret at run time. The value never appears in this file, in the
  # generated configuration or in the log.
  - name: npm registry token
    type: Microsoft.DSC.Transitional/PowerShellScript
    properties:
      input: npm.example.com
      testScript: |
        param($registry)
        [bool](npm config get "//${registry}/:_authToken")
      setScript: |
        param($registry)
        . "$env:LOCALAPPDATA\borc\Get-BorcSecret.ps1"
        npm config set "//${registry}/:_authToken" (Get-BorcSecret NPM_TOKEN)
```

And this `@local` recipe enables the WSL features in an elevated unit, then
installs Ubuntu once they are on:

<!-- example: examples/settings/borc/cookbook/wsl-ubuntu.yaml -->
```yaml
# Ubuntu on WSL. Enables the Windows features first, which needs admin rights
# and a restart.
#
# Layout under BORC_SETTINGS: none.
borc:
  description: WSL with Ubuntu
  reboot: true
$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json
metadata:
  winget:
    processor: dscv3
resources:
  - name: wsl features
    type: Microsoft.DSC.Transitional/WindowsPowerShellScript
    metadata:
      securityContext: elevated
    properties:
      input: Microsoft-Windows-Subsystem-Linux,VirtualMachinePlatform
      testScript: |
        param($features)
        $states = foreach ($feature in $features -split ',') {
          (Get-WindowsOptionalFeature -Online -FeatureName $feature).State -eq 'Enabled'
        }
        -not ($states -contains $false)
      setScript: |
        param($features)
        foreach ($feature in $features -split ',') {
          Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
        }
  - name: ubuntu package
    type: Microsoft.WinGet/Package
    dependsOn:
      - wsl features
    properties:
      id: Canonical.Ubuntu.2404
      source: winget
```

## Errors

borc checks every listed recipe before anything runs. Messages about a
recipe file start with `recipe <id>:`.

| Message | Meaning |
| --- | --- |
| `invalid YAML: ...` | The file is not valid YAML. The message gives the line. |
| `expected a WinGet Configuration document.` | The file is a list or a single value instead of keys. |
| `the file must start with $schema: ... and metadata: winget: processor: dscv3.` | The WinGet header differs from the verified one, often an `aka.ms` schema URL. |
| `unknown top-level key '<key>'.` | Only `borc`, `$schema`, `metadata` and `resources` are allowed. |
| `the borc header must be a map.` | `borc:` holds a list or a single value. |
| `unknown key '<key>' in the borc header.` | Only `description`, `requires`, `reboot`, `parameters` and `secrets` are allowed. |
| `reboot must be true or false.` | Another value under `reboot`. |
| `requires must be a list, for example requires: [a, b].` | The same for `secrets`. |
| `'<value>' is not valid in requires.` | A `requires` entry not in the `repo/recipe` form, or a `secrets` entry that is not a valid name. |
| `parameters must map each parameter name to a description.` | `parameters` holds a list or a single value. |
| `'<name>' is not a valid parameter name (letters, digits and '_').` | Rename the parameter. |
| `resources must be a list.` | `resources` holds something other than a list. |
| `every resource needs a name and a type.` | A unit without `name` or `type`. |
| `two resources are named '<name>'.` | Names must be unique within the recipe. |
| `dependsOn of resource '<name>' must be a list of resource names.` | `dependsOn` holds a single value or something other than text. |
| `resource '<name>' depends on '<other>', which is not a resource of this recipe. Use requires to wait for another recipe.` | A typo in the name, or a unit of another recipe: use `requires` for that. |
| `resource '<name>' depends on itself.` | Remove the entry. |
| `resource '<name>' uses {{<p>}}, which the borc header does not declare under parameters.` | Declare the parameter, or fix the placeholder. |
| `resource '<name>' uses {{<p>}} outside input. Placeholders only work in input.` | Move the value into `input`. |
