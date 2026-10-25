# Getting started

This page is for someone setting up their machine with borc. It explains the
config repo, how machines share it, the two folders borc asks for, and the
daily workflow.

## The config repo

All your configuration lives in one Git repo, the config repo. It holds:

- `borc/borc.yaml`, the list of apps and recipes for this machine
  ([reference](borc-yaml.md));
- `borc/scripts/`, PowerShell commands loaded in every PowerShell 7
  terminal;
- `borc/cookbook/`, your own recipes, used as `@local/<name>`
  ([writing recipes](writing-recipes.md));
- the settings of your apps, organised the way the recipes expect, for
  example `idea/` or `git/`.

The config repo is not copied anywhere: it is cloned straight into the
`BORC_SETTINGS` folder, and apps read and write their settings there. When an
app changes a setting, `git status` shows it.

```
D:\settings\
  .gitignore            chooses which settings files are tracked
  borc\
    borc.yaml           the configuration
    scripts\            PowerShell commands loaded in the terminal
    cookbook\           @local recipes
  idea\                 app settings, organised as recipes expect
  git\
```

Only the `borc/` folder is reserved; the rest of the layout is yours.

### Starting from the starter template

The quickest start is to leave the URL empty when the installer asks for it.
borc then creates `BORC_SETTINGS` as a new local Git repo with:

- a `borc/borc.yaml` with a few winget packages and commented examples;
- a `.gitignore` explaining negation patterns;
- empty `borc/scripts/` and `borc/cookbook/` folders.

Nothing is committed. Review the files, make the first commit, then create an
empty repo on your Git host, add it as a remote and push:

```powershell
cd D:\settings
git add -A
git commit -m "My borc config"
git remote add origin https://github.com/you/settings.git
git push -u origin home
```

If you give the URL of an empty remote repo instead, borc clones it and fills
it from the same starter template, again without committing or pushing.

### Using your own repo

Give its URL when the installer asks. Git Credential Manager handles the
login if the repo is private. The folder must be missing, empty, or already a
clone of the same repo; otherwise the installer stops rather than touch it.

## One branch per machine

Different machines (work, home, laptop) use different branches of the same
config repo. There are no profiles and no inheritance: a branch is the whole
configuration of one machine, and Git handles the rest. To share a change
between machines, merge or cherry-pick it like any other Git change.

When you install borc on a new machine and give a branch name that does not
exist on the remote yet, borc lists the existing branches and offers to
create the new branch from one of them. The new branch only exists locally
until you push it:

```powershell
git -C D:\settings push -u origin laptop
```

Until then, `borc apply` uses the local copy as it is.

## Choosing BORC_SETTINGS and BORC_HOME

The installer asks for two folders and has no default for either:

| Variable | What it is | Example |
| --- | --- | --- |
| `BORC_SETTINGS` | The clone of your config repo. Apps read their settings here. | `D:\settings` |
| `BORC_HOME` | Your home base. New PowerShell 7 terminals open here instead of your user folder. | `D:\sources` |

Give full paths with a drive letter. borc stores both as user environment
variables, and a later run of the installer reuses them.

borc also keeps its own files in `%LOCALAPPDATA%\borc`: the engine, the clones
of recipe repos, and the logs.

To move either folder later, move it by hand, then change the user
environment variable (System Properties > Environment Variables) and open a
new terminal.

## Choosing what is tracked: .gitignore

Apps write their settings straight into the working copy, often with caches
and machine-specific files next to the settings worth keeping. Decide what
Git tracks with `.gitignore` negation patterns: ignore everything under an
app folder, then re-include the parts you want.

<!-- example: examples/settings/.gitignore -->
```gitignore
# IntelliJ IDEA writes many files; keep only the code styles.
idea/*
!idea/codestyles/

# Track the git config, not the credentials helper cache.
git/*
!git/config
```

Note the `idea/*` form: a pattern on the folder itself (`idea/`) would
ignore it entirely, and Git cannot re-include a file inside an ignored
folder.

Ignored files stay local. They never block `borc apply`.

## Terminal scripts

Every `*.ps1` file in `borc/scripts/` is loaded in every PowerShell 7
terminal, in alphabetical order, so your functions and aliases follow you to
each machine.

<!-- example: examples/settings/borc/scripts/git-aliases.ps1 -->
```powershell
# Loaded in every PowerShell 7 terminal by the borc profile block.
function gs { git status --short --branch @args }
function gl { git log --oneline --graph -20 @args }
```

A script that fails prints one warning naming the file; the others still
load. borc never runs these scripts itself. The installer adds a marked block
to your PowerShell 7 profile to load them, and `borc self-update` keeps that
block up to date; the rest of your profile is left alone. The same block turns
on Tab completion for `borc` (see [commands](commands.md#tab-completion)).

## The daily workflow

1. Edit `borc/borc.yaml`, or let `borc install` and `borc uninstall` edit
   it, or change a setting in an app.
2. Check what changed:

   ```powershell
   git -C D:\settings status
   ```

3. Commit and push what you want to keep:

   ```powershell
   git -C D:\settings commit -am "Add VS Code"
   git -C D:\settings push
   ```

4. On another machine using the same branch, run `borc apply`. It pulls the
   change and applies it.

`borc apply` refuses to pull while tracked files have uncommitted changes, so
it never mixes incoming changes with yours. Commit or discard them first.

To see what `borc apply` would do without changing anything, run
`borc apply --what-if`.

To upgrade the apps `borc.yaml` lists, run `borc upgrade`. To update borc
itself, run `borc self-update`. See [commands](commands.md) for the full list.
