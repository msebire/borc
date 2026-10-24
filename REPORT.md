# borc engine v0.1: report

Latest report on top.

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
