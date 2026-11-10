# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions are for release communication. `main` only holds released work;
everything not released yet is on `develop` and listed under [Unreleased].
The version number is chosen when the release is cut.

## [Unreleased]

### Fixed

- A failed `borc apply` says when Windows now needs a restart, which may be why
  units failed, such as a package that needs a Windows feature enabled in the same run.

## [0.1.1] - 2026-11-10

### Changed

- The install one-liner is now `irm ... | iex`, run in a Windows PowerShell
  window. Microsoft Defender blocks the former
  `powershell -ExecutionPolicy Bypass -Command` form as a Trojan.

### Fixed

- The installer enables winget's configuration features, which a new machine may
  have off, and `borc apply` says how to enable them when winget refuses to run.

## [0.1.0] - 2026-11-10

The first release.

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
