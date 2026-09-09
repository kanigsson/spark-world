#!/usr/bin/env python3
"""Exercise the real explorer frontend, worker, terminal, and navigation stack."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import struct
import subprocess
import tempfile
import termios
import time

GV = Path(__file__).resolve().parents[1] / "git_view"
ENV = dict(os.environ, GIT_AUTHOR_NAME="test", GIT_AUTHOR_EMAIL="test@example.org",
           GIT_COMMITTER_NAME="test", GIT_COMMITTER_EMAIL="test@example.org")


class Session:
    def __init__(self, repo, *args):
        self.rows, self.cols = 28, 160
        self.fd, slave = pty.openpty()
        self.resize()

        def setup():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

        self.proc = subprocess.Popen([str(GV), *args], cwd=repo, stdin=slave,
                                     stdout=slave, stderr=slave, preexec_fn=setup)
        os.close(slave)
        os.set_blocking(self.fd, False)

    def resize(self):
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", self.rows, self.cols, 0, 0))

    def read(self, seconds=0.2):
        result = b""
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            try:
                result += os.read(self.fd, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                if error.errno != errno.EAGAIN:
                    raise
            time.sleep(0.01)
        return result

    def frame(self):
        self.read()
        self.rows = 29 if self.rows == 28 else 28
        self.resize()
        data = self.read(0.3)
        return re.sub(rb"\x1b\[[0-9;?]*[ -/]*[@-~]", b"", data).decode(errors="replace")

    def send(self, keys):
        os.write(self.fd, keys)
        self.read(0.5)
        return self.frame()

    def close(self):
        self.send(b"q")
        self.proc.wait(timeout=10)
        os.close(self.fd)
        assert self.proc.returncode == 0


checks = 0


def check(ok, message, frame=""):
    global checks
    assert ok, message + "\n" + frame
    checks += 1
    print("ok:", message, flush=True)


with tempfile.TemporaryDirectory(prefix="gitview-pty-") as repo:
    def git(*args):
        return subprocess.check_output(["git", "-C", repo, *args], env=ENV).decode().strip()

    def write(path, content):
        Path(repo, path).write_text(content)

    git("init", "-q", "-b", "main")
    write("main.txt", "".join(f"line {i:03d}\n" for i in range(1, 101)))
    write("unchanged.txt", "UNCHANGED_CONTEXT_NEEDLE\n")
    git("add", ".")
    git("commit", "-qm", "initial")
    first = git("rev-parse", "HEAD")
    write("main.txt", "".join(("NEW_CHANGE\n" if i == 50 else f"line {i:03d}\n") for i in range(1, 101)))
    write("later.txt", "introduced later\n")
    git("add", ".")
    git("commit", "-qm", "second")
    second = git("rev-parse", "HEAD")
    write("main.txt", "WORKING_CONTENT\n")
    s = Session(repo)
    try:
        s.read(2)
        f = s.frame()
        check("HISTORY" in f and "TREE /" in f and "SOURCE /" in f, "three persistent panes", f)
        check(second[:12] in f and first[:12] in f, "status exposes snapshot and first-parent comparison", f)
        f = s.send(b"a")
        check("CHANGED_ONLY" in f, "cycle tree visibility", f)
        f = s.send(b"a")
        check("ALL_FILES" in f and "unchanged.txt" in f, "browse complete project tree", f)
        f = s.send(b"SUNCHANGED_CONTEXT_NEEDLE\r")
        check("unchanged.txt:1:" in f, "repository snapshot search", f)
        f = s.send(b"\r")
        check("UNCHANGED_CONTEXT_NEEDLE" in f and "scope: unchanged.txt" in f, "follow snapshot search result", f)
        f = s.send(b"\x7f")
        check("unchanged.txt:1:" in f, "back restores search results", f)
        f = s.send(b"\x1b[1;3C")
        check("scope: unchanged.txt" in f and "SOURCE / PLAIN" in f, "forward restores source lens and scope", f)
        f = s.send(b"F")
        f = s.send(b"c" + second.encode() + b"\r")
        # Open later.txt using a tree click (first row in canonical ordering).
        f = s.send(b"\x1b[<0;44;2M")
        check("scope: later.txt" in f, "tree mouse selection opens file", f)
        f = s.send(b"p")
        check("pin: later.txt" in f, "pin is visible", f)
        f = s.send(b"c" + first.encode() + b"\r")
        check("[absent in snapshot]" in f and "pin: later.txt" in f, "pin survives missing historical file", f)
        f = s.send(b"\x7f")
        check("introduced later" in f and second[:12] in f, "back restores snapshot and pinned file", f)
        f = s.send(b"f")
        check("history filter: later.txt" in f and "initial" not in f, "explicit file history filter", f)
        f = s.send(b"F")
        check("initial" in f, "clear file history filter", f)
        f = s.send(b"p")
        # main.txt is second tree row in the all-files tree.
        f = s.send(b"\x1b[<0;44;3M")
        check("scope: main.txt" in f, "open another file without changing snapshot", f)
        f = s.send(b"/line 080\r")
        check("line 080" in f and "line 001" not in f, "search within source", f)
        f = s.send(b"w")
        check("WORKING_CONTENT" in f and "worktree" in f, "switch to working-tree snapshot", f)
        f = s.send(b"\x7f")
        check("line 080" in f and "line 001" not in f, "back restores exact source scroll and search", f)
        s.cols = 55
        f = s.frame()
        check("SOURCE /" in f and "TREE /" not in f, "narrow terminal shows focused pane", f)
        f = s.send(b"\t")
        check("HISTORY" in f, "narrow terminal can switch to history", f)
        s.cols = 160
        f = s.frame()
        check("TREE /" in f, "wide layout restores all panes", f)
    finally:
        s.close()
    check(git("diff", "--name-only") == "main.txt", "TUI navigation is read-only")

print(f"{checks} explorer PTY checks passed")
