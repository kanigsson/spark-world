# Baseline status

Phase 1 of the mono-repo restructuring (see the plan in
`~/aireports/2026-09-18-spark-world-monorepo-plan.md`): the state of every
project in the **flat, as-imported layout**, before anything moves.

The point of this file is a known starting line, not a green one. A project
that does not build or prove today should not have its move blocked; it should
have its failure written down here so the move cannot later be blamed for it.
No proof was repaired while producing this baseline, by explicit choice.

Recorded 2026-09-18. Toolchain: GPRBUILD Pro 27.0w (20260910), GNATprove 0.0w
(Why3 1.8.2+git), Alire 2.1.1, 32 cores.

## Repairs made before measuring

Three cross-project references still assumed the pre-import layout, where the
projects were sibling repositories two levels apart. All three are now
one-level siblings:

| Project | Reference | Was | Now |
| --- | --- | --- | --- |
| `inflate` | `inflate.gpr`, README prose and link | `../../ore/ore_lib.gpr` | `../ore/ore_lib.gpr` |
| `json` | `json.gpr`, Alire pin, README link | `../../unicode_text/…` | `../unicode_text/…` |
| `gitview` | `git_view.gpr`, Alire pin, README link | `../../git-changes/…` | `../git-changes/…` |

`gitview`'s `tui` and `tui_term` references and `term`'s `tui` reference needed
no change: those three were siblings before the import too.

All of these get rewritten again in phases 3 and 4, when the projects move into
`libs/` and `apps/`. Fixing them now is what made this baseline reachable.

## Build and test

| Project | Build | Tests | Notes |
| --- | --- | --- | --- |
| `ore` | pass | pass | 3 runtime suites all "all checks passed"; restriction smoke exits 0 |
| `unicode_text` | pass | pass | `utf_8_tests`, `plain_string_tests`, `bounded_string_tests` |
| `json` | pass | pass | full corpus: 1,898 cases, 0 failures |
| `tui` | pass | pass | 8 suites; demos build |
| `term` (`tui_term`) | pass | pass | `test_output`; demo builds |
| `git-changes` | pass | pass | 183 core checks, 55 integration scenarios; CLI builds |
| `gitview` | pass | pass | model + behavior (184 checks), 34 fixture, 41 PTY, mouse suite |
| `fuzzy_matcher` | pass | pass | 165,293 checks, 30 CLI, 19 interactive |
| `spark_diff` | pass | pass | 119,734 cases / 2,448,265 checks, 3,363 CLI roundtrips |
| `spark_re` | pass | pass | library, 1,198 differential/CLI, 290 walker, 656 grep differential |
| `inflate` | pass | **partial** | library suite passes (6,449 cases, 22 compress differential); **CLI suite fails**, see below |

### Known failures, not repaired

**`inflate` CLI: stack overflow on an 8 MiB input.**
`tests/run_cli_tests.py` aborts at the `large-zero-run` case with
`inflate: stack overflow or erroneous memory access` (default 8 MiB stack).
The three small samples pass. The test carries a comment saying this is a
regression it was written to catch — "Load and Save used to put a file-sized
`Stream_Element_Array` on the process stack" — so a file-sized array is back on
the stack in the CLI's I/O path. Unrelated to the layout; pre-existing since
the project was last touched on 2026-07-30 (imported from the `ore-migration`
branch, not `main`).

**`inflate` spikes `m4_lz77` and `m6_dynamic_tree` do not build.**
Both add `../../src` to their source dirs, pulling in the inflate library,
but do not with `ore_lib.gpr`, so `ore.ads` is not found. The other three
spikes (`m1_fast`, `m2_kraft`, `m3_huffman`) build. Also pre-existing and
independent of the layout; these are throwaway spikes, and the plan already
flags the directory as a candidate for `experiments/`.

## Proof

Each project was proved with its own documented command, level and switches —
these vary on purpose — under a 30-minute wall-clock cap, with
`--counterexamples=off` to keep the runs comparable. Nothing was repaired.

| Project | Result | Checks | Time |
| --- | --- | --- | --- |
| `spark_diff` | all proved | 546 | 70s |
| `ore` | all proved | 2,278 | 372s |
| `unicode_text` | all proved | 2,595 | 52s |
| `tui` | all proved | 1,047 | 54s |
| `gitview` | all proved | 2,692 | 69s |
| `git_changes` | all proved | 189 | 34s |
| `json` | 10 unproved | 2,594 / 2,604 | 55s |
| `fuzzy_matcher` | 1 unproved | 581 / 582 | 53s |
| `spark_re` | 1 unproved | 4,039 / 4,040 | 285s |
| `inflate` | *run not finished* | — | — |
| `term` (`tui_term`) | not applicable | — | — |

`term` is `SPARK_Mode => Off` by design: it is the one crate that owns termios,
signals and controlled types, and that isolation is what makes "nothing else
performs I/O" a structural fact rather than a convention.

`gitview`'s run went through the repaired `git_changes` reference, so the path
fix is confirmed on the proof path and not only on the build path.

### Unproved checks, not repaired

**`json` — 10 checks, none of them json's code.** All ten are range checks
inside SPARKlib's own float-arithmetic lemmas
(`spark-lemmas-floating_point_arithmetic.ads:200` and `:209`, reached through
`spark-lemmas-float_arithmetic.ads:14` and its `long_float` counterpart). They
are an artifact of proving the dependency, not a gap in the parser.

**`fuzzy_matcher` — 1 check.** A loop invariant not preserved by an arbitrary
iteration, at `fuzzy.adb:625`. The project's `make prove` treats unproved
checks as errors, so the run exits 1.

**`spark_re` — 1 check.** A loop invariant not preserved by an arbitrary
iteration, at `spark_re_trees-matching.adb:6257`: `not Accepting (Self,
Model_States (Self, Text, Whole, Earlier))`. Same error treatment, so this run
also exits 1.

### Proof scope worth knowing

`git_changes` proves clean, but its `scripts/prove.sh` names three units
explicitly — `core-validation`, `core-raw`, `core-hunks`. "All proved" there
means those three, not the whole library.

`git-changes` also requires GNATprove 16 specifically and resolves it under
`~/.alire/gnatprove_16.1.0_82528bef`, while every other project proves with
whatever is on `PATH` (here 0.0w). The repository currently proves with two
different provers depending on which project you are in. That is a genuine
coherence problem for the mono-repo and is listed for the consolidation phase.
