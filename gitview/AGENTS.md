# git_view

A read-only project, source, diff and history explorer: a TUI over a git
repository. The proof-of-ecosystem app for the TUI libraries — it embeds the
proved `Tui.Pager` engine twice, as a commit-list pane and a diff pane
composited into one surface.

## Dependencies

Three other projects in this repository:

- `tui` — the proved, I/O-free half: surfaces, panes, the pager engine.
- `tui_term` — the terminal driver, the one place syscalls are allowed.
- `git_changes` — every repository query; this app issues no git commands
  itself.

Don't work around bugs or shortcomings of those libraries here. Fix them
directly in the library and report it. They are in this repository, so the fix
and its client change in one commit.

## Build, test, prove

```sh
gprbuild -P git_view.gpr -j4
gnatprove -P git_view.gpr --level=2 -j4
gprbuild -P tests/explorer_tests.gpr -j4
obj/tests/model_tests
obj/tests/behavior_tests
python3 tests/run_explorer_tests.py
python3 tests/run_explorer_pty_tests.py
python3 tests/run_mouse_tests.py        # legacy regression suite
```

`-XMODE=debug` builds the TUI without optimization; release is the default.

## SPARK posture

The app logic is proved SPARK and currently proves clean. The git interaction
is not this project's code — it is `git_changes`, which keeps its CLI
interaction and owned containers outside its own SPARK core.
