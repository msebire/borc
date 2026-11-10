# Design

Why BORC is the way it is. This page records reasons only; what BORC does is
described in the other pages, and is not repeated here. A change that makes a
new decision adds an entry.

## Principles

- **winget is the package manager; BORC is a thin layer on top.** BORC adds
  what winget lacks for a whole workstation (one repo for the configuration,
  recipes, secrets, settings in Git), and nothing it already does.
- **One config repo.** Nothing to learn beyond Git.
- **The config repo is the settings folder.** No copying, no sync step.
- **Git does the tracking, and the user does the Git.** BORC may edit files,
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

Machines differ in drives and folder habits. The user chooses; BORC makes no
assumption about drives or folders.

### Merged run, reboot recipes first

One `winget configure` run means one UAC prompt, however many units are
elevated. Recipes that may need a restart (Windows features) run in a
separate first run, so a restart happens before the rest depends on it. BORC
stops and asks for the restart rather than resuming by itself: an automatic
resume would need a scheduled task or a Run key, a lasting change to the
machine.

### WinGet rules taken from a real machine

The DSC documentation gives `aka.ms/dsc/schemas/v3/...` schema URLs, and
winget 1.29 rejects them. BORC uses the rules verified on a real machine, and
keeps them in one file (`src/borc/WingetRules.ps1`) so a winget change means
one edit. The same applies to `dependsOn`: the DSC documentation writes
`[resourceId('<type>','<name>')]`, but winget resolves plain unit names
itself, and `winget configure test` accepts both. Only real applies showed
the difference, so rules are verified with `winget configure`, never with
`test` alone. BORC also refuses a recipe with another header, so a recipe that
would fail in winget fails early, with a clear message.

Real applies also showed that units do not inherit the caller's process
environment, so a variable set at process level cannot redirect or sandbox a
`winget configure`, and a value a unit needs has to be a user variable. A value
stored just before the first apply does reach its units: this was checked on a
first install on Windows 11, with both a normal and an elevated unit.

A Windows 11 test also showed that `--accept-configuration-agreements` does not
reach a package: a Store app failed until its unit set `acceptAgreements: true`. BORC
sets it on every package unit, because the user chose the app by listing it, and
`borc install` and `borc upgrade` already accept agreements for the same reason.

The installer still takes the latest winget, whose rules nobody has verified yet,
because a new machine should not start from an old one. So BORC names the
difference when a run fails rather than on every run: most failures have other
causes, and a permanent note would stop being read as soon as winget moves on.

### {{name}} placeholders in input, and dropped units

Recipes stay declarative. "A missing parameter leaves the default untouched"
is guaranteed by BORC, which drops the unit, rather than by each recipe
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
installed on `PSModulePath`, so BORC changes nothing else on the machine.

### Secrets declared by recipes, checked against borc.yaml

A missing secret is reported before anything runs, and the user sees every
secret their machine depends on in one place.

### No secret command

Windows Credential Manager already creates, edits and removes credentials;
a BORC command would only duplicate it.

### install reads its argument by form

Explicit rules (a slash means a recipe, no dot means a Store ID, anything
else is a winget ID) instead of guessing between winget, the Store and
recipes.

### uninstall on a recipe only removes the line

Undoing a recipe is guesswork: settings may have been moved, links created,
features enabled. BORC never removes what it cannot be sure about; it lists
the packages so the user decides.

### apply only adds

`borc.yaml` says what a machine needs, not everything it may hold. If removing a
line uninstalled the app, a merge from another machine's branch could silently
remove software, and BORC would have to guess what a recipe left behind. Removal
stays an explicit `borc uninstall`, on the machine where it is wanted.

### upgrade limited to borc.yaml

Predictable, and it never touches apps BORC did not install. That leaves out
winget and Microsoft.DSC, which rarely need to move and can break configuration
files when they do, so they only move when the installer is run again.

### A fixed version wins over upgrade

A version written in `borc.yaml` or in a recipe is a decision: the user needs
that version. `borc upgrade` respects it rather than moving past it, and says
so; changing the version means editing the file, where the decision lives.
BORC keeps the version in the configuration rather than using `winget pin`,
so the choice is tracked in Git and the same on every machine of the branch.

`borc install` moves an installed package to the fixed version with a configure
unit rather than `winget install`, which refuses to go down to an older version. It
is what `borc apply` does, so the two commands agree. `borc upgrade` stays out of it,
and says when what is installed differs from the fixed version.

### install and uninstall edit borc.yaml as text

`borc.yaml` is the user's file, with their comments and layout. A YAML
serializer would rewrite it; a text edit of the `apps` list changes one line.

### main is the release, develop is the next one

BORC always runs from `main`, and `self-update` follows the branch the engine
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

### The installer runs from a PowerShell window

The first one-liner, `powershell -NoProfile -ExecutionPolicy Bypass -Command "irm
... | iex"`, worked from cmd.exe as well. On 2026-11-10, Microsoft Defender blocked
it as a Trojan on a new Windows 11 machine, judging the command line alone: a second
PowerShell started with the policy bypassed to run a download is how malware works.
The plain `irm ... | iex`, typed in Windows PowerShell, installed BORC on the same
machine. The bypass flag was never needed: the execution policy does not apply to
text run by `iex`, and the installer sets it for its own process. So the installer
is documented for Windows PowerShell only, and the variables that adjust it are set
in that window, where they last until it is closed.

### BORC_BRANCH for testing a branch

A maintainer needs to try a branch on a real machine before it reaches
`main`. `BORC_BRANCH` is read by the installer only, from its own process,
and never stored: it lasts until that window is closed, the engine clone itself
remembers the branch, and the normal one-liner brings a machine back to `main`. A stored setting or a
`borc` option would make it easy to leave a machine on a test branch without
noticing, and would put a maintainer feature in front of every user.

### self-update separate from apply

Engine changes never mix with config pulls: an `apply` that fails can be
told apart from a BORC update that broke something. `apply` only prints a
notice.

### The engine is a Git clone

Git is installed anyway, so the engine is a clone in
`%LOCALAPPDATA%\borc\engine`. No archive download or unpacking code to maintain.
Updating it is a fetch and a hard reset to the remote branch rather than a pull:
nobody works in that clone, and a pull would leave a machine stuck, unable even to
rerun the installer, whenever a test branch was rewritten.

### borc.cmd on the user PATH

A small shim in `%LOCALAPPDATA%\borc\bin` makes `borc` work in any shell (cmd,
Windows PowerShell, PowerShell 7) and in any terminal. A profile function
would only work in PowerShell 7.

### A marked block in the PowerShell 7 profile

Works in any terminal, never overrides "open here" from other tools (BORC
only moves to `BORC_HOME` when the shell starts in the user's home folder),
and leaves the rest of the user's profile untouched.

### self-update refreshes the profile block

The block belongs to BORC and is clearly marked, so it should follow the
engine: a fix to it reaches users with the next `self-update`, not only when
they rerun the installer. The rewrite stays inside the markers and is skipped
when nothing changed. The refresh runs in a child process from the updated
engine, because the process doing the pull still holds the old code.

### A reminder at terminal start, from the engine

The config repo is the settings folder, so apps change it behind the user's
back, and a change only reaches another machine once it is committed and
pushed. A new terminal is a natural moment to be reminded. The check is one
`git status` (about a tenth of a second), with `--no-optional-locks` so it
never blocks Git running elsewhere, and it prints nothing when there is
nothing to do. It counts untracked files too, because a new settings file is
exactly the "commit this or ignore it?" decision to notice.

The profile block only loads `src/profile.ps1` from the engine. That file
holds what happens at terminal start (this check, Tab completion), so it can
change with `self-update` without rewriting the user's profile.

### Tab completion inside the shell

The completer runs on every Tab, so it lives in the shell itself, loaded
by the profile block BORC already manages, rather than starting BORC in a new
process each time. It reads `borc.yaml` as text and lists recipe files
directly, without the YAML module, so it stays instant. Only winget IDs need a
child process, and only once the word has a dot, because winget's own
`winget complete` is the one source that knows them.

### Starter template on an empty URL or an empty remote

Lets someone try BORC in minutes. The first commit stays the user's, so
nothing is published before they have looked at it.

### An example recipe in the template, listed by default

An empty `cookbook/` folder needed a `.gitkeep` and taught nothing. The template
ships `hello-borc` instead, a recipe that adds one command printing a message
from the config repo. It is listed in `borc.yaml`, so a first apply runs it and
the result can be tried straight away, which shows the whole path from a recipe
to a command to settings in Git. It installs no app, needs no admin rights and
exists nowhere but the template, so it costs a new user nothing. Its comments
describe every option, so it doubles as the file to copy.

### A README in the template

A new config repo is opened on GitHub or in a folder before anyone reads BORC's
docs, so it says what it is, with the daily commands and links. It also holds what
real recipe work taught: what to check after an install, in which order to move
settings, how to test and commit. Those are recommendations rather than engine
behaviour, and they belong to the user once the repo exists, so BORC never updates
the file. The tests check its commands, options and links against this repo.

### Offer to create a missing branch

A new branch is exactly what a new machine needs, and starting it from an
existing machine's branch is the common case.

### Pull with --ff-only, stop when offline

A merge would create a commit, and BORC never commits. Stopping when the
config repo cannot be fetched keeps `apply` predictable: it always applies the
latest configuration, or nothing.

### Output in steps, with every command framed

BORC's own messages, Git and winget all write to the same console, and a
long run was hard to follow: it was not clear where a step, or an install,
started and ended. Numbered step headers, a start and an end line around
each external command, and a summary at the end let the user find their place
at a glance and read the result first. Colours help, but the words always say
the result too: the output stays readable in the log, when pasted into an
issue, and without colour. Tool output is still shown in full, because BORC
shows winget's errors as they come.

### Every run ends with its result

Step statuses only say that each step worked. After a long run, the
question is whether anything changed, or with `--what-if`, whether anything
would. So the summary ends with a `Result:` line that answers it, then the
detail.

For `apply`, BORC only reports what it knows for certain: commits pulled,
packages newly installed or at another version (from `winget list` before and
after), and secrets stored. winget prints the same "Unit successfully
applied." for a unit it changed and for one already in place. Its verbose
logs do record each unit's test, but in an internal format, without unit
names, and split across processes for elevated units. BORC does not build on
that, and says that recipes were run rather than claiming they changed.

`upgrade`, `install` and `uninstall` end the same way, because a long list of
framed winget commands answers the question no better there. `upgrade` compares
`winget list` before and after too, since winget's exit code does not say whether
a package moved. `search` and `self-update` end on their answer already.

The log path is a footnote, set apart and dimmed, so the result stays the
last thing read.

### --what-if says what it checked

Knowing whether a recipe's settings are in place means running its
`testScript`s, which is slow and, for elevated units, needs a UAC prompt.
`--what-if` must stay quick, prompt-free and free of recipe code, so it checks
only what `winget list` can tell. Its verdicts never claim more than that: a
recipe whose packages are all there but which also has settings units is
`may be applied`, not `in place`. The count at the end gives the answer at a
glance.

`--check` is the opt-in for a precise answer. It is an option of `--what-if`
rather than a command of its own: it only makes sense when nothing is applied,
since `apply` already tests every unit before acting, and a separate command
would duplicate most of `--what-if`. All units go through one
`winget configure test`, so elevated units ask for admin rights once. BORC
reads winget's per-unit result lines rather than its exit code, which is not 0
as soon as one unit would change; a line it does not recognise becomes
"could not test", never a guess.

### --no-pull for trying a configuration before committing it

`borc apply` refuses to pull over local changes, so a normal run never mixes
incoming commits with the user's edits. While building a configuration, that
forces a commit before every try. `--no-pull` removes the conflict rather than
the safety: when nothing is pulled, there is nothing to mix, so BORC applies
the working copy as it is. It is an explicit option, not a fallback, so
`borc apply` alone keeps pulling the latest configuration or applying nothing.
When the pull is refused or fails, the result points at the option, since the
user may simply be trying things out.

### Trust winget on failures

winget's errors are shown as they come and its exit code is reported. Retry
rounds or skip lists would hide problems and make runs harder to reason
about; `--one-by-one` exists to find the failing recipe instead.

### Plain packages are not elevated

A Windows 11 test counted the UAC prompts: one for the elevated units, and one for
each package whose own installer needs admin rights. Installed packages, portable and
per-user ones, and runs that install nothing add none. Elevating plain packages might
merge a few prompts on a first install, which was not tested, and it would run every
package elevated, against the aim of avoiding admin rights where possible. So they
run as the user, and an installer that needs more asks for it itself.

### The VC++ runtime only when it is missing

An old VC++ runtime makes every file with an elevated unit fail, with an error that
names no cause. The installer checks for `vcruntime140_1.dll` and installs the runtime
only when the file is missing, even with `BORC_SKIP_UPDATES`, since that installs what
is missing. It is not installed every time: that could add a UAC prompt on each run for
a package BORC does not otherwise use. If the install fails, the installer warns and
goes on, as configurations without elevated units still work. This check is a proxy:
the test did not isolate which file mattered, so the troubleshooting page also covers
an old runtime that has the file.

### Non-interactive module install, no PSGallery trust

A fresh machine must not stop on prompts, and BORC leaves no permanent
security change: PSGallery is not marked as trusted, and the execution policy
is bypassed for the installer's process only.

### BORC_SKIP_UPDATES for managed computers

The installer always brings winget, Git and PowerShell 7 up to date, so a
fresh machine starts from known tools. A managed work computer may forbid
that, keep its own versions, or block the PowerShell Gallery. The opt-out
follows `BORC_BRANCH`: read from the installer's process only, never stored,
so a machine is never quietly left out of updates. It skips updates, not
safety: winget must still be able to run configuration files, because BORC
cannot work without them, and a winget older than the version BORC was checked
with gets a warning rather than a refusal.

### Modules in BORC's own folder

`Install-Module -Scope CurrentUser` writes to Documents, which may be
redirected, synced, or protected by Defender's controlled folder access: the
installer failed there on a real work computer. BORC saves the modules it
needs with `Save-Module` into `%LOCALAPPDATA%\borc\modules` and loads them by
path. That folder is never protected, and BORC installs nothing in Documents and
leaves `PSModulePath` as it is, which also fits "no lasting change" better. An empty
`Documents\PowerShell\Scripts\InstalledScriptInfos` folder still appears during the
modules step, most likely created by PowerShellGet; nothing depends on it.

The PowerShell 7 profile cannot move out of Documents. When BORC cannot
write it, it explains why and shows the lines to add, rather than failing a
whole setup over a convenience.

### Windows 11 target, Windows 10 22H2 best effort

New machines run Windows 11. Windows 10 is out of support but still in use,
so 22H2 gets a warning rather than a refusal.

### Engine only; recipes in separate repos

The engine stays free of opinions about tools. Recipes are shared and
versioned on their own, and several recipe repos can be used side by side.
