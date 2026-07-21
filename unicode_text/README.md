# Unicode Text

`Unicode_Text` is a SPARK-compatible UTF-8 text library under development.
The complete design and implementation milestones are described in
[`design.md`](design.md).

Milestone 1 provides the Unicode scalar types, the shared ghost text model,
model relations, foundational algebraic lemmas, and initial proof-scaling
clients.

The current version is `0.1.0`. Releases follow Semantic Versioning; the
repository's version and compatibility policy are described in
[`VERSION`](VERSION), [`CHANGELOG.md`](CHANGELOG.md), and the versioning section
of [`design.md`](design.md#20-versioning-and-compatibility).

Build and prove the current sources with:

```sh
gprbuild -P unicode_text.gpr
gnatprove -P unicode_text.gpr
```

The local `sparklib.gpr` is the application-owned project required by the
installed SPARK library. Build and proof artifacts are written below `obj/`
and `proof/` and are intentionally ignored by Git.

The library is licensed under the Apache License 2.0 with LLVM Exceptions
(`Apache-2.0 WITH LLVM-exception`). See [`LICENSE`](LICENSE).
