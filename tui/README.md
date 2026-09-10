# tui

The proved half of a small terminal-UI ecosystem: everything that can be
computed without touching a terminal. Display widths, a line index over a byte
buffer, a grid of styled cells and its frame diff, a key decoder, the pager
engine, and the app kit that hosts of the engine share. All SPARK, all proved
free of run-time errors, no I/O and no OS anywhere in it.

The terminal itself lives in the sibling `tui_term` crate. That split is the
one boundary in the ecosystem, and it is about trust rather than size:
`tui_term` is `SPARK_Mode => Off` because it owns termios, signals and
controlled types, so keeping it separate is what makes "this library performs
no I/O" a structural fact instead of a convention — and keeps syscalls out of
the build closure of everyone who only needs the proved parts.

## The layers

| Package | What it does | Notes |
|---|---|---|
| `Tui` | the empty `Pure` root | a compilation unit so children can exist |
| `Tui.UTF8` | code-point decoding | shared by the width, input and render paths |
| [`Tui.Width`](docs/width.md) | display columns for a code point | the `wcwidth` Ada lacks |
| [`Tui.Text`](docs/text.md) | line index over an immutable buffer | offsets, not copies |
| [`Tui.Surface`](docs/surface.md) | grid of styled cells, plus frame diff | rendering as data, not effect |
| [`Tui.Input`](docs/input.md) | terminal byte stream to key events | interprets bytes; never reads them |
| [`Tui.Pager`](docs/pager.md) | the viewport engine: view, search, render | the heart of the ecosystem |
| [`Tui.App_Kit`](docs/app_kit.md) | search-pattern editor, status-line buffer | what every host needed twice |

The dependency order is width, text, surface and input over the root, then the
pager over those, then the app kit. It is a shallow DAG and stays one.

## Why one crate

These were eight crates — a root, six layers and the driver — and the split
bought nothing measurable. The package hierarchy is the API and it is
independent of packaging: `Tui.Width.Char_Width` is spelled the same either
way. No consumer ever took a subset; both hosts `with`ed the identical set.
Meanwhile the root crate existed only as an artifact of the split, since
someone has to own the empty `Tui` as a compilation unit and per-crate copies
collide the moment two of them share a build closure.

What the split did cost was standing: eight manifests, project files, READMEs,
object and library trees, and a path-pin block in every consumer. Merging
retires all of it and deletes the root crate outright. A static library links
only referenced objects, so nothing grows.

The one thing worth watching was proof scoping: each crate used to prove in
isolation, which kept runs fast and failures attributable. One `Prove` package
at level 2 covers the merged library (593 checks, all proved), and `-u` still
proves a single unit in seconds when that is what you want.

## Build, test and prove

```sh
gprbuild -P tui.gpr                          # the library
gprbuild -P tests/tests.gpr                  # the behavioural suites
(cd tests && for t in test_width test_text test_surface test_input \
                     test_engine test_pager test_app_kit; do ./$t; done)
gprbuild -P demo/demo.gpr                    # the throwaway demos
gnatprove -P tui.gpr --level=2 -j8           # the proofs
gnatprove -P tui.gpr -u tui-width.adb        # ... or one unit at a time
```

`-XMODE=debug` builds without optimisation and keeps `-gnata`, so the contracts
run as assertions; release is the default, since the contracts are proved
statically and need not run.

## Layout

```
alire.toml     crate manifest (no dependencies, by design)
tui.gpr        library project + gnatprove switches
src/           the layers above, all SPARK_Mode => On
tests/         behavioural suites, one per layer, ordinary Ada with -gnata
demo/          throwaway programs, one per layer, NOT SPARK
docs/          per-layer documentation: what each is, and what its proofs cover
```

## What proof does and does not say

Per layer, the details are in `docs/`. The shape is the same throughout: the
proofs say the code cannot crash, cannot read out of bounds and terminates —
and, where a contract states it, that an invariant holds (the viewport is
always within the content, a diff reports every changed cell). They do not say
the output is what you would want to look at: correct tab stops, correct
widths for a given code point, correct escape decoding. That is what the
behavioural suites in `tests/` are for.
