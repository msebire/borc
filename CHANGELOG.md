# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions are for release communication. `main` only holds released work;
everything not released yet is on `develop` and listed under [Unreleased].
The version number is chosen when the release is cut.

## [Unreleased]

### Added

- `install.ps1`, the one-line installer. It runs under Windows PowerShell 5.1
  and works with a restricted execution policy (bypassed for its own process
  only). It does the OS check, the winget update, Git, PowerShell 7,
  Microsoft.DSC, the PowerShell Gallery modules, the `BORC_SETTINGS` and
  `BORC_HOME` prompts, the config repo clone or starter template, the missing
  branch offer, the environment variables, the `borc` command, the profile
  block, then `borc apply`.
- The `borc` command: `help`, `apply` (with `--what-if` and `--debug`),
  `upgrade`, `install`, `uninstall`, `search` and `self-update`, with one help
  page per command.
- The merged configuration generator:
  - strips the borc header and substitutes `{{name}}` placeholders;
  - drops units whose parameter is missing;
  - prefixes resource names with their recipe;
  - turns `requires` into `dependsOn`;
  - runs `reboot: true` recipes first.
- Validation of `borc.yaml` and recipes, reporting every problem before
  anything runs.
- `Get-BorcSecret`, for PowerShell 7 and Windows PowerShell 5.1, backed by
  Windows Credential Manager.
- The starter template for a new config repo.
- Logs in `%LOCALAPPDATA%\borc\logs`, keeping the last 20 runs.
- Readable output: numbered steps separated by blank lines, a start and an
  end line around every `git` and `winget` command, a summary with each
  step's result and duration, and colours (`NO_COLOR` turns them off), in
  the `borc` command and in the installer.
- `BORC_BRANCH`, for maintainers: installs the engine from another branch
  to test it before release. Rerunning the installer without it goes back to
  `main`.
- `./build/test.ps1`: PSScriptAnalyzer and the Pester tests.
- Documentation: README, getting started, `borc.yaml` reference, writing
  recipes, commands, troubleshooting and design.
