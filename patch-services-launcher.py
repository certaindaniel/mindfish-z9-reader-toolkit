#!/usr/bin/env python3
"""Rebuild the Z9 R9 services.jar Launcher change from its own exact original."""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


EXPECTED_ORIGINAL_SHA256 = "4cdbfb20a84956a93609f4740d8d114a13470085cc1fa92348517be619c13c7d"
EXPECTED_ARCHIVE_ENTRIES = {
    "META-INF/ANDROID.RSA",
    "META-INF/ANDROID.SF",
    "META-INF/MANIFEST.MF",
    "classes.dex",
}
OLD_PACKAGE = '"com.smart.arkbook"'
NEW_PACKAGE = '"cn.modificator.launcher"'
OLD_ACTIVITY = '"com.smart.sarkbook.MainActivity"'
NEW_ACTIVITY = '"cn.modificator.launcher.Launcher"'
DEX_MAGIC = b"dex\n035\0"
METHOD_START = re.compile(r"^\s*\.method\b.*\bsetDefaultLauncher\s*\(")


class PatchError(Exception):
    """An expected input or patching precondition was not met."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run_java_tool(java: str, jar: Path, args: list[str]) -> None:
    command = [java, "-jar", str(jar), *args]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        details = result.stdout.strip()
        raise PatchError(
            f"Tool failed ({jar.name}, exit {result.returncode})"
            + (f":\n{details}" if details else ".")
        )


def matching_methods(smali_root: Path, package_literal: str, activity_literal: str):
    candidates = []
    for source in smali_root.rglob("*.smali"):
        lines = source.read_text(encoding="utf-8").splitlines()
        index = 0
        while index < len(lines):
            if not METHOD_START.search(lines[index]):
                index += 1
                continue

            start = index
            while index < len(lines) and not lines[index].strip() == ".end method":
                index += 1
            if index == len(lines):
                raise PatchError(f"Unterminated method block in {source}")
            end = index
            block = "\n".join(lines[start : end + 1])
            if package_literal in block and activity_literal in block:
                candidates.append((source, lines, start, end))
            index += 1

    return candidates


def find_target_method(smali_root: Path, package_literal: str, activity_literal: str):
    candidates = matching_methods(smali_root, package_literal, activity_literal)
    if len(candidates) != 1:
        raise PatchError(
            "Expected exactly one setDefaultLauncher() containing both original SarkBook strings; "
            f"found {len(candidates)}. The framework layout may differ."
        )
    return candidates[0]


def patch_smali_tree(smali_root: Path) -> None:
    source, lines, start, end = find_target_method(smali_root, OLD_PACKAGE, OLD_ACTIVITY)
    block = "\n".join(lines[start : end + 1])
    if block.count(OLD_PACKAGE) != 1 or block.count(OLD_ACTIVITY) != 1:
        raise PatchError("The target method does not contain exactly one copy of each expected string.")

    lines[start : end + 1] = [
        line.replace(OLD_PACKAGE, NEW_PACKAGE).replace(OLD_ACTIVITY, NEW_ACTIVITY)
        for line in lines[start : end + 1]
    ]
    source.write_text("\n".join(lines) + "\n", encoding="utf-8")

    patched_block = "\n".join(lines[start : end + 1])
    if patched_block.count(NEW_PACKAGE) != 1 or patched_block.count(NEW_ACTIVITY) != 1:
        raise PatchError("The rebuilt smali source did not contain the expected Launcher strings.")


def verify_rebuilt_dex(baksmali_jar: Path, java: str, dex_path: Path, work: Path) -> None:
    if not dex_path.is_file() or dex_path.stat().st_size < len(DEX_MAGIC):
        raise PatchError("The assembler did not produce a DEX file.")
    if dex_path.read_bytes()[: len(DEX_MAGIC)] != DEX_MAGIC:
        raise PatchError("The rebuilt DEX is not Android 4.4-compatible DEX 035.")

    verification_dir = work / "verification-smali"
    run_java_tool(
        java,
        baksmali_jar,
        ["disassemble", str(dex_path), "--api", "19", "-o", str(verification_dir)],
    )
    if len(matching_methods(verification_dir, NEW_PACKAGE, NEW_ACTIVITY)) != 1:
        raise PatchError("The rebuilt target method does not contain the expected Launcher assignment exactly once.")
    if matching_methods(verification_dir, OLD_PACKAGE, OLD_ACTIVITY):
        raise PatchError("The rebuilt target method still contains the original SarkBook assignment.")


def create_output_jar(dex_path: Path, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        raise PatchError(f"Output already exists; choose a new path: {output_path}")

    temporary_output = None
    try:
        with tempfile.NamedTemporaryFile(
            prefix=f".{output_path.name}.", suffix=".tmp", dir=output_path.parent, delete=False
        ) as temporary:
            temporary_output = Path(temporary.name)

        with zipfile.ZipFile(temporary_output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.write(dex_path, arcname="classes.dex")

        with zipfile.ZipFile(temporary_output, "r") as archive:
            if archive.namelist() != ["classes.dex"]:
                raise PatchError("The output JAR has an unexpected entry list.")
            if archive.testzip() is not None:
                raise PatchError("The output JAR failed its ZIP integrity check.")
            if archive.read("classes.dex") != dex_path.read_bytes():
                raise PatchError("The DEX read back from the output JAR differs from the assembled DEX.")

        temporary_output.replace(output_path)
    finally:
        if temporary_output is not None:
            temporary_output.unlink(missing_ok=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create a local, unsigned services.jar for the one recorded R9 firmware. "
            "The input must match the known original SHA-256 exactly."
        )
    )
    parser.add_argument("original_services_jar", type=Path, help="services.jar pulled from the target reader")
    parser.add_argument("output_services_jar", type=Path, help="new local output path; it must not exist")
    parser.add_argument("--baksmali-jar", required=True, type=Path, help="local baksmali 2.5.x JAR")
    parser.add_argument("--smali-jar", required=True, type=Path, help="local smali 2.5.x JAR")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = args.original_services_jar.expanduser().resolve()
    output = args.output_services_jar.expanduser().resolve()
    baksmali_jar = args.baksmali_jar.expanduser().resolve()
    smali_jar = args.smali_jar.expanduser().resolve()

    if not source.is_file():
        raise PatchError(f"Input JAR not found: {source}")
    if source == output:
        raise PatchError("Input and output paths must be different.")
    if output.exists():
        raise PatchError(f"Output already exists; choose a new path: {output}")
    if not baksmali_jar.is_file() or not smali_jar.is_file():
        raise PatchError("Both local smali tool JARs must exist.")

    input_sha256 = sha256_file(source)
    if input_sha256 != EXPECTED_ORIGINAL_SHA256:
        raise PatchError(
            "Refusing to patch this firmware: services.jar SHA-256 is "
            f"{input_sha256}, expected {EXPECTED_ORIGINAL_SHA256}."
        )

    java = shutil.which("java")
    if not java:
        raise PatchError("Java was not found on PATH; install a runtime compatible with smali 2.5.x.")

    with zipfile.ZipFile(source, "r") as archive:
        names = archive.namelist()
        if len(names) != len(EXPECTED_ARCHIVE_ENTRIES) or set(names) != EXPECTED_ARCHIVE_ENTRIES:
            raise PatchError("The archive entry layout differs from the recorded original services.jar.")
        if archive.testzip() is not None:
            raise PatchError("The original JAR failed its ZIP integrity check.")
        original_dex = archive.read("classes.dex")

    if original_dex[: len(DEX_MAGIC)] != DEX_MAGIC:
        raise PatchError("The original classes.dex is not DEX 035 as expected.")

    with tempfile.TemporaryDirectory(prefix="z9-services-patch-") as temporary_directory:
        work = Path(temporary_directory)
        dex_path = work / "classes.dex"
        smali_root = work / "smali"
        rebuilt_dex = work / "classes-patched.dex"
        dex_path.write_bytes(original_dex)

        run_java_tool(
            java,
            baksmali_jar,
            ["disassemble", str(dex_path), "--api", "19", "-o", str(smali_root)],
        )
        patch_smali_tree(smali_root)
        run_java_tool(
            java,
            smali_jar,
            ["assemble", str(smali_root), "--api", "19", "-o", str(rebuilt_dex)],
        )
        verify_rebuilt_dex(baksmali_jar, java, rebuilt_dex, work)
        create_output_jar(rebuilt_dex, output)

    print(f"Original SHA-256: {input_sha256}")
    print(f"Created local services.jar: {output}")
    print(f"Output SHA-256: {sha256_file(output)}")
    print("The output is not installed on the device; the original JAR signature entries were removed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
    except (OSError, zipfile.BadZipFile, UnicodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
