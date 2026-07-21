# Unicode Text

`Unicode_Text` is a SPARK-compatible UTF-8 text library under development.
The complete design and implementation milestones are described in
[`design.md`](design.md).

Milestone 1 provides the Unicode scalar types, the shared ghost text model,
model relations, foundational algebraic lemmas, and initial proof-scaling
clients.

Build and prove the current sources with:

```sh
gprbuild -P unicode_text.gpr
gnatprove -P unicode_text.gpr
```

The local `sparklib.gpr` is the application-owned project required by the
installed SPARK library. Build and proof artifacts are written below `obj/`
and `proof/` and are intentionally ignored by Git.
