#!/usr/bin/env python3
"""Refuse a change to the contracts that does not raise the package version.

Usage: check_version.py BASE_REF

Compares HEAD with BASE_REF. When the change touches what a service builds against
(`src/`, `lakefile.toml`, `lake-manifest.json`, `lean-toolchain`), the `version` of
`lakefile.toml` must be greater than BASE_REF's and must not be released already
(tagged `v<version>` at another commit).
"""
import subprocess
import sys
import tomllib

SURFACE = ("src/", "lakefile.toml", "lake-manifest.json", "lean-toolchain")


def git(*args: str) -> str:
    return subprocess.run(("git", *args), check=True, capture_output=True, text=True).stdout


def parse(lakefile: str, where: str) -> tuple[int, int, int]:
    text = tomllib.loads(lakefile).get("version", "0.0.0")
    parts = text.split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        sys.exit(f"{where}: version {text!r} is not major.minor.patch")
    return (int(parts[0]), int(parts[1]), int(parts[2]))


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    base = sys.argv[1]
    with open("lakefile.toml", encoding="utf-8") as f:
        head_version = parse(f.read(), "HEAD")
    spelled = ".".join(map(str, head_version))

    changed = [
        path
        for path in git("diff", "--name-only", f"{base}...HEAD").splitlines()
        if path.startswith(SURFACE)
    ]
    if not changed:
        print(f"no change to the contracts; version stays {spelled}")
        return

    base_lakefile = subprocess.run(
        ("git", "show", f"{base}:lakefile.toml"), capture_output=True, text=True
    )
    if base_lakefile.returncode != 0:
        print(f"{base} has no lakefile.toml; {spelled} is the first version")
        return
    base_version = parse(base_lakefile.stdout, base)
    base_spelled = ".".join(map(str, base_version))

    listing = "\n".join(f"  {path}" for path in changed)
    if head_version <= base_version:
        sys.exit(
            f"these files changed but the version is still {spelled} "
            f"({base} has {base_spelled}):\n{listing}\n"
            "raise `version` in lakefile.toml"
        )
    if git("tag", "--list", f"v{spelled}").strip():
        tagged = git("rev-parse", f"v{spelled}^{{commit}}").strip()
        if tagged != git("rev-parse", "HEAD").strip():
            sys.exit(f"version {spelled} is already released as v{spelled}; choose a later one")
    print(f"version raised from {base_spelled} to {spelled} for:\n{listing}")


if __name__ == "__main__":
    main()
