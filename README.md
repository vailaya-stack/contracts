# contracts

The contracts the services of vailaya-stack are written against, in Lean 4 with Mathlib.

## Where files go

| File | Module | Holds |
|---|---|---|
| `src/Contracts.lean` | `Contracts` | Only imports: one line per file below, so `import Contracts` gives everything. |
| `src/Contracts/Utils.lean` | `Contracts.Utils` | What every contract is stated with. |
| `src/Contracts/SortService.lean` | `Contracts.SortService` | The contract of the sort service. |
| `src/Contracts/MinService.lean` | `Contracts.MinService` | The contract of the min service. |

A file `src/Contracts/A/B.lean` is the module `Contracts.A.B`, and another file imports it with
`import Contracts.A.B`. `lake build` compiles every `.lean` file under `src/Contracts/`, whether
or not `src/Contracts.lean` imports it. A `.lean` file anywhere else, such as directly in `src/`
or at the top of the repository, belongs to no library: Lake does not compile it and nothing can
import it.

## Working locally

Open the `contracts` folder itself in the editor, not its parent, so Lean finds
`lean-toolchain` and `lakefile.toml`.

```sh
lake exe cache get                     # once per clone: download Mathlib's build
lake build                             # compile everything; errors show here
lake lean src/Contracts/Utils.lean     # compile one file
```

To try a change in a service before releasing it, leave the change uncommitted here and, in
the service, turn on its local override (its README has the commands). The service then builds
this folder as it is on disk.

Before opening a pull request, commit and run

```sh
python3 scripts/check_version.py origin/main
```

It says whether the change needs a new version. The pull request raises it when you did not.

## Versions

`version` in `lakefile.toml` is the version of the contracts. Services pin a release by its
tag, `v<version>`.

- `main` changes only through pull requests, from a branch that is up to date with it.
- A pull request that changes `src/`, `lakefile.toml`, `lake-manifest.json` or
  `lean-toolchain` must raise `version` to one that is not released yet
  (`python3 scripts/check_version.py origin/main`). When it did not, the `Version` workflow
  raises it on the branch: by a patch step from `main`'s version, or by the step the pull
  request's `minor` or `major` label names.
- On every push to `main`, the `Release` workflow tags the commit `v<version>` unless that
  version is released already. Release tags cannot be moved or deleted.
- `Release` then tells each service, which opens its own upgrade pull request. The services
  also check hourly, in case that was missed.

Workflows that write to another repository, or push commits whose checks must run, act as the
org's GitHub App `vailaya-stack-app`, with the org variable `BOT_APP_ID` and the org secret
`BOT_PRIVATE_KEY`.

A release is tied to the Lean toolchain and the Mathlib revision it was built on, so moving
either is a new version.
