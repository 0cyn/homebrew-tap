#!/usr/bin/env python3
"""Validate the permanent stable and development binjad formula matrix."""

import argparse
import json
from pathlib import Path
import re


VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")
SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
FORMULA_PATTERN = re.compile(r"^binjad@(\d+\.\d+\.\d+)\.rb$")


def version_tuple(version):
    if not VERSION_PATTERN.fullmatch(version):
        raise ValueError(f"invalid version: {version}")
    return tuple(int(part) for part in version.split("."))


def formula_fields(path):
    version_match = FORMULA_PATTERN.fullmatch(path.name)
    if not version_match:
        raise ValueError(f"unexpected formula filename: {path.name}")
    binary_ninja_version = version_match.group(1)
    text = path.read_text(encoding="utf-8")
    expected_class = "BinjadAT" + binary_ninja_version.replace(".", "")
    class_match = re.search(r"^class ([A-Za-z0-9]+) < Formula$", text, re.MULTILINE)
    source_match = re.search(r'^\s+revision: "([0-9a-f]{40})",$', text, re.MULTILINE)
    binjad_match = re.search(r'^\s+version "(\d+\.\d+\.\d+)"$', text, re.MULTILINE)
    revision_match = re.search(r"^  revision (\d+)$", text, re.MULTILINE)
    requirement = f"requires Binary Ninja {binary_ninja_version}"
    if not class_match or class_match.group(1) != expected_class:
        raise ValueError(f"{path.name} has the wrong formula class")
    if not source_match or not binjad_match:
        raise ValueError(f"{path.name} lacks an exact source revision or binjad version")
    if requirement not in text:
        raise ValueError(f"{path.name} does not identify its exact Binary Ninja release")
    return {
        "binaryNinjaVersion": binary_ninja_version,
        "sourceRevision": source_match.group(1),
        "binjadVersion": binjad_match.group(1),
        "formulaRevision": int(revision_match.group(1)) if revision_match else 0,
        "developmentCaveat": "development build" in text,
    }


def validate_alias(root, name, version):
    alias = root / "Aliases" / name
    if not alias.is_symlink():
        raise ValueError(f"Aliases/{name} must be a symbolic link")
    expected = Path("../Formula") / f"binjad@{version}.rb"
    if alias.readlink() != expected:
        raise ValueError(f"Aliases/{name} must select binjad@{version}")


def validate(root):
    matrix = json.loads((root / ".github" / "binjad-formulas.json").read_text(encoding="utf-8"))
    if matrix.get("schema") != 1 or not isinstance(matrix.get("formulas"), dict):
        raise ValueError("invalid formula matrix manifest")
    binjad_version = matrix.get("binjadVersion")
    formula_revision = matrix.get("formulaRevision")
    if not isinstance(binjad_version, str) or not VERSION_PATTERN.fullmatch(binjad_version):
        raise ValueError("formula matrix has an invalid binjad version")
    if not isinstance(formula_revision, int) or formula_revision < 0:
        raise ValueError("formula matrix has an invalid formula revision")

    formulae = {}
    for path in sorted((root / "Formula").glob("binjad@*.rb")):
        fields = formula_fields(path)
        formulae[fields["binaryNinjaVersion"]] = fields
    if set(formulae) != set(matrix["formulas"]):
        raise ValueError("formula files do not exactly match the formula matrix")

    stable_versions = []
    dev_versions = []
    for version, record in matrix["formulas"].items():
        version_tuple(version)
        if not isinstance(record, dict) or record.get("channel") not in {"stable", "dev"}:
            raise ValueError(f"invalid formula matrix record for {version}")
        if not SHA_PATTERN.fullmatch(record.get("apiRevision", "")):
            raise ValueError(f"invalid API revision for {version}")
        if not SHA_PATTERN.fullmatch(record.get("sourceRevision", "")):
            raise ValueError(f"invalid source revision for {version}")
        fields = formulae[version]
        if fields["sourceRevision"] != record["sourceRevision"]:
            raise ValueError(f"source revision mismatch for {version}")
        if fields["binjadVersion"] != binjad_version:
            raise ValueError(f"binjad version mismatch for {version}")
        if fields["formulaRevision"] != formula_revision:
            raise ValueError(f"formula revision mismatch for {version}")
        development = record["channel"] == "dev"
        if fields["developmentCaveat"] != development:
            raise ValueError(f"channel caveat mismatch for {version}")
        (dev_versions if development else stable_versions).append(version)

    if stable_versions != [matrix.get("stable")]:
        raise ValueError("formula matrix must select exactly one stable release")
    expected_latest_dev = max(dev_versions, key=version_tuple) if dev_versions else None
    if matrix.get("latestDev") != expected_latest_dev:
        raise ValueError("formula matrix latestDev is not the newest development release")
    validate_alias(root, "binjad", matrix["stable"])
    if expected_latest_dev:
        validate_alias(root, "binjad-dev", expected_latest_dev)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", type=Path, default=Path.cwd())
    options = parser.parse_args()
    validate(options.root.resolve())
    print("binjad formula matrix is valid")


if __name__ == "__main__":
    main()
