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

## 1. Give tokens explicit semantics

`Symbol_Result` is already the working token abstraction: its `Match` case
carries explicit `Length` and `Distance`, and `Match_Applies` gives those
fields byte-level meaning.  The first length-three/four plan still makes that
representation manageable.  If broader matching makes invalid field
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

## 2. Describe decoding with a token trace

Several existing relations express variants of the same fact: a segment of
compressed bits produces a segment of output bytes.  Make that concept
explicit with a paired cursor:

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

`Step` parses one token, checks its semantic effect on `Data`, and advances
both cursor components.  `Trace` composes zero or more steps.

This one concept can subsume most of:

- `Spec_Matches`;
- `Prefix_Matches`;
- `One_Token_Matches`;
- the data-producing part of `Spec_Walk`;
- their separate extension, closing, framing, and functional lemmas.

In particular, the main decoder invariant becomes simply that the trace from
the initial cursor to the current cursor describes the output prefix produced
so far.  Functionality follows from the determinism of `Step`, rather than
from a separate recursive proof that repeats literal and match semantics.

The token sequence need not be materialized as a ghost array.  A cursor-based
inductive relation avoids adding a large bounded ghost buffer and works for an
arbitrary number of tokens within the existing input bound.

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

## 6. Express one compressor-image relation above block formats

At the gzip level, stored and fixed streams currently have separate member
predicates, decoder postconditions, framing lemmas, functionality lemmas, and
branches in `GZip_Round_Trip`.  Adding dynamic blocks in the same style would
introduce a third copy of that structure.

Introduce one semantic relation:

```ada
Body_Encodes (Body, Consumed, Data)
```

with common consequences:

- it is functional in `Data`;
- placing the body in a larger buffer preserves the relation;
- `Inflate.Raw.Decompress` accepts it when the output fits;
- its decoded length is `Data'Length`.

Stored, fixed, and dynamic encoders establish `Body_Encodes` locally.  Gzip
then lifts that single relation through its header, CRC-32, and length trailer.
The top-level round-trip theorem no longer needs to know which compression
strategy was selected.

An especially valuable consequence would be a single decoder-completeness
lemma for compressor images.  That would let the shipping raw decoder consume
the token trace directly and could remove the need for a separate specialized
fixed-image decoder proof.

## When to introduce the abstractions

Do not make all of these abstractions a prerequisite phase for the remaining
M6 work.  The fixed-Huffman compressor, now with boundary-based length-three
and length-four matches at distances one and three, is connected through
`Inflate.GZip.Compress`, the raw decoder's proved success path, and
`Inflate.Theorems.GZip_Round_Trip`.  The remaining work is to support more
lengths and wider distances, then add dynamic trees without breaking that
connection.

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
| `Trace_Cursor` and `Step`/`Trace` | After the fixed-Huffman matcher covers a materially broader range of lengths and distances.  Proceed only if the trace can delete `Spec_Matches`, `Prefix_Matches`, and `One_Token_Matches`, plus a meaningful part of `Spec_Walk`. |
| Append-only logical bitstream | During dynamic-Huffman work, if the concrete header and payload proofs multiply framing lemmas.  The working fixed writer alone does not justify this refactor. |
| Codebook abstraction | Just before integrating the dynamic payload, once the fixed and dynamic implementations provide two concrete instances from which to shape the interface. |
| `Body_Encodes` | After the dynamic body has a local encoding relation, but before wiring it into gzip and the round-trip theorem.  At that point it can replace stored/fixed/dynamic branches instead of wrapping only the current two. |

## Recommended M6 order

1. **Complete.** Keep the proved distance-3 extension as the stable baseline.  It establishes
   explicit match meaning in the existing representation without a parallel
   token model; the complete proof and runtime suites pass.
2. **Complete for the first variable-length slice.** The plan is boundary-only,
   and unaligned length-four distance-one runs retain the local M4
   back-reference witness.
3. Broaden the fixed selector beyond lengths three/four and distances one/three,
   then rerun the complete proof and runtime suites.  This establishes a
   materially general-LZ77 fixed-code baseline before another proof
   architecture change.
4. Reassess `Step`/`Trace` against that baseline.  Attempt it only with an
   explicit list of existing relations and lemmas that the new model will
   delete.
5. Implement and prove the dynamic tree builder locally, without immediately
   adding another top-level gzip branch.
6. Introduce the codebook boundary while sharing payload serialization between
   the fixed and dynamic implementations.  Introduce the append-only stream at
   this point only if actual framing duplication demonstrates its value.
7. Once the dynamic body relation is established, introduce `Body_Encodes` and
   use it to connect dynamic compression to gzip and the existing round-trip
   theorem.

This is feature-driven abstraction: establish a semantic seam before concrete
proof logic is duplicated, but generalize it only when the next feature gives
the abstraction at least two real cases.

Treat the next attempt as an A/B refactor with explicit acceptance criteria:

- one semantic relation replaces the existing specialized relations instead
  of being bridged to them;
- the proof code becomes smaller or removes substantial duplicated case
  analysis;
- the complete relevant GNATprove run passes with `-j` (for example `-j0`),
  not only focused subprogram runs;
- the existing build, round-trip tests, and compressor differential tests
  remain clean.

Until those conditions can be met, the existing specialized proof is simpler
and more trustworthy for the current compressor.
