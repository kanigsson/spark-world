# Tui.Pager

The embeddable pager **engine** — the heart of the ecosystem. Written in SPARK
and proved free of run-time errors. See **Proof status** for what is and isn't
proved.

It is the layer that combines the foundations: the line index, the display
widths and the cell surface all meet here.

## What it is

A pager as a **component**, not a program: it owns no terminal and runs no loop.
A host gives it materialised content and a surface to draw on; the host owns the
screen and the event loop. The standalone pager and a git viewer will be two
such hosts.

- `Tui.Pager` — shared types (line numbering reused from `Tui.Text`, screen
  `Dimension`, tab width).
- `Tui.Pager.View` — the **viewport**: `Top`/`Left`/`Height`/`Width`, with
  `Scroll_*`, `Page_*`, `Half_Page_*`, `Go_Top`/`Go_Bottom`, `Set_Size`. Every
  operation keeps the view within the content — you cannot scroll past either
  end.
- `Tui.Pager.Render` — `Draw`: paint the visible content into a `Tui.Surface`.
  Decodes UTF-8, uses `Tui.Width` for column advance (wide glyphs take two cells,
  combining marks none), expands tabs, applies horizontal scroll, truncates at
  the surface width, and blanks rows past end-of-content.

```ada
V : Tui.Pager.View.Viewport;
...
Tui.Pager.View.Set_Size (V, Height => Rows, Width => Cols, Total => Lines);
Tui.Pager.View.Scroll_Down (V, Lines, 1);
Tui.Pager.Render.Draw (Target_Surface, Content_Buffer, Line_Index, V);
```

## Key design decision: materialised content, not a Source interface

The engine consumes **already-materialised content** — a `Tui.Text` line index
over a byte buffer the host holds — rather than an abstract `Source` interface
that the engine would call back into. That is deliberate: a `Source` (a file read
on demand, `git log` output) is the **I/O boundary**, inherently non-SPARK, and
belongs in a host or a thin adapter — not inside the proven core. Keeping content
as plain data is what lets the entire engine be pure and provable, and what lets
the tests validate it with no terminal present.

## What's here vs. deferred

Built and proved now: the viewport (`View`) and rendering (`Render`).

Deferred to the host / a later layer (the orchestration + I/O boundary):

- an abstract **Source** interface for lazily-generated content;
- the **Engine** instance with a key-command map and host callbacks (Enter
  opens a commit, "selected line N", etc.).

## v1 layout simplifications (documented, revisitable)

- long lines are **truncated**, not wrapped (wrap is a future layout mode);
- control characters other than TAB, and combining/zero-width marks, are not
  drawn (they advance nothing) rather than shown in caret notation;
- a wide glyph straddling the left scroll edge is skipped; one straddling the
  right edge keeps its head cell.

## Proof status

```
gnatprove -P tui.gpr -u tui-pager-engine.adb   ->   Success: all checks proved (283 checks)
```

(The count is for the engine's own units, proved on their own with
`gnatprove -P tui.gpr -u`; proving the whole crate reports every layer at once.)

What is proved:

- **No run-time errors** anywhere in the engine — viewport arithmetic, the UTF-8
  decoder (which never reads past a line's end and clamps out-of-range code
  points), and all the layout index math (surface cells, buffer slices). Loops
  are proved to **terminate**.
- **Viewport-bounds contracts**: every scrolling operation establishes
  `V.Top <= Max_Top (Total, Height)`, i.e. the view is provably always within
  the content (`Go_Top` gives `Top = 1`, `Go_Bottom` gives `Top = Max_Top`).

What is **not** proved:

- That the rendered glyphs are **visually what you'd expect** — correct tab
  stops, correct truncation, correct wide-glyph placement. There is no
  functional contract describing the pixels; that behavioural correctness is
  pinned by the tests in `tests/`, not by proof.

In short: the proofs say the engine **cannot crash, cannot read out of bounds,
always terminates, and never scrolls off the content**; the tests say it **lays
out the text correctly**.

## Where this lives

```
src/tui-pager.ads
src/tui-pager-view.ads
src/tui-pager-view.adb
src/tui-pager-render.ads
src/tui-pager-render.adb
src/tui-pager-engine.ads
src/tui-pager-engine.adb
src/tui-pager-search.ads
src/tui-pager-search.adb
tests/src/test_pager.adb
demo/src/demo_pager.adb
```

The whole library builds, tests and proves as one; see the crate
[README](../README.md) for the commands. To prove this layer alone:

```sh
gnatprove -P tui.gpr -u tui-pager.ads
```
