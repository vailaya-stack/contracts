# contracts

## GitHub configuration

To set up your new GitHub repository, follow these steps:

* Under your repository name, click **Settings**.
* In the **Actions** section of the sidebar, click "General".
* Check the box **Allow GitHub Actions to create and approve pull requests**.
* Click the **Pages** section of the settings sidebar.
* In the **Source** dropdown menu, select "GitHub Actions".

After following the steps above, you can remove this section from the README file.

## Versions

`version` in `lakefile.toml` is the version of the contracts. Services pin a release by its
tag, `v<version>`.

- A pull request that changes `src/`, `lakefile.toml`, `lake-manifest.json` or
  `lean-toolchain` must raise `version` to one that is not released yet. The `Version`
  workflow checks it with `python3 scripts/check_version.py origin/main`.
- `main` changes only through pull requests, and the check must pass before one merges.
- On every push to `main`, the `Release` workflow tags the commit `v<version>` unless that
  version is released already.

A release is tied to the Lean toolchain and the Mathlib revision it was built on, so moving
either is a new version.
