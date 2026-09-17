# Tui.Surface

An in-memory grid of styled terminal cells, plus a minimal frame **diff**,
written in SPARK and proved free of run-time errors (with a soundness contract
on the diff). This is step one of a small TUI ecosystem (a pager, then a key
decoder, then host apps such as a git-history navigator). It is the
most-depended-upon piece, so it is built first and to a deliberately high bar —
it sets the template every later layer copies. See **Proof status** for exactly
what is and isn't proved.

## What it is

- `Tui.Surface` — a `Surface (Rows, Cols)`: a 2-D grid of `Cell`s, where a cell
  is a glyph plus foreground/background `Color` and a `Style`. Bounds-safe
  `Get` / `Set` / `Blank` / `Clear`, each carrying a full frame condition
  ("everything else is unchanged"), and `Copy` — a region blit of one whole
  surface into a rectangle of another, the compositing primitive a multi-pane
  host uses to assemble per-pane surfaces into the screen.
- `Tui.Surface.Diff` — `Compute (Previous, Current, Changes, Count)`: the set of
  cells that changed between two frames, so a driver repaints only those.

Rendering here is **data, not effect**: a producer fills a surface, a driver
reads it. The library performs no I/O and touches no terminal.

## The conventions this layer sets

1. **One namespace.** Everything lives under `Tui.*`. The root `Tui` is `Pure`
   and empty so it never constrains a child.
2. **The library is SPARK and only SPARK.** Every unit in `src/` is
   `SPARK_Mode => On` and proved free of run-time errors. No syscalls, no I/O,
   no global state.
3. **Anything that touches the OS lives outside the library crate.** The only
   terminal-aware code is the throwaway `demo/`, kept out of `tui.gpr`
   precisely so a consumer never drags I/O in. The driver is its own crate,
   `tui_term`, `SPARK_Mode => Off` at its edges — the one boundary in the
   ecosystem that is about trust rather than size.
4. **Contracts first, then proof, then completeness.** Specs state the full
   intent; we prove soundness + absence-of-run-time-error now and tighten
   toward full functional correctness (see below).
5. **gnatprove and tests are both first-class.** Proof covers all inputs; the
   tests in `tests/` pin concrete expectations and double as examples.

## Proof status

```
gnatprove -P tui.gpr -u tui-surface.adb   ->   Success: all checks proved (175 checks)
```

"All checks proved" means every verification condition arising from the
contracts *in the code* is discharged. It is **not** a blanket claim of
functional correctness — only the properties actually written as contracts are
proved. Concretely, what is proved:

- **No run-time errors** anywhere — no overflow, no out-of-range index, no range
  violation (this is the SPARK "silver" level).
- The **`Set` / `Blank` / `Clear` / `Copy` frame conditions** — each touches
  exactly the cells it should and leaves the rest unchanged; for `Copy` this
  includes full functional correctness (the target rectangle equals the
  source, cell for cell).
- **Diff soundness** — every change `Compute` reports is a genuine difference
  carrying the new value.

What is **not** yet proved (and so must not be assumed):

- **Diff completeness / uniqueness** — that *every* differing cell appears, and
  exactly once. The property is written as the ghost function `Is_Complete` in
  `tui-surface-diff.ads` but is **not** part of `Compute`'s postcondition yet, so
  gnatprove does not check it. Promoting it is the next proof milestone and will
  likely need a small ghost model of "cells seen so far". Until then,
  completeness rests only on the behavioural tests.

## Where this lives

```
src/tui-surface.ads
src/tui-surface.adb
src/tui-surface-diff.ads
src/tui-surface-diff.adb
tests/src/test_surface.adb
demo/src/demo_surface.adb
```

The whole library builds, tests and proves as one; see the crate
[README](../README.md) for the commands. To prove this layer alone:

```sh
gnatprove -P tui.gpr -u tui-surface.adb
```
