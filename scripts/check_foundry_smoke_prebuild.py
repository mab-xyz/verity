#!/usr/bin/env python3
"""Every Verity module a Foundry test compiles on demand is prebuilt by CI.

Tests deploy smoke contracts with `deployCompiledVerityModule("Contracts.X", ...)` or
`_ensureVerityModuleYul("Contracts.X", ...)`. Locally the Yul is compiled on demand,
which needs `lake`. CI's Foundry jobs have no Lean toolchain: they only get the Yul
that the "Pre-build smoke test Yul artifacts" steps of `.github/workflows/verify.yml`
compile from their `smoke_modules=( ... )` lists. A module missing from a list makes
its test fail in CI only, with `lake: command not found`.

Usage: python3 scripts/check_foundry_smoke_prebuild.py [--root DIR]
Silent and exit 0 when every such module is in every list; otherwise lists the
missing ones per list and exits 1.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

_CALL_RE = re.compile(
    r"(?:deployCompiledVerityModule|_ensureVerityModuleYul)\(\s*\"(?P<module>Contracts\.[\w.]+)\"",
    re.S,
)
_LIST_RE = re.compile(r"smoke_modules=\((?P<body>.*?)\)", re.S)
_MODULE_RE = re.compile(r"Contracts\.[\w.]+")


def modules_used_by_tests(root: Path) -> set[str]:
    """Modules the Foundry tests compile on demand (string literal arguments)."""
    used: set[str] = set()
    for path in (root / "test").rglob("*.sol"):
        used.update(m.group("module") for m in _CALL_RE.finditer(path.read_text(encoding="utf-8")))
    return used


def prebuild_lists(root: Path) -> list[set[str]]:
    """The module sets of each `smoke_modules=( ... )` list in verify.yml."""
    text = (root / ".github" / "workflows" / "verify.yml").read_text(encoding="utf-8")
    return [set(_MODULE_RE.findall(m.group("body"))) for m in _LIST_RE.finditer(text)]


def missing_modules(root: Path) -> list[tuple[int, list[str]]]:
    used = modules_used_by_tests(root)
    lists = prebuild_lists(root)
    if not lists:
        return [(-1, sorted(used))]
    return [(i, sorted(used - listed)) for i, listed in enumerate(lists) if used - listed]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args(argv)
    problems = missing_modules(args.root)
    if not problems:
        return 0
    for index, missing in problems:
        where = "no smoke_modules list found in verify.yml" if index < 0 else f"smoke_modules list #{index + 1}"
        print(f"{where}: modules compiled by Foundry tests but not prebuilt by CI "
              "(add them, or the test fails in CI with `lake: command not found`):", file=sys.stderr)
        for module in missing:
            print(f"  {module}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
