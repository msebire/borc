# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions are for release communication. `main` only holds released work;
everything not released yet is on `develop` and listed under [Unreleased].
The version number is chosen when the release is cut.

## [Unreleased]

### Added

- `install.ps1`, the one-line installer: from a blank Windows machine to a working
  configuration, from your config repo or from a starter template.
  `BORC_SKIP_UPDATES` adapts it to managed computers.
- The `borc` command: `apply` (with `--what-if`, `--check`, `--no-pull` and
  `--one-by-one`), `upgrade`, `install`, `uninstall`, `search`, `self-update`, `help` and
  `--version`, with Tab completion in PowerShell 7.
- `borc.yaml`, which lists winget apps, Microsoft Store apps and recipes, with
  optional fixed versions, parameters and secrets.
- Recipes, WinGet Configuration files merged into one run, with recipes that may
  need a restart first. Everything is validated before anything runs.
- `Get-BorcSecret`, backed by Windows Credential Manager.
- A starter template with a README, a welcome banner and an example recipe.
- A reminder in each new PowerShell 7 terminal when the config repo has uncommitted
  or unpushed work.
- Documentation: getting started, `borc.yaml` reference, writing recipes, commands,
  troubleshooting and design.
