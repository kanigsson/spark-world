# fuzzy

An allocation-free fuzzy matcher — a proved SPARK library, a batch CLI and a
full-screen picker on top of it. Case-sensitive, byte-oriented, returns the K
best scores.

## The library is proved, and it is the product

Everything under `src/` is SPARK and fully discharged: run-time safety,
initialization and dependency, termination, and functional contracts that go
well beyond absence of errors — matching is proved equivalent to the recursive
earliest-occurrence subsequence model, the returned prefix is proved to be
exactly the best K matches, and ranking is proved strict. There are no assumed
lemmas, skipped proofs or `SPARK_Mode => Off` in the library.

**A change to `src/` is a change to that proof.** Touching the scoring table,
the greedy alignment or the insertion order means re-proving, not just
re-testing, and a weakened postcondition to make a run pass is the thing the
project exists to prevent. `cli/`, `tests/` and `benchmarks/` are ordinary Ada
and Python outside the proof boundary.

## The CLI owns the allocation, on purpose

The library never allocates and takes every buffer from its caller; standard
input has no size known in advance, so the CLI grows its corpus by doubling.
That asymmetry is the design, not an oversight — keep new storage decisions on
the CLI side of the boundary.

The picker reads one screenful of results and doubles that bound only when the
selection reaches the end of what came back, so scrolling is unbounded without
paying for a large K on every keystroke.

## Terminal handling here is hand-rolled

`--interactive` takes over `/dev/tty` in raw mode directly, with no dependency
on `libs/tui`. Restoring the terminal on every exit path — including `SIGTERM`
and `SIGHUP` — is load-bearing; an added exit path that skips it is a
user-visible regression. Results go to standard output so the picker stays
usable inside a command substitution, which is what `shell/fuzzy.bash` needs.

## Build, test, prove

```sh
make build            # library, CLI, benchmark, tests
make test             # library suite, CLI, picker
make test-contracts   # the same with assertions and ghost code executed
make flow             # initialization and dependency analysis
make prove            # --level=2 --proof=per_path, cvc5 and z3
make bench            # 100,000 synthetic paths, K=30, 20 searches
```

`local.mk` is included if present and stays untracked: the project states which
tools it needs and never where they live. `scripts/validate.py` records a
reproducibility manifest — it hashes `src/`, `cli/`, `tests/`, `benchmarks/`,
`scripts/`, the two project files, the `Makefile` and `docs/design.md`, so
renaming any of those means updating its list.

Tests are differential against an independent full-sort oracle across candidate
orderings and output capacities, which is what covers ranking ties that the
contracts state but do not pin down case by case.

## Known unproved check

One loop invariant at `fuzzy.adb:625` is not proved preserved by an arbitrary
iteration; the repository baseline in `docs/STATUS.md` records it at 581 of 582
checks proved. `Prove` passes `--checks-as-errors=on`, so `make prove` exits 1
because of this one check — read the count, not the status. It is recorded
rather than suppressed; do not make the run green by relaxing the contract.

## Dependencies

None. No `libs/` reference, no Alire dependency beyond the toolchain.
