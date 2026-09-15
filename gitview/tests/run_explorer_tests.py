#!/usr/bin/env python3
"""Repository fixtures for snapshot, comparison, overlay and path boundaries."""
import os
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
PROBE = HERE.parent / "obj/tests/explorer_probe"
ENV = dict(os.environ, GIT_AUTHOR_NAME="Explorer", GIT_AUTHOR_EMAIL="e@example.org",
           GIT_COMMITTER_NAME="Explorer", GIT_COMMITTER_EMAIL="e@example.org")
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("ok:", message)


with tempfile.TemporaryDirectory(prefix="gitview-explorer-") as tmp:
    repo = Path(tmp)

    def git(*args):
        return subprocess.check_output(["git", "-C", tmp, *args], env=ENV).decode().strip()

    def write(path, text):
        p = repo / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)

    def commit(message):
        git("add", "-A")
        git("commit", "-qm", message)
        return git("rev-parse", "HEAD")

    def probe(snapshot="HEAD", path="src/main.txt", kind="commit", tree="all_files",
              lens="gutter", base="", search="", scope="", root="", cwd=None):
        output = subprocess.check_output(
            [str(PROBE), snapshot, path, kind, tree, lens, base, search, scope, root],
            cwd=cwd or tmp, timeout=30).decode()
        assert "[git error]" not in output, output
        header, history, tree_text, source = output.split("=== ")
        return dict(header=header, history=history, tree=tree_text, source=source)

    git("init", "-q", "-b", "main")
    write("src/main.txt", "old first\nkeep middle\nold last\n")
    write("context/unchanged.txt", "unchanged needle\n")
    write("deleted.txt", "base-only text\n")
    write("rename.txt", "rename identity\n" * 20)
    weird = "strange\tname\n[1].txt"
    write(weird, "literal path needle\n")
    (repo / "binary.bin").write_bytes(b"a\0b")
    first = commit("root commit")
    write("src/main.txt", "new first\nkeep middle\nnew last\n")
    (repo / "deleted.txt").unlink()
    git("mv", "rename.txt", "renamed.txt")
    second = commit("modify delete rename")

    f = probe()
    check("context/unchanged.txt" in f["tree"], "full snapshot contains unchanged files")
    check("+ 1 | new first" in f["source"] and "- [base] old first" in f["source"], "replacement overlay and base ghost")
    check("keep middle" in f["source"], "full file context remains available")
    check("[parents:" in f["history"], "history exposes graph parent information")
    f = probe(tree="changed_only")
    check("context/unchanged.txt" not in f["tree"], "changed-only tree omits unchanged files")
    check("src/\n" not in f["tree"], "flat changed-only tree")
    f = probe(lens="plain")
    check("old first" not in f["source"] and "new first\nkeep middle\nnew last" in f["source"], "plain lens is target content")
    check("[base-only deleted file]" in probe(path="deleted.txt")["source"], "deleted file is explicitly base-only")
    check("R renamed.txt" in probe(path="renamed.txt")["tree"], "rename identity from git-changes")
    check("rename identity" in probe(path="renamed.txt")["source"], "renamed file content")
    check("[binary file]" in probe(path="binary.bin")["source"], "unchanged binary placeholder")
    f = probe(path=weird)
    check("literal path needle" in f["source"] and r"strange\tname\n[1].txt" in f["tree"], "control-byte path identity preserved")
    check("old first" in probe(snapshot=first, lens="plain")["source"], "root commit uses empty-tree comparison")
    check("[absent in snapshot]" in probe(snapshot=first, path="renamed.txt")["source"], "missing pinned path does not switch files")
    check("unchanged needle" in probe(path="context/unchanged.txt")["source"], "unchanged file can be opened")
    f = probe(search="needle")
    check("context/unchanged.txt:1:" in f["tree"], "snapshot-wide search includes unchanged files")
    check(r"strange\tname\n[1].txt:1:" in f["tree"], "search preserves NUL-delimited path identity")
    check(probe(scope="context/unchanged.txt")["history"].count("[parents:") == 1, "file-scoped history")
    check(probe(cwd=repo / "src")["tree"] == probe()["tree"], "subdirectory launch uses repository-root paths")

    write("src/main.txt", "staged first\nkeep middle\nnew last\n")
    git("add", "src/main.txt")
    write("src/main.txt", "working first\nkeep middle\nnew last\n")
    write("untracked.txt", "untracked content\n")
    check("working first" in probe(kind="worktree")["source"], "HEAD to worktree includes unstaged content")
    check("staged first" in probe(kind="staging")["source"], "index snapshot is independent of worktree")
    check("new first" in probe()["source"], "commit content is independent of worktree")
    check("? untracked.txt" in probe(kind="worktree", tree="changed_only")["tree"], "untracked path visible in working changes")
    check("untracked content" in probe(kind="worktree", path="untracked.txt")["source"], "untracked file can be read")
    check("old first" in probe(base=first)["source"], "arbitrary base comparison")

    git("reset", "--hard", "-q", "HEAD")
    (repo / "untracked.txt").unlink()
    write("src/main.txt", "new first\nkeep middle\n")
    third = commit("delete at EOF")
    check("- [base] new last" in probe()["source"], "deletion anchored after final target line")
    write("src/main.txt", "keep middle\n")
    fourth = commit("delete at BOF")
    check("- [base] new first" in probe()["source"], "deletion anchored before first target line")
    git("checkout", "-qb", "feature", second)
    write("feature.txt", "feature branch\n")
    feature = commit("feature commit")
    git("checkout", "-q", "main")
    git("merge", "--no-ff", "-qm", "merge feature", "feature")
    f = probe(path="feature.txt")
    check("A feature.txt" in f["tree"], "merge comparison uses first parent")
    check("feature commit" in probe(root="feature")["history"], "arbitrary branch history")
    check(git("status", "--porcelain") == "", "exploration leaves index and worktree unchanged")

print(f"{checks} explorer fixture checks passed")
