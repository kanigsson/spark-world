# Tui.Panes

The layer between "one engine painting one surface" and an application: a row
of panes, where a mouse report lands in them, the text selection a drag
describes, the bytes a copy puts on the clipboard, and a highlighted row that
keeps step with its viewport. Written in SPARK and proved free of run-time
errors. See **Proof status** for what the proofs do and don't cover.

## Why it exists

An application showing more than one document at once has to answer the same
questions every time: how wide is each pane, which pane did that click land
in, what does dragging across two of them select, and what happens to the
selected row when the viewport moves underneath it. None of that is engine
work — the engine deliberately knows only one viewport — and none of it is
application policy either.

It existed twice before it lived here, in the two `git_view` frontends, in
incompatible forms: one with proved layout arithmetic, proved hit-testing, a
mouse state machine, drag-select and an OSC 52 clipboard; the other, the
newer and now default one, with inline width arithmetic, a loop over its pane
enumeration, no minimum widths, no separator, no drag-select and no
clipboard. The two also silently disagreed about whether the wheel moves the
keyboard. By the ecosystem's own rule — extract on the second consumer, a
third copy is forbidden — the trigger had already fired.

## What it is

| Package               | Contents |
|-----------------------|----------|
| `Tui.Panes`           | the pane index: a fixed, client-declared row of at most `Max_Panes` |
| `Tui.Panes.Layout`    | `Compute` places panes across the width from weights, minima and drop priorities; `Locate` hit-tests and returns **pane-local** coordinates; `Rescue_Focus`, `Adjust`, `Split_At` |
| `Tui.Panes.Gesture`   | the `Recognizer`: press, drag, release, wheel and separator drag turned into a described `Gesture`, under a declared `Policy` |
| `Tui.Panes.Selection` | linear selection coordinates and their ordering |
| `Tui.Panes.Highlight` | overlays over an already-rendered pane surface: current row, selection, separator |
| `Tui.Panes.Clip`      | a selection turned into bounded bytes, and base64 a quartet at a time |
| `Tui.Panes.List`      | the selection-to-viewport coupling: a highlighted line that drags the viewport only when it would leave the screen |

Four decisions shape it.

**Panes are a fixed set indexed by position from the left.** A host that names
its panes with an enumeration converts with `Pane'Pos (P) + 1`. A runtime pane
tree would be a different and much larger library, and nothing asks for one.
Layout is one row of columns: no nesting, no vertical splits, and per-pane
title rows are not modelled — a title is content the host paints into its own
pane surface, and rows reserved for chrome are described to `Locate` as a
first content row and a content height.

**Hit-testing returns pane-local coordinates.** This is the largest single
simplification the extraction buys. The pane's own coordinate frame used to
be a value nowhere, so the same arithmetic was spread over three interlocking
contracts — the locator published bounds, the position mapper restated them,
and the body then recomputed `Col - Left_Width - 2` by hand. `Local_Row` and
`Local_Col` collapse all three, and remove "which pane is to the left of me"
from every caller.

**Recognition is mechanism; consequence is policy.** The recognizer says a
click happened in pane 2 on document line 40; whether that opens a commit is
the host's business. The contentious choices are a `Policy` record rather than
behaviour baked into a frontend: whether the wheel follows the cursor or the
keyboard, whether a drag may cross a pane boundary, whether Shift hands the
drag back to the terminal's own selection.

**The layer never owns content.** It is handed each pane's scroll offsets and
line total as a small `Frame` value, which is all that turning a screen cell
into a document position needs. Document ownership — and the proof leverage
that comes with it — stays in the host, which matters because the two hosts
own documents differently and for good reasons.

Encoding a clipboard payload is here; *emitting* it is not. `Tui.Term.Clipboard`
writes the OSC 52 sequence, because a terminal write is an effect and effects
live in the driver. Splitting the two also makes the encoder testable without
a terminal.

## Proof status

```
gnatprove -P tui.gpr -u tui-panes-layout.adb   ->   Success: all checks proved
```

The whole library, this layer included, proves in one run: **928 checks**, all
proved.

What is proved, beyond the absence of run-time errors and termination: that a
computed row is **disjoint, ordered and inside the terminal** — shown panes
run left to right, never overlap, and never reach past the last column — and
that it **covers the width exactly**: the leftmost starts at column 1, each
next one begins exactly one separator past its predecessor's end, and the
rightmost ends on the last column. That pair is what makes a composite paint
unable to overflow the screen surface, which is why it is stated in the
contract rather than left to the reader of the body. `Locate` proves its
returned local coordinates lie inside the pane it names, and the recognizer
proves the pane it reports is one the caller passed in.

What is *not* proved: that a 45/55 split is the split you wanted, that the
base64 alphabet is the right one, or that a drag selects the text you meant.
Those are pinned by `tests/src/test_panes.adb`.

## Where this lives

Above the engine, beside the app kit, below the apps — and never below the
driver: nothing here performs I/O.
