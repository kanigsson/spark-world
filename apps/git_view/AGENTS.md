# git_view

A read-only project, source, diff and history explorer: a TUI over a git
repository. The proof-of-ecosystem app for the TUI libraries — it embeds the
proved `Tui.Pager` engine twice, as a commit-list pane and a diff pane
composited into one surface.

## Dependencies

Three other projects in this repository:

- `../../libs/tui` — the proved, I/O-free half: surfaces, panes, the pager
  engine.
- `../../libs/tui_term` — the terminal driver, the one place syscalls are
  allowed.
- `../../libs/git_changes` — every repository query; this app issues no git
  commands itself.

It is the only project here with three library dependencies, so it is what a
change to any of them gets checked against.

Don't work around bugs or shortcomings of those libraries here. Fix them
directly in the library and report it. They are in this repository, so the fix
and its client change in one commit.

The term-side split matters in both directions: this app drives `Mode`,
`Output`, `Input` and `Signals` itself rather than using `tui_term`'s
`Event_Loop`. Anything computable belongs in `tui`, above the driver.

## Build, test, prove

```sh
make build   # builds the three libraries along with the app
make test    # model and behavior suites, fixture, PTY and mouse suites
make flow
make prove
```

`-XMODE=debug` builds without optimization and keeps contracts; release is the
default. The proof level and switches live in the `Prove` package in
`git_view.gpr`, not on the command line, so `make prove` passes neither.

The test suites split by what they need: `model_tests` and `behavior_tests` are
in-process, `run_explorer_tests.py` builds fixture repositories, and
`run_explorer_pty_tests.py` drives a real pseudo-terminal.
`run_mouse_tests.py` is a legacy regression suite kept for its coverage.

## SPARK posture

The app logic — state, keymap, selection rules, SHA parsing, formatters — is
proved SPARK and proves clean (2,692 checks in the baseline). Only the OS edges
are `SPARK_Mode => Off`: the main unit and the repository adapters. The git
interaction is not this project's code at all; it is `git_changes`, which keeps
its CLI interaction and owned containers outside its own SPARK core.

## `docs/`

`ROADMAP.md` is the current direction. `LEGACY.md` and
`temporal_code_explorer_design.md` describe an older direction that was not
taken; they are kept as documents, not as code, and nothing builds from them.
Read them as history rather than as specification.
