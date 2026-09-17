# inflate

A one-shot, no-heap DEFLATE/zlib/gzip/ZIP codec in SPARK, plus a CLI that
compresses and decompresses whole files. The whole library is SPARK; `cli/`,
`tests/` and `bench/` are ordinary Ada, C and Python.

## What is proved, and what only the tests cover

Three different strengths, and conflating them overstates the result:

- **Absence of run-time errors, termination, initialization/data-flow** over
  the whole library.
- **Decode model.** Every successful raw DEFLATE decode is proved to satisfy an
  executable canonical decode model. The model deliberately does **not** reuse
  the shipping Huffman table or fast map — it is an independent check, and the
  shipping decoder calls it only after an otherwise successful decode. Keep
  them independent.
- **Round trip.** `Inflate.Theorems.GZip_Round_Trip` proves, for every input,
  that decompressing the compressor's output restores it exactly with
  `Status = OK`. This is the theorem to preserve; `docs/compression.md` is the
  ratio ladder, and every step on it must leave the theorem standing.

Differential agreement with C zlib is **testing**, not proof. So is ZIP and
container acceptance behaviour.

Two table-internal bounds are defensive checks returning a defined error status
rather than proved invariants. `spikes/m2_kraft/` proved in isolation that both
are dead code; porting that proof in is on the ladder, not done.

## Structure worth knowing before changing the proof

The compressor emits blocks **back to front** because the decode-model relation
recurses front to back, so a backward loop makes each iteration exactly one
unfolding and the invariant is the relation itself on the written tail. The
decoder must walk forward, so it uses a separate non-final-prefix relation
extended by a snoc lemma and closed by a composition lemma. Reversing either
direction means rebuilding the invariant, not editing it.

The shipping decoder and the ordinary validation path are iterative; recursive
stored-fragment relations live in the proof layer only. `debug.adc` sets
`Assertion_Policy (Ignore)` and then `Ignore_Pragma (Assertion_Policy)`, so a
source-local `Check` policy cannot re-enable them — that is deliberate: it
keeps the recursive relations off every run-time stack path.

## Build, test, prove

```sh
make build      # library and bin/inflate
make test       # library suite: 6,449 cases plus 22 compress differential
make test-cli   # CLI round-trip and compatibility (see below)
make prove      # -j16 --no-subprojects
make bench      # needs libz.a
```

**Bound the prover parallelism; do not pass `-j0`.** The memory limit is per
prover process, so one job per core on a many-core machine exceeds available
memory, and the hardest checks here — the `Spec_Walk` loop invariants in
`Inflate.Dynamic` — are exactly the ones that reach it. `-j16` peaks near 11 GB
and needs no raised timeout. Starving those checks of their default 60 seconds
is what makes them look unprovable. `--no-subprojects` leaves Ore to its own run.

## `make test-cli` fails today, and the failure is real

`tests/run_cli_tests.py` aborts at `large-zero-run` with `inflate: stack
overflow or erroneous memory access` on an 8 MiB input at the default 8 MiB
stack. The three small samples pass. The test carries a comment saying it was
written to catch exactly this: `Load` and `Save` used to put a file-sized
`Stream_Element_Array` on the process stack. A file-sized array is back on the
stack in the CLI's I/O path. This is a CLI bug, not a library or layout
problem, and it predates the mono-repo move — see `docs/STATUS.md`.

## Known unproved checks

Two, both recorded in `docs/STATUS.md` rather than suppressed: an assertion at
`inflate-fixed.adb:932` (`Encoding_Matches`), where the provers hit their time
and memory limit rather than finding it false, so a longer timeout or higher
level may well close it; and a loop invariant at `inflate-dynamic.adb:3783` on
the `Spec_Walk` count against `Info.Decoded_Length`. Unlike `fuzzy` and
`spark_re`, this project's proof does not treat unproved checks as errors, so
the run exits 0 with them outstanding — read the counts.

## Dependencies

`../../libs/ore/ore_lib.gpr`, and nothing else. Ore supplies the physical byte
and word types, the byte array every layer is written against, the checked
endian field access the three container formats parse headers with, and the bit
layer the encoders' stream model is stated through. Both projects are in this
repository: if something is missing there, add it there, in the same commit as
the change here.

## `spikes/`

Five standalone `.gpr` proof spikes (`m1_fast`, `m2_kraft`, `m3_huffman`,
`m4_lz77`, `m6_dynamic_tree`). They are segregated experiments that nothing
builds or ships, kept here rather than in `experiments/` because they are about
this project's proof. Some reach into `../../src` for sources, so a source
rename can break one without breaking the build.
