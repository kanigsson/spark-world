# json

An RFC 8259 pull parser in SPARK over caller-provided buffers: one event per
call, payloads returned as slices into the input, nothing materialized.

## The properties that define it

No heap, no access type, no recursion, no OS dependency, no package state.
Malformed input is a status value, never an exception. Every byte is validated
on the way through, and a document that parses to `Document_End` conforms to
RFC 8259. A change that breaks any of those is a change of product, not an
implementation detail — this library exists to parse untrusted input.

Two deliberate departures from Python's `json`, which the differential tests
encode rather than work around: lone surrogates in `\uXXXX` escapes are
rejected (they have no UTF-8 encoding), and `NaN`/`Infinity` are rejected
(RFC 8259 has no such tokens).

## UTF-8 belongs to unicode_text

Classification, scalar decoding and encoding come from
`../../libs/unicode_text/unicode_text_lib.gpr`. This library keeps only the
JSON string and escape grammar. **Do not add a second UTF-8 range table or
encoder here** — if something is missing, add it there; both projects are in
this repository, so the library change and its client change in one commit.
Note the consequence in error reporting: unicode_text reports malformed and
incomplete raw sequences through one classifier result, so both map to
`Invalid_UTF8`, while structural truncation still reports `Truncated`.

## Build, test, prove

```sh
gprbuild  -P json.gpr                 # release: -O2, checks suppressed
gprbuild  -P json.gpr -XMODE=debug    # -gnata, -O0
cd tests && ./run_tests.py            # full corpus, ~1,900 documents
cd tests && ./run_tests.py --quick
gnatprove -P json.gpr --level=2
```

Suppressing run-time checks in release is the point of the proof, not a
shortcut: they are discharged statically. So a release build is only as safe
as the last proof run — do not relax a contract to make a build pass.

The suite is differential against Python's `json` module on the same bytes:
for accepted documents the whole event stream must match, for rejected ones
the crate must reject too. That is what stands in for a functional-correctness
proof here, so behavioural changes need cases there.

## Two things about the corpus

It is not fully reproducible. Part of it is the project's own GNATprove output
(`obj/gnatprove/result.json` and the SARIF), so the case count moves with
whether the project has been proved lately — the phase-1 baseline recorded
1,898 and a later run 1,899 for this reason alone.

Worse, it also globs `../../../inflate/obj/gnatprove/*.json`, reaching into
another project's proof output. That path tracks where that project lives and
whether it has been proved; it matches nothing at the moment, which makes it
dead as well as wrong. It is due to be replaced by a fixture of this library's
own — see `docs/STATUS.md`.

## SPARK posture

The whole library is SPARK. Proof covers absence of run-time errors,
termination and initialization/data-flow, not functional correctness.

A run leaves a handful of checks unproved, and none of them are this
library's code: they are range checks inside SPARKlib's own float-arithmetic
lemmas, reached through proving the dependency. How many varies between runs —
the phase-1 baseline saw 10, a later run 3 — because the provers are close to
the edge on them. Do not chase them here, and do not read a change in the
count as a change in this library.
