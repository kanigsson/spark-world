#!/usr/bin/env python3
"""Behavioural tests for git_view's mouse support, driven through a pty.

Complements the proofs and the input crate's decoder tests: this exercises
the whole pipeline — terminal mode handshake, SGR reports through the
decoder, hit-testing against the painted layout — by injecting mouse
reports into a pty and inspecting what the app draws.

Two things make this work headlessly:
  * the child gets the pty as its controlling terminal (TIOCSCTTY) with an
    explicit window size, so the app believes it is on a real terminal;
  * the app repaints by cell-level diff, so after each interaction the test
    toggles the pty height — the SIGWINCH forces one full frame, which can
    be grepped for contiguous text (a diff of "1/60" -> "6/60" would emit
    only the changed cell, never the whole string).

Build ../git_view first (gprbuild -P ../git_view.gpr), then run this file.
"""
import os, pty, sys, time, fcntl, struct, termios, subprocess, errno, re
import shutil, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GV = os.path.join(HERE, "..", "git_view")
COLS = 100
INTERACTION_SETTLE = 0.75

failures = []

def check(cond, label):
    print(("  ok   : " if cond else "  FAIL : ") + label)
    if not cond:
        failures.append(label)

def diff_top(frame):
    plain = re.sub(rb"\x1b\[[0-9;?]*[ -/]*[@-~]", b"", frame)
    match = re.search(rb"\[diff\] [0-9a-f]+ +(\d+)-", plain)
    return int(match.group(1)) if match else 0

def make_repo(repo):
    env = dict(os.environ,
               GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    def git(*args):
        return subprocess.run(["git", "-C", repo] + list(args), env=env,
                              check=True, capture_output=True, text=True)
    git("init", "-q")
    for i in range(1, 59):
        with open(os.path.join(repo, "f.txt"), "a") as f:
            f.write(f"line {i}\n")
        if i == 1:
            with open(os.path.join(repo, "00_sample.adb"), "w") as f:
                f.write("procedure Sample is\nbegin\n   raise Program_Error;\nend Sample;\n")
            git("add", "f.txt", "00_sample.adb")
        else:
            git("add", "f.txt")
        git("commit", "-q", "-m", f"c{i:02d}")
    # A penultimate source commit exercises language-aware token colours.
    with open(os.path.join(repo, "00_sample.adb"), "w") as f:
        f.write("procedure Sample is -- Ada comment\n   Value : Integer := 0;\nbegin\n")
        for _ in range(24):
            f.write("   Value := Value + 1;\n")
        f.write("   null;\nend Sample;\n")
    with open(os.path.join(repo, "01_sample.py"), "w") as f:
        f.write("def greet(name):\n")
        for _ in range(24):
            f.write("    name = \"hello \" + name  # Python comment\n")
        f.write("    return name\n")
    git("add", "00_sample.adb", "01_sample.py")
    git("commit", "-q", "-m", "c59-syntax")
    git("tag", "v-syntax")

    # Newest commit: a numbered file makes wheel scrolling observable.
    with open(os.path.join(repo, "big.txt"), "w") as f:
        for i in range(1, 61):
            f.write(f"DIFFLINE_{i:02d}\n")
    git("add", "big.txt")
    git("commit", "-q", "-m", "c60-big")
    git("branch", "old", "HEAD~10")
    main_branch = git("branch", "--show-current").stdout.strip()
    git("switch", "-q", "-c", "side", "HEAD~5")
    with open(os.path.join(repo, "side.txt"), "w") as f:
        f.write("side history\n")
    git("add", "side.txt")
    git("commit", "-q", "-m", "side-only")
    git("switch", "-q", main_branch)

class Session:
    def __init__(self, repo, *args):
        self.rows = 30
        self.master, slave = pty.openpty()
        self._winsz(self.rows)
        def child_setup(s=slave):
            os.setsid()
            fcntl.ioctl(s, termios.TIOCSCTTY, 0)
        self.proc = subprocess.Popen(
            [GV] + list(args), cwd=repo,
            stdin=slave, stdout=slave, stderr=slave,
            preexec_fn=child_setup)
        os.close(slave)
        self.capture = b""

    def _winsz(self, rows):
        fcntl.ioctl(self.master, termios.TIOCSWINSZ,
                    struct.pack("HHHH", rows, COLS, 0, 0))

    def read_for(self, secs):
        start = len(self.capture)
        end = time.time() + secs
        os.set_blocking(self.master, False)
        while time.time() < end:
            try:
                data = os.read(self.master, 65536)
                if data:
                    self.capture += data
            except OSError as e:
                if e.errno == errno.EIO:
                    break
                if e.errno != errno.EAGAIN:
                    raise
            time.sleep(0.05)
        return self.capture[start:]

    def full_frame(self, settle=1.0):
        """Toggle the pty height; the resize makes the app paint in full."""
        self.rows = 31 if self.rows == 30 else 30
        self._winsz(self.rows)
        return self.read_for(settle)

    def send(self, data):
        os.write(self.master, data)

    def finish(self):
        try:
            self.send(b"q")
        except OSError:
            pass
        tail = self.read_for(1.0)
        self.proc.wait(timeout=5)
        os.close(self.master)
        return tail

repo = tempfile.mkdtemp(prefix="gv_mouse_repo_")
try:
    make_repo(repo)

    # ---- run 1: mouse on (default) -----------------------------------------
    s = Session(repo)
    first = s.read_for(2.0)
    check(b"\x1b[?1002h" in first and b"\x1b[?1006h" in first,
          "startup emits drag-mouse enable (?1002h ?1006h)")
    check(b"[commits] 1/60" in first, "initial status: [commits] 1/60")
    check(b"HEAD ->" in first and b"tag: v-syntax" in first,
          "commit list shows HEAD and tag decorations")
    check(b"38;5;5" in first, "ref decorations receive their own colour")

    # Click row 6 of the list pane (col 5): selection jumps to commit 6.
    s.send(b"\x1b[<0;5;6M\x1b[<0;5;6m")
    time.sleep(INTERACTION_SETTLE)
    frame = s.full_frame()
    check(b"[commits] 6/60" in frame, "left click on list row 6 -> status 6/60")
    check(b"line 55" in frame and b"DIFFLINE_60" not in frame,
          "left click immediately loads the clicked commit's diff")

    # The second commit contains two source languages and their keywords.
    s.send(b"\x1b[<0;5;2M\x1b[<0;5;2m")
    time.sleep(INTERACTION_SETTLE)
    frame = s.full_frame()
    check(frame.count(b"38;5;5") >= 2,
          "Ada and Python keywords receive syntax-token colour")
    syntax_color_count = frame.count(b"38;5;5")

    # Syntax is optional, while the green/red diff gutter remains independent.
    s.send(b"s")
    time.sleep(INTERACTION_SETTLE)
    frame = s.full_frame()
    check(frame.count(b"38;5;5") < syntax_color_count,
          "s toggles source syntax colours off")
    check(b"38;5;2" in frame and b"38;5;1" in frame,
          "syntax-off keeps green/red diff gutter cues")
    s.send(b"s")
    time.sleep(INTERACTION_SETTLE)
    frame = s.full_frame()
    check(frame.count(b"38;5;5") >= 2,
          "s toggles source syntax colours back on")

    # Structural navigation works independently of literal search state.
    s.send(b"\t}")
    time.sleep(INTERACTION_SETTLE)
    first_file = diff_top(s.full_frame())
    s.send(b"}")
    time.sleep(INTERACTION_SETTLE)
    second_file = diff_top(s.full_frame())
    s.send(b"]")
    time.sleep(INTERACTION_SETTLE)
    second_hunk = diff_top(s.full_frame())
    s.send(b"[")
    time.sleep(INTERACTION_SETTLE)
    previous_hunk = diff_top(s.full_frame())
    s.send(b"{")
    time.sleep(INTERACTION_SETTLE)
    previous_file = diff_top(s.full_frame())
    check(first_file > 1 and second_file > first_file,
          f"}} jumps forward through changed files ({first_file} -> {second_file})")
    check(second_hunk > second_file and previous_hunk < second_hunk,
          f"]/[ jump between diff hunks ({previous_hunk} < {second_hunk})")
    check(previous_file < previous_hunk,
          f"{{ jumps back to the previous changed file ({previous_file} < {previous_hunk})")

    # Return to the newest, deliberately long diff for scrolling checks.
    s.send(b"\x1b[<0;5;1M\x1b[<0;5;1m")
    time.sleep(INTERACTION_SETTLE)
    frame = s.full_frame()
    check(b"[commits] 1/60" in frame and b"DIFFLINE_01" in frame,
          "click row 1 restores the newest long diff")

    # Wheel down twice over the DIFF pane (col 60) without focusing it:
    # new DIFFLINE_NN rows must appear, focus must stay on the list.
    high = max(int(m) for m in re.findall(rb"DIFFLINE_(\d\d)", s.capture))
    before_wheel = len(s.capture)
    s.send(b"\x1b[<65;60;10M" * 2)
    time.sleep(INTERACTION_SETTLE)
    frame = s.full_frame()
    new = [int(m) for m in re.findall(rb"DIFFLINE_(\d\d)", frame)]
    check(bool(new) and max(new) > high,
          f"wheel down over diff pane reveals new lines (>{high:02d})")
    check(b"[diff]" not in s.capture[before_wheel:],
          "wheel over diff pane does NOT move focus")

    # Wheel down over the LIST pane (col 5): viewport scrolls, selection
    # clamps along (3 notches = 9 lines: top -> 10, selection 6 -> 10).
    s.send(b"\x1b[<65;5;10M" * 3)
    time.sleep(INTERACTION_SETTLE)
    frame = s.full_frame()
    check(b"[commits] 10/60" in frame,
          "wheel down over list drags selection (10/60)")

    # Click in the diff pane: focus moves there.
    s.send(b"\x1b[<0;60;10M\x1b[<0;60;10m")
    time.sleep(INTERACTION_SETTLE)
    frame = s.full_frame()
    check(b"[diff]" in frame, "left click in diff pane -> [diff] focus")

    # Drag within the diff: motion is decoded, the range is retained on screen,
    # and release copies it through OSC 52 without leaving the TUI.
    before = len(s.capture)
    s.send(b"\x1b[<0;48;10M\x1b[<32;57;10M\x1b[<0;57;10m")
    time.sleep(INTERACTION_SETTLE)
    copied = s.capture[before:] + s.full_frame()
    check(b"\x1b]52;c;" in copied, "drag release emits an OSC 52 clipboard copy")
    check(b"Selection copied" in copied, "drag selection reports copied status")

    tail = s.finish()
    check(b"\x1b[?1006l" in tail and b"\x1b[?1002l" in tail,
          "quit emits mouse-disable (?1006l ?1002l)")

    # ---- run 2: --no-mouse --------------------------------------------------
    s = Session(repo, "--no-mouse")
    first = s.read_for(2.0)
    check(b"\x1b[?1002h" not in first and b"\x1b[?1006h" not in first,
          "--no-mouse: no mouse-enable emitted")
    check(b"[commits] 1/60" in first, "--no-mouse: app still paints")
    tail = s.finish()
    check(b"\x1b[?1006l" not in tail and b"\x1b[?1002l" not in tail,
          "--no-mouse: no mouse-disable on the way out either")

    # ---- run 3: an explicit branch/revision -------------------------------
    s = Session(repo, "--no-mouse", "old")
    first = s.read_for(2.0)
    check(b"[commits] 1/50" in first,
          "branch argument limits the displayed history")
    s.finish()

    # ---- runs 4-7: history filters ----------------------------------------
    s = Session(repo, "--no-mouse", "--author", "t", "--since", "2000-01-01",
                "--until", "2030-01-01", "--first-parent")
    first = s.read_for(2.0)
    check(b"[commits] 1/60" in first,
          "author/date/first-parent filters combine")
    s.finish()

    s = Session(repo, "--no-mouse", "--grep", "c59-syntax")
    first = s.read_for(2.0)
    check(b"[commits] 1/1" in first,
          "message filter limits history")
    s.finish()

    s = Session(repo, "--no-mouse", "--", "big.txt")
    first = s.read_for(2.0)
    check(b"[commits] 1/1" in first,
          "path filter limits history")
    s.finish()

    s = Session(repo, "--no-mouse", "--all")
    first = s.read_for(2.0)
    check(b"[commits] 1/61" in first,
          "--all includes side-branch history")
    s.finish()

    # ---- non-interactive command-line diagnostics -------------------------
    r = subprocess.run([GV, "--help"], cwd=repo,
                       capture_output=True, text=True)
    check(r.returncode == 0 and "usage: git_view" in r.stdout,
          "--help prints usage and succeeds")

    r = subprocess.run([GV, "--bogus"], cwd=repo,
                       capture_output=True, text=True)
    check(r.returncode != 0 and "unknown option" in r.stderr,
          "--bogus is rejected with a message")

    r = subprocess.run([GV, "--author"], cwd=repo,
                       capture_output=True, text=True)
    check(r.returncode != 0 and "requires a value" in r.stderr,
          "a filter missing its value is rejected")

    r = subprocess.run([GV, "old", "main"], cwd=repo,
                       capture_output=True, text=True)
    check(r.returncode != 0 and "extra argument" in r.stderr,
          "a second revision is rejected")
finally:
    shutil.rmtree(repo, ignore_errors=True)

print()
print("ALL TESTS PASSED" if not failures else f"{len(failures)} TEST(S) FAILED")
sys.exit(1 if failures else 0)
