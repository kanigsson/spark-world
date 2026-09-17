# TODO

Work on what is already here: proof cost, contract shape, gaps a client has
hit. New packages do not belong in this file — the library grows from client
demand, recorded in [`FEEDBACK.md`](FEEDBACK.md), not from a plan.

## Cut the proof time down

The timeout in `ore_lib.gpr` and `ore.gpr` is 180 seconds, raised from 60 in
0.3.0 because the field operations on a 64-bit word were proved on their own at
60 and lost in a whole-library run, where the provers compete for the cores. A
timeout that high is not a proof time — it is the margin the slowest goal needs,
and it makes a whole-project run slow enough to discourage running one.

What is known about where the time goes: the hard goals are bit-level contracts
on `Word64` with a variable shift amount, which are bit-vector problems, and
`Ore.Bits.Extract` for `Word64` is the one that failed first. Nothing else in
either project has come close to the limit.

The value-view lemmas added in 0.4.0 are the same shape at the same width, and
`Lemma_Extract_Value` for `Word64` needed its two steps named in the body rather
than more time — which is the cheaper fix and the one to reach for first.

Worth trying, roughly in order of how much they would tell us:

* Measure it first — `gnatprove --report=statistics` per unit, to name the
  goals rather than guess at them.
* Cut the 64-bit goals down. A postcondition quantified over 64 positions with a
  symbolic shift may be provable in steps a prover disposes of individually,
  the way the array-level frame in `Ore.Bit_Cursors` had to be.
* Check whether the level can drop. If the slow goals are slow at `--level=2`
  because of a prover order rather than their difficulty, a lower level with a
  targeted `Loop_Invariant` or lemma may be both faster and steadier.
* Only then lower the timeout, and re-run from scratch on a loaded machine
  before believing the result.
