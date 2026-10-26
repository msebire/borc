# Troubleshooting

## Where the log is

Every borc command except `help` writes a log to `%LOCALAPPDATA%\borc\logs`
and prints its path on the last line, in dark gray:

```
Log: C:\Users\you\AppData\Local\borc\logs\20261024-101500-123-apply.log
```

The configuration files borc generated for the run sit next to it, with the
same name: `...-apply.reboot.winget.yaml` and `...-apply.main.winget.yaml`.
borc keeps the last 20 runs. Secret values never appear in either.

## The installer cannot update winget

The installer updates winget with `Repair-WinGetPackageManager -Latest`. When
that fails, it stops with:

```
winget could not be updated: ...
Update App Installer from the Microsoft Store, then run the borc installer again.
```

Open the Microsoft Store, search for **App Installer**, update it, then run
the one-liner again. Every step of the installer can be run again safely.

## A unit failed

borc shows winget's output and errors as they come, and adds no retry or skip
logic of its own. When winget reports a failure, `borc apply` ends with:

```
Error: winget configure reported a failure, exit code ... Its errors are shown above.
```

and exits with code 1.

1. Read winget's error just above that line, or in the log.
2. Open the generated configuration next to the log to see the unit as winget
   received it. Resource names start with their recipe, for example
   `recipes/node: npm cache`.
3. Run `borc apply --debug`. It runs the recipes one at a time, then the plain
   packages, and names the failing recipe:

   ```
   Error: The failing recipe is recipes/node.
   ```

   Each run may show its own UAC prompt.
4. Fix the cause (or report it to the recipe repo), then run `borc apply`
   again. Units already in place are skipped.

## Windows needs a restart

Recipes marked `reboot: true` run first. If Windows needs a restart after
them, `borc apply` stops before the rest, prints:

```
Warning: Windows needs a restart. Restart, then run borc apply again.
```

and exits with code 3010. Restart, then run `borc apply` again; there is no
automatic resume. The recipes that already ran are skipped, and the rest of
the configuration runs.

borc only stops when the restart became needed during its own run. A restart
that was already pending before `borc apply` started does not stop it.

## borc apply refuses to pull

```
Error: These tracked files in D:\settings have uncommitted changes:
  borc/borc.yaml
Commit or discard them, then run borc apply again: borc does not pull over local changes.
To apply them as they are, without pulling, run borc apply --no-pull.
```

The result at the end repeats it:

```
Result: nothing was applied: commit or discard the local changes listed above.
  tip: borc apply --no-pull applies your working copy as it is, without pulling
```

borc never mixes a pull with your local changes. If you are still trying out
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
because you are offline, borc shows Git's error and the same `--no-pull` tip.
Merge or rebase by hand, then run `borc apply` again; borc never merges for
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
WARNING: borc: my-tools.ps1 failed to load: ...
```

The other scripts still load. Fix the file and open a new terminal, or
dot-source it by hand to see the full error:

```powershell
. D:\settings\borc\scripts\my-tools.ps1
```

## The Windows 10 warning

```
WARNING: This is Windows 10 22H2. borc targets Windows 11; it continues, on a best effort basis.
```

borc targets Windows 11. Windows 10 22H2 (build 19045) is out of support but
still usable, so the installer warns and continues. Older Windows versions are
refused.

## Changing or removing a secret

borc has no command for secrets; Windows Credential Manager already does the
job. borc stores each secret as a generic credential named `borc:<NAME>`.

- **Change it:** open **Credential Manager** from the Start menu, choose
  **Windows Credentials**, find `borc:NPM_TOKEN` under **Generic Credentials**,
  then **Edit**. Or remove it, and `borc apply` asks for the new value.
- **Remove it:** same place, **Remove**. Or from a terminal:

  ```powershell
  cmdkey /delete:borc:NPM_TOKEN
  ```

The next `borc apply` asks again for any declared secret that is missing.
