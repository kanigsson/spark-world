# unicode_text

SPARK-compatible UTF-8 text: the scalar types and ghost text model
(`Unicode_Text`, `Unicode_Text.Models`), strict validation, encoding, decoding,
search and split iterators (`Unicode_Text.Utf_8`), and generic fixed-capacity
bounded strings (`Unicode_Text.Bounded`). No heap, no encoding but UTF-8.

## Two projects, on purpose

- `unicode_text_lib.gpr` — the production project, `src/` only. This is what the
  Alire crate exposes and what a client withs.
- `unicode_text.gpr` — the proof umbrella: the production project plus
  `tests/proof` and `sparklib.gpr`. Prove through this one.

A client must with the *lib* project, never the umbrella; the umbrella would
drag the proof clients and SPARKlib into the client's build.

## SPARKlib

`sparklib.gpr` here is a local project extending `sparklib_internal`, so
`with "sparklib"` resolves from this directory. It is an implicit dependency on
the SPARK library shipped with the toolchain, and the reason proof runs pass
`-XSPARKLIB_EXTERNALLY_BUILT=true`: a normal build compiles SPARKlib's objects
with the active compiler, and proof then uses its contracts without reanalysing
it. A build that has never been run makes the first proof run much slower, not
wrong.

Because SPARKlib ships with the prover, this is the one project where changing
prover changes a dependency. Prove through `../../tools/gnatprove`, which takes
SPARKlib from the prover it pins; a run that mixes them aborts on an
`inconsistent spark version` ali file, and the stale objects under
`obj/sparklib/` have to be cleared with `--clean` before it will run again.

## Build, test, prove

```sh
gprbuild  -P unicode_text_lib.gpr
../../tools/gnatprove -P unicode_text.gpr -XSPARKLIB_EXTERNALLY_BUILT=true
gprbuild  -P tests/runtime/runtime_tests.gpr
./obj/runtime_tests/utf_8_tests
./obj/runtime_tests/plain_string_tests
./obj/runtime_tests/bounded_string_tests
```

The runtime suites are exhaustive over the scalar range rather than sampled;
that is why they take a while and why a change to validation or encoding is
expected to be caught by them.

## Design document

`docs/design.md` is the specification, not a record of what was built: it is
written in the future tense, numbers its milestones, and says which are done
(currently 1-6; 7 is planned but not started). Keep its status line accurate
when a milestone lands. Its versioning section is the compatibility policy the
crate's version follows.

## SPARK posture

Proves clean at `--level=2`. Ghost code is `Assertion_Policy (Ghost => Ignore)`
in `gnat.adc`, so the text model costs nothing at run time even in an
assertion-enabled build.

## Clients

`json` withs `../../libs/unicode_text/unicode_text_lib.gpr` for UTF-8
classification and scalar coding, and keeps only the JSON string and escape
grammar itself. Do not add a second UTF-8 table there — extend this library.
