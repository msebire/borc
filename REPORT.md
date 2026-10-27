# borc engine v0.1: report

Latest report on top.

---

## Step 19: installer fix for controlled folder access (2026-10-27)

### Done

- **Bug,** from the maintainer's work computer: the installer stopped at
  "Updating winget" with "Could not find a part of the path
  '...\Documents\WindowsPowerShell\Modules\Microsoft.WinGet.Client\1.29.380'",
  then wrongly advised updating App Installer.
  - **Diagnosis:** `EnableControlledFolderAccess = 1`. Defender blocks
    unknown programs from writing in Documents, where
    `Install-Module -Scope CurrentUser` puts modules. Documents itself was
    normal (not redirected, present).
- **Fix:**
  - **Modules:** `install.ps1` saves `Microsoft.WinGet.Client` with
    `Save-Module` into `%LOCALAPPDATA%\borc\modules\WindowsPowerShell`, and
    setup saves `powershell-yaml` into `%LOCALAPPDATA%\borc\modules\PowerShell`.
    Both are imported by path; the engine loads `powershell-yaml` from there
    when present. A module already available elsewhere is still reused.
  - **Messages:** a module that cannot be installed is named ("Could not
    install the PowerShell module …"), and the App Installer advice only
    appears when `Repair-WinGetPackageManager` itself fails.
  - **Profile:** when the profile (also in Documents) cannot be written,
    setup and `self-update` carry on. borc names controlled folder access
    when it is on, and prints the lines to add by hand.
- **Docs:** `troubleshooting.md` ("Controlled folder access"), `design.md`,
  `CHANGELOG.md`.
- **Tests:** no `Install-Module` anywhere in `install.ps1`; a saved module is
  reused; each error message; `powershell-yaml` saved into borc's folder; the
  profile explanation with controlled folder access on and off. 262 tests
  pass.

### Assumptions

- A module the user already has on `PSModulePath` is used as it is, not
  saved again.

### Questions

- None.

### Deviations

- From the spec ("modules go to -Scope CurrentUser"): they go to
  `%LOCALAPPDATA%\borc\modules` instead, for the reason above. Still per
  user, still no PSGallery trust, and no change to Documents or
  `PSModulePath`.

### To verify

- The installer on the work computer, with controlled folder access on.

---

## Step 18: apply --no-pull (2026-10-26)

### Done

- **`borc apply --no-pull`** applies the config repo and the recipe repos as
  they are:
  - no dirty check and no pull, so uncommitted changes are applied too;
  - no update notice;
  - a recipe repo not cloned yet is still cloned, because its recipes could
    not run otherwise;
  - the steps say so, and the Result shows `pulled: skipped (--no-pull)`.
- **`--what-if --no-pull`** previews the working copy: nothing is fetched,
  and `borc.yaml` and the recipes are read from disk. It combines with
  `--check`, and `apply --no-pull` with `--debug`.
- **The tip:** when the pull is refused (local changes) or fails (diverged
  branch, offline), the Result ends with "tip: borc apply --no-pull applies
  your working copy as it is, without pulling". The refusal message itself
  also says it.
- **Tab completion** offers `--no-pull`.
- **Docs:** the `apply` help page and `commands.md`, `troubleshooting.md`
  ("borc apply refuses to pull"), `getting-started.md` (daily workflow),
  `design.md` and `CHANGELOG.md`.
- **Tests:** a dirty working copy applied with `--no-pull` without pulling;
  the tip after a refusal and after a failed pull; `--what-if --no-pull`
  reading an uncommitted change without fetching; the completion list.
  253 tests pass.
- **Checked by hand** on a throwaway repo: the refusal with its tip, and
  `--what-if --no-pull` showing an uncommitted app as "would be installed".
  A real `apply --no-pull` was not run, as it would run `winget configure`.

### Assumptions

- **Recipe repos are not pulled with `--no-pull` either,** which also makes
  it work offline.

### Questions

- None.

### Deviations

- Beyond the spec, which always pulls: added at the maintainer's request.
  Without the option, borc still refuses to pull over local changes.

### To verify

- A real `borc apply --no-pull` on the maintainer's config.

---

## Step 17: reminder of uncommitted changes at terminal start (2026-10-25)

### Done

- **`src/profile.ps1`** runs at each PowerShell 7 start. When the config
  repo has something left to do, it prints one dark-yellow line, for
  example "borc: 3 uncommitted changes, 1 commit not pushed in D:\settings
  (git -C D:\settings status)". It counts:
  - modified and untracked files, `.gitignore` respected;
  - commits not pushed, as of the last fetch;
  - a branch that was never pushed.

  It is silent when everything is clean, when the folder is not a Git repo,
  or when Git is missing.
- **One `git status`** with `--no-optional-locks`, about 80 ms (135 ms the
  first time), measured on the borc repo.
- **Profile block:** it now loads `src/profile.ps1`, which loads the
  completion and runs the check. `self-update` delivers the block change; the
  profile block test now copies both files, and a new test checks the warning
  from a real repo with a change and an unpushed commit.
- **Tests:** `tests/Status.Tests.ps1` runs on temporary repos (clean,
  modified and untracked, ignored, unpushed, never pushed, not a repo).
- **Docs:** `getting-started.md` (daily workflow), `design.md` and
  `CHANGELOG.md`.

### Assumptions

- **No fetch at start-up:** it would need the network. "Not pushed" is as of
  the last fetch or `borc apply`.
- **`NO_COLOR`** turns the line's colour off, like everything else.

### Questions

- None.

### Deviations

- Beyond the spec: added at the maintainer's request.

### To verify

- The start time on the real config repo, which holds app settings and may
  be larger than the borc repo.

---

## Step 16: a Result at the end of every run (2026-10-25)

### Done

- **The summary ends with `Result:`**, a one-line answer and its detail,
  then a blank line and the log path in dark gray.
- **`--what-if` result:**
  - the headline is "there are changes to apply", "probably nothing to
    apply" (only `may be applied` left; with `--check`, units that could not
    be tested), or "nothing to apply";
  - the detail gives the pulls ("config repo 1 commit to pull", "recipe repo
    acme would be cloned"), the verdict counts and the secrets that would be
    asked for.
- **`apply` result:**
  - "done, with changes", "done; nothing new was pulled or installed",
    restart needed, or winget failure;
  - the detail gives the commits pulled per repo, the packages newly
    installed or at another version (from `winget list` before and after),
    the recipes run, and the secrets stored.
  - A dirty working copy or a plan error gives "nothing was applied: ...".
- **winget's output was probed** on harmless runs. It prints "Unit
  successfully applied." both for a changed unit and for one already in
  place. Its verbose logs record each test result, but without unit names,
  in an internal format, and per process. borc reports recipes as run, and
  says why.
- **One `winget list` call** now answers for all packages, both in
  `--what-if` and around `apply`. A package missing from it (Store apps can
  show under another ID) is still asked about on its own. Redirected
  `winget list` output is not truncated.
- **Docs and tests:** `docs/commands.md` (both result tables),
  `troubleshooting.md`, `design.md` and `CHANGELOG.md`. Tests cover the
  layout, each headline, the details, the one-call list, and the results in
  the command runs. The apply tests now mock `winget list`. 244 tests pass. A
  `--what-if` on a throwaway repo with a pending commit read as expected.

### Assumptions

- **A pull counts as a change** to apply, even if the incoming commits do not
  change what would be installed.
- **"version changed"** covers both upgrades and downgrades: borc only
  compares the versions.

### Questions

- None.

### Deviations

- Beyond the spec: added at the maintainer's request.

### To verify

- The `apply` result after a real run with something to install.

---

## Step 15: Tab completion (2026-10-25)

### Done

- **`src/completion.ps1`** registers a native argument completer for `borc`
  and `borc.cmd`. It completes:
  - the commands, after `borc` and `borc help`;
  - each command's options, with `--check` only after `--what-if`;
  - `@local` recipes (quoted) and the recipes of the cloned repos, after
    `install`, and winget IDs once the word has a dot, through
    `winget complete`;
  - the apps `borc.yaml` lists, after `uninstall`;
  - recipe names, after `search`.
- **Loading:** the profile block dot-sources it from the engine clone, so
  `self-update` keeps it current. It works in Windows PowerShell 5.1 when
  dot-sourced by hand.
- **Tests:** go through `TabExpansion2`, as a real shell does, with
  `BORC_SETTINGS` and `LOCALAPPDATA` set at process level only and
  winget's completion answered by the test. The profile test now runs with
  its own `LOCALAPPDATA` and checks that completion is loaded. 230 tests
  pass.
- **Checked by hand:** the real `winget complete` call returns `Git.GCM` and
  `Git.Git`, and under 5.1 `borc apply --wh` completes to `--what-if`.
- **Docs:** a "Tab completion" section in `docs/commands.md`, plus
  `getting-started.md`, `design.md` and `CHANGELOG.md`.

### Assumptions

- Recipes from clones are listed by folder (`%LOCALAPPDATA%\borc\recipes`),
  so a repo removed from `borc.yaml` still shows until its clone is deleted.
- Once the argument is given, PowerShell's usual file-name completion takes
  over.

### Questions

- None.

### Deviations

- Beyond the spec: added at the maintainer's request.

### To verify

- Pressing Tab in a real Windows Terminal after `borc self-update`.

---

## Step 14: fixed versions (2026-10-25)

### Done

- **`borc.yaml`:** a `winget` entry accepts `version: '<version>'`. An
  unquoted number (YAML reads `1.7` as a number) is an error, and so is
  `version` on an `msstore` entry.
- **Generated configuration:** the version reaches the
  `Microsoft.WinGet/Package` unit. Recipes could already set `version` on
  their own package units; borc now reads it too.
- **`borc upgrade`:** skips every package with a fixed version, from
  `borc.yaml` or a recipe, and says "<id> stays at <version>, the version
  fixed in <where>". When the same package is listed twice, a fixed version
  from either entry wins.
- **`--what-if`:** counts a package with a fixed version as installed only
  in that exact version, read from the version column of `winget list`
  (not the available one), and shows "version 1.7.1 fixed, 1.8.2 is
  installed".
- **Real check** on this machine, through a configuration generated by borc,
  with harmless effects and jq uninstalled afterwards:
  - `jqlang.jq` with `version: '1.7.1'` installed 1.7.1 while 1.8.2 was
    available;
  - a second apply left it at 1.7.1;
  - `--what-if` reported it installed with its version fixed.
- **Docs and tests:**
  - docs: `borc-yaml.md` (a `version` section, real example file, error
    row), `writing-recipes.md`, the `upgrade` help page and
    `commands.md`, a `design.md` entry, `CHANGELOG.md`, and the
    `WingetRules.ps1` comment;
  - tests: parsing, the unit, `winget list` reading on real output, the
    upgrade skip and the verdicts. 216 tests pass.

### Assumptions

- The version is kept in the configuration rather than set with
  `winget pin`, so it is tracked in Git and the same on every machine of a
  branch.

### Questions

- None.

### Deviations

- Beyond the spec, which has no versions: added at the maintainer's request.

### To verify

- What a real apply does when a newer version than the fixed one is already
  installed: downgrade, or a winget error.

---

## Step 13: apply --what-if --check (2026-10-25)

### Done

- **New step:** `borc apply --what-if --check` adds one step, "Testing the
  recipes' units (winget configure test)".
  - Every recipe unit, from the reboot run and the main run, goes through a
    single `winget configure test`, so elevated units ask for one UAC
    prompt. Plain packages are left out: `winget list` already answers for
    them.
  - Each recipe then shows `would be applied` (naming the units that would
    change), `in place`, or `may be applied` with the units that could not
    be tested and why.
- **Command line:** `borc apply --check` without `--what-if` is refused with
  exit code 2.
- **winget's test output, probed on a harmless file** (winget 1.29.380):
  - each unit's `<type> [<name>]` line is followed by "System is (not) in
    the described configuration state.", or by "The configuration unit
    failed while attempting to test…" and the script's error;
  - a unit that depends on one not in place is still tested;
  - no `setScript` runs;
  - the exit code is not 0 as soon as one unit would change, so borc reads
    the lines.

  These strings are in `WingetRules.ps1`, and the real output is a test
  fixture.
- **Checked by hand:** a throwaway repo with its elevated recipes removed (so
  no UAC prompt) gave definite verdicts. The test step took 27 s.
- **Docs and tests:** the `apply` help page, `docs/commands.md`,
  `docs/design.md` and `CHANGELOG.md` are updated. New tests cover the
  parser on the real output, the checked verdicts, the summary wording, the
  refused option and a full `--what-if --check` run with winget mocked.
  209 tests pass.

### Assumptions

- **Unknown output:** a result line borc does not recognise (another winget
  version, or a non-English UI) gives "could not test", and the recipe stays
  `may be applied`.
- **Failed tests:** a unit whose test fails is shown as "could not test",
  with the exception text as the reason.

### Questions

- None.

### Deviations

- None.

### To verify

- `--check` with elevated units: one UAC prompt for all of them.
- winget's result lines under a non-English Windows UI. borc then reports
  "could not test" rather than guessing, but the strings may need adding.

---

## Step 12: verdicts in apply --what-if (2026-10-25)

### Done

- `--what-if` used to list every recipe as "would be applied", because it
  never checked recipes. It now gives each line a verdict from what it can
  know without running recipe code:
  - **Plain apps:** `installed` or `would be installed`.
  - **`would be applied`:** one of the recipe's `Microsoft.WinGet/Package`
    units is missing.
  - **`in place`:** the recipe only installs packages, and all of them are
    there.
  - **`may be applied`:** the packages are there, but the settings units are
    only checked by `borc apply`.
- Under each recipe, borc lists the missing packages, the settings units it
  did not check, and the units skipped for a missing parameter. Reboot
  recipes are listed first, as they run first.
- A count line ends the list, for example "2 would be installed or applied,
  1 may be applied, 3 in place.", with a one-time explanation of "may be
  applied" when it appears.
- The `apply` help page and `docs/commands.md` describe the verdicts.
  `docs/design.md` has an entry, and `CHANGELOG.md` has a line. New tests in
  `tests/Preview.Tests.ps1`; 201 tests pass. A run on the throwaway check
  repo read as expected.

### Assumptions

- A recipe whose units are all skipped (missing parameters) and that has no
  package is `in place`: borc would run nothing for it.

### Questions

- None.

### Deviations

- None.

### To verify

- Nothing new.

---

## Step 11: dependsOn and requires fixed for winget 1.29 (2026-10-24)

### Done

- **Bug:** a recipe's own `dependsOn` made `borc apply` fail with "The
  dependency `[resourceId(...)]` was not found within the configuration"
  (exit code 0x8A15C007). `requires` between recipes generated the same
  form, so it was broken too.
- **Accepted form, found with real `winget configure` runs** (winget
  1.29.380, DSC 3.2.2, Windows 10 22H2, PowerShell 7.6.8). Every unit was
  harmless: Git.Git already installed, `testScript` returning `$true`, no
  elevation.

  | Case | `dependsOn` entry | Result |
  | --- | --- | --- |
  | A | `[resourceId('...PowerShellScript','first')]` | exit 0x8A15C007, "not found" |
  | B | `first` | applied |
  | C | `@local/x: first` | applied |
  | D | `[resourceId('...','@local/x: first')]` | exit 0x8A15C007, "not found" |
  | E | `git package` (Package target) | applied |
  | F | `@local/x: git package` (Package target) | applied |
  | G | `nothing-by-this-name` | exit 0x8A15C007, so names really are checked |
  | H | `@local/x: first`, listed after its dependant | applied, `first` applied first |

  winget's dscv3 path matches `dependsOn` entries against unit names as
  plain text and orders the units itself. The `resourceId()` form never
  works. borc's prefixed names (`@`, `/`, `:`, spaces) are fine.
- **Fix:**
  - `WingetRules.ps1`: `Format-WingetDependsOn` emits the plain name, and
    `ConvertFrom-WingetDependsOn` reads the plain name or the `resourceId`
    form. The comment records what was verified, and how.
  - `Generator.ps1`: a recipe's own entries become the plain prefixed name;
    `requires` adds the plain prefixed names of the required recipe's units.
  - `Recipe.ps1`: new check errors for a `dependsOn` naming something that
    is not a unit of the recipe (with a hint to use `requires`), a unit
    depending on itself, and a `dependsOn` that is not a list. The "no `'`
    in resource names" rule is gone: it only protected the `resourceId`
    expression.
- **End to end:** borc's own generator built a file from harmless `@local`
  recipes (a Package target, a plain and a `resourceId` own `dependsOn`, and
  `requires` across recipes listed in reverse order). A real
  `winget configure` applied all four units in dependency order, exit code 0.
- **Tests:**
  - golden files regenerated;
  - the plain and `resourceId` authoring forms;
  - a new check that every emitted `dependsOn` names a unit of the same run;
  - the new check errors.

  195 tests pass.
- **Docs:** `writing-recipes.md` gets a `dependsOn` rule in the verified
  list, explains plain names and `requires`, and has a new error table. The
  `depends-on` fragment and the `wsl-ubuntu` example now use the plain name.
  `CLAUDE.md` is updated too.

### Assumptions

- Existing recipes keep working: a `resourceId` entry naming a unit of the
  same recipe is turned into the plain name. Recipe authors do not have to
  change anything, but the docs now recommend the plain name.

### Questions

- None.

### Deviations

- None.

### To verify

- Nothing new: item 9 of the fresh-machine checklist is now verified on
  Windows 10 22H2. It still needs a Windows 11 run.

---

## Step 10: readable output (2026-10-24)

### Done

- The maintainer found the output hard to follow: borc's messages, Git's and
  winget's output ran together, and nothing showed where a step or an install
  started and ended. Agreed changes:
  1. **Numbered step headers**, `==> [n/total] ...`, with a blank line
     before each step.
  2. **A start and an end line around each external command**: `> command`,
     the output indented after `|`, then `< done in 14s` or
     `< failed, exit code ..., after 3s`. Codes that are not failures say
     what they mean ("no upgrade available").
  3. **A summary** with each step's result (`done`, `failed`, `restart`)
     and duration, and "Stopped after step n of total" when a run ends early.
  4. **Colours** for the console only: step headers cyan, done green,
     failed red, warnings and restart yellow, tool output dark gray.
     `NO_COLOR` turns them off. The log gets the same lines with the time
     and no colours.
- Steps in every command:
  - `apply`: 5 steps.
  - `apply --what-if`: 4 steps, with the check last so a failure points at
    it.
  - `upgrade`, `uninstall`, `search` and `self-update`: 2 steps each.
  - `install`: 3 steps.
  - setup: 5 steps.
  - `install.ps1`: 5 steps.
- `install.ps1` runs its external commands with `Start-Process`, so their
  output stays on the console as winget draws it, and only the exit code
  comes back. This fixes a bug where git's output was mixed into the value a
  function returned.
- `docs/commands.md` explains how to read the output. `docs/design.md`,
  `CHANGELOG.md` and the tests are updated; 190 tests pass. A sample
  `apply --what-if` on a throwaway repo read as expected.

### Assumptions

- `--what-if` shows the steps in the order fetch, apps, secrets, check.
- The installer's summary covers its own five steps; setup and `borc apply`
  print their own steps and summaries inside step 5.

### Questions

- None.

### Deviations

- None.

### Verified on the maintainer's machine

Run in a real console (the Terminal panel of the Claude app), with read-only
commands only:

- **PowerShell 7:** `apply --what-if` on a throwaway repo shows the steps,
  framed commands and summary as designed.
- **Colours, read back from the console screen buffer:**
  - PowerShell 7: step headers Cyan, `>` default, `|` output DarkGray,
    `< done` Green, `< failed` Red, warnings Yellow, summary lines by
    result.
  - Windows PowerShell 5.1 (installer functions): Cyan, Green and Red as
    designed.
- **The installer under 5.1:**
  - a `winget search` through `Invoke-InstallCommand` shows winget's own
    table, and the function returns exactly the exit code (0, or 128 for a
    failing git);
  - a child `pwsh` started the same way as setup sees an interactive
    console (input not redirected, window width readable), which
    `Read-Host` needs.

### To verify

- Colours in Windows Terminal and the classic console window (the checks
  above ran in the app's terminal).
- An actual prompt answered during setup, and winget's progress bar during a
  real install, through the one-liner.

---

## Step 9: installer fix from the first branch test (2026-10-24)

### Done

- The maintainer's first `BORC_BRANCH` test failed with parse errors at
  line 8 of `install.ps1`. Cause: the UTF-8 BOM. A file run from disk has
  its BOM skipped, but `irm` returns the raw text, so the BOM stayed in
  front of `<#`, the comment block never opened, and its text was parsed as
  code.
- `install.ps1` is now saved without a BOM; it was already ASCII only. The
  exception is recorded in `CLAUDE.md` and `.editorconfig`, and the
  repository test accepts it.
- New tests check that `install.ps1` has no BOM and no non-ASCII byte, and
  that it parses under Windows PowerShell 5.1 when decoded both as UTF-8 and
  as Windows-1252, the ways `irm` may decode it.
- Checked by hand: serving the file locally as `text/plain` and parsing what
  `irm` returns gives 0 errors (the script was not run).

### Assumptions

- Only `install.ps1` is affected: every other PowerShell file is run or
  dot-sourced from disk, where a BOM is needed for Windows PowerShell 5.1.

### Questions

- None.

### Deviations

- `install.ps1` breaks the "BOM for PowerShell files" convention, for the
  reason above.

### To verify

- Item 1 and item 11 of the fresh-machine checklist, through the real
  one-liner.

---

## Final report (2026-10-24)

### Done

Everything is on the branch `develop`, one commit per step. `main` is
untouched: it only receives released work.

- **Install:** `install.ps1` hands over to `src/setup.ps1` for the steps
  that run under PowerShell 7.
- **The `borc` command:** `src/borc.cmd` and `src/borc.ps1` run the module
  in `src/Borc/`, which provides every command of the spec. Its help pages
  are in `src/Borc/help/`.
- **Generator and validation:** `Generator.ps1` builds the merged
  configuration; `Config.ps1`, `Recipe.ps1` and `Plan.ps1` check
  `borc.yaml` and the recipes. All WinGet format rules are in
  `WingetRules.ps1`; the URL constant is in `Constants.ps1`.
- **Starter template and logs:** the template is in `src/Borc/template/`.
  Logs go to `%LOCALAPPDATA%\borc\logs` and the last 20 are kept.
- **`Get-BorcSecret`:** `src/Borc/Get-BorcSecret.ps1`, tested under
  PowerShell 7 and Windows PowerShell 5.1.
- **Tests:** `./build/test.ps1` runs PSScriptAnalyzer (no findings) and 169
  Pester tests, all passing. They cover:
  - parsing and validation;
  - the generator, against golden files;
  - the text edits of `borc.yaml`;
  - the profile block;
  - Git behaviour on temporary repos;
  - secrets and logs;
  - every command with winget mocked;
  - `install.ps1` functions and its parsing under 5.1;
  - the documentation itself.
- **Docs:** the README and the seven pages in `docs/`. Every YAML block in
  them is a file in `docs/examples/`, checked by the tests, and
  `docs/commands.md` is checked word for word against the help pages.
- **Rules for later sessions:** `CLAUDE.md` holds the hard rules and the test
  safety rules.
- **Changelog:** `CHANGELOG.md` lists this work under `[Unreleased]`; the
  version number is set when the release is cut.
- **Branches:** this work is on `develop`, and `main` only receives
  releases (README, Development section). `BORC_BRANCH=develop` installs the
  engine from `develop` to try it before a release.
- **Manual checks:** a test config repo with `@local` recipes for the
  checks is in `tests/manual/`.
- **Real environment:** after every full run, nothing existed in
  `%LOCALAPPDATA%\borc`, neither `BORC_SETTINGS` nor the user `PATH` had
  changed, and no `borc-test:` credential was left.
- **Safe checks:** I ran the five checks below in a throwaway folder. All
  behaved as described.

### Assumptions

The step reports below list them all. The ones with the most effect:

- **Exit codes:** 0 done, 1 failed, 2 usage error, 3010 restart needed.
- **Plain packages:** `winget:` and `msstore:` apps run first in the main
  run, as `Microsoft.WinGet/Package` units with `id` and `source`.
- **Restart detection:** borc compares the CBS and Windows Update registry
  keys before and after each run.
- **A config branch with no upstream** is applied from the local copy.
- **Extra validation:** a duplicate app, a placeholder outside `input`, a
  `'` in a resource name, a WinGet header that differs from the verified
  one, and unknown keys are all errors.
- **`Microsoft.DSC`** is installed as the winget package `Microsoft.DSC`.
- **Reruns of the installer** reuse a `BORC_SETTINGS` that is already a Git
  repo, without asking for the URL again.

### Questions

1. **Plain packages and UAC.** Machine-scope installers run from a
   non-elevated `Microsoft.WinGet/Package` unit may show their own UAC
   prompts, which would break "a single UAC prompt". Should plain packages
   get `securityContext: elevated`? That installs per-user apps from an
   elevated context. **Decision (maintainer, 2026-10-24):** keep them
   non-elevated for now, and decide after the fresh-machine check (item 3).

### Deviations

- **Release model:** instead of release tags, `main` holds released work only
  and `develop` everything else. The one-liner fetches `install.ps1` from
  `main`, the engine is a `main` clone, `self-update` pulls the engine's
  branch, and the update notice compares with that branch. Tags are for
  communication only.
- **Install order:** `install.ps1` clones the engine before the questions,
  so the remaining steps run from the tested module. All of them still
  happen before `borc apply`.
- **`docs/commands.md`** adds a few lines around the help pages (logs, the
  two runs, exit codes). The pages themselves are word for word.

### To verify

#### Safe to run on the maintainer's machine

**Status (2026-10-24):** the maintainer ran all five checks: OK.

Run these in a separate PowerShell 7 window, from the repo root, and close it
afterwards. The environment variables are set for that process only, so logs
and clones stay in `$check`.

```powershell
$check = "$env:TEMP\borc-check"
./tests/manual/New-CheckRepo.ps1 -Path $check
$env:BORC_SETTINGS = "$check\settings"
$env:LOCALAPPDATA = "$check\localappdata"
Import-Module ./src/Borc/Borc.psd1
```

1. **`apply --what-if` changes nothing.** It lists `Git.Git` as installed,
   the four recipes (the reboot one "runs first"), the skipped
   `greeting file` unit, and `BORC_CHECK_SECRET` to be asked for. It ends
   with "Nothing was changed". The status shows nothing and the log shows
   one commit.

   ```powershell
   Invoke-Borc -Arguments apply, --what-if
   git -C $check\settings status --short
   git -C $check\settings log --oneline
   ```

2. **A dirty tracked file blocks the pull.** The refusal lists
   `borc/borc.yaml` and exits with 1 before any winget call. Only run
   `apply` while the file is dirty.

   ```powershell
   Add-Content $check\settings\borc\borc.yaml '# local edit'
   Invoke-Borc -Arguments apply
   git -C $check\settings checkout -- borc/borc.yaml
   ```

3. **Unknown parameter and undeclared secret errors.** Both errors are
   reported together, nothing runs, and the exit code is 1.

   ```powershell
   Copy-Item $check\bad-parameter.borc.yaml $check\settings\borc\borc.yaml -Force
   Invoke-Borc -Arguments apply, --what-if
   git -C $check\settings checkout -- borc/borc.yaml
   ```

4. **`install` and `uninstall` edit `borc.yaml`.** Removing a recipe deletes
   only its line. Git is installed, so `install` skips winget and only adds
   the line back. Never run `uninstall Git.Git` here: it would really
   uninstall Git.

   ```powershell
   Invoke-Borc -Arguments uninstall, '@local/borc-check-reboot'
   git -C $check\settings diff
   ```

   Then remove the line `  - winget: Git.Git` in an editor, and run:

   ```powershell
   Invoke-Borc -Arguments install, Git.Git
   git -C $check\settings diff
   ```

5. **The profile block, on a temporary profile.** Expect one warning for
   `20-broken.ps1`, then the two check lines, then `$check` as the
   location.

   ```powershell
   & (Get-Module Borc) { param($Path) Set-BorcProfileBlock -Path $Path } "$check\profile.ps1"
   Get-Content $check\profile.ps1
   pwsh -NoProfile -Command "Set-Location `$HOME; `$env:BORC_HOME = '$check'; . '$check\profile.ps1'; Get-BorcCheck; Get-BorcCheckAfter; (Get-Location).Path"
   ```

Clean up with `Remove-Item $check -Recurse -Force` after closing the window.

#### Needs a fresh Windows 11 machine

The recipe checks use `tests/manual/settings`. Push it to a test repo (one
branch, for example `check`), or leave the URL empty during install and copy
`borc/cookbook/`, `borc/scripts/` and `borc/borc.yaml` into
`BORC_SETTINGS` afterwards.

1. [ ] **The one-liner with a restricted execution policy.** It works, and
   `Get-ExecutionPolicy -List` is the same before and after.
2. [ ] **Empty URL and new branch.** An empty URL creates the starter repo,
   with nothing committed. A new branch name lists the remote branches and
   creates the branch from the chosen one.
3. [ ] **One UAC prompt.** `borc apply` shows a single UAC prompt for the
   main run (plus one for the reboot run, if any). A second `borc apply`
   changes nothing.
4. [ ] **A missing parameter leaves the default.** Without `greeting`,
   `%LOCALAPPDATA%\borc-check\greeting.txt` does not exist. With
   `greeting: hello` under `@local/borc-check-param`, it does.
5. [ ] **Secrets.** `BORC_CHECK_SECRET` is asked once.
   `%LOCALAPPDATA%\borc-check\secret.txt` reads `found=True elevated=True`.
   The next `apply` does not ask again.
6. [ ] **Reboot recipe.** `@local/borc-check-reboot` runs first, the restart
   message appears, and the exit code is 3010. After the restart, `apply`
   finishes.
7. [ ] **Updates.** `self-update` moves the engine to the latest `main`, and
   `apply` shows the update notice while `main` is ahead. After you edit the
   text inside the borc block of `$PROFILE.CurrentUserAllHosts`, a
   `self-update` puts it back and leaves the rest of the profile alone.
8. [ ] **Terminal.** A new PowerShell 7 terminal opens in `BORC_HOME`,
   `Get-BorcCheck` works, and `20-broken.ps1` only prints a warning.
9. [ ] **Cross-recipe `dependsOn` and the WinGet rules.**
   `%LOCALAPPDATA%\borc-check\requires.txt` exists and the
   `@local/borc-check-requires` unit did not fail. The generated
   configuration next to the log shows the `dependsOn`. The WinGet file
   rules hold on Windows 11.
10. [ ] **Windows 10.** On Windows 10 22H2 the warning appears and the run
    continues.
11. [ ] **Testing a branch.** The one-liner with `BORC_BRANCH` (README,
    Development) installs the engine from that branch. `self-update` follows
    it, and the normal one-liner switches the engine back to `main`. The
    backtick form works from a PowerShell prompt.

Also to verify on a real machine:

- **The DSC form:** the `dependsOn` form, and the prefixed names (with `/`,
  `:` and spaces) inside `resourceId`.
- **winget:** the plain `Microsoft.WinGet/Package` unit form, the
  `winget configure` flags, and the exit codes `0x8A15002B`, `0x8A150014`
  and `0x8A150061`.
- **Restart detection:** the registry keys after enabling a Windows feature.
- **Installer modules:** `Install-Module -Force` under PowerShellGet 1.0,
  and `Repair-WinGetPackageManager -Latest` without admin rights.
- **Elevated units:** `Get-BorcSecret` and `BORC_SETTINGS` inside elevated
  units, and the case where a standard user elevates with another admin
  account.
- **`borc.cmd`** with LF line endings under cmd.exe.
- **Execution policy:** the pwsh 7 default policy lets the profile block
  load `borc/scripts/`.
- **The user `PATH`** change reaches new terminals without a logoff.

---

## Step 8: documentation (2026-10-24)

### Done

- Wrote `README.md` and `docs/`:
  - `getting-started.md`;
  - `borc-yaml.md`;
  - `writing-recipes.md`;
  - `commands.md`;
  - `troubleshooting.md`;
  - `design.md`.
- Every YAML block is a file under `docs/examples/`. The tests check that
  the block matches the file and that borc accepts it: the full example tree
  goes through `Get-BorcPlan` and the generator, and fragments must parse.
- `commands.md` shows every help page; a test checks them word for word.
- The URL test covers the docs, the README, the template and install.ps1.
- Reread the docs against the code. The error tables were missing several
  messages the code produces; I added them.

### Assumptions

- Recipe snippets in `writing-recipes.md` (the header, `dependsOn`, a
  placeholder, a secret, a symlink) are fragment files under
  `docs/examples/fragments/`. They are checked for valid YAML and for the
  exact WinGet header, not run through borc.

### Questions

- None new.

### Deviations

- None.

### To verify

- Nothing new.

---

## Step 7: commands, entry points and install.ps1 (2026-10-24)

### Done

- `Invoke-Borc` reads the arguments and runs `help`, `apply` (`--what-if`,
  `--debug`), `upgrade`, `install`, `uninstall`, `search` and `self-update`.
  `borc help`, `borc help <command>`, `--help` and `-h` show the pages in
  `src/Borc/help/`.
- `src/borc.cmd` (copied to `%LOCALAPPDATA%\borc\bin`, added to the user
  `PATH`) runs `src/borc.ps1` from the engine clone.
- `install.ps1` (Windows PowerShell 5.1) runs these steps, then
  `src/setup.ps1` (pwsh 7) runs `Invoke-BorcSetup`:
  - process-only `Bypass` and TLS 1.2;
  - the OS check;
  - `Microsoft.WinGet.Client` and `Repair-WinGetPackageManager -Latest`;
  - Git, PowerShell 7 and `Microsoft.DSC` through winget;
  - the engine clone on `main`, or on the branch `BORC_BRANCH` names for
    maintainer testing (never stored; rerunning without it goes back to
    `main`).
- The command tests mock winget and Credential Manager. They run on
  temporary Git repos and check:
  - the run order;
  - the restart stop (exit code 3010);
  - a failure exiting 1;
  - the secret prompt;
  - plan errors stopping everything before any run;
  - the dirty working copy refusal;
  - `--debug` naming the failing recipe;
  - `--what-if` changing nothing;
  - the `install`, `uninstall`, `upgrade` and `search` behaviour;
  - cloning, updating and leaving a `BORC_BRANCH` engine, and the update
    notice following the engine's branch.
- A Windows PowerShell 5.1 process checks that `install.ps1` parses.
- After a full run, nothing exists in `%LOCALAPPDATA%\borc`, neither
  `BORC_SETTINGS` nor the user `PATH` changed, and no `borc-test:`
  credential is left.
- 158 tests pass.

### Assumptions

- **Exit codes**: 0 done, 1 failed, 2 usage error, 3010 restart needed
  (the Windows code for "success, restart required").
- **`install` of a recipe** clones its repo if missing, checks the plan with
  the recipe added, asks only for that recipe's missing secrets, runs it on
  its own, then adds the line.
- **`install` of a winget ID** checks `winget show` only when the ID is not
  listed yet.
- **`uninstall` of a recipe** that `borc.yaml` does not list is an error (exit
  code 1).
- **`--what-if` with a dirty working copy** warns and continues, since it
  pulls nothing.
- **Recipe repos missing from disk** are reported by `--what-if` as "not
  cloned yet", and their recipes are not checked.
- **Restart detection** reads the CBS `RebootPending` and Windows Update
  `RebootRequired` keys only. `PendingFileRenameOperations` is skipped,
  because ordinary installers set it all the time.
- **Setup creates `BORC_HOME`** when it does not exist.
- **`self-update` hands over to the updated engine** in a child process,
  which copies `borc.cmd` and `Get-BorcSecret.ps1` again and rewrites the
  profile block between its markers when it changed. A change to any of them
  reaches users with the next update.
- **A config branch with no upstream** (starter template, new branch) is
  applied from the local copy, with a hint to push it.
- **The user `PATH`** is read and written through the registry
  (`REG_EXPAND_SZ`), so unexpanded entries survive.

### Questions

- None.

### Deviations

- None.

### To verify

- The winget exit codes `0x8A15002B` (no applicable upgrade), `0x8A150014`
  (no package found) and `0x8A150061` (already installed).
- `borc.cmd` with LF line endings (forced by `.gitattributes`) under cmd.exe.
- `Install-Module -Force` under the PowerShellGet 1.0 that ships with 5.1,
  without a prompt.
- `winget configure --disable-interactivity` still shows the UAC prompt.

---

## Step 6: Git operations, template, secrets, logs (2026-10-24)

### Done

- `Git.ps1` covers:
  - the dirty working copy refusal;
  - `pull --ff-only`;
  - fetching without merging;
  - reading a file at a ref;
  - the `BORC_SETTINGS` folder check;
  - creating the settings folder (empty URL, empty remote, existing or
    missing branch).
- The starter template is in `src/Borc/template/`.
- Secrets are asked for once and stored as `borc:<NAME>`; only names reach
  the log.
- Logs rotate at 20, together with the generated files of their run.
- The Git tests run on temporary bare remotes. The Credential Manager tests
  use `borc-test:` and clean up; a Windows PowerShell 5.1 process reads the
  secret back.

### Assumptions

- In the starter `.gitignore`, the negation patterns are a commented
  example, because an active `idea/*` would affect people who have no idea
  folder.
- `.gitkeep` files keep the empty `scripts/` and `cookbook/` folders.
- A new branch made from another one has no upstream until the user pushes
  it.

### Questions

- None.

### Deviations

- None.

### To verify

- Nothing new.

---

## Step 5: borc.yaml text edits and profile block (2026-10-24)

### Done

- `ConfigEdit.ps1` adds and removes `apps` items as text. Tests show that
  comments, indentation, CRLF and the rest of the file survive.
- `ProfileBlock.ps1` adds or replaces the marked block and leaves the rest of
  the profile alone. A child pwsh process checks load order, the single
  warning for a broken script, and the move to `BORC_HOME`.
- 79 tests pass.

### Assumptions

- A new item goes after the last real item of `apps` (with its
  continuation lines), so commented examples further down stay in place.
- Removing a recipe item removes its more-indented lines (`parameters` and
  their comments) too.
- "Starts in the user's home folder" means the current folder is exactly
  `$HOME` when the profile runs.

### Questions

- None.

### Deviations

- None.

### To verify

- Nothing new.

---

## Step 4: merged configuration generator (2026-10-24)

### Done

- `Generator.ps1` builds the reboot run and the merged main run, plus the
  one-recipe documents for `--debug` and `install`.
- Golden files are in `tests/fixtures/golden/` (rewrite them with
  `BORC_UPDATE_GOLDEN=1` in the process).

### Assumptions

- Plain `winget` and `msstore` apps come first in the main run, so recipes
  can count on them; recipes follow in `requires` order.
- A recipe's own `dependsOn` entries are renamed to the prefixed names. An
  entry pointing at a dropped unit is removed.
- `requires` on a recipe in the other run adds no `dependsOn`: run order
  already holds.

### Questions

- None.

### Deviations

- None.

### To verify

- The plain package unit form: `Microsoft.WinGet/Package` with `id` and
  `source` (`winget` or `msstore`).

---

## Step 3: borc.yaml and recipe parsing (2026-10-24)

### Done

- `Config.ps1` reads `borc.yaml`, `Recipe.ps1` reads a recipe (borc header,
  WinGet header check, resources, placeholders), and `Plan.ps1` checks them
  against each other and orders recipes by `requires`.
- All problems are collected and reported together.
- Fixtures under `tests/fixtures/` cover parameters, secrets, `reboot`,
  `requires`, elevation and `@local`.
- 39 tests pass.

### Assumptions

- Parameter names match case-insensitively (`npmcache` sets `npmCache`), as
  PowerShell does elsewhere.
- Extra validation errors beyond the spec: a duplicate apps entry, a
  placeholder outside `input`, a resource name containing `'`, two resources
  sharing a name, and unknown keys in `borc.yaml`, the borc header or the
  recipe top level.

### Questions

- None.

### Deviations

- None.

### To verify

- Nothing new.

---

## Step 2: CLAUDE.md and skeleton (2026-10-24)

### Done

- Added `CLAUDE.md` with the hard rules and the test safety rules, pointing
  to `docs/design.md`.
- Added the module skeleton, `Constants.ps1` (the one URL constant),
  `WingetRules.ps1` (every WinGet format rule), the thin wrappers, logging,
  `Get-BorcSecret.ps1` and `build/test.ps1`.
- Removed `build/` from `.gitignore`.

### Assumptions

- Strict mode is level 1 in the module (uninitialised variables only): higher
  levels throw on `.Count` of a single value and on missing YAML keys.
- The one-liner is
  `powershell -NoProfile -ExecutionPolicy Bypass -Command "irm <raw main>/install.ps1 | iex"`.
  It always starts Windows PowerShell 5.1, and `Bypass` applies to that
  process only.

### Questions

- None.

### Deviations

- None.

### To verify

- Nothing new.

---

## Step 1b: answers to the plan questions (2026-10-24)

### Done

- Recorded the maintainer's answers:
  1. **Release model, as recommended.**
     - `main` only holds released work. `develop` holds everything not yet
       released: small changes go straight to it, bigger ones through
       feature branches merged into it.
     - A release adds the version number to the `[Unreleased]` section of
       `CHANGELOG.md` on `develop`, then fast-forwards `main` to that
       commit. The number is chosen at release time, never ahead.
     - `main` stays the default branch on GitHub, so visitors see the
       released docs and the one-liner.
     - The one-liner downloads `install.ps1` from `main`, and install.ps1
       clones the engine on `main` into `%LOCALAPPDATA%\borc\engine`.
     - `self-update` runs `git pull --ff-only` on the branch the engine is
       on.
     - The `apply` notice compares the engine with the latest commit of that
       branch (`git ls-remote`). It still skips silently when offline.
     - Tags, if the maintainer creates them, are for communication only;
       the app never reads them.
  2. **`BORC_BRANCH` for trying unreleased work.** install.ps1 reads it from
     its own process only and clones that branch, usually `develop`. The
     engine clone then stays on it, and the normal one-liner switches it back
     to `main`. The variable is never stored.
  3. **PATH shim**: `%LOCALAPPDATA%\borc\bin\borc.cmd`, with that folder added
     to the user `PATH`.
  4. **Recipes dot-source** `$env:LOCALAPPDATA\borc\Get-BorcSecret.ps1`.
  5. **Recipe files**: `<recipe>.yaml` at the repo root, the same in
     `borc/cookbook/`, with an optional `description:` field in the borc
     header.
  6. **A `requires` target missing from `borc.yaml`** is an error.
  7. **A reboot recipe requiring a normal recipe** is an error.
  8. **Offline `apply`**: borc stops with Git's error.
  9. **`--what-if`** lists every app and recipe after the pull and marks the
     packages `winget list` already shows.
  10. **Prefix form**: `recipes/idea: node cache`. Names containing `'` are
      rejected.
  11. **`uninstall` of an app not in `borc.yaml`** still runs
      `winget uninstall` and says there was no line to remove.

### Assumptions

- The manifest keeps `ModuleVersion = '0.0.0'` until the first release; the
  release commit sets it, together with the changelog section.
- I create no tags.

### Questions

- None open.

### Deviations

- From the spec: "newest release tag" becomes "latest commit of `main`" in
  the one-liner, `self-update` and the update notice. The design reason still
  holds: unfinished work never reaches users, because it stays on `develop`
  until it is released.

### To verify

- The engine clone is a plain `main` checkout. A `self-update` after a
  force-push to `main` fails with Git's fast-forward error.

---

## Step 1: plan (2026-10-24)

### Done

- Created the branch `develop` from `main`. `main` only receives released
  work.
- Read the spec and checked the local tooling: pwsh 7.6.8, Pester 6.2.0,
  PSScriptAnalyzer 1.25.0, powershell-yaml 0.4.12, winget 1.29.380, Git 2.55.
  This machine runs Windows 10 22H2 (19045), so local runs will show the
  Windows 10 warning.
- Wrote this plan. No code yet.

#### Files

```
install.ps1                     bootstrap, Windows PowerShell 5.1, standalone
bin/borc.cmd                    command shim (see Q3)
src/Borc/
  Borc.psd1                     manifest; the version is set at release time
  Borc.psm1                     loads the files below, exports Invoke-Borc
  borc.ps1                      entry point: parses args, dispatches commands
  Constants.ps1                 repo URL, release branch, folder names, credential prefix
  WingetRules.ps1               $schema URL, processor, resource type names,
                                dependsOn form, resource name prefix form
  Private/
    Config.ps1                  Read-BorcConfig, Test-BorcConfig (borc.yaml)
    Recipe.ps1                  Resolve-BorcRecipe, Read-BorcRecipe (header split)
    Generator.ps1               New-BorcConfiguration (merged + reboot run)
    ConfigEdit.ps1              Add-BorcAppEntry, Remove-BorcAppEntry (text edits)
    ProfileBlock.ps1            Get/Set-BorcProfileBlock
    Git.ps1                     dirty check, pull --ff-only, fetch/what-if,
                                clone, branch creation, starter template
    Setup.ps1                   steps install.ps1 hands off to under pwsh 7
    Secrets.ps1                 asks for missing secrets
    Log.ps1                     Start-BorcLog, Write-BorcLog, log rotation
    Reboot.ps1                  pending restart detection
    Release.ps1                 update notice, self-update
    Wrappers/
      Winget.ps1                Invoke-BorcWinget (the only place calling winget)
      CredentialStore.ps1       CredRead/CredWrite P/Invoke (prefix as parameter)
      Environment.ps1           Get/Set-BorcEnvironmentVariable
  Commands/                     one file per command: Apply, Upgrade, Install,
                                Uninstall, Search, SelfUpdate, Help
  help/                         one text page per command (source for borc help)
  template/                     starter config repo
  BorcSecret/                   Get-BorcSecret module, PS 5.1 and 7 (see Q4)
build/test.ps1                  PSScriptAnalyzer + Pester, non-zero exit on failure
tests/
  *.Tests.ps1
  fixtures/                     test recipes, borc.yaml files, golden files
  manual/                       small test config repo with @local recipes
docs/
  getting-started.md  borc-yaml.md  writing-recipes.md  commands.md
  troubleshooting.md  design.md
  examples/                     every YAML shown in the docs, validated by tests
CLAUDE.md  CHANGELOG.md  README.md
```

#### Main flow

- **install.ps1** (5.1): forces process-scope `Bypass` and TLS 1.2, checks the
  OS, installs `Microsoft.WinGet.Client` and runs
  `Repair-WinGetPackageManager -Latest`, then installs or upgrades Git,
  PowerShell 7 and `Microsoft.DSC` through winget and reloads `PATH` from the
  registry. Next it clones the engine on `main` into
  `%LOCALAPPDATA%\borc\engine`. It hands everything else to
  `pwsh -File engine\src\Borc\Setup.ps1`: `powershell-yaml`, the prompts and
  folder check, the config clone, template or branch, the environment
  variables, the shim, the profile block, then `borc apply`. With this split,
  most of the install logic lives in the module and can be tested.
- **Generator**: it reads each recipe and splits off the `borc:` header. It
  checks the WinGet header against the constants, substitutes `{{name}}` in
  `input` (after parsing, so values cannot break the YAML), and drops units
  that use a missing parameter. Names are prefixed and the recipe's own
  `dependsOn` references are rewritten to the prefixed names. Every unit of a
  recipe gets a `dependsOn` on every kept unit of the recipes it `requires`.
  Recipes are sorted by `requires` (a cycle is an error). Plain `winget:` and
  `msstore:` apps become `Microsoft.WinGet/Package` units in the main run. The
  output is two documents, reboot run and main run, written with the header
  from `WingetRules.ps1`.
- **Text edits**: they find the top-level `apps:` block and append an item
  using the existing item indentation. Removing an item takes its
  continuation lines too (for example `parameters:`). The rest of the file is
  left byte for byte.
- **Get-BorcSecret**: C# `CredRead` through `Add-Type`, the same code on 5.1
  and 7. The credential prefix is a parameter so tests use `borc-test:`.

### Assumptions

1. **The engine is a Git clone** on `main` in `%LOCALAPPDATA%\borc\engine`.
   `self-update` runs `git pull --ff-only`. The update notice compares the
   engine's commit with `git ls-remote` of its branch.
2. **Versions are set at release time.** `CHANGELOG.md` keeps an
   `[Unreleased]` section for everything on `develop`; the release commit
   gives it a number and sets the manifest version to match.
3. **Single URL constant**: `install.ps1` is downloaded alone, so it cannot
   read `Constants.ps1`. It keeps a copy of the URL, and a test fails if that
   copy, the one-liner in the README and docs, or any GitHub URL in the docs
   differs from `Constants.ps1`.
4. **`git pull --ff-only`** for the config repo, because a merge would create
   a commit. On divergence borc shows Git's error and stops.
5. **Dirty check**: `git status --porcelain --untracked-files=no`. Untracked
   and ignored files never block.
6. **Restart detection**: the usual registry keys (CBS `RebootPending`,
   Windows Update `RebootRequired`, `PendingFileRenameOperations`), compared
   before and after a run. A restart that was already pending does not stop
   `apply`, otherwise it could loop. A restart needed after the reboot run
   stops `apply` before the main run.
7. **`--debug`**: one `winget configure` run per recipe in `requires` order,
   then one run for the plain packages. It stops at the first failure and
   names the recipe. Each run may show its own UAC prompt.
8. **Rerunning install.ps1** when `BORC_SETTINGS` is already a Git repo
   skips the URL and branch prompts and reuses the clone. A local repo with
   no remote (from an empty URL) counts as "the same repo".
9. **Starter template**: `borc.yaml` with `Git.Git`,
   `Microsoft.PowerShell` and `Microsoft.WindowsTerminal`, plus commented
   recipe, parameter, `@local` and secret examples. `.gitkeep` files keep the
   empty `scripts/` and `cookbook/` folders.
10. **Validation errors** are reported together before anything runs. Beyond
    the spec's checks, they cover: an unknown recipe repo or alias, a missing
    recipe file, a recipe whose WinGet header differs from the verified one,
    a `{{name}}` placeholder not declared in the header, a `requires` cycle,
    an apps entry that is not exactly one of `winget`/`msstore`/`recipe`, and
    a parameter value that is not a quoted string or plain scalar text.
11. **Logs**: every command except `help` writes a log. The generated
    configuration files (no secrets in them) are saved next to the log for
    debugging and rotated with it.
12. **The profile block** reads `$env:BORC_SETTINGS` and `$env:BORC_HOME` at
    shell start instead of hardcoding paths, so moving a folder by hand only
    means changing the variable. It uses a `foreach` statement (not
    `ForEach-Object`) so dot-sourced functions land in the global scope.
13. **`install` with a recipe** validates first, runs the recipe, and adds
    the line only if the run succeeded. The same applies to winget and Store
    apps.
14. **`.gitignore` ignores `build/`**, which would hide `build/test.ps1`. I
    will remove that line.

### Questions

My recommendation comes first in each. Answer "defaults" to take all of
them.

1. **Release model.** The spec moves the engine to "the newest release tag",
   which means knowing the version before releasing and resolving tags in
   the one-liner. Recommended instead:
   - `main` only holds released work, and `develop` everything not yet
     released, directly or through feature branches;
   - a release numbers the changelog's `[Unreleased]` section on `develop`,
     then fast-forwards `main` to that commit;
   - the one-liner, the engine clone and `self-update` follow `main`.

   The alternative is tags as in the spec, with a GitHub API call or a
   release asset to find the newest one.
2. **Trying unreleased work on a machine.** Recommended: install.ps1 reads a
   `BORC_BRANCH` variable from its own process only, never stored, and clones
   that branch (usually `develop`). The engine then follows it until the
   normal one-liner brings it back to `main`. The alternative is a hidden
   `-Ref` parameter.
3. **How `borc` becomes a command.** (a) Add `%LOCALAPPDATA%\borc\bin` (with
   `borc.cmd`, which runs `pwsh -NoProfile -ExecutionPolicy Bypass -File ...`)
   to the user `PATH`. This works in any shell, but it is a persistent change
   the spec does not list (recommended). (b) A `borc` function in the
   profile block, which only works in PowerShell 7.
4. **How a recipe script reaches `Get-BorcSecret`.** Scripts run in a fresh
   process. (a) The recipe dot-sources it:
   `. "$env:LOCALAPPDATA\borc\Get-BorcSecret.ps1"`. This changes nothing on
   the machine (recommended). (b) borc adds a modules folder to the user
   `PSModulePath`, so the function autoloads under 5.1 and 7.
5. **Where a recipe lives in its repo, and its description** (for `search`).
   Recommended: `<recipe>.yaml` at the repo root (`recipes/idea` means
   `idea.yaml` in the repo `recipes`), the same in `borc/cookbook/`, and the
   description is a new optional `description:` field in the borc header.
   The alternative is the first comment line.
6. **`requires` naming a recipe that `borc.yaml` does not list.** Recommended:
   an error before anything runs. The alternative is adding it to the run
   silently.
7. **`requires` across runs.** A normal recipe requiring a `reboot: true`
   recipe works by run order, and borc emits no `dependsOn` for it. A
   `reboot: true` recipe requiring a normal one: recommended error.
8. **Offline `apply`.** If the config repo cannot be fetched: (a) stop with
   Git's error (recommended; matches "trust the tools"), or (b) warn and
   apply the local copy.
9. **`--what-if` "which apps would be installed".** Recommended: read
   `borc.yaml` and the recipes as they would be after the pull, list every
   app and recipe, and mark winget and Store packages that `winget list`
   already shows. Recipe state is not checked, because
   `winget configure test` may itself need UAC.
10. **Resource name prefix.** Recommended `recipes/idea: node cache`. Names
    containing `'` are rejected because they would break the `resourceId`
    expression. The form is one constant, so it is easy to change if DSC
    dislikes `/` or `:` (see To verify).
11. **`uninstall` of an app that is not in `borc.yaml`.** Recommended: still
    run `winget uninstall` and say there was no line to remove. The
    alternative is refusing.

### Deviations

- None in behaviour. Structure only: install.ps1 clones the engine before
  the remaining steps, so the module can run them under pwsh 7. The spec
  lists the command install later, but all of these steps still happen
  before `borc apply`.

### To verify

- The `dependsOn` form
  `[resourceId('<type>','<name>')]` with the 2023/08 schema and DSC 3.2.2.
- The prefixed resource names (`/`, `:` and spaces) inside `resourceId`.
- The `Microsoft.WinGet/Package` resource and its properties (`id`,
  `source: msstore`) under `processor: dscv3`.
- The flags borc passes to `winget configure` (`--accept-configuration-agreements`,
  `--disable-interactivity`) and how the exit code reports a failed unit.
- One UAC prompt for a merged run with several elevated units.
- `Get-BorcSecret` from an elevated unit. This works when the same account
  elevates, but not when a standard user enters another admin account,
  because Credential Manager is per user.
- `BORC_SETTINGS` and `BORC_HOME` are visible inside elevated units.
- `Repair-WinGetPackageManager -Latest` without admin rights, and
  `Install-Module` with the PowerShellGet 1.0 that ships with 5.1.
- Restart detection from the registry after a WSL or Virtual Machine Platform recipe.
- The pwsh 7 default execution policy lets the profile block load
  `borc/scripts/` on a fresh machine.
