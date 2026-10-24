# Commands

Every page below is exactly what `borc help <command>` prints. `borc help`
lists the commands; `borc <command> --help` and `borc <command> -h` show the
same page as `borc help <command>`.

Every command except `help` writes a timestamped log to
`%LOCALAPPDATA%\borc\logs`, keeps the last 20, and prints the log path at the
end. Secret values are never logged.

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
Usage: borc apply [--what-if] [--debug]

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
              which apps and recipes would be installed and which secrets
              would be asked for. Changes nothing.
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

## borc upgrade

<!-- help: upgrade -->
```text
Usage: borc upgrade

Upgrades, through winget, the apps borc.yaml lists: the plain winget and
Store IDs, and the winget packages of the listed recipes. Apps borc.yaml does
not list are never touched, and neither are settings. An app that is not
installed yet is skipped; borc apply installs it.

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
