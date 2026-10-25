# Commands

Every page below is exactly what `borc help <command>` prints. `borc help`
lists the commands; `borc <command> --help` and `borc <command> -h` show the
same page as `borc help <command>`.

Every command except `help` writes a timestamped log to
`%LOCALAPPDATA%\borc\logs`, keeps the last 20, and prints the log path at the
end. Secret values are never logged.

## Reading the output

Every command except `help` shows its work in numbered steps, and the
installer does the same:

```text

==> [1/5] Pulling the config repo (D:\settings)
  > git -C D:\settings pull --ff-only
  |   Already up to date.
  < done in 1s

==> [2/5] Pulling recipe repos
...

Summary:
  done     [1/5] Pulling the config repo (D:\settings)  1s
  done     [2/5] Pulling recipe repos                   3s
  failed   [3/5] Checking borc.yaml and the recipes     0s
  Stopped after step 3 of 5.
Log: C:\Users\you\AppData\Local\borc\logs\20261024-101500-123-apply.log
```

- `==> [n/total]` starts a step. A blank line separates the steps.
- `>` starts an external command (`git`, `winget`). Its output follows,
  indented after `|`, and `<` ends it with the result and the time it took:
  `done in 14s`, or `failed, exit code 0x8A150014, after 3s`. A code that is
  not a failure says what it means, such as `done in 2s (no upgrade
  available)`. The installer shows winget's output as winget draws it, without
  the `|` indent.
- The summary lists every step reached with `done`, `failed` or `restart`
  (Windows needs a restart) and its duration. When a command stops early, the
  last line says after which step.

In the console, step headers are cyan, `done` is green, `failed` and errors
are red, warnings and `restart` are yellow, and tool output is dark gray. The
words always say the result too, so nothing depends on the colour. Set the
`NO_COLOR` environment variable to turn colours off. The log file holds the
same lines with the time in front and no colours.

## Tab completion

In PowerShell 7, press Tab after `borc` to complete:

| After | Tab offers |
| --- | --- |
| `borc ` | the commands |
| `borc help ` | the commands |
| `borc apply --` | `--what-if`, `--debug`, `--help`, and `--check` once `--what-if` is there |
| `borc install ` | your `@local` recipes and the recipes of the cloned recipe repos; winget IDs once the text has a dot, such as `Git.` |
| `borc uninstall ` | the apps and recipes `borc.yaml` lists |
| `borc search ` | recipe names |

`@local` recipes are completed with quotes (`'@local/fonts'`), because `@`
has a meaning of its own in PowerShell. Once the argument is given,
PowerShell falls back to completing file names, as for any other command.

The borc block of your PowerShell 7 profile loads the completion, and
`borc self-update` keeps it current. In Windows PowerShell 5.1, load it by
hand, or add this line to that profile:

```powershell
. "$env:LOCALAPPDATA\borc\engine\src\completion.ps1"
```

## borc

<!-- help: index -->
```text
borc turns a blank Windows machine into a working developer workstation.

Usage: borc <command> [options]

Commands:
  help [<command>]   List the commands, or show the page of one command
  apply              Pull and apply the configuration
  upgrade            Upgrade the apps borc.yaml lists, through winget
  install <app>      Install an app and add it to borc.yaml
  uninstall <app>    Uninstall an app and remove it from borc.yaml
  search <term>      Search recipes and winget packages
  self-update        Update borc itself to the latest version

Run borc help <command>, borc <command> --help or borc <command> -h for
the page of one command.
```

## borc help

<!-- help: help -->
```text
Usage: borc help [<command>]

Without a command, lists the borc commands. With a command, shows its page.
borc <command> --help and borc <command> -h show the same page.
```

## borc apply

<!-- help: apply -->
```text
Usage: borc apply [--what-if [--check]] [--debug]

Pulls the config repo and the recipe repos, then applies borc.yaml.

  1. Refuses to pull while tracked files in BORC_SETTINGS have uncommitted
     changes. Commit or discard them, then run borc apply again. Untracked
     and ignored files never block.
  2. Pulls the config repo and the recipe repos, and prints a notice when a
     newer borc exists (skipped silently when offline).
  3. Checks borc.yaml and every listed recipe, and reports all problems
     before anything runs.
  4. Asks once for each secret declared in borc.yaml that Windows Credential
     Manager does not hold yet.
  5. Runs the recipes marked reboot: true first, then one merged
     configuration with the other recipes and the plain packages.
  6. If Windows needs a restart, asks you to restart and run borc apply
     again.

winget's output and errors are shown as they come. borc adds no retry or
skip logic of its own.

Options:
  --what-if   Fetch without merging, then show what the pull would bring,
              a verdict for each app and recipe, and which secrets would be
              asked for. Changes nothing and runs no recipe code. Verdicts:
                would be installed, would be applied: something is missing
                may be applied: no package is missing, but the recipe's
                  settings are only checked when borc apply runs
                installed, in place: nothing to do
  --check     With --what-if only: also run each recipe unit's test
              (winget configure test), so every recipe is either "would be
              applied" or "in place". Slower; testScripts run, setScripts
              never do; elevated units ask for one UAC prompt.
  --debug     Run the recipes one at a time, to find the one that fails.
              Each run may show its own UAC prompt.
  -h, --help  Show this page.

Exit codes:
  0     Done.
  1     A check failed or winget reported a failure.
  3010  Windows needs a restart; restart and run borc apply again.
```

`borc apply` runs `winget configure` once for the recipes marked
`reboot: true`, then once for everything else, so a run normally shows one
UAC prompt per `winget configure` that has elevated units. The generated
configuration files are saved next to the log.

### What `--what-if` checks

`--what-if` runs no recipe code, so it only knows what `winget list` can tell
it. It says so, line by line:

```text
==> [2/4] What would be installed
  winget  Git.Git                       installed
  winget  Microsoft.VisualStudioCode    would be installed

  recipe  @local/wsl-ubuntu             would be applied (runs first, may need a restart)
          packages: 0 of 1 installed (Canonical.Ubuntu.2404)
          settings: 1 unit, not checked
  recipe  recipes/node                  may be applied
          packages: 1 of 1 installed
          settings: 2 units, not checked; 1 skipped (no value for npmPrefix)
  recipe  @local/fonts                  in place
          packages: 1 of 1 installed, no settings

  2 would be installed or applied, 1 may be applied, 2 in place.
  "may be applied": no package is missing, but its settings are only
  checked when borc apply runs.
```

- **A plain app** is `installed` or `would be installed`.
- **A recipe** is:
  - `would be applied` when one of its packages (`Microsoft.WinGet/Package`
    units) is missing;
  - `in place` when it only installs packages and all of them are there;
  - `may be applied` otherwise: its packages are there, but its settings
    units (scripts) are only checked by their `testScript` when `borc apply`
    runs, and winget then skips the ones already in place.
- **Under each recipe,** borc lists the missing packages, the settings units
  it did not check, and the units skipped because a parameter has no value.
- **The last lines** count the verdicts.

### A precise answer: `--what-if --check`

`borc apply --what-if --check` adds one step: every recipe unit, from both
runs, goes through a single `winget configure test`. Each unit's `testScript`
runs, and no `setScript` does. Every recipe then gets a definite verdict:

```text
  recipe  recipes/node                  would be applied
          units: 2 of 3 in place
          would change: npm cache
          skipped: 1 (no value for npmPrefix)
  recipe  @local/fonts                  in place
          units: 1 of 1 in place
```

- **Plain apps** keep the `winget list` answer.
- **A unit whose test fails** (for example, because the tool it checks is not
  installed yet) is listed under `could not test`, with the reason, and its
  recipe stays `may be applied`.
- **It is slower:** winget starts every resource. Elevated units ask for one
  UAC prompt, for all of them together.
- **`--check` only works with `--what-if`:** a real `borc apply` already runs
  every test before acting.

## borc upgrade

<!-- help: upgrade -->
```text
Usage: borc upgrade

Upgrades, through winget, the apps borc.yaml lists: the plain winget and
Store IDs, and the winget packages of the listed recipes. Apps borc.yaml does
not list are never touched, and neither are settings. An app that is not
installed yet is skipped; borc apply installs it. A package with a fixed
version, in borc.yaml or in a recipe, stays at that version.

Options:
  -h, --help  Show this page.
```

## borc install

<!-- help: install -->
```text
Usage: borc install <app>

Installs an app and adds it to the apps list of borc.yaml. The argument is
read by its form:

  repo/recipe or @local/<name>   a recipe
  no dot, such as 9NBLGGH4NNS1   a Microsoft Store ID
  anything else, such as Git.Git a winget ID, checked to exist first

An app already listed is only installed if it is missing. A recipe is checked
first (parameters, secrets, requires), then run; set its parameters by
editing borc.yaml.

The change to borc.yaml keeps its comments and formatting, and is left
uncommitted for you to review.

Options:
  -h, --help  Show this page.
```

## borc uninstall

<!-- help: uninstall -->
```text
Usage: borc uninstall <app>

Uninstalls an app and removes it from the apps list of borc.yaml. The
argument is read by its form, as for borc install.

  winget or Store app  Runs winget uninstall, then removes its line. An app
                       borc.yaml does not list is still uninstalled.
  recipe               Only removes its line, then lists the winget packages
                       the recipe installed so you can remove them with
                       borc uninstall <id>. borc does not undo a recipe.

The change to borc.yaml keeps its comments and formatting, and is left
uncommitted for you to review.

Options:
  -h, --help  Show this page.
```

## borc search

<!-- help: search -->
```text
Usage: borc search <term>

Searches recipe names and descriptions in the local clones of the recipe
repos and in borc/cookbook/, then runs winget search <term>.

Options:
  -h, --help  Show this page.
```

## borc self-update

<!-- help: self-update -->
```text
Usage: borc self-update

Updates borc in %LOCALAPPDATA%\borc to the latest version, then refreshes
the borc block in your PowerShell 7 profile: only the text between its
markers, and only when it changed. It never touches the config repo or
installed apps. borc apply only prints a notice when an update exists.

Options:
  -h, --help  Show this page.
```

Running the one-line installer again also updates borc.

## Exit codes

All commands exit with 0 on success and 1 on a failure. A wrong command,
option or missing argument exits with 2. `borc apply` and `borc install`
exit with 3010 when Windows needs a restart.
