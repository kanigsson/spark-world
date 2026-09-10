# Tui.Input

A byte-at-a-time terminal **input decoder** — raw bytes in, typed key events out
— written in SPARK and proved free of run-time errors. Crate #2 of the TUI
ecosystem (see the parent `ROADMAP.md`), and the second consumer of the `Tui.*`
root namespace. See **Proof status** for exactly what the proofs do and don't
cover.

## What it is

`Tui.Input` — a `Decoder` you feed one byte at a time:

```ada
D : Tui.Input.Decoder;
E : Tui.Input.Key_Event;
Avail : Boolean;
...
Feed (D, Some_Byte, E, Avail);     --  Avail => E holds a completed event
```

It recognises printable ASCII, C0 controls (as `Ctrl-<letter>`), UTF-8 multibyte
(assembled into a `Char` code point), CSI sequences (`ESC [ … final` — arrows,
navigation, function keys, and the `ESC [ 1 ; 5 A = Ctrl-Up` modifier encoding),
SS3 sequences (`ESC O x` — application-mode F1–F4 / arrows), SGR mouse reports
(`ESC [ < b ; x ; y M/m` — presses, releases, drag motion and wheel notches, with their
1-based screen position and modifiers; the driver must have asked the terminal
for them), and `ESC <byte>` as an Alt-modified key.

### The two design decisions worth knowing

1. **Byte-at-a-time.** `Feed` consumes exactly one byte and emits at most one
   event. Simplest thing to prove and the natural shape for a state machine; can
   grow a buffer-slice entry point later without disturbing this core.
2. **Time lives in the caller.** A lone `ESC` is ambiguous — the Escape key, or
   the unfinished head of a sequence? The decoder never guesses on a timer. A
   driver that sees no follow-up byte within its timeout calls `Flush`, which
   turns a pending bare `ESC` into `Escape`. `Is_Pending` tells the driver when
   to arm that timeout. This keeps the decoder pure and provable.

## Proof status

```
gnatprove -P tui.gpr -u tui-input.adb   ->   Success: all checks proved (72 checks)
```

What is proved: **no run-time errors** across every possible byte sequence (the
SPARK "silver" level), plus `Flush`'s one functional contract (a pending bare
`ESC` resolves to `Escape`). Notably, an internal type predicate ties the UTF-8
accumulator to the number of continuation bytes still expected, which is what
proves the `Acc * 64 + …` assembly steps cannot overflow. (Consequence: every
state transition that moves coupled fields assigns the record *as a whole* —
field-by-field updates would transiently break that predicate.)

What is **not** proved: that each byte sequence maps to the *right* event — that
`ESC [ A` is `Up`, that `0x03` is `Ctrl-C`, and so on. The decoder carries no
functional contract describing the mapping, so gnatprove does not check it. That
behavioural correctness is pinned by the tests in `tests/`, not by proof. In
short: the proofs say the decoder **cannot crash or misbehave on any input**;
the tests say it **decodes the right keys**.

## v1 assumptions (documented, revisitable)

- Malformed/aborted sequences emit `Unknown` and the offending byte is dropped
  (not re-fed). Fine for a pager that ignores unknown keys.
- `Ctrl-H` / `Ctrl-I` / `Ctrl-M` alias `Backspace` / `Tab` / `Enter`.
- `Ctrl-<letter>` reports the uppercase code point (e.g. `Ctrl-C` → 67).
- `Alt` + multibyte is not decoded (rare; yields `Unknown`).
- Bracketed paste is not yet handled.

## Where this lives

```
src/tui-input.ads
src/tui-input.adb
tests/src/test_input.adb
demo/src/demo_input.adb
```

The whole library builds, tests and proves as one; see the crate
[README](../README.md) for the commands. To prove this layer alone:

```sh
gnatprove -P tui.gpr -u tui-input.adb
```
