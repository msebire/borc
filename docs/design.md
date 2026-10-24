# Design

Why borc is the way it is. This page records reasons only; what borc does is
described in the other pages, and is not repeated here. A change that makes a
new decision adds an entry.

## Principles

- **winget is the package manager; borc is a thin layer on top.** borc adds
  what winget lacks for a whole workstation (one repo for the configuration,
  recipes, secrets, settings in Git), and nothing it already does.
- **One config repo.** Nothing to learn beyond Git.
- **The config repo is the settings folder.** No copying, no sync step.
- **Git does the tracking, and the user does the Git.** borc may edit files,
  but commits and pushes stay the user's.
- **Idempotent.** Running anything twice is safe, so the answer to almost any
  interruption is "run it again".
- **No install-time scripts in the config.** Anything that runs at install
  time is a recipe, so it can be shared, reviewed and tested on its own.
- **Secrets never go in a repo.**
- **Report everything before running anything.** A run that stops halfway is
  worse than a run that never starts.

## Decisions

### One config repo, one branch per machine

There are no profiles, layers or inheritance to learn. Machines differ by
branch, and Git already handles branching, merging and cherry-picking
changes between them.

### The config repo is the settings folder

Apps write straight into the working copy, so `git status` shows what
changed and there is no sync step to forget. `.gitignore` with negation
patterns picks what is tracked, and ignored files never block a pull.

### No default for BORC_SETTINGS and BORC_HOME

Machines differ in drives and folder habits. The user chooses; borc makes no
assumption about drives or folders.

### Merged run, reboot recipes first

One `winget configure` run means one UAC prompt, however many units are
elevated. Recipes that may need a restart (Windows features) run in a
separate first run, so a restart happens before the rest depends on it. borc
stops and asks for the restart rather than resuming by itself: an automatic
resume would need a scheduled task or a Run key, a lasting change to the
machine.

### WinGet rules taken from a real machine

The DSC documentation gives `aka.ms/dsc/schemas/v3/...` schema URLs, and
winget 1.29 rejects them. borc uses the rules verified on a real machine, and
keeps them in one file (`src/Borc/WingetRules.ps1`) so a winget change means
one edit. borc also refuses a recipe with another header, so a recipe that
would fail in winget fails early, with a clear message.

### {{name}} placeholders in input, and dropped units

Recipes stay declarative. "A missing parameter leaves the default untouched"
is guaranteed by borc, which drops the unit, rather than by each recipe
author writing "if empty, do nothing" in every script.

### Unknown parameter is an error, values are strings

Typos are caught before anything runs, instead of being silently ignored.
`input` reliably carries strings only, so values are strings in `borc.yaml`
too, rather than YAML numbers or booleans that would change on the way.

### Secrets read through Get-BorcSecret

A placeholder would write the secret into the generated configuration file.
An environment variable depends on DSC passing it to elevated processes,
which is unverified. Reading Windows Credential Manager from the script
avoids both. The helper is dot-sourced from a fixed path rather than
installed on `PSModulePath`, so borc changes nothing else on the machine.

### Secrets declared by recipes, checked against borc.yaml

A missing secret is reported before anything runs, and the user sees every
secret their machine depends on in one place.

### No secret command

Windows Credential Manager already creates, edits and removes credentials;
a borc command would only duplicate it.

### install reads its argument by form

Explicit rules (a slash means a recipe, no dot means a Store ID, anything
else is a winget ID) instead of guessing between winget, the Store and
recipes.

### uninstall on a recipe only removes the line

Undoing a recipe is guesswork: settings may have been moved, links created,
features enabled. borc never removes what it cannot be sure about; it lists
the packages so the user decides.

### upgrade limited to borc.yaml

Predictable, and it never touches apps borc did not install.

### install and uninstall edit borc.yaml as text

`borc.yaml` is the user's file, with their comments and layout. A YAML
serializer would rewrite it; a text edit of the `apps` list changes one line.

### main is the release, develop is the next one

borc always runs from `main`, and `self-update` follows the branch the engine
is on. `main` only ever holds released, safe work, so unfinished work never
reaches users. `develop` collects everything not released yet, so changes can
be tried together on a real machine (with `BORC_BRANCH=develop`) before they
ship. `main` only moves by fast-forward to a commit of `develop`, so the two
never diverge and nothing has to be merged back, except after an urgent fix
made from `main`.

The version number is chosen when the release is cut: work on `develop` is
listed as unreleased, and nobody has to guess the next number. Tags and the
changelog tell people what changed, but the app never reads them, which keeps
the installer and `self-update` simple: no tag lookup, no GitHub API.

### BORC_BRANCH for testing a branch

A maintainer needs to try a branch on a real machine before it reaches
`main`. `BORC_BRANCH` is read by the installer only, from its own process,
and never stored: the engine clone itself remembers the branch, and the
normal one-liner brings a machine back to `main`. A stored setting or a
`borc` option would make it easy to leave a machine on a test branch without
noticing, and would put a maintainer feature in front of every user.

### self-update separate from apply

Engine changes never mix with config pulls: an `apply` that fails can be
told apart from a borc update that broke something. `apply` only prints a
notice.

### The engine is a Git clone

Git is installed anyway, so the engine is a clone in
`%LOCALAPPDATA%\borc\engine`, and updating it is a fast-forward pull. No
archive download or unpacking code to maintain.

### borc.cmd on the user PATH

A small shim in `%LOCALAPPDATA%\borc\bin` makes `borc` work in any shell (cmd,
Windows PowerShell, PowerShell 7) and in any terminal. A profile function
would only work in PowerShell 7.

### A marked block in the PowerShell 7 profile

Works in any terminal, never overrides "open here" from other tools (borc
only moves to `BORC_HOME` when the shell starts in the user's home folder),
and leaves the rest of the user's profile untouched.

### self-update refreshes the profile block

The block belongs to borc and is clearly marked, so it should follow the
engine: a fix to it reaches users with the next `self-update`, not only when
they rerun the installer. The rewrite stays inside the markers and is skipped
when nothing changed. The refresh runs in a child process from the updated
engine, because the process doing the pull still holds the old code.

### Starter template on an empty URL or an empty remote

Lets someone try borc in minutes. The first commit stays the user's, so
nothing is published before they have looked at it.

### Offer to create a missing branch

A new branch is exactly what a new machine needs, and starting it from an
existing machine's branch is the common case.

### Pull with --ff-only, stop when offline

A merge would create a commit, and borc never commits. Stopping when the
config repo cannot be fetched keeps `apply` predictable: it always applies the
latest configuration, or nothing.

### Trust winget on failures

winget's errors are shown as they come and its exit code is reported. Retry
rounds or skip lists would hide problems and make runs harder to reason
about; `--debug` exists to find the failing recipe instead.

### Non-interactive module install, no PSGallery trust

A fresh machine must not stop on prompts, and borc leaves no permanent
security change: PSGallery is not marked as trusted, and the execution policy
is bypassed for the installer's process only.

### Windows 11 target, Windows 10 22H2 best effort

New machines run Windows 11. Windows 10 is out of support but still in use,
so 22H2 gets a warning rather than a refusal.

### Engine only; recipes in separate repos

The engine stays free of opinions about tools. Recipes are shared and
versioned on their own, and several recipe repos can be used side by side.
