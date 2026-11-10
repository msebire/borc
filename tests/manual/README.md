# Manual checks

What the Pester tests cannot prove: they mock winget, so only a real machine shows
that BORC works with it. `New-CheckRepo.ps1` creates a throwaway config repo from
`settings/`, whose `@local` recipes exercise each feature.

## Safe on a machine you use

These checks only read winget's state. Run them in a separate PowerShell 7 window,
from the repo root, and close it afterwards. The variables are set for that process,
so logs and clones stay in `$check`.

```powershell
$check = "$env:TEMP\borc-check"
./tests/manual/New-CheckRepo.ps1 -Path $check
$env:BORC_SETTINGS = "$check\settings"
$env:LOCALAPPDATA = "$check\localappdata"
Import-Module ./src/borc/borc.psd1
```

Only run `apply` as step 2 does, while a tracked file is dirty, so it stops before
winget. A real `borc apply` would act on your real profile whatever these variables
say, because winget units ignore the caller's environment.

1. **`apply --what-if` changes nothing.** It lists `Git.Git` as installed and the
   four recipes, with the reboot one first, says `BORC_CHECK_SECRET` would be asked
   for, and ends with "Nothing was changed". The status shows nothing.

   ```powershell
   Invoke-Borc -Arguments apply, --what-if
   git -C $check\settings status --short
   ```

2. **A dirty tracked file blocks the pull.** The refusal lists `borc/borc.yaml` and
   exits with 1 before any winget call. Nothing is pulled or run while it is dirty.

   ```powershell
   Add-Content $check\settings\borc\borc.yaml '# local edit'
   Invoke-Borc -Arguments apply
   git -C $check\settings checkout -- borc/borc.yaml
   ```

3. **Unknown parameter and undeclared secret.** Both errors are reported together,
   nothing runs, and the exit code is 1.

   ```powershell
   Copy-Item $check\bad-parameter.borc.yaml $check\settings\borc\borc.yaml -Force
   Invoke-Borc -Arguments apply, --what-if
   git -C $check\settings checkout -- borc/borc.yaml
   ```

4. **`uninstall` on a recipe only removes its line.**

   ```powershell
   Invoke-Borc -Arguments uninstall, '@local/borc-check-reboot'
   git -C $check\settings diff
   ```

   Never run `uninstall Git.Git` here: it really uninstalls Git.

5. **The profile block, on a temporary profile.** Expect one warning for
   `20-broken.ps1`, then the two check lines, then `$check` as the location.

   ```powershell
   & (Get-Module borc) { param($Path) Set-BorcProfileBlock -Path $Path } "$check\profile.ps1"
   pwsh -NoProfile -Command "Set-Location `$HOME; `$env:BORC_HOME = '$check'; . '$check\profile.ps1'; Get-BorcCheck; Get-BorcCheckAfter; (Get-Location).Path"
   ```

Clean up with `Remove-Item $check -Recurse -Force` after closing the window.

## On a fresh Windows 11 machine

These checks install software and change the machine, so use a virtual machine or a
machine you can reinstall. Push `settings/` to a test repo, or leave the URL empty
during the install and copy its `borc/` folder into `BORC_SETTINGS` afterwards.

1. **The one-liner with a restricted execution policy.** It works, and
   `Get-ExecutionPolicy -List` is the same before and after.
2. **Empty URL and new branch.** An empty URL creates the starter repo with nothing
   committed, and `hello-borc` works in a new terminal. A new branch name lists the
   remote branches and creates the branch from the chosen one.
3. **The first apply sees `BORC_SETTINGS`.** Setup stores the variable just before
   that apply. Use a config repo with a recipe whose unit reads it, and check that the
   unit got the value, not an empty one.
4. **UAC prompts.** `borc apply` shows one prompt per `winget configure` with elevated
   units. Count the prompts plain packages add, which decides whether they should run
   elevated. A second `borc apply` changes nothing.
5. **A Microsoft Store app.** A `- msstore:` entry with a free app installs through
   `borc apply`. `borc install` takes another path, so it does not prove this.
6. **A missing parameter leaves the default.** Without `greeting`,
   `%LOCALAPPDATA%\borc-check\greeting.txt` does not exist. With `greeting: hello`
   under `@local/borc-check-param`, it does.
7. **Secrets.** `BORC_CHECK_SECRET` is asked once.
   `%LOCALAPPDATA%\borc-check\secret.txt` reads `found=True elevated=True`, and the
   next `apply` does not ask again.
8. **Reboot recipe.** `@local/borc-check-reboot` runs first, the restart message
   appears, and the exit code is 3010. After the restart, `apply` finishes.
9. **Updates.** `apply` shows the update notice while the engine's branch is ahead,
   and `self-update` moves the engine to it, even if the branch was rewritten. After
   you edit the text inside the BORC block of `$PROFILE.CurrentUserAllHosts`,
   `self-update` puts it back and leaves the rest of the profile alone.
10. **Terminal.** A new PowerShell 7 terminal opens in `BORC_HOME`, `Get-BorcCheck`
    works, and `20-broken.ps1` only prints a warning.
11. **`requires` across recipes.** `%LOCALAPPDATA%\borc-check\requires.txt` exists and
    the `@local/borc-check-requires` unit did not fail. The generated configuration
    next to the log shows the `dependsOn`.
12. **A failed first apply.** With a recipe that fails, the installer marks the last
    step `partial`, says BORC is installed, and `borc apply` works in a new terminal.
13. **Testing a branch.** The one-liner with `BORC_BRANCH` (see the README) installs
    the engine from that branch, `self-update` follows it, and the normal one-liner
    switches the engine back to `main`.
14. **The VC++ runtime, on a clean machine.** Note whether `vcruntime140_1.dll` is in
    `System32` before the install. A first apply with an elevated unit works, and the
    installer only installed the runtime if the file was missing. This needs a machine
    that never had the runtime upgraded, such as a new virtual machine.
15. **Agreements.** `acceptAgreements` is in the generated configuration of each
    package unit, and a winget package with agreements installs through `borc apply`.
16. **A fixed version below the installed one.** `borc install` moves the package down
    and ends with `is now at`. `borc upgrade` then shows what is installed if it differs.
17. **`--what-if --check` with an elevated unit.** One UAC prompt, then a definite
    verdict for that unit.
18. **Readable output.** The shield icon and winget's accents and ellipses show properly
    in the console and in the log, and the console's code page is unchanged afterwards.

Windows 10 22H2 is best effort: the installer warns and goes on, and the same checks
apply.
