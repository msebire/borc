# CLAUDE.md

Repository conventions for Claude Code sessions.

- Line endings: LF everywhere, PowerShell files included (enforced by `.gitattributes`).
- Indentation: 2 spaces, no tabs.
- Encoding: UTF-8 with BOM for PowerShell files (`*.ps1`, `*.psm1`, `*.psd1`) so
  Windows PowerShell 5.1 reads them correctly; UTF-8 without BOM for everything else.
  Exception: `install.ps1` has no BOM and stays ASCII only, because the one-liner
  pipes it through `irm | iex`, where a BOM becomes a character that breaks the
  parsing. The tests check both.
- Every file ends with a newline; trim trailing whitespace (except in Markdown).
- Never commit secrets: no tokens, passwords, keys or credentials, not even in examples.

## Why BORC is the way it is

Read `docs/design.md` before changing behaviour. It records the principles and
the reason for each design decision. A change that makes a new decision adds an
entry there.

Behaviour is described in one place only: the user docs under `docs/` and the
help pages in `src/borc/help/`. Any behaviour change updates them in the same
commit. Every YAML example in the docs is a real file under `docs/examples/`,
checked by the tests.

## Hard rules

The WinGet file rules were verified on a real machine (winget 1.29.380, DSC
3.2.2). Follow them exactly, and keep them in `src/borc/WingetRules.ps1` only:

- `$schema: https://raw.githubusercontent.com/PowerShell/DSC/main/schemas/2023/08/config/document.json`.
  Never switch to the `aka.ms/dsc/schemas/v3/...` URLs: winget 1.29 rejects them.
- `metadata: winget: processor: dscv3`.
- Script resources: `Microsoft.DSC.Transitional/PowerShellScript` (PowerShell 7)
  and `Microsoft.DSC.Transitional/WindowsPowerShellScript` (Windows PowerShell 5.1).
- `input` passes the values, and each script declares exactly one `param`.
- `testScript` outputs exactly one boolean.
- Elevation goes through `metadata: securityContext: elevated`.
- `Microsoft.WinGet/Package` units set `acceptAgreements: true`: without it, a package
  with agreements fails, and `--accept-configuration-agreements` does not reach it.
- `dependsOn` entries are plain unit names. winget 1.29 never finds the
  `[resourceId('<type>','<name>')]` form from the DSC docs (verified with real
  `winget configure` runs; `winget configure test` accepts anything).

If a rule looks wrong, keep it and raise the doubt with the maintainer.

Other rules:

- Secret values never appear in files, logs or the generated configuration.
- BORC never commits or pushes in the user's config repo.
- Every step is idempotent.
- `install` and `uninstall` edit the `apps` list of `borc.yaml` as text, so
  comments and formatting survive. Never rewrite the file through a YAML serializer.
- No package manager other than winget and the Microsoft Store, except the
  PowerShell Gallery modules the docs name, and inside a recipe's own script.
- The engine repo URL lives in `src/borc/Constants.ps1`. `install.ps1` keeps a
  copy, and the tests check that every copy matches.
- Branches: `main` only holds released work, and `develop` everything not yet
  released. Commit small changes straight to `develop`; bigger ones go through a
  feature branch merged into it. Never push or merge into `main` unless the
  maintainer asks: a release fast-forwards `main` to a commit of `develop`.
  Never write a version number ahead of the release. Try a branch on a real
  machine with `BORC_BRANCH` (see the README); never store that variable.
- Naming: the product is BORC, in uppercase, in prose, messages and comments.
  Lowercase is only for what is typed or on disk: the `borc` command, `borc.yaml`,
  the `borc/` folders, `%LOCALAPPDATA%\borc`, the `borc:` recipe key, `borc:<NAME>`
  credentials, and the profile markers `# >>> borc >>>`, which existing profiles contain.
  Folders in the repo are lowercase too, including the module's (`src/borc/`,
  `commands/`, `private/`). PowerShell names stay as PowerShell expects:
  `Invoke-Borc`, `Get-BorcSecret`, `$script:BorcRepoUrl`.
- Keep the code readable: small functions, comments only where the intent is not obvious.

## Test safety rules

Tests run on the maintainer's own Windows machine and must never touch the real
environment:

- Credential Manager tests use the `borc-test:` prefix and clean up after themselves.
- Environment variables are set at process level only.
- PowerShell profile tests work on a temporary file.
- Git tests run in temporary folders.
- Never run a real `winget install`, `winget configure` or `install.ps1` without
  asking the maintainer first. A process-level variable does not contain a real
  `winget configure`: its units ignore the caller's environment and act on the
  real profile.
- winget, Credential Manager and environment variables sit behind thin wrappers
  in `src/borc/private/wrappers/`; tests mock them.

Run everything with `./build/test.ps1` (PSScriptAnalyzer and Pester).
