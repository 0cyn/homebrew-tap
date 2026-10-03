#!/usr/bin/env python3

import json
from pathlib import Path
import tempfile
import unittest

from CheckFormulaMatrix import validate


class FormulaMatrixTests(unittest.TestCase):
    def repository(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / ".github").mkdir()
        (root / "Aliases").mkdir()
        (root / "Formula").mkdir()
        matrix = {
            "schema": 1,
            "binjadVersion": "0.2.0",
            "formulaRevision": 0,
            "stable": "6.0.10601",
            "latestDev": "6.1.10811",
            "formulas": {
                "6.0.10601": {
                    "channel": "stable",
                    "apiRevision": "1" * 40,
                    "sourceRevision": "2" * 40,
                },
                "6.1.10811": {
                    "channel": "dev",
                    "apiRevision": "3" * 40,
                    "sourceRevision": "4" * 40,
                },
            },
        }
        (root / ".github" / "binjad-formulas.json").write_text(json.dumps(matrix), encoding="utf-8")
        self.write_formula(root, "6.0.10601", "2" * 40, development=False)
        self.write_formula(root, "6.1.10811", "4" * 40, development=True)
        (root / "Aliases" / "binjad").symlink_to("../Formula/binjad@6.0.10601.rb")
        (root / "Aliases" / "binjad-dev").symlink_to("../Formula/binjad@6.1.10811.rb")
        return root

    @staticmethod
    def write_formula(root, version, source, development):
        qualifier = " development build" if development else ""
        identifier = version.replace(".", "")
        (root / "Formula" / f"binjad@{version}.rb").write_text(
            f"class BinjadAT{identifier} < Formula\n"
            f"  url \"https://github.com/0cyn/binjad.git\",\n"
            f"      revision: \"{source}\",\n"
            f"      using:    :git\n"
            f"  version \"0.2.0\"\n"
            f"  # requires Binary Ninja {version}{qualifier}\n"
            "end\n",
            encoding="utf-8",
        )

    def test_complete_matrix(self):
        validate(self.repository())

    def test_missing_formula(self):
        root = self.repository()
        (root / "Formula" / "binjad@6.1.10811.rb").unlink()
        with self.assertRaisesRegex(ValueError, "do not exactly match"):
            validate(root)

    def test_wrong_dev_alias(self):
        root = self.repository()
        (root / "Aliases" / "binjad-dev").unlink()
        (root / "Aliases" / "binjad-dev").symlink_to("../Formula/binjad@6.0.10601.rb")
        with self.assertRaisesRegex(ValueError, "must select"):
            validate(root)


if __name__ == "__main__":
    unittest.main()
