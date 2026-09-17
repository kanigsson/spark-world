# spark_re

An allocation-free, byte-oriented Thompson NFA regex library in SPARK, with two
ordinary Ada CLIs on top of it: `spark-grep` (files named on the command line
or records on stdin) and `spark-rg` (recursive walk).

## The proof is the product, and it reaches correctness

`src/` is proved past absence of run-time errors: the tree compiler and the NFA
simulator are proved **sound and complete** against independent tree-span and
instruction-path models, the scanners against independent byte-span
definitions, and successful parsing constructs a derivation in an independent
grammar — with completeness, so a pattern that has a derivation cannot produce
`Syntax_Error`. `Compile_For_Text` composes them: `Search` and `Full_Match`
equal the declarative `NFA_Accepts` model.

`docs/PROOF.md` states the theorems, the unit split and the proof boundary.
**Read it before changing anything under `src/`**, and keep it in step — a
change to the grammar, the instruction set or the closure is a change to a
theorem, not an implementation detail.

The unit split is load-bearing: `Spark_Re_Trees.Parsing` never names a program,
an instruction or an NFA state, `Spark_Re_Trees.Matching` never names a pattern
span, a scanner or a grammar level, and neither withs the other. A `with` added
between them would let a change in one layer reopen the other's proof.

Semantic models and certificates use SPARK's `Static` ghost level: proved,
never executed, not even in contract-enabled builds. The generic body is
checked through the default `Regex` instance only — a custom instantiation
needs its own run.

## Keep the kernel clean

No allocation, no I/O, no global state in `src/`, and the library depends on
nothing. Executable adapters, shared I/O and the recursive walker stay outside
the proof boundary, in `cli/`. Storage is automatic and sized by the compiled
state count, which matters on small-stack targets.

**Licensing:** this project is Apache-2.0. Do not copy implementation code from
GPL-only projects such as gsh.

## `common/spark_cli` is vendored here, deliberately

It is a separate crate — argument and usage handling — and its only clients are
`spark-grep` and `spark-rg`. It stays inside this project until a second
project adopts it; at that point it becomes `libs/spark_cli`. `fuzzy`,
`spark_diff` and `inflate` each hand-roll the same job today, so this is the
repository's most likely first promotion.

Its assertions follow the library's build mode, so the two must be switched
together — hence `CHECKS_VARS` naming both `SPARK_RE_BUILD` and
`SPARK_CLI_BUILD` in the `Makefile`.

## Build, test, prove

```sh
make build            # library, both CLIs, tests
make test             # library suite, then the three Python oracles
make test-contracts   # the same with executable library contracts
make flow
make prove            # --level=4
```

Proof runs at `--level=4` here, higher than elsewhere in the repository, and
takes minutes rather than seconds. `local.mk` is included if present and stays
untracked.

`tests/test_cli.py` is differential against Python `re` and GNU `grep -aE` in
locale C over 290 patterns in both search and whole-record modes; `test_rg.py`
and `test_matcher.py` cover the walker and the retained-storage `Matcher`. That
differential agreement is on this corpus — it is not POSIX compatibility, and
the CLIs implement a named subset rather than replacing grep or ripgrep.

## Known unproved check

One loop invariant at `spark_re_trees-matching.adb:6257` is not proved
preserved by an arbitrary iteration. The baseline in `docs/STATUS.md` records
4,039 of 4,040 checks proved; `--checks-as-errors=on` makes the run exit 1 on
that one check, so read the count, not the status. Do not silence it.

## Dependencies

None outside the project. `docs/BENCHMARKS.md` holds the simulator and walker
measurements, `docs/ROADMAP.md` the ordered future work — its ordering
principle is that changes leaving `Search = NFA_Accepts` untouched are cheap
because they are refinements under existing theorems.
