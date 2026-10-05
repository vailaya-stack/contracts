# contracts

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
- Each service checks hourly for a new release and opens its own upgrade pull request. With
  a secret `SERVICES_DISPATCH_TOKEN` that can write to the services, `Release` starts those
  checks at once.

A release is tied to the Lean toolchain and the Mathlib revision it was built on, so moving
either is a new version.
