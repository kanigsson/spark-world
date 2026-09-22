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


class Screen:
    """Just enough terminal to see what the incremental repaint left behind.

    The viewer paints by sending only the cells that changed since the last
    frame, so a frame that goes missing shows up here and nowhere else: a
    full repaint (which is what Session.frame does, by resizing) would hide
    it. Cursor moves, SGR and erase are all these frames use.
    """

    def __init__(self, rows, cols):
        self.rows, self.cols = rows, cols
        self.glyph = [[" "] * cols for _ in range(rows)]
        self.inverse = [[False] * cols for _ in range(rows)]
        self.row = self.col = 0
        self.inv = False

    def feed(self, data):
        i = 0
        while i < len(data):
            byte = data[i]
            if byte == 0x1B:
                match = re.match(rb"\x1b\[([0-9;?]*)([@-~])", data[i:])
                if match:
                    self.control(match.group(1).decode(), match.group(2).decode())
                    i += match.end()
                    continue
                i += 1
                continue
            if byte == 0x0D:
                self.col = 0
                i += 1
                continue
            if byte == 0x0A:
                self.row = min(self.row + 1, self.rows - 1)
                i += 1
                continue
            width = 1 if byte < 0x80 else 2 if byte < 0xE0 else 3 if byte < 0xF0 else 4
            try:
                glyph = data[i:i + width].decode()
            except UnicodeDecodeError:
                glyph = "?"
            if self.row < self.rows and self.col < self.cols:
                self.glyph[self.row][self.col] = glyph
                self.inverse[self.row][self.col] = self.inv
            self.col = min(self.col + 1, self.cols - 1)
            i += width

    def control(self, params, final):
        if "?" in params:
            return
        values = [int(p) if p else 0 for p in params.split(";")] if params else [0]
        if final in "Hf":
            self.row = max(0, min((values[0] or 1) - 1, self.rows - 1))
            second = values[1] if len(values) > 1 else 1
            self.col = max(0, min((second or 1) - 1, self.cols - 1))
        elif final == "m":
            for value in values:
                if value in (0, 27):
                    self.inv = False
                elif value == 7:
                    self.inv = True
        elif final == "J" and values[0] == 2:
            self.glyph = [[" "] * self.cols for _ in range(self.rows)]
            self.inverse = [[False] * self.cols for _ in range(self.rows)]
            self.row = self.col = 0

    def separators(self):
        return [c for c in range(self.cols) if self.glyph[0][c] in ("\u258c", "\u2590")]

    def panes(self):
        """The column span of each pane, taken from the separators on screen."""
        edges = [-1] + self.separators() + [self.cols]
        return [(a + 1, b) for a, b in zip(edges, edges[1:]) if b - a > 4]

    def marked_rows(self, span, rows):
        first, last = span
        out = []
        for r in rows:
            wide = sum(1 for c in range(first, last) if self.inverse[r][c])
            if wide > 0.8 * (last - first):
                out.append((r, "".join(self.glyph[r][first:last]).strip()))
        return out



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
    write("main.txt", "STAGED_CONTENT\n")
    git("add", "main.txt")
    write("main.txt", "WORKING_CONTENT\n")
    s = Session(repo)
    try:
        s.read(2)
        f = s.frame()
        check("HISTORY" in f and "TREE /" in f and "SOURCE /" in f, "three persistent panes", f)
        check(second[:12] in f and first[:12] in f, "status exposes snapshot and first-parent comparison", f)
        check("CHANGED_ONLY" in f, "tree starts on the changed files", f)
        check("scope: later.txt" in f and "SOURCE / TARGET / HUNKS" in f,
              "the first changed file is open at startup", f)
        f = s.send(b"j")
        check(first[:12] in f and "[absent in snapshot]" in f,
              "moving in the history pane shows the commit without opening it", f)
        f = s.send(b"\x7f")
        check(second[:12] in f, "back returns to where the browse started", f)
        # The uncommitted snapshots head the history, so they are reached by
        # moving the selection rather than by remembering a key.
        f = s.send(b"k")
        check("snapshot: index" in f, "the index is a row of the history", f)
        f = s.send(b"k")
        check("snapshot: worktree" in f and "M main.txt" in f,
              "the working tree is the first row of the history, with its "
              "uncommitted changes", f)
        f = s.send(b"\x7f")
        check(second[:12] in f, "back leaves the uncommitted snapshots", f)
        f = s.send(b"\t")
        f = s.send(b"k")
        check("scope: COMMIT_MSG" in f and "commit " + second[:12] in f
              and "Author:" in f,
              "the commit message is the first row of the tree", f)
        f = s.send(b"\x7f")
        f = s.send(b"j")
        check("scope: main.txt" in f and "NEW_CHANGE" in f,
              "moving in the tree pane shows the file without opening it", f)
        f = s.send(b"\x7f")
        check("scope: later.txt" in f, "back returns to the file the browse started on", f)
        f = s.send(b"\t\t")
        f = s.send(b"a")
        check("ALL_FILES" in f and "unchanged.txt" in f, "browse complete project tree", f)
        f = s.send(b"a")
        check("CHANGED_ONLY" in f, "a toggles back to the changed files", f)
        f = s.send(b"SUNCHANGED_CONTEXT_NEEDLE\r")
        check("unchanged.txt:1:" in f, "repository snapshot search", f)
        f = s.send(b"\r")
        check("UNCHANGED_CONTEXT_NEEDLE" in f and "scope: unchanged.txt" in f, "follow snapshot search result", f)
        f = s.send(b"\x7f")
        check("unchanged.txt:1:" in f, "back restores search results", f)
        f = s.send(b"\x1b[1;3C")
        check("scope: unchanged.txt" in f and "SOURCE / TARGET / PLAIN" in f,
              "forward restores source presentation and scope", f)
        f = s.send(b"F")
        f = s.send(b"c" + second.encode() + b"\r")
        # Open later.txt using a tree click: the commit message heads the
        # tree, so the first file is the second row. The tree pane starts
        # after the history pane's 30% of the 160 columns.
        f = s.send(b"\x1b[<0;52;3M")
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
        # main.txt is the second file row, below the message and later.txt.
        f = s.send(b"\x1b[<0;52;4M")
        check("scope: main.txt" in f, "open another file without changing snapshot", f)
        check("SOURCE / TARGET / PLAIN" in f,
              "opening a file preserves the plain target presentation", f)
        f = s.send(b"g]")
        check("SOURCE / TARGET / PLAIN" in f and "NEW_CHANGE" in f,
              "plain source retains comparison hunk navigation", f)
        f = s.send(b"v")
        check("SOURCE / BASE / PLAIN" in f and "line 050" in f
              and "NEW_CHANGE" not in f,
              "side toggle shows exact base source at the same hunk", f)
        f = s.send(b"v")
        check("SOURCE / BOTH / PLAIN" in f and "NEW_CHANGE" in f
              and "line 050" in f,
              "both-side view interleaves the replacement", f)
        f = s.send(b"v")
        check("SOURCE / TARGET / PLAIN" in f and "NEW_CHANGE" in f,
              "side cycle returns to target source", f)
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
        # The pane layer brings the legacy viewer's mouse work to the
        # explorer: a drag selects text and reaches the clipboard, and a
        # separator drag reshapes the row.
        s.read(0.3)
        os.write(s.fd, b"\x1b[<0;95;4M")     # press inside the source pane
        s.read(0.3)
        os.write(s.fd, b"\x1b[<32;105;4M")   # drag right along the line
        s.read(0.3)
        os.write(s.fd, b"\x1b[<0;105;4m")    # release
        copied = s.read(0.5)
        check(b"\x1b]52;c;" in copied,
              "a drag in the source pane copies over OSC 52")

        # Column 52 is in the tree pane while history takes 30% of 160.
        f = s.send(b"\x1b[<0;52;2M")
        check("scope:" in f, "column 52 is in the tree pane", f)
        os.write(s.fd, b"\x1b[<0;49;5M")     # press the first separator
        s.read(0.3)
        os.write(s.fd, b"\x1b[<32;70;5M")    # drag it right
        s.read(0.3)
        os.write(s.fd, b"\x1b[<0;70;5m")
        f = s.frame()
        check("HISTORY" in f and "TREE /" in f,
              "the row still paints after a separator drag", f)
        f = s.send(b"\x1b[<0;52;2M")
        check("HISTORY" in f,
              "the widened history pane now owns column 52", f)

    finally:
        s.close()
    check(git("diff", "--name-only") == "main.txt", "TUI navigation is read-only")

    #  Keys faster than the repository worker. Every frame is a set of
    #  changed cells over the one before it, so anything that drops a frame
    #  -- or paints two current rows -- leaves a second highlighted row on
    #  screen that no later frame ever erases.
    for i in range(1, 13):
        write(f"spam{i:02d}.txt", f"file {i}\n")
    git("add", ".")
    git("commit", "-qm", "many files")
    for i in range(1, 13):
        write(f"spam{i:02d}.txt", f"file {i} changed\n")
    fast = Session(repo)
    try:
        screen = Screen(fast.rows, fast.cols)
        screen.feed(fast.read(2))
        for _ in range(40):
            os.write(fast.fd, b"}")
            screen.feed(fast.read(0.03))
        screen.feed(fast.read(2))
        content = range(1, fast.rows - 4)
        panes = screen.panes()
        check(len(panes) == 3, f"three panes on screen, found {len(panes)}")
        for span in panes:
            marked = screen.marked_rows(span, content)
            check(len(marked) <= 1,
                  "a pane highlights at most one row while keys arrive faster "
                  "than frames",
                  repr(marked))
        status = "".join(screen.glyph[fast.rows - 2])
        tree = screen.marked_rows(panes[1], content)
        check(bool(tree) and tree[0][1].split()[-1] in status,
              "the highlighted tree row is the one the status line names",
              repr(tree) + status)
    finally:
        fast.close()

print(f"{checks} explorer PTY checks passed")
