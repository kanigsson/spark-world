# tui_term

The terminal driver for the TUI ecosystem: raw and alternate-screen mode, a
`Tui.Surface` turned into ANSI/SGR bytes, keystrokes read back through the
proved `Tui.Input` decoder, resize and quit signals, and an optional event
loop. Six child packages under `Tui.Term`, plus `Tui.Term.Sys` for the raw
bindings.

## SPARK_Mode is Off here, deliberately

This is the only project in the repository that is `SPARK_Mode => Off` on
purpose, and the reason is containment, not difficulty: it owns the syscalls,
the controlled types and the interrupt handlers, so that everything above it
can be proved and can truthfully say it performs no I/O. There are no proofs
here and none are wanted.

The corollary binds in both directions. **Nothing that could live in `tui`
belongs here.** The clipboard is the worked example: the OSC 52 encoding is
pure and lives in `Tui.Panes.Clip`, and only the write is here. When adding a
feature, split it the same way and leave the computable half above.

## Guaranteed restore is the load-bearing property

`Tui.Term.Mode.Session` enters raw/alt mode in `Initialize` and restores in
`Finalize`, so every path that unwinds the stack — normal exit, unhandled
exception, a caught `SIGTERM` that breaks the loop — hands the terminal back.
A change that restores the terminal from an explicit call instead, or that
adds an exit path around the session object, breaks the one promise this
library makes that a user notices when it fails. Raw mode also means Ctrl-C
arrives as a key rather than a signal, so the host, not the runtime, decides
what it does.

## Build and test

```sh
gprbuild -P tui_term.gpr
gprbuild -P tests/tests.gpr && ./tests/test_output   # terminal-free
gprbuild -P demo/demo.gpr  && ./demo/main            # interactive, NOT SPARK
```

`tests/test_output` redirects fd 1 through a pipe and asserts the exact bytes;
it needs no terminal and is what stands in for proof here. A change to the
output encoding, the diff application or the colour downgrade needs a case
there. `demo/` is throwaway and nothing depends on it.

## Assumptions that are not portability bugs

Hardcoded ANSI/xterm sequences and no terminfo; Linux/x86-64 `termios` and
`ioctl` constants written out literally (`TCSAFLUSH`, `TIOCGWINSZ`); a wide
glyph emitted as one cell; one process, one terminal, with the read-side byte
buffer process-wide and not task-safe because a single host loop owns the read.
All are recorded in the README as v1 assumptions and are revisitable — but they
are decisions, so change them deliberately rather than as a fix.

## Dependencies and clients

Withs `../../libs/tui/tui.gpr`, and nothing else. `git_view` withs both and
drives `Mode`, `Output`, `Input` and `Signals` itself rather than using
`Event_Loop`.
