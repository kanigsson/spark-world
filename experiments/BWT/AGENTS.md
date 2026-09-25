# BWT

SPARK reference implementations of the classical and bijective BWT, with all
three inverse laws in `BWT.Theorems` proved. Core code and ghost proofs are
in `src/`. `tests/` is ordinary Ada and uses
`../../tools/testing/testing.gpr`. There is no generated source and no
SPARK-off code. [PROOF.md](PROOF.md) maps the proof.

`make prove` must report zero unproved checks. It names the pinned prover and
treats unproved checks as errors. Keep `-U`, or uncalled ghost proof units
drop out of the run. The 5-second budget is deliberate: every check proves
well inside it. If a change needs more, split the lemma instead (see the
proof-engineering notes in PROOF.md). A 2-second from-scratch run
(`--timeout=2 -f`) is a quick way to find checks near the edge.

Before changing code, know:

- The bijective table sorts with `Later_First` ties and the classical one with
  `Earlier_First`. The bijective proof needs exact LF, which only the later-first
  order gives. The classical order fixes which of several equal rows is
  `Primary`, so changing it changes classical output.
- `Bijective_Decode` first computes its visiting order (`Decode_Order`), then
  gathers letters. SPARK has no ghost parameters, so the order must be an
  ordinary result for its contract to reach the proofs.
- The bijective contracts live in `BWT.Bijective`. The public functions in `BWT`
  are thin wrappers, and the bijective laws are proved in `BWT`'s body.
- The encoders' functional specifications (`Is_Classical_BWT`,
  `Is_Bijective_BWT`) and the rotation vocabulary they use live in `BWT`'s
  spec: a parent's contracts cannot name its children. Lemmas about that
  vocabulary stay in `Rotations` and `Sorting`.
- Both encoders read their tables from `Doubling.Sorted_Rows`. The
  selection-sorted tables (`Classical_Table` in `BWT`'s body,
  `Bijective.Table_Of`) are ghost now: they only define the specified rows.
  A change to an encoder's order must keep the hypotheses of the
  `*_Rows_Unique` lemmas, not match the selection sort.
- Ghost lemmas of the form `Get_*` extract one instance of an opaque
  predicate. They exist for proof speed, not logic.

Validation (2026-09-25, `Max_Length` = 2**24): `make prove` proves all 8,388
checks under the pinned GNATprove FSF 16.1.0 (Why3 1.8.2+git, CVC5 1.3.2,
Z3 4.15.4, Alt-Ergo 2.6.1); a forced run (`-f`) took 8½ min at `-j16` before the search units; not re-measured since.
Three checks need Alt-Ergo (see the Makefile). `BWT.Circular` (2026-09-25) proves from scratch at `--timeout=2`.
The development GNATprove 0.0w
was last checked at a bound of 1,024.
`make test` passes 881,309 checks in about 7 s, `make test-contracts` passes 2,344 (about 10 min: it executes the ghost proofs, and skips the locator), `make flow`
is clean and `make format-check` passes. GPRbuild Pro 27.0w.

`make bench` times a production build (`-gnatp`, no contracts). Never time
the `checks` build: its ghost checks dominate everything it runs. The bench
lifts the stack limit itself, and reads its `SOURCE` corpus from the
repository's tracked files (about 45 s in all). `make bench-corpora` times
the same build on public corpora, which `bench/fetch-corpora.sh` downloads
into `obj/corpora` on first use. Never commit them. It takes several
minutes at 4 MiB; `CORPORA_SIZES=1048576` is quicker.
