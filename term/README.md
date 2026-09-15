# tui_term

The **terminal driver** for the TUI ecosystem (see the parent `ROADMAP.md`):
the one crate that talks to the OS. It puts the terminal into raw / alternate-
screen mode, turns a `Tui.Surface` into ANSI/SGR bytes, reads keystrokes back
through the proved `Tui.Input` decoder, and notices resizes — and it **always**
hands the terminal back, even on an exception or an external `kill`.

Everything above it stays pure: the pager engine fills a surface, this crate is
where "rendering is data" finally becomes an effect. `SPARK_Mode` is **Off**
here — this is the deliberate, isolated home of the syscalls, controlled types,
and interrupt handlers the rest of the ecosystem keeps out.

## What it is

Six child packages under `Tui.Term`:

| Package               | Role                                                                 |
|-----------------------|----------------------------------------------------------------------|
| `Tui.Term.Mode`       | RAII `Session`: raw mode (termios) + alt screen + hidden cursor, **guaranteed restore** in `Finalize`. `Get_Size` via `TIOCGWINSZ`. |
| `Tui.Term.Output`     | `Blit` a whole `Surface`, or `Apply` a `Surface.Diff`; cursor + SGR; colour **downgrade** to the terminal's depth. |
| `Tui.Term.Signals`    | `SIGWINCH` (resize, read-and-clear) and `SIGTERM` (latched quit) via protected interrupt handlers. |
| `Tui.Term.Input`      | `Next`: read bytes, pump them through a `Tui.Input.Decoder`, resolve a lone `ESC` on a short timeout. |
| `Tui.Term.Event_Loop` | Optional batteries-included loop: two callbacks (paint, key) and it runs the whole cycle with diffed redraws. |
| `Tui.Term.Clipboard`  | `Set`: put a `Tui.Panes.Clip.Payload` on the clipboard over OSC 52. The encoding is pure and lives in the library; only the write is here. |

The smallest possible host:

```ada
with Tui.Term.Event_Loop;
...
Tui.Term.Event_Loop.Run (Paint => My_Paint'Access, On_Key => My_Key'Access);
```

`Run` enters raw/alt mode, sizes a back-buffer surface to the terminal, calls
`My_Paint` to fill it, blits it, then loops — reading keys, repainting (by
**diffing** against the previous frame and emitting only changed cells), and
rebuilding on resize — until the key handler asks to quit, a `SIGTERM` arrives,
or stdin closes. The terminal is restored unconditionally on the way out.
When requested, button-event mouse tracking includes drag motion as well as
presses, releases, and wheel notches.

A host that wants to own its own loop ignores `Event_Loop` and wires `Mode`,
`Output`, `Input` and `Signals` directly — exactly what the standalone `pager`
and `git_view` will do.

### Three names that depart from the roadmap

`Out`, `In` and `Loop` are all Ada reserved words, so the roadmap's
`Tui.Term.Out` / `.In` / `.Loop` are spelled **`Tui.Term.Output`**,
**`Tui.Term.Input`** and **`Tui.Term.Event_Loop`**.

## Design decisions worth knowing

1. **Guaranteed restore is a controlled type, not discipline.** A
   `Tui.Term.Mode.Session` enters raw/alt mode in `Initialize` and restores in
   `Finalize`. Any path that unwinds the stack — normal exit, an unhandled
   exception, a caught `SIGTERM` that breaks the loop — runs `Finalize`. The
   terminal is never left wedged.
2. **Raw mode means Ctrl-C is a key, not a signal.** `cfmakeraw` turns off
   `ISIG`, so an interactive Ctrl-C arrives as the byte `0x03` — an ordinary
   `Tui.Input` key event the host treats as "quit". `SIGINT` is therefore not
   handled (and this GNAT runtime reserves it anyway); `SIGTERM` *is* caught so
   an external `kill` still exits cleanly and restores.
3. **Signals only flip a flag.** Handlers run at interrupt priority, so they do
   the one safe thing — set a Boolean in a protected object — and the event loop
   acts on it at a safe point. `SIGWINCH` is read-and-clear (re-query size once
   per burst); the quit flag latches.
4. **Time for the lone ESC lives here.** The decoder is pure and never guesses
   on a clock; `Tui.Term.Input` supplies the timing, flushing a stranded `ESC`
   into the Escape key after a short window.
5. **Colour intent is kept, downgrade happens at the wire.** A surface always
   records the producer's full (truecolour) intent; `Output` downgrades to the
   configured `Color_Depth` — truecolour, 256, 16, or monochrome — only as bytes
   go out.

## v1 assumptions (documented, revisitable)

- Hardcoded ANSI/xterm sequences; **no terminfo** (per the roadmap). Linux/
  x86-64 `termios`/`ioctl` constants are hardcoded (`TCSAFLUSH`, `TIOCGWINSZ`).
- A wide (CJK) glyph is emitted as a single cell — surfaces currently store one
  code point per cell. `Blit` re-homes the cursor every row and `Apply`
  positions every change absolutely, which bounds any column drift. Full
  wide-glyph cells are future work shared with the rest of the stack.
- One process, one terminal: the read-side byte buffer in `Tui.Term.Input` is
  process-wide and not task-safe by design (a single host loop owns the read).

## Build & run

```sh
gprbuild -P tui_term.gpr                            # the library
gprbuild -P tests/tests.gpr  && ./tests/test_output # terminal-free output tests
gprbuild -P demo/demo.gpr    && ./demo/main         # interactive: a movable colour box
```

In the demo: arrow keys move the box, resize the window to watch it re-layout,
and `q` / `Esc` / `Ctrl-C` quit — after which your terminal is exactly as you
left it.

## Layout

```
alire.toml          crate manifest (depends on tui)
tui_term.gpr        library project
src/                Tui.Term (+ .Mode .Output .Signals .Input .Event_Loop)
tests/              test_output: redirects fd 1 through a pipe, asserts the bytes
demo/               throwaway: a movable colour box driven by Event_Loop (NOT SPARK)
```

## Proof status

This is the OS edge: `SPARK_Mode => Off`, by design. There are no proofs here —
the verifiable work lives in the layers below (`Tui.Surface`, `Tui.Input`,
`Tui.Pager`), which this crate only reads from and writes out. Correctness here
is pinned by the terminal-free `tests/` (deterministic byte assertions) and by
dogfooding the `demo/`.
