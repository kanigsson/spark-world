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
- Ghost lemmas of the form `Get_*` extract one instance of an opaque
  predicate. They exist for proof speed, not logic.

Validation (2026-09-24): `make prove` proves all 5,506 checks from a clean
tree under the pinned GNATprove FSF 16.1.0 (Why3 1.8.2+git, CVC5 1.3.2,
Z3 4.15.4). The development GNATprove 0.0w also proves them all. Its
tightest check is a frame-heavy invariant in `Decode_Order`: it needs more
than 2 s but fits in 5. `make test` passes 49,232 checks,
`make test-contracts` passes 218, `make flow` is clean and
`make format-check` passes. GPRbuild Pro 27.0w.
