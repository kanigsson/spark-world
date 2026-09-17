# Tui.Width

Display-column width for Unicode code points — the Ada/SPARK analogue of POSIX
`wcwidth`, which the standard library lacks. Crate #4 of the TUI ecosystem (see
the parent `ROADMAP.md`) and the last of the pure-SPARK foundations. Written in
SPARK and proved free of run-time errors. See **Proof status** for what the
proofs do and don't cover.

## What it is

`Tui.Width.Char_Width (CP)` returns how many terminal columns a code point
occupies:

- **0** — a combining mark / zero-width character, or a non-printable control;
- **2** — an East-Asian wide or fullwidth glyph;
- **1** — everything else.

Plus the predicates behind it: `Is_Control`, `Is_Wide`, `Is_Zero_Width`. The
pager's layout uses this to map code points onto cells; without it, CJK and
combining text misalign.

```ada
W := Tui.Width.Char_Width (16#4E00#);   --  => 2  (CJK)
W := Tui.Width.Char_Width (16#0301#);   --  => 0  (combining acute)
```

## Table provenance and scope

The classification is a **binary search over sorted interval tables**. Those
tables are a **curated subset of the well-known Unicode blocks** — the classic
Markus-Kuhn `wcwidth` set: the common combining ranges, and the standard CJK /
Hangul / fullwidth / emoji wide ranges. They are correct for the common cases
but are **not** the full Unicode Character Database.

A complete implementation regenerates them offline from `UnicodeData.txt`
(general categories `Mn`, `Me`, `Cf`) and `EastAsianWidth.txt` (`W`, `F`). The
tables are shaped exactly like that generated output, so they can be replaced
wholesale without touching the lookup. `Tables_Well_Formed` checks the
sorted/non-overlapping invariant the search relies on (a test asserts it, so a
transcription slip when editing the tables is caught).

## Proof status

```
gnatprove -P tui.gpr -u tui-width.adb   ->   Success: all checks proved (26 checks)
```

What is proved:

- **No run-time errors** for every code point — including the binary search:
  no out-of-range table index, and `Mid + 1` / `Mid - 1` cannot overflow (the
  table index range is bounded for exactly this reason). The search is also
  proved to **terminate** (a loop variant).
- **`Char_Width`'s classification contract**: its result equals the documented
  combination of `Is_Control` / `Is_Zero_Width` / `Is_Wide`.

What is **not** proved:

- That the **tables contain the right code points** — i.e. that the widths are
  actually correct per Unicode. That is data, not logic; its correctness rests
  on the tables' provenance and on the behavioural tests, not on proof.
- That the tables are sorted (the search's correctness precondition). This is
  checked at run time by `Tables_Well_Formed`, which a test asserts — it is not
  a static proof.

In short: the proofs say the lookup **cannot crash and always terminates**; the
tests (and `Tables_Well_Formed`) say it **returns the right widths** for the
covered code points.

## Notes

- Grapheme-cluster segmentation (emoji ZWJ sequences, regional-indicator flags)
  is a separate, harder problem deferred to a future `Tui.Width.Cluster`; this
  layer is per-code-point only.
- The shared empty `Tui` root is part of this crate; it exists as a
  compilation unit so children can hang off it, and it is `Pure` and
  empty so it never constrains one.

## Where this lives

```
src/tui-width.ads
src/tui-width.adb
tests/src/test_width.adb
demo/src/demo_width.adb
```

The whole library builds, tests and proves as one; see the crate
[README](../README.md) for the commands. To prove this layer alone:

```sh
gnatprove -P tui.gpr -u tui-width.adb
```
