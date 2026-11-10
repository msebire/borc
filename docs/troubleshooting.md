# Troubleshooting

## Where the log is

Every BORC command except `help` writes a log to `%LOCALAPPDATA%\borc\logs`
and prints its path on the last line, in dark gray:

```
Log: C:\Users\you\AppData\Local\borc\logs\20261024-101500-123-apply.log
```

The configuration files BORC generated for the run sit next to it, with the
same name: `...-apply.reboot.winget.yaml` and `...-apply.main.winget.yaml`.
BORC keeps the last 20 runs. Secret values never appear in either.

## Microsoft Defender blocks the installer

```
The terminator '#>' is missing from the multiline comment.
```

with a Defender alert, **Threat blocked**, category Trojan, whose affected item is
a command line starting with `powershell.exe -NoProfile -ExecutionPolicy Bypass
-Command irm https://raw.githubusercontent.com/...`. That form wraps the installer
in a second PowerShell, which is how malware usually runs a download, so Defender
removes it and nothing runs. It was the documented one-liner before 2026-11-10.

Run the installer from a Windows PowerShell window instead, as the README shows:

```powershell
irm https://raw.githubusercontent.com/msebire/borc/main/install.ps1 | iex
```

## The installer cannot update winget

The installer updates winget with `Repair-WinGetPackageManager -Latest`. When
that fails, it stops with:

```
winget could not be updated: ...
Update App Installer from the Microsoft Store, then run the BORC installer again.
```

Open the Microsoft Store, search for **App Installer**, update it, then run
the one-liner again. Every step of the installer can be run again safely.

Before that, the installer needs the PowerShell module
`Microsoft.WinGet.Client` from the PowerShell Gallery. When it cannot get it,
the message names the module instead:

```
Could not install the PowerShell module Microsoft.WinGet.Client, which BORC uses to update winget: PowerShell Gallery is currently unavailable. ...
```

"Currently unavailable" means PowerShell could not reach the Gallery: a short
Gallery outage, or a company network that blocks it or needs a proxy. Try
again later, or keep the installed winget with `BORC_SKIP_UPDATES=1` (see the
README, "On a managed computer"), which does not need the Gallery for winget.

## Controlled folder access

When Defender's controlled folder access (ransomware protection) is on, it
blocks unknown programs from writing in protected folders such as Documents.
BORC keeps out of them: the PowerShell Gallery modules it needs
(`Microsoft.WinGet.Client`, `powershell-yaml`) go to
`%LOCALAPPDATA%\borc\modules`, which is not protected.

One file still lives in Documents: the PowerShell 7 profile, where BORC adds
its block. If BORC cannot write it, setup goes on and says so:

```
Warning: Could not write the BORC block to C:\Users\you\Documents\PowerShell\profile.ps1: ...
Controlled folder access is on, and it protects the Documents folder that holds this profile. ...
To load borc/scripts and Tab completion in PowerShell 7, add these lines to ...:
```

Either allow `pwsh.exe` in Windows Security (Virus & threat protection >
Ransomware protection > Allow an app through Controlled folder access), then
run `borc self-update`, which writes the block again; or copy the lines BORC
prints into the profile yourself. Your organisation may manage this setting.

## A unit failed

BORC shows winget's output and errors as they come, and adds no retry or skip
logic of its own. When winget reports a failure, `borc apply` ends with:

```
Error: winget configure reported a failure, exit code ... Its errors are shown above.
```

and exits with code 1.

1. Read winget's error just above that line, or in the log.
2. Open the generated configuration next to the log to see the unit as winget
   received it. Resource names start with their recipe, for example
   `recipes/node: npm cache`.
3. Run `borc apply --one-by-one`. It runs the recipes one at a time, then the plain
   packages, and names the failing recipe:

   ```
   Error: The failing recipe is recipes/node.
   ```

   Each run may show its own UAC prompt.
4. Fix the cause (or report it to the recipe repo), then run `borc apply`
   again. Units already in place are skipped.

## Every unit fails with an internal error

```
The configuration unit failed due to an internal error: -532462766
```

When this appears for every unit, without any other explanation, and the run ends
with `exit code 0x8A15C005`, the likely cause is an old VC++ runtime. If the file has
an elevated unit, `winget configure` starts a second process, which then cannot load
`WindowsPackageManager.dll`, and the units that need no elevation fail with it.
Windows records it in **Event Viewer**, under **Windows Logs > Application**: a
**.NET Runtime** error for `ConfigurationRemotingServer.exe`, with
`System.DllNotFoundException`.

The installer installs the runtime when `vcruntime140_1.dll` is missing from
`System32`, and BORC says so after a failed run if that file is missing. An old
runtime may have the file and still lack something, so upgrade it either way
(`arm64` instead of `x64` on an ARM machine):

```powershell
winget upgrade --id Microsoft.VCRedist.2015+.x64
```

Then run `borc apply` again.

## winget rejects a configuration file

BORC's WinGet file rules were verified with winget 1.29, and the installer takes
the latest winget. When a run fails on another version, BORC adds:

```
This is winget 1.30.1, and BORC's configuration files were verified with winget 1.29.380. If the error is about the file itself, see "winget rejects a configuration file" in the troubleshooting page.
```

Most failures have nothing to do with this: a package or a script failed, and
winget's error says so. It matters when the error is about the file, such as its
schema, its processor or a `dependsOn` it cannot find. If so:

1. Run `borc self-update`, in case a newer BORC already handles that winget.
2. If that does not help, report it on the
   [BORC repo](https://github.com/msebire/borc/issues), with the output of
   `borc --version` and `winget --version`, and the configuration file saved next
   to the log.

On a new machine, `BORC_SKIP_UPDATES=1` keeps the winget already installed (see the
README, "On a managed computer"), which helps when that one works.

## Windows needs a restart

Recipes marked `reboot: true` run first. If Windows needs a restart after
them, `borc apply` stops before the rest, prints:

```
Warning: Windows needs a restart. Restart, then run borc apply again.
```

and exits with code 3010. Restart, then run `borc apply` again; there is no
automatic resume. The recipes that already ran are skipped, and the rest of
the configuration runs.

BORC only stops when the restart became needed during its own run. A restart
that was already pending before `borc apply` started does not stop it.

## borc apply refuses to pull

```
Error: These tracked files in D:\settings have uncommitted changes:
  borc/borc.yaml
Commit or discard them, then run borc apply again: BORC does not pull over local changes.
To apply them as they are, without pulling, run borc apply --no-pull.
```

The result at the end repeats it:

```
Result: nothing was applied: commit or discard the local changes listed above.
  tip: borc apply --no-pull applies your working copy as it is, without pulling
```

BORC never mixes a pull with your local changes. If you are still trying out
your changes, run `borc apply --no-pull`: it applies the working copy as it
is, without pulling, so you can commit once it works. `borc apply --what-if
--no-pull` previews it first.

Otherwise, look at the changes with
`git -C D:\settings diff`, then commit them:

```powershell
git -C D:\settings commit -am "Describe the change"
```

or discard them:

```powershell
git -C D:\settings restore borc/borc.yaml
```

Untracked and ignored files never block. If an app keeps changing a tracked
file you do not care about, ignore it in `.gitignore` (see
[getting started](getting-started.md#choosing-what-is-tracked-gitignore)).

If the pull itself fails, because your branch and the remote have diverged or
because you are offline, BORC shows Git's error and the same `--no-pull` tip.
Merge or rebase by hand, then run `borc apply` again; BORC never merges for
you. Offline, `borc apply --no-pull` applies what you have.

## Unknown parameter or undeclared secret

```
Error: borc.yaml or a recipe has problems; nothing was run:
  borc.yaml: recipe recipes/node has no parameter 'npmcach' (it declares: npmCache).
  borc.yaml: recipe recipes/node uses the secret NPM_TOKEN, which is not declared under secrets.
```

Nothing ran. For an unknown parameter, fix the name in `borc.yaml`: the
message lists the parameters the recipe declares. For an undeclared secret,
add it under `secrets` with a short description:

<!-- example: examples/secrets.borc.yaml -->
```yaml
secrets:
  NPM_TOKEN: token for the company npm registry
```

See [the borc.yaml reference](borc-yaml.md#errors) for every message.

## A script in borc/scripts/ is broken

When a script in `borc/scripts/` throws while a PowerShell 7 terminal starts,
you see one warning:

```
WARNING: BORC: my-tools.ps1 failed to load: ...
```

The other scripts still load. Fix the file and open a new terminal, or
dot-source it by hand to see the full error:

```powershell
. D:\settings\borc\scripts\my-tools.ps1
```

## The Windows 10 warning

```
WARNING: This is Windows 10 22H2. BORC targets Windows 11; it continues, on a best effort basis.
```

BORC targets Windows 11. Windows 10 22H2 (build 19045) is out of support but
still usable, so the installer warns and continues. Older Windows versions are
refused.

## Changing or removing a secret

BORC has no command for secrets; Windows Credential Manager already does the
job. BORC stores each secret as a generic credential named `borc:<NAME>`.

- **Change it:** open **Credential Manager** from the Start menu, choose
  **Windows Credentials**, find `borc:NPM_TOKEN` under **Generic Credentials**,
  then **Edit**. Or remove it, and `borc apply` asks for the new value.
- **Remove it:** same place, **Remove**. Or from a terminal:

  ```powershell
  cmdkey /delete:borc:NPM_TOKEN
  ```

The next `borc apply` asks again for any declared secret that is missing.
