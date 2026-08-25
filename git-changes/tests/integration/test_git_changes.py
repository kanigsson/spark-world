#!/usr/bin/env python3
"""Black-box and differential tests over disposable Git repositories."""

from __future__ import annotations

import os
import re
import stat
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "bin" / "git-changes"
PROBE = ROOT / "tests" / "bin" / "api_probe"
STALE_PROBE = ROOT / "tests" / "bin" / "stale_content_probe"


def run(*args: str | bytes | Path, cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    encoded = [os.fsencode(arg) if isinstance(arg, Path) else arg for arg in args]
    result = subprocess.run(encoded, cwd=cwd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if check and result.returncode != 0:
        raise AssertionError(
            f"command failed ({result.returncode}): {encoded!r}\n"
            f"stdout={result.stdout!r}\nstderr={result.stderr!r}")
    return result


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    return run("git", "-C", repo, *args, check=check)


def write(repo: Path, name: str, data: bytes) -> None:
    path = repo / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def init(repo: Path, object_format: str | None = None) -> None:
    args = ["init", "-q"]
    if object_format:
        args.append(f"--object-format={object_format}")
    git(repo, *args)
    git(repo, "config", "user.email", "tests@example.invalid")
    git(repo, "config", "user.name", "git_changes tests")


def capture(repo: Path, *mode: str, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    return run(CLI, repo, *mode, check=check)


def text(result: subprocess.CompletedProcess[bytes]) -> str:
    return result.stdout.decode("latin-1")


def file_lines(output: str) -> list[str]:
    return [line for line in output.splitlines() if re.match(r"^[ADMRC TUXB] ", line)]


def assert_has(output: str, prefix: str, old: str, new: str) -> None:
    needle = f"{prefix} {old} -> {new} "
    assert any(line.startswith(needle) for line in output.splitlines()), (needle, output)


def unescape_path(value: str) -> bytes | None:
    if value == "-":
        return None
    result = bytearray()
    i = 0
    while i < len(value):
        if value[i] != "\\":
            result.append(ord(value[i]))
            i += 1
        elif value[i + 1] == "\\":
            result.append(ord("\\"))
            i += 2
        elif value[i + 1] == "t":
            result.append(9)
            i += 2
        elif value[i + 1] == "n":
            result.append(10)
            i += 2
        elif value[i + 1] == "r":
            result.append(13)
            i += 2
        else:
            assert value[i + 1] == "x"
            result.append(int(value[i + 2:i + 4], 16))
            i += 4
    return bytes(result)


def cli_inventory(output: str) -> list[tuple[str, bytes | None, bytes | None, str | None, str | None, str | None, str | None]]:
    records = []
    pattern = re.compile(
        r"^([ACDMRTUXB]) (.*?) -> (.*?) id=[0-9a-f]{64} "
        r"old-mode=(\S+) new-mode=(\S+) old-object=(\S+) new-object=(\S+)")
    for line in output.splitlines():
        match = pattern.match(line)
        if match:
            fields = match.groups()
            records.append((fields[0], unescape_path(fields[1]),
                            unescape_path(fields[2]),
                            *(None if item == "-" else item for item in fields[3:])))
    return records


def raw_inventory(repo: Path, revision: str) -> list[tuple[str, bytes | None, bytes | None, str | None, str | None, str | None, str | None]]:
    data = git(
        repo, "diff", "--raw", "-z", "--no-abbrev", "--no-color",
        "--no-ext-diff", "--no-textconv", "--diff-algorithm=myers",
        "--find-renames=50%", revision, "--").stdout
    fields = data.split(b"\0")
    records = []
    i = 0
    while i < len(fields) - 1:
        header = fields[i]
        i += 1
        parts = header.split(b" ")
        assert len(parts) == 5 and parts[0].startswith(b":")
        old_mode = parts[0][1:].decode()
        new_mode = parts[1].decode()
        old_object = parts[2].decode()
        new_object = parts[3].decode()
        status = parts[4].decode()
        old_path = fields[i]
        i += 1
        if status[0] in "RC":
            new_path = fields[i]
            i += 1
        else:
            new_path = old_path
        if status[0] == "A":
            old_path = None
        elif status[0] == "D":
            new_path = None
        records.append((
            status[0], old_path, new_path,
            None if old_mode == "000000" else old_mode,
            None if new_mode == "000000" else new_mode,
            None if set(old_object) == {"0"} else old_object,
            None if set(new_object) == {"0"} else new_object,
        ))
    return records


def hunk_ranges(data: bytes | str) -> list[tuple[int, int, int, int]]:
    if isinstance(data, str):
        data = data.encode("latin-1")
    pattern = re.compile(
        rb"@@ -\s*(\d+)(?:,\s*(\d+))? \+\s*(\d+)(?:,\s*(\d+))?"
        rb"(?: @@| id=)")
    return [(int(a), int(b or b"1"), int(c), int(d or b"1"))
            for a, b, c, d in pattern.findall(data)]


def make_child(repo: Path) -> tuple[str, str]:
    init(repo)
    write(repo, "child.txt", b"one\n")
    git(repo, "add", "child.txt")
    git(repo, "commit", "-qm", "child one")
    old = git(repo, "rev-parse", "HEAD").stdout.strip().decode()
    write(repo, "child.txt", b"two\n")
    git(repo, "commit", "-qam", "child two")
    new = git(repo, "rev-parse", "HEAD").stdout.strip().decode()
    return old, new


def main() -> None:
    checks = 0
    with tempfile.TemporaryDirectory(prefix="git-changes-tests-") as temporary:
        tmp = Path(temporary)
        repo = tmp / "repo"
        child = tmp / "child"
        repo.mkdir()
        child.mkdir()
        child_old, child_new = make_child(child)
        init(repo)

        base_files = {
            "mod.txt": b"one\ntwo\nthree\n",
            "staged.txt": b"before staged\n",
            "delete.txt": b"delete me\n",
            "rename-old.txt": (b"rename payload\n" * 20),
            "copy-source.txt": (b"copy payload\n" * 20),
            "mode.sh": b"#!/bin/sh\nexit 0\n",
            "binary.bin": b"old\x00binary",
            "type-entry": b"regular\n",
            "no-final.txt": b"old no newline",
            "space tab\tquote\".txt": b"special old\n",
        }
        for name, data in base_files.items():
            write(repo, name, data)
        run("git", "clone", "-q", child, repo / "vendor" / "sub")
        git(repo / "vendor" / "sub", "checkout", "-q", child_old)
        non_utf8 = os.fsencode(repo) + b"/non-utf8-\xff.txt"
        fd = os.open(non_utf8, os.O_CREAT | os.O_WRONLY, 0o644)
        os.write(fd, b"byte old\n")
        os.close(fd)
        git(repo, "add", "-A")
        git(repo, "update-index", "--add", "--cacheinfo", f"160000,{child_old},vendor/sub")
        git(repo, "commit", "-qm", "base")
        base = git(repo, "rev-parse", "HEAD").stdout.strip().decode()

        clean = text(capture(repo))
        assert "files 0 fresh" in clean
        checks += 1

        write(repo, "mod.txt", b"one\nchanged\nthree\nadded\n")
        write(repo, "staged.txt", b"after staged\n")
        git(repo, "add", "staged.txt")
        write(repo, "new-staged.txt", b"new staged\n")
        git(repo, "add", "new-staged.txt")
        (repo / "delete.txt").unlink()
        git(repo, "mv", "rename-old.txt", "rename-new.txt")
        write(repo, "copy-new.txt", base_files["copy-source.txt"])
        git(repo, "add", "copy-new.txt")
        write(repo, "copy-source.txt", base_files["copy-source.txt"] + b"source changed\n")
        os.chmod(repo / "mode.sh", os.stat(repo / "mode.sh").st_mode | stat.S_IXUSR)
        write(repo, "binary.bin", b"new\x00binary\x01")
        (repo / "type-entry").unlink()
        os.symlink("mod.txt", repo / "type-entry")
        write(repo, "no-final.txt", b"new no newline plus")
        write(repo, "space tab\tquote\".txt", b"special new\n")
        fd = os.open(non_utf8, os.O_WRONLY | os.O_TRUNC)
        os.write(fd, b"byte new\n")
        os.close(fd)
        git(repo, "update-index", "--cacheinfo", f"160000,{child_new},vendor/sub")
        git(repo / "vendor" / "sub", "checkout", "-q", child_new)

        staged = text(capture(repo, "tree-index", "HEAD"))
        assert_has(staged, "M", "staged.txt", "staged.txt")
        assert_has(staged, "A", "-", "new-staged.txt")
        assert_has(staged, "R", "rename-old.txt", "rename-new.txt")
        assert "submodule" in staged and "vendor/sub" in staged
        checks += 4

        unstaged = text(capture(repo, "index-worktree"))
        assert_has(unstaged, "M", "mod.txt", "mod.txt")
        assert_has(unstaged, "D", "delete.txt", "-")
        assert_has(unstaged, "M", "mode.sh", "mode.sh")
        assert_has(unstaged, "T", "type-entry", "type-entry")
        assert "binary.bin" in unstaged and " binary" in unstaged
        assert r'''space tab\tquote".txt''' in unstaged, unstaged
        assert r"non-utf8-\xFF.txt" in unstaged, unstaged
        assert "new-staged.txt" not in unstaged
        checks += 8

        combined = text(capture(repo, "tree-worktree", "HEAD"))
        assert "new-staged.txt" in combined and "mod.txt" in combined
        assert "  @@ - 2, 1 + 2, 1 " in combined
        assert "no-final.txt" in combined
        assert "copy-new.txt" in combined
        checks += 4

        assert cli_inventory(combined) == raw_inventory(repo, "HEAD")
        canonical_patch = git(
            repo, "diff", "--unified=0", "--no-color", "--no-ext-diff",
            "--no-textconv", "--diff-algorithm=myers", "--find-renames=50%",
            "HEAD", "--").stdout
        expected_hunks = hunk_ranges(canonical_patch)
        # Git renders a gitlink update as a synthetic one-line patch.  The
        # library classifies submodules as non-text content, so that final
        # synthetic hunk is intentionally not a Changed_Span.
        assert expected_hunks[-1] == (1, 1, 1, 1)
        expected_hunks.pop()
        assert hunk_ranges(combined) == expected_hunks, (
            hunk_ranges(combined), expected_hunks, combined)
        checks += 2

        again = text(capture(repo, "tree-worktree", "HEAD"))
        ids = re.findall(r" id=([0-9a-f]{64})", combined)
        assert ids and ids == re.findall(r" id=([0-9a-f]{64})", again)
        checks += 1

        probe = text(run(PROBE, repo))
        assert "COPIED old-path=copy-source.txt new-path=copy-new.txt" in probe
        assert "MODIFIED old-path=mod.txt new-path=mod.txt old= 14 new= 24" in probe
        path_probe = text(run(PROBE, repo, "mod.txt"))
        assert "count= 1" in path_probe and "mod.txt" in path_probe
        stale_probe = text(run(STALE_PROBE, repo, "mod.txt"))
        assert "CONTENT_CHANGED" in stale_probe
        checks += 4

        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "all changes")
        head = git(repo, "rev-parse", "HEAD").stdout.strip().decode()
        tree = text(capture(repo, "tree-tree", base, head))
        assert "TREE_TO_TREE_COMPARISON" in tree and "files" in tree
        assert "rename-new.txt" in tree and "binary.bin" in tree
        checks += 3

        bare = tmp / "bare.git"
        run("git", "clone", "-q", "--bare", repo, bare)
        bare_tree = text(capture(bare, "tree-tree", base, head))
        assert "TREE_TO_TREE_COMPARISON" in bare_tree and "rename-new.txt" in bare_tree
        invalid = capture(bare, "tree-worktree", "HEAD", check=False)
        assert invalid.returncode != 0 and b"UNSUPPORTED_COMPARISON" in invalid.stderr
        checks += 2

        sha = tmp / "sha256"
        sha.mkdir()
        sha_init = git(sha, "init", "-q", "--object-format=sha256", check=False)
        if sha_init.returncode == 0:
            git(sha, "config", "user.email", "tests@example.invalid")
            git(sha, "config", "user.name", "git_changes tests")
            write(sha, "wide.txt", b"old\n")
            git(sha, "add", "wide.txt")
            git(sha, "commit", "-qm", "base")
            write(sha, "wide.txt", b"new\n")
            sha_out = text(capture(sha))
            assert re.search(r"old=[0-9a-f]{64}", sha_out)
            assert "wide.txt" in sha_out
            checks += 2

        unborn = tmp / "unborn"
        unborn.mkdir()
        init(unborn)
        failure = capture(unborn, check=False)
        assert failure.returncode != 0 and b"UNRESOLVED_REVISION" in failure.stderr
        checks += 1

    print(f"integration tests: {checks} scenario checks passed")


if __name__ == "__main__":
    main()
