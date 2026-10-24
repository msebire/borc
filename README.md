# borc

**Blank to Operational, Rejoin the Collective.**

*Resistance is futile.*

borc is a Windows-only tool that turns a blank machine into a working
developer workstation. winget is the package manager; borc is a thin layer on
top of it. It installs your apps through winget and the Microsoft Store,
applies recipes that wire each tool up, and keeps your settings in one Git
repo that apps read from directly. It is built on WinGet Configuration
(DSC v3) and PowerShell.

## Install

Open a terminal (Windows Terminal, PowerShell or cmd) and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/msebire/borc/main/install.ps1 | iex"
```

This works even when the execution policy blocks scripts. The policy is
bypassed for this one process and left as it is.

## Five-minute quick start

1. Run the one-liner above.
2. When it asks for `BORC_SETTINGS`, give a folder for your settings, for
   example `D:\settings`. For `BORC_HOME`, give your home base, for example
   `D:\sources`.
3. When it asks for the config repo URL, press Enter. borc creates a new local
   repo in `D:\settings` from a starter template.
4. Give a branch name for this machine, for example `home`.
5. borc runs `borc apply`, which installs the few apps of the starter
   `borc/borc.yaml`.

Then:

- edit `D:\settings\borc\borc.yaml` to add apps, or run
  `borc install Microsoft.VisualStudioCode`;
- run `borc apply` again;
- when you are happy, commit, add a remote and push. borc never commits or
  pushes for you.

Run `borc help` for every command.

## Documentation

- [Getting started](docs/getting-started.md): the config repo, branches,
  folders, `.gitignore` and the daily workflow.
- [borc.yaml reference](docs/borc-yaml.md): every key, and every error.
- [Writing recipes](docs/writing-recipes.md): the borc header, the WinGet file
  rules and a complete example.
- [Commands](docs/commands.md): every command and option.
- [Troubleshooting](docs/troubleshooting.md).
- [Design](docs/design.md): why borc is the way it is.

## Development

The engine lives in `src/`, its tests in `tests/`. Run every check with:

```powershell
./build/test.ps1
```

It runs PSScriptAnalyzer and all Pester tests (Pester 5.5 or later), and exits
with a non-zero code on any failure. `./build/test.ps1 -Filter Generator` runs
only the test files whose name contains `Generator`.

The tests never touch the real machine: Credential Manager tests use the
`borc-test:` prefix and clean up, environment variables stay in the test
process, and Git and profile tests work in temporary folders.

### Branches and releases

- `main` only holds released work. The one-liner installs from it.
- `develop` holds everything not yet released. Small changes go straight to
  it; bigger ones go through a feature branch merged into it.
- A release gives the `[Unreleased]` section of [CHANGELOG.md](CHANGELOG.md)
  its version number and sets `ModuleVersion` in `src/Borc/Borc.psd1`, in a
  commit on `develop`. Then `main` is fast-forwarded to that commit with
  `git push origin develop:main`. The number is chosen at release time,
  never ahead.
- An urgent fix while `develop` holds unfinished work: branch from `main`,
  release the fix, then merge `main` back into `develop`.

### Testing a branch before releasing it

To try unreleased work on a machine, usually `develop` or a feature branch,
set `BORC_BRANCH` for the installer's process only, from a PowerShell prompt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "`$env:BORC_BRANCH='my-branch'; irm https://raw.githubusercontent.com/msebire/borc/my-branch/install.ps1 | iex"
```

- The installer warns, then clones the engine on `my-branch`. On a machine
  where borc is already installed, it switches the engine to that branch.
- From then on, the clone remembers the branch, not the variable: `borc`
  runs that branch, `borc self-update` pulls its new commits, and
  `borc apply` notices when the branch has moved on.
- To go back to the release, run the normal one-liner, without
  `BORC_BRANCH`. The installer switches the engine back to `main`.

The variable is never stored, so a machine cannot stay on a test branch by
accident. The URL above takes `install.ps1` from the branch itself, which
also tests your changes to the installer.

## License

See [LICENSE](LICENSE).
