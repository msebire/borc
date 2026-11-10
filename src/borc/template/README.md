# BORC configuration

This repo describes one Windows machine for
[BORC](https://github.com/msebire/borc): the apps it installs, how they are wired
up, and their settings. Each machine has its own branch. This file comes from
BORC's starter template, so make it yours.

| Where | What |
| --- | --- |
| `borc/borc.yaml` | The apps and recipes of this machine |
| `borc/cookbook/` | Your own recipes, used as `@local/<name>` |
| `borc/scripts/` | PowerShell commands loaded in every PowerShell 7 terminal |
| `.gitignore` | Which settings files are tracked |
| Any other folder | The settings of one app, such as `git/` |

## Useful commands

| Command | What it does |
| --- | --- |
| `borc apply` | Pull this repo and apply the configuration |
| `borc apply --what-if` | Show what would change, without changing anything |
| `borc apply --what-if --check` | The same, also running the recipes' tests |
| `borc apply --no-pull` | Apply the files as they are, uncommitted changes included |
| `borc apply --one-by-one` | Run the recipes one at a time, to find the one that fails |
| `borc search <term>` | Search your recipes and winget packages |
| `borc install <app>` | Install one app or recipe and add it to `borc.yaml` |
| `borc uninstall <app>` | Uninstall an app and remove it from `borc.yaml` |
| `borc upgrade` | Upgrade the apps `borc.yaml` lists |
| `borc self-update` | Update BORC itself |
| `borc help <command>` | Show the full page of one command |

BORC never commits or pushes here. To save a change, or share it with another
machine:

```powershell
git add -A
git commit -m "Add My App"
git push
```

If Git does not know who you are yet, it stops and tells you which
`git config --global` commands to run.

A new repo has no remote yet, so its first push takes two commands, with the URL of
an empty repo you created and the name of this branch:

```powershell
git remote add origin <url>
git push -u origin <branch>
```

## Documentation

- [Getting started](https://github.com/msebire/borc/blob/main/docs/getting-started.md)
- [borc.yaml reference](https://github.com/msebire/borc/blob/main/docs/borc-yaml.md)
- [Writing recipes](https://github.com/msebire/borc/blob/main/docs/writing-recipes.md)
- [Commands](https://github.com/msebire/borc/blob/main/docs/commands.md)
- [Troubleshooting](https://github.com/msebire/borc/blob/main/docs/troubleshooting.md)

## Adding an app

These recommendations work for a person or for an AI agent.

### Plain entry or recipe

- Find the package with `borc search <name>`. Prefer winget, and use a Microsoft
  Store ID only when winget has no package.
- When nothing needs adjusting after the install, a plain `- winget: <id>` line is
  enough.
- Otherwise, write a recipe. It holds the package too, and its line replaces the
  plain one.

### What to check after installing

Look at the real machine rather than guessing: paths, shortcut names and install
scope differ between apps.

| Check | What to do |
| --- | --- |
| Desktop shortcut | Remove it in a unit, if you keep apps in the Start Menu only. Use a wildcard when the name holds a version (`GIMP*`). |
| Start Menu entry | Create it when missing. Portable (zip) packages often have none. |
| Settings | Keep them in this repo, as described below. |
| Command on PATH | Try `Get-Command <exe>` in a new terminal. When missing, add the folder to the user PATH, and replace an older entry after an upgrade. |
| Environment variables | Set them as user variables, following the newest installed version. |
| Shell integration | Use a unit for a context menu, and a file in `borc/scripts/` for completion or the prompt. |
| Self-updates | An update can rename a folder or put a removed shortcut back. Units run on every `borc apply`, so they must still work afterwards. |
| Start at login, tray icon, telemetry | Decide these on purpose, as they are matters of preference. |

### Keeping settings in this repo

Use the first of these that the app allows:

1. The app's own way to use another location: an environment variable, a pointer
   file, or a config entry.
2. A directory junction for a whole folder, which needs no admin rights.
3. A symbolic link for a single file, which needs admin rights unless Developer
   Mode is on.

Then:

- On the first machine, move the current settings into this repo. On the next ones,
  keep the local copy as a `.bak` and use the repo's.
- Many apps save their settings when they close. Have the recipe stop with a message
  asking to close the app while it moves the files.
- In `.gitignore`, ignore the app's folder and re-include only the files worth
  keeping. Never track caches, sessions, window state, history, logs or license
  files.
- Keep this machine's absolute paths out of tracked files. Use `BORC_SETTINGS` in
  recipes, and write a local file that stays ignored when an app needs a real path.
- After the first run, change a setting in the app and look at `git status` to see
  which files it wrote.

### Writing the recipe

- Start with a comment saying what the recipe does and why, then
  `Layout under BORC_SETTINGS:` (or `none`). Your future self will need the why.
- Use one small unit per job, with a name that says what it does, such as
  `no desktop shortcut`.
- `testScript` outputs exactly one boolean, and checks everything `setScript` does.
  `setScript` must be safe to run again.
- Each script unit declares one `param`, and gets its value from `input`.
- `dependsOn` takes plain unit names. `requires` takes recipes.
- Avoid needing admin rights when you can, as each elevated run can ask for a UAC
  prompt: prefer user variables, the user PATH, HKCU and junctions. Elevate only the
  units that need it (Public desktop, Program Files, HKLM, symbolic links, Windows
  features).
- Stay on the latest version unless you have a reason to fix one. When a recipe
  downloads a file itself, follow the latest release rather than a fixed URL.
- Never write a token or a password in this repo. Read it with `Get-BorcSecret`,
  declare it under `secrets:` in `borc.yaml`, and never pass it through `input`.

### Testing

- `borc apply --what-if --no-pull` checks your uncommitted files and lists what
  would change.
- `borc install @local/<name>` runs that one recipe, uncommitted changes included,
  which is much faster than a full `borc apply`.
- These runs are real: they install software and change your profile. Setting a
  variable such as `$env:LOCALAPPDATA` in your terminal does not redirect them.
- Afterwards, check the result on the machine: shortcuts, Start Menu, PATH, and the
  settings files in this repo. Then run it again to confirm there is nothing left to
  apply.

### Committing

Commit each app on its own: its `borc.yaml` line, recipe, settings files and
`.gitignore` block together, and nothing else. An app is then easy to review, to
revert, or to cherry-pick into another machine's branch.
