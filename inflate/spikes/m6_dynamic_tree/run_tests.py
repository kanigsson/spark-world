#!/usr/bin/env python3
"""Run the focused dynamic-body harness and check C zlib interoperability."""

from pathlib import Path
import re
import subprocess
import zlib


HERE = Path(__file__).resolve().parent
HARNESS = HERE / "dynamic_tree_test"

result = subprocess.run(
    [HARNESS],
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
)
print(result.stdout, end="")

match = re.search(r"^dynamic body hex: ([0-9a-f]+)$", result.stdout, re.MULTILINE)
if match is None:
    raise AssertionError("dynamic body hex output is missing")

decoded = zlib.decompress(bytes.fromhex(match.group(1)), wbits=-15)
if decoded != b"abcabcabc":
    raise AssertionError(f"C zlib decoded {decoded!r}")

print("C zlib dynamic-body interoperability passed")
