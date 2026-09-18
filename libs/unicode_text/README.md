# Unicode Text

`Unicode_Text` is a SPARK-compatible UTF-8 text library under development.
The complete design and implementation milestones are described in
[`design.md`](docs/design.md).

Milestones 1 through 6 provide the Unicode scalar types, the shared ghost text
model, strict UTF-8 validation, single-scalar encoding and decoding, validation
error offsets, code-point length and indexed access, forward cursors, plain
prefix/suffix/comparison operations, compositional byte-range and
byte-concatenation proof relations, byte/model bridge lemmas, and proof clients.
They also provide generic fixed-byte-capacity bounded strings with construction,
conversion, clearing, append, equality, indexed access, and forward iteration.
Milestone 5 adds byte spans, code-point slices, forward and reverse scalar
search, substring search, containment, bounded wrappers, and model-level
first/last-occurrence contracts. Milestone 6 adds allocation-free scalar and
substring split iterators returning byte spans, including model-level
reconstruction and delimiter-absence contracts.

The current version is `0.6.0`. Releases follow Semantic Versioning; the
repository's version and compatibility policy are described in
[`VERSION`](VERSION), [`CHANGELOG.md`](CHANGELOG.md), and the versioning section
of [`design.md`](docs/design.md#20-versioning-and-compatibility).

Build the library-only project and prove the library plus proof clients with:

```sh
gprbuild -P unicode_text_lib.gpr
../../tools/gnatprove -P unicode_text.gpr -XSPARKLIB_EXTERNALLY_BUILT=true
```

Run the exhaustive scalar round-trip, malformed-input, and plain-string tests
with:

```sh
gprbuild -P tests/runtime/runtime_tests.gpr
./obj/runtime_tests/utf_8_tests
./obj/runtime_tests/plain_string_tests
./obj/runtime_tests/bounded_string_tests
```

`unicode_text_lib.gpr` is the production project exposed by the Alire crate.
It contains only the units under `src/`.  `unicode_text.gpr` is the proof
umbrella: it imports the production project and adds `tests/proof` and the
application-owned `sparklib.gpr`.  Build and proof artifacts are written below
`obj/` and `proof/` and are intentionally ignored by Git.

The library is licensed under the Apache License 2.0 with LLVM Exceptions
(`Apache-2.0 WITH LLVM-exception`). See [`LICENSE`](LICENSE).
