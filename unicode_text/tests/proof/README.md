# Model proof-scaling experiments

`Model_Scaling` exercises chains of 1, 2, 4, 8, and 16 relational
concatenations. Each client proves that the original text remains a prefix of
the final result using only the public `Unicode_Text.Models` specification.
`Nonempty_Witness` separately constructs concrete scalar sequences and proves
concatenation, slicing, and containment, guarding against vacuous results.
`Concatenation_Associativity` is the demand-driven client for the one public
model lemma retained in Milestone 1.

`Byte_Layer_Proofs` checks the public scalar round-trip theorem and supplies
non-vacuous witnesses at every UTF-8 width and scalar boundary. The byte-layer
implementation itself proves bounds safety, strict recursive progress, scalar
range safety, validation/model agreement, and the encoding/decoding formulas.

The cases deliberately contain no implementation details and no calls to the
library lemma bodies. They are an initial guard against sudden proof-complexity
growth as the model API evolves.

Run them together with the library proof using:

```sh
gnatprove -P unicode_text.gpr
```

The initial Milestone 1 run proves every scaling case with the project-wide
10,000-step limit. Numeric performance thresholds will be set only after the
API and toolchain reach a stable pilot, as specified in `design.md`.
