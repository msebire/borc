# Writing recipes

This page is for someone writing recipes. A recipe is a WinGet Configuration
file for one tool: it installs the tool and wires it up, typically by
pointing the tool's settings at `BORC_SETTINGS`. Recipes hold no personal
opinions; preferences belong in the user's config repo.

A recipe lives in a recipe repo, as `<name>.yaml` at the root of the repo
(`recipes/node` is `node.yaml` in the repo `recipes`), or in
`borc/cookbook/<name>.yaml` of a config repo for `@local/<name>`.

The starter template includes a small working recipe to copy,
`borc/cookbook/hello-borc.yaml`, with every option described in its comments.

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

## The BORC header

Then comes the `borc:` header. BORC reads it, then strips it before handing
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
| `upgrade` | The units only `borc upgrade` runs, to update what the recipe installs outside winget. See [upgrades outside winget](#upgrades-outside-winget). |

Recipes are always named explicitly by users, so there are no name clash
rules and no way for one recipe to replace another.

## The WinGet file rules

Below the BORC header, every recipe starts with exactly this header:

<!-- example: examples/fragments/winget-header.yaml -->
```yaml
$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json
metadata:
  winget:
    processor: dscv3
```

winget 1.29 rejects the `aka.ms/dsc/schemas/v3/...` URLs from the DSC
documentation as "not known", and BORC refuses a recipe whose header differs.
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
  BORC merges all recipes into one run, so the user sees a single UAC prompt
  however many units are elevated. A `reboot: true` recipe runs on its own, so
  an elevated unit in one adds a second prompt, on every `borc apply`, even when
  nothing has to change: winget needs the rights to run its `testScript`.
- Apps are installed with `Microsoft.WinGet/Package` units (`id` and
  `source`). `borc upgrade` upgrades these, with admin rights when the unit sets
  `securityContext: elevated`, and `borc uninstall` lists them when the user
  removes the recipe. Add `version` to install a given version
  instead of the latest; `borc upgrade` then leaves the package alone. BORC sets
  `acceptAgreements: true` on these units, unless the recipe sets it itself: a
  package with agreements fails without it.
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
  recipe, use `requires` in the BORC header.
- Write the names as they appear in the recipe; BORC adds the recipe prefix
  for you (see below).
- BORC also accepts `"[resourceId('<type>','<name>')]"` entries in existing
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

BORC substitutes the user's value before running winget. When the user does
not give the parameter, BORC drops every unit whose `input` uses it, so the
tool's default stays untouched. You never have to handle a missing value in
the script.

- Placeholders only work in `input`. Anywhere else, BORC reports an error.
- Every placeholder must be declared under `parameters` in the BORC header.
- Values are always strings.
- A unit can use several placeholders in one `input`; it is dropped if any
  of them is missing.
- A `dependsOn` entry pointing at a dropped unit is removed.

## Secrets: Get-BorcSecret

A recipe never receives a secret through `input`, because the value would be
written into the generated configuration file. Instead, the script reads it
at run time with `Get-BorcSecret`, a helper BORC installs in
`%LOCALAPPDATA%\borc`. Dot-source it first; it works under PowerShell 7 and
Windows PowerShell 5.1, in elevated units too:

<!-- example: examples/fragments/secret.yaml -->
```yaml
      setScript: |
        param($registry)
        . "$env:LOCALAPPDATA\borc\Get-BorcSecret.ps1"
        npm config set "//${registry}/:_authToken" (Get-BorcSecret NPM_TOKEN)
```

List every secret the recipe reads under `secrets` in the BORC header. BORC
checks that the user declared it in `borc.yaml` and asks for its value before
anything runs. `Get-BorcSecret` throws when the secret is missing.

Never write a secret to the output, a file or a log.

## Upgrades outside winget

`borc upgrade` upgrades the `Microsoft.WinGet/Package` units of a recipe. An app
the recipe installs another way, such as a .NET global tool, needs an upgrade
unit: a script unit the BORC header names under `upgrade`.

- Only `borc upgrade` runs it, after the winget packages, in one
  `winget configure` with the upgrade units of every listed recipe.
  `borc apply`, `borc install` and `apply --what-if --check` leave it out.
- Its `testScript` says whether the app is up to date. It returns `$true` when
  there is nothing to do, also when the app is not installed: installing it is
  `borc apply`'s job. winget then skips the `setScript`.
- `borc upgrade --what-if --check` runs that test, so it says whether an update
  is available.
- It follows the rules of any unit: `input` and its parameters, `Get-BorcSecret`,
  `securityContext: elevated`.
- No other unit may depend on it, and it cannot be a package unit.
- Closing or restarting the app is the recipe's business. Prefer failing with a
  clear message to closing an app that may hold unsaved work. An app the
  `setScript` starts keeps running after winget ends; never start it with
  `-WindowStyle Hidden`, which Windows applies to the app's own window.

<!-- example: examples/recipes/recipes/codealta.yaml -->
```yaml
# CodeAlta, a .NET global tool, with the .NET 10 SDK it needs. winget does not
# manage the tool, so an upgrade unit updates it.
#
# Layout under BORC_SETTINGS: none.
borc:
  description: CodeAlta desktop, with the .NET 10 SDK it needs
  upgrade: [codealta update]
$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json
metadata:
  winget:
    processor: dscv3
resources:
  - name: dotnet sdk
    type: Microsoft.WinGet/Package
    properties:
      id: Microsoft.DotNet.SDK.10
      source: winget
  - name: codealta
    type: Microsoft.DSC.Transitional/PowerShellScript
    dependsOn:
      - dotnet sdk
    properties:
      input: CodeAlta
      testScript: |
        param($package)
        $dotnet = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
        [bool]((& $dotnet tool list --global | Out-String) -match "(?im)^$package\s")
      setScript: |
        param($package)
        $dotnet = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
        & $dotnet tool install --global $package
        if ($LASTEXITCODE -ne 0) { throw "dotnet tool install failed, exit code $LASTEXITCODE" }
  # Only borc upgrade runs this unit: the header lists it under upgrade.
  - name: codealta update
    type: Microsoft.DSC.Transitional/PowerShellScript
    properties:
      input: CodeAlta
      testScript: |
        param($package)
        # In place when the latest version is installed, or when the tool is not
        # installed at all: installing it is borc apply's job.
        . "$env:LOCALAPPDATA\borc\Write-BorcVersion.ps1"
        $dotnet = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
        $list = & $dotnet tool list --global | Out-String
        if ($list -notmatch "(?im)^$package\s+(\S+)") { return $true }
        $installed = $Matches[1]
        $index = Invoke-RestMethod "https://api.nuget.org/v3-flatcontainer/$($package.ToLowerInvariant())/index.json"
        $latest = @($index.versions | Where-Object { $_ -notmatch '-' })[-1]
        Write-BorcVersion -App $package -Installed $installed -Available $latest
        $installed -eq $latest
      setScript: |
        param($package)
        . "$env:LOCALAPPDATA\borc\Write-BorcVersion.ps1"
        # The app holds the files the update replaces.
        if (Get-Process alta -ErrorAction SilentlyContinue) { throw 'Close CodeAlta, then run borc upgrade again.' }
        $dotnet = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
        & $dotnet tool update --global $package
        if ($LASTEXITCODE -ne 0) { throw "dotnet tool update failed, exit code $LASTEXITCODE" }
        $list = & $dotnet tool list --global | Out-String
        if ($list -match "(?im)^$package\s+(\S+)") { Write-BorcVersion -App $package -Installed $Matches[1] }
        # Started once, the app rewrites its Start menu shortcut.
        Start-Process (Join-Path $env:USERPROFILE '.dotnet\tools\alta.cmd')
```

## Versions: Write-BorcVersion

winget tells BORC the version of a package, but only the recipe knows where to
find the version of an app it installs another way. An upgrade unit reports it
with `Write-BorcVersion`, a helper BORC installs in `%LOCALAPPDATA%\borc` next to
`Get-BorcSecret`. Dot-source it first, as the example above does:

- In the `testScript`, report the installed version and the newest one:
  `Write-BorcVersion -App CodeAlta -Installed $installed -Available $latest`.
- In the `setScript`, after the update, report the version now installed:
  `Write-BorcVersion -App CodeAlta -Installed $installed`.

`borc upgrade` then reads the reports in order: a version that changed is listed
under `upgraded`, with the old and the new version, and one that did not change
is only written to the log. `borc upgrade --what-if --check` shows the installed
and newest versions the tests reported, in its table.

- `-App` is the name the summary shows, often the name of the app.
- The helper prints nothing, so a `testScript` still outputs one boolean, and it
  never throws, so a report never fails a unit.
- Each value is cut to one short line of plain text.
- A unit that reports nothing is only said to have run, as before.
- Elevated units report too, when UAC elevates your own account. When it asks for
  another administrator's account, their reports go to that account's folder, and
  BORC shows the recipe as run.

## Settings in BORC_SETTINGS

Scripts find the config repo through the `BORC_SETTINGS` environment
variable. Point the tool at its folder there, through the tool's own
configuration (an environment variable, a config file entry, a command-line
setting).

Units do not inherit the terminal's process. A variable set only with
`$env:NAME = ...` does not reach them, so a value a unit needs has to be a user
variable, as `BORC_SETTINGS` is.

When an app cannot move its configuration, the recipe may link the default
location to `BORC_SETTINGS`. This is a workaround for that one recipe, not a
general mechanism. Prefer a directory junction for a whole folder, which needs no
admin rights. A symlink for a single file usually needs an elevated unit:
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

## How BORC merges recipes

BORC runs one merged configuration rather than one file per recipe. Knowing
what it does helps when reading a log:

- The BORC header is stripped.
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
# The BORC header. BORC reads it and strips it before running winget.
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

  # Uses the optional parameter. Without npmCache in borc.yaml, BORC drops
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

BORC checks every listed recipe before anything runs. Messages about a
recipe file start with `recipe <id>:`.

| Message | Meaning |
| --- | --- |
| `invalid YAML: ...` | The file is not valid YAML. The message gives the line. |
| `expected a WinGet Configuration document.` | The file is a list or a single value instead of keys. |
| `the file must start with $schema: ... and metadata: winget: processor: dscv3.` | The WinGet header differs from the verified one, often an `aka.ms` schema URL. |
| `unknown top-level key '<key>'.` | Only `borc`, `$schema`, `metadata` and `resources` are allowed. |
| `the borc header must be a map.` | `borc:` holds a list or a single value. |
| `unknown key '<key>' in the borc header.` | Only `description`, `requires`, `reboot`, `parameters`, `secrets` and `upgrade` are allowed. |
| `reboot must be true or false.` | Another value under `reboot`. |
| `requires must be a list, for example requires: [a, b].` | The same for `secrets` and `upgrade`. |
| `'<value>' is not valid in requires.` | A `requires` entry not in the `repo/recipe` form, or a `secrets` entry that is not a valid name. |
| `parameters must map each parameter name to a description.` | `parameters` holds a list or a single value. |
| `'<name>' is not a valid parameter name (letters, digits and '_').` | Rename the parameter. |
| `resources must be a list.` | `resources` holds something other than a list. |
| `every resource needs a name and a type.` | A unit without `name` or `type`. |
| `two resources are named '<name>'.` | Names must be unique within the recipe. |
| `dependsOn of resource '<name>' must be a list of resource names.` | `dependsOn` holds a single value or something other than text. |
| `resource '<name>' depends on '<other>', which is not a resource of this recipe. Use requires to wait for another recipe.` | A typo in the name, or a unit of another recipe: use `requires` for that. |
| `resource '<name>' depends on itself.` | Remove the entry. |
| `'<name>' in upgrade is not a resource of this recipe.` | A typo in the `upgrade` list, or a unit that was renamed. |
| `'<name>' in upgrade is a package unit; borc upgrade already upgrades packages.` | Remove it from the list: `borc upgrade` moves packages anyway. |
| `resource '<a>' depends on '<b>', an upgrade unit; only borc upgrade runs it.` | `<a>` runs in `borc apply`, where `<b>` never does. Remove the entry. |
| `resource '<name>' uses {{<p>}}, which the borc header does not declare under parameters.` | Declare the parameter, or fix the placeholder. |
| `resource '<name>' uses {{<p>}} outside input. Placeholders only work in input.` | Move the value into `input`. |
