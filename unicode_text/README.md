# Unicode Text

`Unicode_Text` is a SPARK-compatible UTF-8 text library under development.
The complete design and implementation milestones are described in
[`design.md`](design.md).

Milestones 1 through 5 provide the Unicode scalar types, the shared ghost text
model, strict UTF-8 validation, single-scalar encoding and decoding, validation
error offsets, code-point length and indexed access, forward cursors, plain
prefix/suffix/comparison operations, compositional byte-range and
byte-concatenation proof relations, byte/model bridge lemmas, and proof clients.
They also provide generic fixed-byte-capacity bounded strings with construction,
conversion, clearing, append, equality, indexed access, and forward iteration.
Milestone 5 adds byte spans, code-point slices, forward and reverse scalar
search, substring search, containment, bounded wrappers, and model-level
first/last-occurrence contracts.

The current version is `0.5.0`. Releases follow Semantic Versioning; the
repository's version and compatibility policy are described in
[`VERSION`](VERSION), [`CHANGELOG.md`](CHANGELOG.md), and the versioning section
of [`design.md`](design.md#20-versioning-and-compatibility).

Build and prove the current sources with:

```sh
gprbuild -P unicode_text.gpr
gnatprove -P unicode_text.gpr
```

Run the exhaustive scalar round-trip, malformed-input, and plain-string tests
with:

```sh
gprbuild -P tests/runtime/runtime_tests.gpr
./obj/runtime_tests/utf_8_tests
./obj/runtime_tests/plain_string_tests
./obj/runtime_tests/bounded_string_tests
```

The local `sparklib.gpr` is the application-owned project required by the
installed SPARK library. Build and proof artifacts are written below `obj/`
and `proof/` and are intentionally ignored by Git.

The library is licensed under the Apache License 2.0 with LLVM Exceptions
(`Apache-2.0 WITH LLVM-exception`). See [`LICENSE`](LICENSE).
