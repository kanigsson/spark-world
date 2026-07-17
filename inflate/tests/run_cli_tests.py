#!/usr/bin/env python3
"""Focused end-to-end tests for the inflate command."""

import gzip
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "bin" / "inflate"


def run(*args: Path | str, ok: bool = True) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(
        [str(CLI), *(str(arg) for arg in args)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if (result.returncode == 0) != ok:
        raise AssertionError(
            f"unexpected exit status {result.returncode}: "
            f"{result.stderr.decode(errors='replace')}"
        )
    return result


with tempfile.TemporaryDirectory(prefix="inflate-cli-") as directory:
    work = Path(directory)
    samples = [b"", bytes(range(256)) * 4, b"compress me\n" * 10_000]

    for index, data in enumerate(samples):
        plain = work / f"plain-{index}"
        compressed = work / f"plain-{index}.gz"
        restored = work / f"restored-{index}"
        plain.write_bytes(data)

        run("compress", plain, compressed)
        assert gzip.decompress(compressed.read_bytes()) == data

        run("decompress", compressed, restored)
        assert restored.read_bytes() == data

    # Load and Save used to put a file-sized Stream_Element_Array on the
    # process stack, so an 8 MiB input failed with the usual 8 MiB stack
    # limit before the compressor ran. Exercise both I/O directions.
    large = work / "large-zero-run"
    large.write_bytes(bytes(8 * 1024 * 1024))
    large_compressed = work / "large-zero-run.gz"
    large_restored = work / "large-zero-run.out"
    run("compress", large, large_compressed)
    run("decompress", large_compressed, large_restored)
    assert large_restored.read_bytes() == large.read_bytes()

    foreign = work / "foreign.gz"
    foreign.write_bytes(gzip.compress(samples[-1], compresslevel=9))
    restored = work / "foreign.out"
    run("decompress", foreign, restored)
    assert restored.read_bytes() == samples[-1]

    concatenated = work / "concatenated.gz"
    concatenated.write_bytes(gzip.compress(b"first") + gzip.compress(b"second"))
    restored = work / "concatenated.out"
    run("decompress", concatenated, restored)
    assert restored.read_bytes() == b"firstsecond"

    invalid = work / "invalid.gz"
    invalid.write_bytes(b"not gzip")
    output = work / "must-not-exist"
    result = run("decompress", invalid, output, ok=False)
    assert b"decompression failed" in result.stderr
    assert not output.exists()

print("CLI tests passed")
