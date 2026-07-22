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

`Plain_String_Proofs` proves cursor counting, model-order iteration, equality
of active storage prefixes, and model concatenation after appending valid text
using only the public `Unicode_Text.UTF_8` specification. Its loop invariants
mention cursor positions and model indices, never UTF-8 continuation-byte
arithmetic. The active-prefix and append cases are the representative bounded
storage obligations required by Milestone 3.1.

`Bounded_String_Proofs` instantiates the Milestone 4 generic and proves an
append at exact byte capacity plus repeated scalar appends whose final model is
the expected scalar sequence. The instantiations also cause GNATprove to
analyze the complete generic implementation.

The cases deliberately contain no implementation details and no calls to the
library lemma bodies. They are an initial guard against sudden proof-complexity
growth as the model API evolves.

Run them together with the library proof using:

```sh
gnatprove -P unicode_text.gpr
```

The proof project uses all available provers with a 30-second per-attempt
timeout. Numeric performance thresholds will be set only after the API and
toolchain reach a stable pilot, as specified in `design.md`.
