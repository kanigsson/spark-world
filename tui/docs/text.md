# Tui.Text

A line index over an immutable byte buffer — bytes in, line spans out — written
in SPARK and proved free of run-time errors. Crate #3 of the TUI ecosystem (see
the parent `ROADMAP.md`). See **Proof status** for exactly what the proofs do and
don't cover.

## What it is

`Tui.Text` builds an index of line boundaries so a pager can fetch "line N" in
O(1). It stores **offsets, not copies**: the caller owns the buffer, the index
records where each line starts and how long it is.

```ada
Idx : Tui.Text.Index (Capacity => 10_000);
...
Scan (Idx, Buf);          --  record every complete (LF-terminated) line
Seal (Idx, Buf);          --  at EOF: finalise an unterminated final line
...
N    := Line_Count (Idx);
Bytes := Line (Idx, Buf, 1);   --  a slice of Buf, no copy
```

### Design decisions worth knowing

1. **Offsets over an externally-owned buffer.** The index never copies content;
   it holds `(Start, Length)` spans. The price is that `Line` takes the buffer
   back as a parameter, with a precondition that it still covers the scanned
   prefix.
2. **Incremental and append-aware.** `Scan` remembers how far it got; call it
   again on a grown buffer (a pipe) and it resumes. Complete lines only — a
   trailing partial line is finalised by `Seal` at end-of-input. This is the
   file-vs-pipe distinction made explicit.
3. **UTF-8-agnostic by design.** `LF`/`CR` bytes can never appear inside a
   multibyte UTF-8 sequence, so splitting on them is byte-safe regardless of
   encoding. Column width and tab stops are a *display* concern owned by the
   `Tui.Width` layer and the pager's layout — deliberately not here.
4. **Bounded, no allocation.** `Capacity` (a discriminant) caps the line count;
   reaching it sets `Truncated` rather than overflowing or allocating.

## Proof status

```
gnatprove -P tui.gpr -u tui-text.adb   ->   Success: all checks proved (54 checks)
```

What is proved:

- **No run-time errors** for all inputs — no overflow, no out-of-range index, no
  range violation (SPARK "silver"). This includes the offset arithmetic
  (CR-stripping, empty lines, line starts that sit one past the buffer end).
- **A safety invariant on the index**: every recorded span lies within the
  scanned prefix (`Start + Length <= Scanned + 1`). This is the contract that
  makes slicing a line out of the buffer provably in-bounds — so `Line` cannot
  read outside the buffer.
- **`Line`'s length contract**: the returned slice's length equals the span's
  length.

What is **not** proved:

- That lines are split at the *right* places — correct CRLF handling, correct
  empty-line and unterminated-tail behaviour. There is no functional contract
  describing the splitting, so gnatprove does not check it; that behavioural
  correctness is pinned by the tests in `tests/`.
- The **append-only usage contract** (between `Scan` calls the already-scanned
  prefix must be unchanged) is documented, not machine-checked. Violating it
  affects correctness, not safety.

In short: the proofs say it **cannot crash and cannot slice out of bounds**; the
tests say it **splits lines correctly**.

## Notes

- A single `Tui.Text` package holds both the index and the scanner. The roadmap
  sketched a `Tui.Text.Lines` / `Tui.Text.Scan` split, but the two are tightly
  coupled (the scanner mutates the index), so consolidating is cleaner — and
  consistent with how `Tui.Input` ended up.
- The shared empty `Tui` root is part of this crate; it exists as a
  compilation unit so children can hang off it, and it is `Pure` and
  empty so it never constrains one.
- A lone trailing `CR` with no following `LF` is kept as content (only a `CR`
  immediately before an `LF` is stripped). Documented v1 behaviour.

## Where this lives

```
src/tui-text.ads
src/tui-text.adb
tests/src/test_text.adb
demo/src/demo_text.adb
```

The whole library builds, tests and proves as one; see the crate
[README](../README.md) for the commands. To prove this layer alone:

```sh
gnatprove -P tui.gpr -u tui-text.adb
```
