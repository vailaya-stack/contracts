#!/usr/bin/env python3
"""Check, or raise, the version of the contracts against a base revision.

Usage: check_version.py [--fix [--level patch|minor|major]] BASE_REF

Compares HEAD with BASE_REF. When the change touches what a service builds against
(`src/`, `lakefile.toml`, `lake-manifest.json`, `lean-toolchain`), the `version` of
`lakefile.toml` must be greater than BASE_REF's and must not be released already
(tagged `v<version>` at another commit).

With `--fix`, nothing is checked: a version below BASE_REF's raised by one `--level` step
is rewritten to that in `lakefile.toml`, uncommitted.
"""
import argparse
import re
import subprocess
import sys
import tomllib

SURFACE = ("src/", "lakefile.toml", "lake-manifest.json", "lean-toolchain")
LAKEFILE = "lakefile.toml"

Version = tuple[int, int, int]


def git(*args: str) -> str:
    return subprocess.run(("git", *args), check=True, capture_output=True, text=True).stdout


def parse(lakefile: str, where: str) -> Version:
    text = tomllib.loads(lakefile).get("version", "0.0.0")
    parts = text.split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        sys.exit(f"{where}: version {text!r} is not major.minor.patch")
    return (int(parts[0]), int(parts[1]), int(parts[2]))


def spell(version: Version) -> str:
    return ".".join(map(str, version))


def step(version: Version, level: str) -> Version:
    major, minor, patch = version
    return {
        "major": (major + 1, 0, 0),
        "minor": (major, minor + 1, 0),
        "patch": (major, minor, patch + 1),
    }[level]


def main() -> None:
    parser = argparse.ArgumentParser(usage=__doc__)
    parser.add_argument("base")
    parser.add_argument("--fix", action="store_true")
    parser.add_argument("--level", choices=("patch", "minor", "major"), default="patch")
    args = parser.parse_args()
    base = args.base

    with open(LAKEFILE, encoding="utf-8") as f:
        text = f.read()
    head_version = parse(text, "HEAD")
    spelled = spell(head_version)

    changed = [
        path
        for path in git("diff", "--name-only", f"{base}...HEAD").splitlines()
        if path.startswith(SURFACE)
    ]
    if not changed:
        print(f"no change to the contracts; version stays {spelled}")
        return

    base_lakefile = subprocess.run(
        ("git", "show", f"{base}:{LAKEFILE}"), capture_output=True, text=True
    )
    if base_lakefile.returncode != 0:
        print(f"{base} has no {LAKEFILE}; {spelled} is the first version")
        return
    base_version = parse(base_lakefile.stdout, base)
    base_spelled = spell(base_version)

    if args.fix:
        target = step(base_version, args.level)
        if head_version >= target:
            print(f"version {spelled} is already at least {spell(target)}")
            return
        raised, count = re.subn(
            r'(?m)^version\s*=\s*"[^"]*"', f'version = "{spell(target)}"', text, count=1
        )
        if count != 1:
            sys.exit(f"{LAKEFILE} has no top-level `version` to raise")
        with open(LAKEFILE, "w", encoding="utf-8") as f:
            f.write(raised)
        print(f"version raised from {spelled} to {spell(target)} ({base} has {base_spelled})")
        return

    listing = "\n".join(f"  {path}" for path in changed)
    if head_version <= base_version:
        sys.exit(
            f"these files changed but version {spelled} is not above the {base_spelled} "
            f"of {base}:\n{listing}\nraise `version` in {LAKEFILE}"
        )
    if git("tag", "--list", f"v{spelled}").strip():
        tagged = git("rev-parse", f"v{spelled}^{{commit}}").strip()
        if tagged != git("rev-parse", "HEAD").strip():
            sys.exit(f"version {spelled} is already released as v{spelled}; choose a later one")
    print(f"version raised from {base_spelled} to {spelled} for:\n{listing}")


if __name__ == "__main__":
    main()
