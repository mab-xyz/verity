#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import check_foundry_smoke_prebuild as check

WORKFLOW = """
jobs:
  build:
    steps:
      - run: |
          smoke_modules=(
            Contracts.Smoke.A
            {extra}
          )
      - run: |
          smoke_modules=(
            Contracts.Smoke.A
            Contracts.Smoke.B
          )
"""

TEST = """
contract T {
    function setUp() public {
        a = deployCompiledVerityModule("Contracts.Smoke.A", "A", _smokeYulDir());
        b = deployCompiledVerityModule(
            "Contracts.Smoke.B", "B", _smokeYulDir());
    }
}
"""


class SmokePrebuildTests(unittest.TestCase):
    def _run(self, extra: str) -> tuple[list[tuple[int, list[str]]], int]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".github" / "workflows").mkdir(parents=True)
            (root / ".github" / "workflows" / "verify.yml").write_text(
                textwrap.dedent(WORKFLOW).replace("{extra}", extra))
            (root / "test").mkdir()
            (root / "test" / "T.t.sol").write_text(TEST)
            return check.missing_modules(root), check.main(["--root", str(root)])

    def test_module_missing_from_one_list_is_reported(self) -> None:
        missing, status = self._run("")
        self.assertEqual(status, 1)
        self.assertEqual(missing, [(0, ["Contracts.Smoke.B"])])

    def test_all_lists_complete_is_silent(self) -> None:
        missing, status = self._run("Contracts.Smoke.B")
        self.assertEqual((missing, status), ([], 0))


if __name__ == "__main__":
    unittest.main()
