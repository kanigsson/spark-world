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

**Licensing:** this project is `Apache-2.0 WITH LLVM-exception`. Do not copy
implementation code from GPL-only projects such as gsh.

## The two vendored crates under `common/`, deliberately

`common/spark_cli` is a separate crate — record framing and the I/O around it
— and its only clients are `spark-grep` and `spark-rg`. It stays inside this
project until a second project adopts it; at that point it becomes
`libs/spark_cli`. `fuzzy`,
`spark_diff` and `inflate` each hand-roll the same job today, so this is the
repository's most likely first promotion.

Its assertions follow the library's build mode, so the two must be switched
together — hence `CHECKS_VARS` naming both `SPARK_RE_BUILD` and
`SPARK_CLI_BUILD` in the `Makefile`.

`common/grep_front` is the other half of the same story and travels with it.
It holds what `spark-grep` and `spark-rg` both *decide* — the option letters,
the record-selection rule, the record prefix, the literal escape, the exit
status — as against what they do. Unlike `spark_cli` it is SPARK and proved,
by `make prove-front`, away from the library's run: keeping the two runs apart
is what stops a clean result here being buried inside the run that the
library's one open check makes fail. It reads the same `SPARK_CLI_BUILD`
external on purpose, so the two crates cannot be switched apart.

**It depends on nothing, and that is load-bearing.** A withed library's units
join a project's own proof run whatever switch is passed — neither
`--no-subprojects` nor naming this crate's files keeps them out — so a
dependency here would put thousands of someone else's goals, and their open
checks, in front of this crate's eighty-one. That is why a record's line
number and a count arrive as images rather than as values: the image library
is the caller's business. Adding a `with` to `grep_front.gpr` costs the run's
`--checks-as-errors=on` and its eight seconds.

`Grep_Diag`, in the same crate, is a SPARK specification over an ordinary Ada
body. Naming the standard error file takes a unit out of SPARK — that, and not
the option parsing, is why these front ends were ordinary Ada throughout — so
the channel is declared with the state each operation touches and implemented
outside the boundary. Add to the spec, not to the callers.

What the shared part must **not** grow is a letter only one program accepts.
Each program handles its own letters and reports the rest as an error, and the
CLI tests require that: `spark-grep -i` and `spark-grep -P` must fail. A
shared parser that accepted the union would take that diagnostic away.

## Build, test, prove

```sh
make build            # library, both CLIs, tests
make test             # library and front-end suites, then the three oracles
make test-contracts   # the same with executable library contracts
make flow
make prove            # --level=4, the library
make prove-front      # --level=2, the shared CLI front end
```

Proof runs at `--level=4` here, higher than elsewhere in the repository, and
takes minutes rather than seconds. `local.mk` is included if present and stays
untracked.

`tests/test_front.adb` is a unit suite over the shared front end, including
the letters it must reject; the contracts state the same rules but a proved
contract is checked by nobody in a release build.

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
