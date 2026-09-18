# tui

The proved, I/O-free half of the terminal-UI ecosystem: display widths, a line
index over a byte buffer, a grid of styled cells and its frame diff, a key
decoder, the pager engine, the app kit and the pane layer. All SPARK, no I/O,
no OS.

## The one rule

**Nothing in `src/` may touch the terminal, the OS, or `Ada.Text_IO`.** The
sources have no context clauses onto anything of the sort, and that is the
property the whole split exists to keep: `tui_term` is `SPARK_Mode => Off`
precisely so that this library can be entirely on. A syscall added here is not
a small compromise; it moves the boundary and puts termios into the build
closure of everyone who only wanted the proved parts.

Rendering is data, not effect: a pane produces a surface, and someone else
writes it out.

## One crate, on purpose

This was eight crates — a root, six layers and the driver — and was merged into
one. The package hierarchy is the API and is independent of packaging;
`Tui.Width.Char_Width` is spelled the same either way, no consumer ever took a
subset, and a static library links only referenced objects. Do not split it
back up without a consumer that actually wants a subset. The README records the
reasoning in full.

The layer order — width, text, surface and input over the root, then the pager,
then the app kit and panes — is a shallow DAG. Keep it one.

## Build, test, prove

```sh
gprbuild  -P tui.gpr                       # release by default
gprbuild  -P tui.gpr -XMODE=debug          # -O0, -gnata: contracts run
gprbuild  -P tests/tests.gpr && (cd tests && for t in test_width test_text \
   test_surface test_input test_engine test_pager test_app_kit test_panes; \
   do ./$t; done)
../../tools/gnatprove -P tui.gpr --level=2 -j8   # 1086 checks, all proved
../../tools/gnatprove -P tui.gpr -u tui-width.adb  # one unit, seconds
```

`demo/` is throwaway, one program per layer, and is **not** SPARK. It exists to
look at a layer by hand; it is not a test and nothing depends on it.

## `Byte` and `Code_Point` are the root's

`Tui.Width`, `Tui.Text` and `Tui.Input` each used to declare their own `Byte` /
`Code_Point`. Those were distinct *types*, so a byte read by `Tui.Input` and a
byte held by `Tui.Text` needed a conversion between them. There is now one
declaration in `Tui`, and the layers carry subtypes of it under the same names
so that `Tui.Text.Byte` still resolves for clients that spell it that way.

Two consequences worth knowing before changing it back. A name inherited from
a parent is not a declaration in the child, so the subtypes cannot simply be
deleted — every qualified client reference would stop compiling. And the
operators now belong to `Tui`, so `use Tui.Text;` alone no longer makes `=` on
`Byte` directly visible; a unit that needs it says `use type Tui.Byte;`.

`Tui.Text` also owns the `String` <-> `Buffer` conversion now (`To_Buffer`,
`To_String`), which six tests and demos had each written. A library whose whole
input is a `Buffer` should say how to build one.

## What the proofs do not cover

The proofs say the code cannot crash, cannot read out of bounds, terminates,
and — where a contract states it — holds an invariant: the viewport stays
within the content, a diff reports every changed cell. They say nothing about
the output being *right*: tab stops, the display width of a given code point,
escape-sequence decoding. That is what the suites in `tests/` are for, one per
layer. A change to a width table or a decoder needs a test, not a proof.

`docs/` carries the per-layer detail, including what each layer's proofs cover.
Keep a layer's document current with its contracts.

## Clients

`tui_term` withs `../../libs/tui/tui.gpr` and drives the terminal; `git_view`
withs both and embeds the pager engine twice. Both are in this repository, so a
change here that breaks them is fixed in the same commit.
