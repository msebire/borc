# borc.yaml reference

`borc/borc.yaml` in the config repo describes what borc installs on this
machine. It has three top-level keys, all optional: `recipes`, `apps` and
`secrets`.

<!-- example: examples/settings/borc/borc.yaml -->
```yaml
recipes:
  - repo: https://github.com/someone/recipes.git
  - repo: https://github.com/acme/recipes.git
    alias: acme
apps:
  - winget: Git.Git
  - msstore: 9NBLGGH4NNS1
  - recipe: recipes/node
    parameters:
      npmCache: D:\caches\npm
  - recipe: '@local/wsl-ubuntu'
secrets:
  NPM_TOKEN: token for the company npm registry
```

borc checks the whole file, and every recipe it lists, before anything runs.
All problems are reported together; nothing is installed until they are
fixed.

## recipes

The recipe repos to use. Each entry has:

| Key | Required | Meaning |
| --- | --- | --- |
| `repo` | yes | The Git URL of the recipe repo. |
| `alias` | no | The name to use for this repo. Needed when two repos share a Git repo name. |

A repo is named after its Git repo name, the last part of the URL without
`.git`: `https://github.com/someone/recipes.git` is `recipes`. In the example
above, both repos are called `recipes`, so the second one gets the alias
`acme`.

borc clones each repo into `%LOCALAPPDATA%\borc\recipes\<name>` and pulls it
on every `borc apply`. A recipe `recipes/node` is the file `node.yaml` at the
root of the `recipes` repo.

## apps

The apps to install, in order. Each entry has exactly one of these keys:

| Key | Value | Example |
| --- | --- | --- |
| `winget` | A winget package ID. | `- winget: Git.Git` |
| `msstore` | A Microsoft Store ID. | `- msstore: 9NBLGGH4NNS1` |
| `recipe` | A recipe, as `repo/recipe`. | `- recipe: recipes/node` |

Find IDs with `borc search <term>`, or add an app with `borc install`, which
edits this list for you and keeps your comments and formatting.

### version

A `winget` entry can fix the version to install, instead of the latest one:

<!-- example: examples/version.borc.yaml -->
```yaml
apps:
  - winget: jqlang.jq
    version: '1.7.1'
```

- Quote the value: YAML would read `1.7` as a number.
- `winget show --id <id> --versions` lists the versions available.
- `borc upgrade` leaves a package with a fixed version alone, and says so.
  To move to another version, change the value and run `borc apply`.
- `--what-if` counts the app as installed only when this exact version is
  installed.
- `msstore` entries have no version: the Store always installs the current
  one.

### @local recipes

`@local/<name>` is a recipe of your own, in `borc/cookbook/<name>.yaml` of
the config repo. It needs no `recipes` entry. Quote it, because YAML gives
`@` a special meaning at the start of a value:

<!-- example: examples/local-recipe.borc.yaml -->
```yaml
apps:
  - recipe: '@local/wsl-ubuntu'
```

### parameters

A recipe entry can set the parameters its recipe declares:

<!-- example: examples/parameters.borc.yaml -->
```yaml
recipes:
  - repo: https://github.com/someone/recipes.git
apps:
  - recipe: recipes/node
    parameters:
      npmCache: D:\caches\npm
```

- Values are strings. Quote values YAML would read as something else, such
  as `'8080'` or `'true'`.
- Parameters are optional. A parameter you leave out leaves the tool's
  default untouched: borc skips the part of the recipe that would set it.
- A parameter the recipe does not declare is an error. This catches typos
  before anything runs. `borc search` shows a recipe's description, and the
  recipe file lists its parameters in its `borc:` header.
- Parameter names match without regard to case.

## secrets

Every secret a listed recipe reads, by name, with a short description:

<!-- example: examples/secrets.borc.yaml -->
```yaml
secrets:
  NPM_TOKEN: token for the company npm registry
```

On `borc apply`, borc asks once for each declared secret that Windows
Credential Manager does not hold yet, and stores it there as `borc:<NAME>`.
Values never go in the config repo, the logs or the generated configuration.
To change or remove a secret, use Windows Credential Manager (see
[troubleshooting](troubleshooting.md#changing-or-removing-a-secret)).

Names use letters, digits and `_`.

## Errors

borc reports these before anything runs. Fix the file, then run the command
again.

### In borc.yaml

| Message | Meaning |
| --- | --- |
| `borc.yaml not found: <path>` | `BORC_SETTINGS` has no `borc/borc.yaml`. Check the variable points at the config repo. |
| `invalid YAML: ...` | The file is not valid YAML. The message gives the line. |
| `expected keys recipes, apps and secrets at the top level.` | The file is a list or a single value instead of keys. |
| `unknown key '<key>'. Expected recipes, apps or secrets.` | A top-level key borc does not know, often a typo such as `app:`. |
| `recipes must be a list of '- repo: <url>' entries.` | `recipes` holds something other than a list. |
| `each recipes entry needs a repo URL.` | A `recipes` entry without `repo`. |
| `unknown key '<key>' in the recipes entry for <url>.` | Only `repo` and `alias` are allowed. |
| `'<name>' is not a valid recipe repo name or alias (letters, digits, '.', '_' and '-').` | Choose another alias. |
| `apps must be a list.` | `apps` holds something other than a list. |
| `the <kind> entry under apps needs a value.` | For example `- winget:` with nothing after it. |
| `parameters of <id> must map each parameter name to a value.` | `parameters` holds a list or a single value. |
| `secrets must map each secret name to a short description.` | `secrets` holds a list or a single value. |
| `two recipe repos are named '<name>'. Give one of them an alias.` | Two `recipes` entries end with the same Git repo name. |
| `each apps entry needs exactly one of winget, msstore or recipe.` | An `apps` entry has none of these keys, or more than one. |
| `unknown key '<key>' in the apps entry for <id>.` | For example `parameters` under a `winget` entry, or `version` under an `msstore` entry. |
| `'<value>' is not a recipe reference. Use repo/recipe or @local/<name>.` | A `recipe` value without the `repo/` part. |
| `recipe <id> refers to the repo '<repo>', which is not listed under recipes.` | Add the repo under `recipes`, or fix the name or alias. |
| `parameter <name> of <id> must be a string. Quote the value, ...` | A number, `true` or a list where a string is expected. |
| `version of <id> must be a string. Quote it, ...` | `version: 1.7` without quotes, which YAML reads as a number. |
| `<kind> <id> is listed twice under apps.` | The same app appears twice. |
| `'<name>' is not a valid secret name (letters, digits and '_').` | Rename the secret. |

### Between borc.yaml and the recipes

| Message | Meaning |
| --- | --- |
| `recipe <id> not found: <path>` | No such file in the recipe repo, or in `borc/cookbook/` for `@local`. |
| `recipe <id> has no parameter '<name>' (it declares: ...)` | Unknown parameter: a typo, or a parameter the recipe does not offer. |
| `recipe <id> uses the secret <NAME>, which is not declared under secrets.` | Undeclared secret: add it under `secrets` with a description. |
| `recipe <id> requires <other>, which borc.yaml does not list under apps.` | Add the required recipe to `apps`. |
| `recipe <id> is marked reboot: true and runs first, so it cannot require <other>, which is not.` | A recipe author's problem: report it to the recipe repo. |
| `recipes require each other in a loop: a -> b -> a.` | A recipe author's problem, as above. |

Errors inside a recipe file start with `recipe <id>:` and are described in
[writing recipes](writing-recipes.md#errors).
