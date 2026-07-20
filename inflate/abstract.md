# Proof Abstractions for M6

One possible long-term simplification is to stop proving a direct relationship
between input bytes and the final encoded bitstream at every layer.  A semantic
DEFLATE token stream could sit between them:

```text
Input bytes -> token selection -> [Literal | Match]*
                                      |
                              Huffman serialization
                                      |
                                  DEFLATE bits
```

The proof can then establish two largely independent properties:

1. Expanding the selected tokens reproduces the input.
2. Parsing the serialized bits recovers the same tokens.

This could separate LZ77 correctness from Huffman serialization and prevent
each new match shape or block format from being repeated throughout the proof.

## Experiment: explicit tokens in the fixed proof

This abstraction was tried as a local refactor of `Inflate.Fixed` and then
reverted.  The experiment introduced:

- a discriminated `Token` type for literals, matches, and end-of-block;
- a general `Matches` relation with explicit match length and distance;
- a `To_Token` conversion and `Lemma_Token_Meaning` bridge to the existing
  byte-level relation;
- a functional lemma for token expansion;
- token-based implementations of `Spec_Matches`, `Encoding_Matches`, the
  compressor-spec bridge, and `Lemma_Spec_Functional`.

The experiment had some positive results:

- the build and runtime tests still passed: 6,443 regular cases and 16
  compressor differential cases, with no failures;
- after refinement, focused level-4 proofs passed for `Lemma_Token_Meaning`,
  `Spec_Matches`, `Encoding_Matches`, `Lemma_Compressor_Spec`, and
  `Lemma_Spec_Functional`.

The overall result was negative for the current code, however:

- the refactor added 181 net lines to `inflate-fixed.adb`;
- the old byte-level relation remained necessary, so `To_Token` and
  `Lemma_Token_Meaning` added a second semantic layer and a proof bridge
  instead of replacing existing machinery;
- it did not simplify `Prefix_Matches`, `One_Token_Matches`, the decoder loop
  invariants, or the specialized fixed-image decoder;
- broad GNATprove runs did not close cleanly.  The full-project run proved
  4,259 of 4,265 checks, and a fixed-unit run proved 1,842 of 1,850 checks.
  The remaining results were time or memory limits rather than
  counterexamples, and the changed focused obligations were later proved, but
  these runs still do not establish that the refactor preserves overall proof
  performance.

The conclusion is to defer this abstraction.  It demonstrated that token
semantics can support the functional proof, but it did not yet remove enough
lower-level proof code to justify its size or proof-performance risk.

## Successful follow-up: enrich the existing symbol

The next experiment kept the existing proof structure and generalized it in
place instead of adding a parallel token layer.  It:

- added `Distance` to `Symbol_Result`, whose `Length` field was already
  present;
- introduced `Match_Applies` as the fixed-image spelling of the M4
  back-reference equation;
- replaced the repeated `(length = 3, distance = 1)` byte equations in the
  encoding relations, framing lemmas, functionality proof, and specialized
  decoder with that relation;
- extended the selector and fixed-code parser with a second concrete match,
  `(length = 3, distance = 3)`.

This smaller abstraction succeeded.  The complete level-4 project proof now
closes all 4,358 checks, while the debug suite passes 6,444 regular cases and
17 compressor differential cases.  The distance-3 compressor image is decoded
independently by C zlib in the new differential case.

At that point this was not yet a general LZ77 compressor: match length remained
fixed at three, distances were limited to one and three, and selection was tied
to aligned three-byte groups.  The important result was narrower: explicit
match semantics could replace specialized equations without introducing a
second representation or degrading the complete proof run.

## Successful next step: explicit boundaries and variable length

The compression plan is now explicit without adding a parallel token type.
`Selected_Token` chooses the existing `Symbol_Result`; `Next_Position` and
`Token_Bit_Cost` expose its cursor and encoding effects.  `Plan_Remaining`,
`Plan_Start`, and `Token_Boundary` describe the unique token partition with a
single forward recurrence, replacing `Match_Start`, `Match_Continuation`, and
all modulo-three reasoning.

That boundary made the first variable-length extension local.  At any reached
position, including unaligned byte position one, a four-byte continuation of a
single-byte run becomes `(length = 4, distance = 1)`.  The existing
length-three distance-one and distance-three choices remain fallbacks.  Each
selected match proves `Match_Applies`, and `Copy_Selected_Match` gives the
specialized decoder one local operation whose postcondition is that same M4
window equation for lengths three and four.

The focused fixed-code run proves all 1,920 checks at level 2.  The complete
level-4 library proof closes all 4,342 checks with no assumptions or
justifications, and the debug suite passes 6,444 regular cases plus 17
compressor differential cases.  The zero-run regression checks the exact
length-four/distance-one bits and C zlib independently decodes the result.

## Successful broader fixed-code baseline

The selector now searches distances one through four at every reached token
boundary and chooses the longest match of length three through ten, preferring
the smaller distance on a tie.  This rectangular domain is the useful first
general baseline: all its fixed literal/length and distance symbols need no
extra bits, so the payload format stays at twelve bits per match while the
finder exercises every overlap shape from period one through four.

`Matching_Length` proves the byte recurrence as it scans.  `Selected_Token`
exports that recurrence through `Match_Applies`, and the specialized decoder
now uses one forward-copy loop instead of separate distance-one and
distance-three implementations.  The token-boundary lemma was generalized to
all lengths in the domain and remains the sole bridge into the existing prefix
and framing relations.

The focused fixed-code run proves all 1,919 checks at level 2.  The complete
level-4 library proof closes all 4,341 checks with no assumptions or
justifications.  The debug suite passes 6,445 regular cases plus 18 compressor
differential cases; exact bit-level regressions exercise length-ten matches at
distances one, three, and four, and C zlib independently decodes every emitted
member.

## Bounded reassessment: retain the current trace proof

The planned `Step`/`Trace` reassessment is complete.  The broader fixed-code
baseline makes the proposed correspondence precise, but it does not expose a
profitable replacement boundary:

| Proposed concept | Existing proof it would replace | Reassessment |
|------------------|---------------------------------|--------------|
| `Step` | `One_Token_Matches` | The literal and match cases, cursor equations, and `Match_Applies` obligation are identical.  This is a rename, not a deletion of proof logic. |
| `Trace` | `Prefix_Matches` | The recursive cases and termination measure are identical.  The current data-frame, append, and extension lemmas would need trace-named equivalents. |
| A complete trace ending at end-of-block | `Spec_Matches` | It still needs the end-of-block and consumed-byte conditions, plus a closing lemma from the mutable decoder prefix.  The compressor, framing, and functionality proofs retain the same recursive cases. |

`Spec_Walk` also cannot be meaningfully absorbed by this trace.  The analyzer
uses it to validate token shape, distance bounds, termination, and decoded
length before an output slice exists.  In contrast, the proposed `Step`
requires a `Data` value to check literal values and `Match_Applies`.  Sharing
the recursion would therefore require either a ghost output value that the
analyzer does not have, or a second data-free structural trace plus a bridge
to the semantic trace.  Both add a layer without removing the analyzer's
existing proof.

The concrete deletion inventory consequently does not meet the acceptance
criterion.  The names `Spec_Matches`, `Prefix_Matches`, and
`One_Token_Matches` could disappear, but their definitions and the substance
of `Lemma_Compressor_Spec`, `Lemma_Spec_Frame`, `Lemma_Spec_Functional`,
`Lemma_Prefix_Data_Frame`, `Lemma_Prefix_Snoc`, `Lemma_Prefix_Extend`, and
`Lemma_Prefix_Close` would remain.  `Spec_Walk` and its iterative refinement
would remain as well.  No source refactor is justified at this boundary; the
current boundary proof is the stable baseline for dynamic-Huffman work.

## 1. Give tokens explicit semantics

`Symbol_Result` is already the working token abstraction: its `Match` case
carries explicit `Length` and `Distance`, and `Match_Applies` gives those
fields byte-level meaning.  The current length-three-through-ten and
distance-one-through-four domain still makes that representation manageable.
If broader matching makes invalid field
combinations burdensome, a discriminated token type could then look like this:

```ada
type Token_Kind is (Literal, Match, End_Of_Block);

type Token (Kind : Token_Kind) is record
   case Kind is
      when Literal =>
         Value : Byte;
      when Match =>
         Length   : Match_Length;
         Distance : Match_Distance;
      when End_Of_Block =>
         null;
   end case;
end record;
```

The semantic relation should continue to cover:

- a literal appends one byte;
- a match appends bytes satisfying `Inflate.Model.Copies_Match`;
- end-of-block appends nothing.

`Match_Applies` has replaced the repeated three-byte copy equations in
`Spec_Matches`, `Encoding_Matches`, `One_Token_Matches`, the functionality
proof, and the specialized decoder.  Before supporting general lengths and
distances, either share `Inflate.Model.Copies_Match` directly or prove one
small equivalence lemma between it and `Match_Applies`; both spell the same
window equation, including overlapping copies.

The central local theorem for a selected match should become:

```text
Selected match at Position
  => Copies_Match (Data, Position, Length, Distance)
```

That theorem is independent of how aggressively the match finder searches.

## 2. Deferred proposal: describe decoding with a token trace

If a later shared fixed/dynamic payload decoder creates a real deletion target,
the candidate abstraction remains a paired cursor:

```ada
type Trace_Cursor is record
   Bit_Position : Natural;
   Out_Position : Natural;
end record;
```

Define logical relations such as:

```ada
Step  (Stream, Data, From, To)
Trace (Stream, Data, From, To)
```

`Step` would parse one token, check its semantic effect on `Data`, and advance
both cursor components.  `Trace` would compose zero or more steps.  A useful
future version must share that semantics across concrete fixed and dynamic
payload paths and thereby delete their separate case analysis.  At the current
boundary, however, the main decoder's trace invariant would only be a new
spelling of `Prefix_Matches`, and functionality would still need the recursive
literal and overlapping-match argument recorded in the reassessment above.

The token sequence need not be materialized as a ghost array.  A cursor-based
inductive relation avoids adding a large bounded ghost buffer and works for an
arbitrary number of tokens within the existing input bound, if this proposal
later acquires a concrete deletion target.

## 3. Make the compression plan explicit

This step is now complete.  Selection and advancement are exposed directly:

```ada
Selected_Token (Data, Position)
Next_Position  (Data, Position)
Token_Bit_Cost (Data, Position)
```

`Plan_Remaining` advances one byte at a time and records how much of the current
token remains; `Plan_Start` recovers its start and `Token_Boundary` identifies
the positions the compressor visits.  The compressor loop now uses the
invariant:

```text
Position is a token boundary
and the selected tokens before Position expand to Data (0 .. Position - 1)
and the bits written so far serialize exactly those tokens.
```

This eliminated `Match_Continuation` and the modulo-three reasoning.
`Data_Bits` retains a value at intermediate byte counts only to support
prefix relations, but charges the token at its boundary.  Broadening the match
finder now changes `Selected_Token` and its soundness proof rather than the
shape of every relation over encoded bytes.

## 4. Reason about an append-only logical bitstream

The physical `Byte_Array` mutation currently requires snapshots and several
forms of "the earlier bits did not change" lemmas.  Hide that implementation
detail behind an append operation:

```ada
Append_Code (Buffer, Cursor, Code, Length)
```

Its contract should state that:

- the logical bit prefix is extended by exactly `Code`;
- the old prefix is preserved;
- the cursor advances by `Length`;
- bits outside the written interval are irrelevant to the logical stream.

Only `Append_Code` needs to refine this logical operation to writes in a byte
array.  The compressor loop can reason about an accumulating sequence of bits
instead of invoking `Lemma_Prefix_Frame`, `Lemma_Byte_Frame`,
`Lemma_Byte_Prefix_Frame`, and `Lemma_Encodes_Frame` after individual writes.

This also avoids relying on zero-initialized unwritten bits to establish the
end-of-block code: end-of-block can be appended like any other code.

## 5. Separate the codebook from token semantics

Fixed and dynamic Huffman should differ in how their codebook is obtained, not
in the payload proof.  Introduce a codebook concept exposing:

- `Code_Of (Symbol)`;
- `Length_Of (Symbol)`;
- a `Ready` or prefix-free validity predicate;
- `Decode (Encode (Symbol)) = Symbol`;
- sequence framing: concatenated symbol encodings decode in order.

The M3 spike's `Codebook`, `Ready`, `Code_Of`, and `Is_Encoding` are already a
useful model for this concept, although the abstraction need not reuse that
package directly.

The fixed encoder supplies a constant codebook.  The dynamic encoder proves
that the code-length header reconstructs a ready codebook.  The token payload
proof is then identical for both.  This keeps dynamic-header correctness
separate from literal/length and distance token semantics.

The encoder side of this boundary is now implemented.  `Inflate.Codebooks`
represents the two fixed assignments and canonical assignments behind `Ready`,
`Length_Of`, and `Code_Of`; `Inflate.Dynamic.Build_Codebook` turns the proved
bounded lengths into the canonical instance.  `Inflate.Payload.Serialize` owns
the single literal, length/distance, and end-of-block writer, with exact
bit-count, encoding, and frame contracts.  `Inflate.Fixed.Compress` delegates
to it and bridges the common relation to the existing fixed-image theorem,
while the dynamic runtime harness serializes the same token plan through
canonical books.  The local body step is now complete as well:
`Inflate.Dynamic.Serialize_Header` emits all literal/length and distance lengths
through a deliberately simple complete four-bit code-length alphabet, avoiding
repeat-code cases.  `Header_Encodes` records the exact reconstructed books, and
`Inflate.Dynamic.Is_Encoding` composes that header with the shared payload
relation.  The focused harness round trips the resulting body through the
shipping decoder and independent model, then C zlib decodes the same bytes.

## 6. Express one compressor-image relation above block formats

At the gzip level, stored and fixed streams had separate member predicates,
decoder postconditions, framing lemmas, functionality lemmas, and branches in
`GZip_Round_Trip`.  Adding dynamic blocks in the same style would have
introduced a third copy of that structure.

Introduce one semantic relation:

```ada
Body_Encodes (Body, Consumed, Data)
```

with common consequences for integrated alternatives, and the following target
for each new alternative:

- it is functional in `Data`;
- placing the body in a larger buffer preserves the relation;
- `Inflate.Raw.Decompress` accepts it when the output fits;
- its decoded length is `Data'Length`.

This boundary is now implemented in `Inflate.Bodies` for stored, fixed, and
dynamic semantic alternatives.  The selected stored/fixed encoders and the local
dynamic serializer each establish `Body_Encodes`; common framing and
functionality route all three alternatives without exposing a format branch to
`Inflate.Raw`, `Inflate.GZip`, or `Inflate.Theorems`.  The common relation
remains proof-only, while the precise dynamic decoded-body alternative is
executable.  Runtime compressor validation also invokes the executable full
DEFLATE model.  The separate gzip member predicates and both selected-format
branches in `GZip_Round_Trip` remain gone.

The dynamic introduction remains local, but its witness-erasure prerequisite
is complete.  `Literal_Book_From_Header` and `Distance_Book_From_Header`
deterministically rebuild the exact canonical records carried by the header,
and `Lemma_Encoding_Uses_Header_Books` lifts the explicit-book serializer
relation to `Inflate.Dynamic.Is_Encoding (Body, Consumed, Data)`.  The next step
has now closed its framing consequence: `Inflate.Payload.Lemma_Payload_Frame`
preserves the shared payload bits across arrays of different lengths, and
`Inflate.Dynamic.Lemma_Encoding_Frame` combines that with header recovery to
preserve the witness-free relation when a container adds trailing bytes.
`Inflate.Dynamic.Lemma_Encoding_Functional` now proves the other local
consequence by combining canonical prefix separation and rank uniqueness with
the existing LZ77 window equation. `Inflate.Dynamic.Analyze` recovers the
serialized canonical books and walks the bounded literal/match payload without
an output witness. `Encoding_Matches` checks the actual decoded token semantics,
and the broader executable `Dynamic.Decodes` relation records those semantics
with exact input and output sizes without claiming the deterministic serializer
plan. `Dynamic.Decompress` constructs the output and proves that relation for
every accepted bounded stream whose output fits. Serializer images map into it,
and its framing and functionality lemmas carry it through `Body_Encodes`. The
executable common recognition and size queries, raw success contract, and model
agreement now cover dynamic input as well as stored and fixed input.

This completes the dynamic decoder-completeness consequence at the common
boundary. Separate specialized fixed and dynamic decoders remain useful local
proof paths beneath that shared contract.

## When to introduce the abstractions

Do not make all of these abstractions a prerequisite phase for the remaining
M6 work.  The fixed-Huffman compressor, now with boundary-based longest
matches of length three through ten at distances one through four, is connected
through `Inflate.GZip.Compress`, the raw decoder's proved success path, and
`Inflate.Theorems.GZip_Round_Trip`.  The remaining work is to support more
lengths and wider distances, then emit dynamic blocks without breaking that
connection.  The broader fixed-code baseline, bounded `Step`/`Trace`
reassessment, dynamic header/body serializer, and common semantic body
boundary and the dynamic witness-erasure, framing, functionality, decoder, and
executable-recognition proofs are now complete. The next work is selection of
the dynamic body from gzip.

Introducing abstractions before features can prevent duplication, but proof
abstractions also introduce quantified relations, conversion theorems, and
additional solver boundaries.  They should therefore be introduced just in
time: after a concrete feature exposes the semantic boundary, but before that
feature's proof is copied into several layers.

M4's `Inflate.LZ77.Copy_Match` is the positive example.  It factored three
concrete shipping copy paths into one proved primitive and replaced their
implementations.  The explicit-token experiment is the negative example: it
wrapped a working specialized relation without removing it.

| Abstraction | Best time to attempt it |
|-------------|-------------------------|
| Explicit token semantics | Started successfully: `Symbol_Result` now carries length and distance, and `Match_Applies` replaced the `(3, 1)` equations.  Extend this representation in place; add another token type only if it can replace it. |
| Explicit compression plan | Complete: `Selected_Token`, `Next_Position`, `Token_Bit_Cost`, and the forward boundary state replaced the modulo-three plan before the first variable-length token landed. |
| `Trace_Cursor` and `Step`/`Trace` | Reassessed and deferred.  At the current boundary they rename `One_Token_Matches` and `Prefix_Matches` but cannot replace the data-free `Spec_Walk`; the associated framing, closing, and functionality proofs would remain.  Revisit only if a later shared payload decoder provides a concrete deletion target. |
| Append-only logical bitstream | Deferred.  The shared concrete payload writer closed with one framing proof, so no duplicated header/payload framing logic currently justifies another stream representation.  Revisit if dynamic-header serialization changes that evidence. |
| Codebook abstraction | Complete: `Inflate.Codebooks` supplies fixed and canonical instances, and `Inflate.Payload.Serialize` uses only their common ready/length/code interface. |
| `Body_Encodes` | Landed for stored/fixed at the intended just-in-time point and now admits the dynamic semantic relation as well. Common dynamic introduction, framing, cross-format disjointness, functionality, executable recognition, exact sizes, and decode success are complete. The next consumer is gzip selection. |

## Recommended M6 order

1. **Complete.** Keep the proved distance-3 extension as the stable baseline.  It establishes
   explicit match meaning in the existing representation without a parallel
   token model; the complete proof and runtime suites pass.
2. **Complete for the first variable-length slice.** The plan is boundary-only,
   and unaligned length-four distance-one runs retain the local M4
   back-reference witness.
3. **Complete.** The fixed selector now chooses the longest length-three
   through length-ten match over distances one through four; the complete
   proof and runtime suites pass.
4. **Complete: retain the current proof.** `Step`/`Trace` would rename the
   specialized relations while leaving their proof logic and the data-free
   analyzer recursion in place, so the attempted refactor's entry criterion
   was not met.
5. **Complete.** `Inflate.Dynamic.Build_Lengths` now constructs a balanced
   complete code locally for every DEFLATE-sized alphabet, with used-symbol
   coverage, a proved length bound of nine, exact Kraft equality, and no
   optimality claim or top-level gzip branch.
6. **Complete.** `Inflate.Codebooks` separates fixed and canonical code
   assignments, and `Inflate.Payload.Serialize` replaces the fixed writer while
   also serving the dynamic codebook adapter.  Actual framing duplication did
   not justify an append-only logical-stream layer.
7. **Complete.** The dynamic header serializes complete canonical books without
   RLE, and the local dynamic-body relation composes it with the shared payload
   without widening the gzip branch.
8. **Complete.** `Body_Encodes` admits stored, fixed, and dynamic relations and
   routes common framing, functionality, executable recognition, exact sizes,
   and raw decode success. The dynamic decoded-body relation is broader than
   the deterministic serializer image but checks actual token semantics. The
   next step is to select the body from gzip without reintroducing a format
   branch above the boundary.

This is feature-driven abstraction: establish a semantic seam before concrete
proof logic is duplicated, but generalize it only when the next feature gives
the abstraction at least two real cases.

Treat any future attempt as an A/B refactor with explicit acceptance criteria:

- one semantic relation replaces the existing specialized relations instead
  of being bridged to them;
- the proof code becomes smaller or removes substantial duplicated case
  analysis;
- the complete relevant GNATprove run passes with `-j` (for example `-j0`),
  not only focused subprogram runs;
- the existing build, round-trip tests, and compressor differential tests
  remain clean.

`Body_Encodes` met these conditions for the integrated stored/fixed proof and
the dynamic alternative reuses its framing and functionality cases.  Use the
same test for any later abstraction; retain a specialized local relation when
it cannot delete proof above its own layer.
