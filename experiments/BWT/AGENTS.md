# BWT

Experimental SPARK reference algorithms, not yet proved roundtrip. All core
code and ghost theorem bodies are in `src/`; `tests/` is ordinary Ada and uses
`../../tools/testing/testing.gpr`. No generated source and no SPARK-off core.

`BWT.Theorems` contains three **unproved targets**, not trusted lemmas. Do not
call them to justify other proofs until their bodies are discharged. Do not
move their assertions into assumed/imported contracts or silence failures.
`PLAN.md` gives the proof order and the important duplicate/periodic cases.

Use one matching compiler/prover toolchain. `make prove` deliberately uses the
caller-provided GNATprove and treats unproved checks as errors. Keep `-U`:
otherwise uncalled theorem units can disappear from a proof run. All normal
builds enable contracts, so `test` and `test-contracts` run the same suite.

Validation baseline (2026-09-22): `make test` passes 49,232 checks;
`make flow` passes all 23 checks; `make format-check` passes. Toolchain:
GNAT/GPRbuild Pro 27.0w (20260910), development GNATprove reporting `0.0w`,
Why3 1.8.2+git, CVC5 1.3.2 and Z3 4.15.4. The repository formatter resolves
the shared pin; no local tool locations belong in tracked files.

`make prove`: **199/206 checks proved, seven unproved**, with a nonzero exit
as intended. Nothing is justified or suppressed. Exact remaining obligations:

- `bwt-theorems.adb:7,12,17`: the three inverse equalities. The algorithms'
  contracts currently specify shape only; the semantic lemmas in `PLAN.md`
  are needed. A proved theorem *postcondition* downstream of an unproved
  assertion does not establish the theorem.
- `bwt.ads:24`: the nonempty classical primary row is in range. Sorting needs
  a permutation/preservation contract and the extraction loop needs a witness.
- `bwt.adb:225`: initialization of the inverse's `Next <= Last'Length`
  invariant; the outer loop needs to carry it.
- `bwt.adb:227`: output indexing at `Next`. Relate remaining output space to
  unvisited positions to establish positivity.
- `bwt.adb:233`: all output positions filled (`Next = 0`). Requires visited
  accounting and coverage invariants across the outer scan.

All seven reached the five-second proof budget; this is not evidence that
longer timeouts alone suffice. There is also a harmless flow warning for the
redundant initialization of the classical decoder's output (`bwt.adb:134`).
Full runtime safety and all universal inverse laws remain unproved. Successful
helper proofs establish only their current contracts: in particular, LF's
range is proved, but its permutation property is not yet specified or proved.
The generated full report is `obj/core/gnatprove/gnatprove.out` (untracked).
