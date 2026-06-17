#!/usr/bin/env python3
"""Verify every Homebrew task in roles/ has a retry loop.

Homebrew taps, formulae, and casks all hit the network and intermittently fail
with transient errors ("Connection reset by peer", "early EOF", curl timeouts).
Our convention is that every such task carries a retry loop:

    register: <name>
    retries: 3
    delay: 15
    until: <name> is not failed

Ansible has no global "retry everything" knob, so the convention is per-task and
easy to forget on a newly added task. This check fails CI when a
community.general.homebrew{,_tap,_cask} task is missing `until:`.

Run locally:  python3 scripts/check_homebrew_retries.py
Exits 0 if all good, 1 (and lists offenders) otherwise.
"""
from __future__ import annotations

import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required (pip install pyyaml, or it ships with ansible).")

ROLES_DIR = Path(__file__).resolve().parent.parent / "roles"

# Module names that perform network operations and must retry.
HOMEBREW_MODULES = {
    "homebrew",
    "homebrew_tap",
    "homebrew_cask",
    "community.general.homebrew",
    "community.general.homebrew_tap",
    "community.general.homebrew_cask",
}


def iter_tasks(node):
    """Yield every task dict, descending into block/rescue/always."""
    if isinstance(node, list):
        for item in node:
            yield from iter_tasks(item)
    elif isinstance(node, dict):
        for section in ("block", "rescue", "always"):
            if section in node:
                yield from iter_tasks(node[section])
                return
        yield node


def violations_in_file(path: Path) -> list[str]:
    try:
        docs = list(yaml.safe_load_all(path.read_text()))
    except yaml.YAMLError as exc:
        return [f"{path}: YAML parse error: {exc}"]

    found = []
    for doc in docs:
        for task in iter_tasks(doc):
            module = next((k for k in task if k in HOMEBREW_MODULES), None)
            if module and "until" not in task:
                name = task.get("name", "<unnamed>")
                found.append(f"{path}:  {name}  (module: {module})")
    return found


def main() -> int:
    yml_files = sorted(p for p in ROLES_DIR.rglob("*.yml"))
    offenders: list[str] = []
    for path in yml_files:
        offenders.extend(violations_in_file(path))

    if offenders:
        print("Homebrew tasks missing a retry loop (add retries/delay/until):\n")
        for line in offenders:
            print(f"  - {line}")
        print(
            "\nEvery community.general.homebrew{,_tap,_cask} task must set "
            "`until:` (with retries/delay). See scripts/check_homebrew_retries.py."
        )
        return 1

    print(f"OK — all Homebrew tasks across {len(yml_files)} role files have retry loops.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
