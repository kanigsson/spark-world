# Unicode Text Library Design

Status: Milestone 1 complete

This document defines a proposed SPARK-compatible string library whose only
concrete encoding is UTF-8. The library is intended to support ordinary Ada
`String` values, fixed-capacity bounded strings, safe read-only views, and
possibly an owning resizable representation later. All representations share
one mathematical model: a finite sequence of Unicode scalar values.

The provisional library and root package name is `Unicode_Text`. The project
directory is named `unicode_text`.

## 1. Goals

The library shall:

- Represent text exclusively as well-formed UTF-8.
- Offer useful operations directly on ordinary Ada `String` values.
- Offer a fixed-capacity bounded representation with no dynamic allocation.
- Give every representation the same code-point-sequence model.
- Specify operations in a way that is useful to clients of GNATprove, not only
  sufficient to prove the library body.
- Distinguish byte positions, code-point indices, and abstract text clearly.
- Reject malformed UTF-8 rather than silently replacing malformed input.
- Allow zero bytes as ordinary encoded U+0000 values.
- Preserve arbitrary lower bounds on input Ada strings semantically: the lower
  bound is not part of the text model.
- Avoid requiring clients to reason about UTF-8 continuation bytes when proving
  ordinary properties of concatenation, slicing, searching, or splitting.
- Support efficient byte-oriented implementations where UTF-8 canonicality
  makes them equivalent to code-point operations.
- Provide measurable proof-performance and runtime-performance criteria.

## 2. Non-goals for the initial library

The initial library will not provide:

- Multiple encodings or an encoding-selection abstraction.
- Implicit repair of malformed UTF-8 using U+FFFD.
- Locale-sensitive collation.
- Grapheme-cluster indexing as the fundamental string index.
- Unicode normalization as part of equality.
- Case-insensitive equality as part of ordinary equality.
- Escaping mutable access to the internal buffer of a bounded string.
- An owning, dynamically resizing string until the bounded and borrowed forms
  have demonstrated adequate proof usability.

Normalization, case mapping, character properties, grapheme segmentation, and
collation depend on a particular Unicode data version. They belong in explicit,
versioned child packages rather than in the foundational UTF-8 abstraction.

## 3. Terminology

A Unicode code point is an integer in `U+0000 .. U+10FFFF`. The surrogate
range `U+D800 .. U+DFFF` consists of code points but not Unicode scalar values.
UTF-8 encodes Unicode scalar values, so the text model contains scalar values,
not arbitrary code points.

An octet is an integer in `0 .. 255`. Each Ada `Character` in a concrete UTF-8
string is interpreted as an octet through `Character'Pos`; its Ada or Latin-1
character interpretation is irrelevant.

A byte offset denotes a gap between bytes and is naturally zero based. For a
string of byte length `N`, valid offsets range from `0` through `N`.

A code-point index identifies a model element and is one based. For a nonempty
model of length `N`, valid indices range from `1` through `N`.

## 4. Package organization

The provisional hierarchy is:

```ada
Unicode_Text
Unicode_Text.Models
Unicode_Text.UTF_8
Unicode_Text.Bounded
Unicode_Text.Search
Unicode_Text.Views
```

The exact split may change during implementation, but the conceptual ownership
is as follows:

- `Unicode_Text` defines scalar values and common public terminology.
- `Unicode_Text.Models` defines the ghost text model and model relations.
- `Unicode_Text.UTF_8` validates, decodes, encodes, and operates on Ada strings.
- `Unicode_Text.Bounded` provides generic fixed-byte-capacity strings.
- `Unicode_Text.Search` provides character and substring search operations if
  keeping them out of the root improves readability.
- `Unicode_Text.Views` provides spans and, later, scoped borrowed views.

Because UTF-8 is the only concrete encoding, plain-string operations may
eventually move into the root package. The hierarchy must not imply that other
encodings will necessarily be added.

## 5. Unicode scalar values

The foundational scalar declarations are:

```ada
type Code_Point is range 0 .. 16#10_FFFF#;

subtype Scalar_Value is Code_Point
with Static_Predicate =>
  Scalar_Value in
    16#0000# .. 16#D7FF#
  | 16#E000# .. 16#10_FFFF#;
```

Keeping both names makes the surrogate exclusion explicit. All decoded values,
model elements, and encoding inputs use `Scalar_Value`.

This definition is independent of a Unicode data version. The set of Unicode
scalar values is stable even though assigned characters and their properties
change between Unicode releases.

## 6. Common mathematical text model

The common model is an unbounded finite functional sequence of scalar values:

```ada
package Scalar_Sequences is new
  SPARK.Containers.Functional.Infinite_Sequences
    (Element_Type         => Scalar_Value,
     Use_Logical_Equality => True);

subtype Text is Scalar_Sequences.Sequence;
```

`Text` is intended for ghost code and contracts, not runtime storage. Its
fundamental operations are:

```ada
Length (T) : Big_Natural
Get (T, I) : Scalar_Value
First      = 1
Last (T)   = Length (T)
```

The model is always finite, even though its indices and length are mathematical
integers. The word `Infinite` in the instantiated container name refers to the
unbounded mathematical index domain, not to infinite text values.

Equality is extensional:

```text
X = Y
  iff
Length(X) = Length(Y)
  and
for every I in 1 .. Length(X), X[I] = Y[I].
```

The common model deliberately contains none of the following:

- an Ada array lower bound;
- an encoded byte length;
- a storage capacity;
- a normalization form;
- an allocator or ownership state;
- a cached hash or cached code-point count.

## 7. Exact relationship between Ada strings and the model

For an Ada `String` value `S`, define its one-based octet sequence by:

```text
Octets(S)[I] = Character'Pos(S(S'First + I - 1))
```

for `1 <= I <= S'Length`.

Consequences include:

- `S'Length` is the encoded byte length.
- `S'First` is not part of the model.
- Equal byte sequences with different Ada bounds have equal text models.
- `Character'Val(0)` is valid and represents U+0000.
- No terminating zero is implied or added.

### 7.1 Canonical encoding of one scalar value

For a scalar value `C`, `Encode_One(C)` is defined as follows. Arithmetic is
integer arithmetic and each displayed result is an octet.

```text
C <= 16#007F#:
  [C]

C <= 16#07FF#:
  [16#C0# + C / 64,
   16#80# + C mod 64]

C <= 16#FFFF#:
  [16#E0# + C / 4096,
   16#80# + (C / 64) mod 64,
   16#80# + C mod 64]

otherwise:
  [16#F0# + C / 262144,
   16#80# + (C / 4096) mod 64,
   16#80# + (C / 64) mod 64,
   16#80# + C mod 64]
```

The third case never encodes a surrogate because `C` is a `Scalar_Value`.

For a text model `[C1, ..., Cn]`, encoding is pointwise concatenation:

```text
Encode([C1, ..., Cn]) =
  Encode_One(C1) & ... & Encode_One(Cn).
```

The encoding of the empty model is the empty octet sequence.

### 7.2 Validity and model definition

UTF-8 validity is defined mathematically by:

```text
Is_Valid_UTF_8(S)
  iff
there exists T : Text such that Octets(S) = Encode(T).
```

For a valid string, its model is:

```text
Model(S) =
  the unique T such that Octets(S) = Encode(T).
```

Canonical UTF-8 encoding makes this text model unique.

The Ada-facing declarations have the following shape:

```ada
function Is_Valid_UTF_8 (S : String) return Boolean;

function Model (S : String) return Text
with
  Ghost,
  Pre => Is_Valid_UTF_8 (S);
```

`Model` is deliberately partial through its precondition. Malformed input has
no arbitrary or replacement-character model. A lossy repair operation, if one
is ever added, will have a separate explicit name and model.

### 7.3 Executable validation classes

The executable validator accepts precisely the following forms:

| Width | First octet | Second octet | Third octet | Fourth octet |
|---|---|---|---|---|
| 1 | `00 .. 7F` | - | - | - |
| 2 | `C2 .. DF` | `80 .. BF` | - | - |
| 3 | `E0` | `A0 .. BF` | `80 .. BF` | - |
| 3 | `E1 .. EC`, `EE .. EF` | `80 .. BF` | `80 .. BF` | - |
| 3 | `ED` | `80 .. 9F` | `80 .. BF` | - |
| 4 | `F0` | `90 .. BF` | `80 .. BF` | `80 .. BF` |
| 4 | `F1 .. F3` | `80 .. BF` | `80 .. BF` | `80 .. BF` |
| 4 | `F4` | `80 .. 8F` | `80 .. BF` | `80 .. BF` |

All other forms are invalid. In particular, the validator rejects:

- isolated continuation octets;
- truncated encodings;
- `C0` and `C1`;
- all other overlong encodings;
- UTF-8 encodings of surrogates;
- encodings greater than U+10FFFF;
- `F5 .. FF`.

The internal decoder should expose a single-step result:

```ada
type Encoded_Width is range 1 .. 4;

type Decoded_Unit is record
   Value : Scalar_Value;
   Width : Encoded_Width;
end record;

function Valid_At
  (S : String; Byte_Position : Positive) return Boolean;

function Decode_One
  (S : String; Byte_Position : Positive) return Decoded_Unit
with Pre => Valid_At (S, Byte_Position);
```

The validator and ghost `Model` function must share the same byte
classification rules. The foundational bridge theorem is:

```text
Is_Valid_UTF_8(S)
  implies
Octets(S) = Encode(Model(S)).
```

## 8. Model relations used in contracts

Contracts should generally use extensional property relations rather than build
large functional sequences. This keeps quantifier structure visible and avoids
unnecessary model construction.

### 8.1 Concatenation

`Is_Concatenation(Left, Right, Result)` means:

```text
Length(Result) = Length(Left) + Length(Right)

and for every I in 1 .. Length(Left):
  Result[I] = Left[I]

and for every J in 1 .. Length(Right):
  Result[Length(Left) + J] = Right[J].
```

### 8.2 Append

`Is_Append(Before, Value, After)` means:

```text
Length(After) = Length(Before) + 1

and Before is a prefix of After

and After[Length(After)] = Value.
```

### 8.3 Slice

Slices use a one-based first code-point index and a count:

```text
Is_Slice(Source, First, Count, Result)
```

means:

```text
1 <= First <= Length(Source) + 1
0 <= Count <= Length(Source) - (First - 1)
Length(Result) = Count

and for every I in 1 .. Count:
  Result[I] = Source[First + I - 1].
```

This definition represents an empty suffix using
`First = Length(Source) + 1` and `Count = 0` without inventing a zero
code-point index.

### 8.4 Prefix, suffix, and containment

Prefix and suffix relations compare model elements, not bytes. Containment says
that the needle model is a slice of the haystack model at some valid starting
position. Search operations refine containment with a returned position and,
for ordinary `Find`, first-occurrence minimality.

## 9. Plain Ada string API

The initial plain-string API should provide:

```ada
function Is_Valid_UTF_8 (S : String) return Boolean;
function Validate (S : String) return Validation_Result;

function Byte_Length (S : String) return Natural;

function Code_Point_Length (S : String) return Natural
with
  Pre => Is_Valid_UTF_8 (S),
  Post =>
    To_Big_Integer (Code_Point_Length'Result)
      = Length (Model (S));

function Element
  (S : String; Index : Positive) return Scalar_Value
with
  Pre =>
    Is_Valid_UTF_8 (S)
    and then Index <= Code_Point_Length (S);
```

Useful proved bounds are:

```text
Code_Point_Length(S) <= S'Length

S'Length <= 4 * Code_Point_Length(S)
```

for valid nonempty strings, with both lengths zero for the empty string.

For valid strings, Ada byte equality and model equality coincide:

```text
Left = Right
  iff
Model(Left) = Model(Right).
```

This is a consequence of canonical encoding. Ada array lower bounds do not
affect array equality or the text model.

## 10. Iteration and cursors

Repeated `Element(S, I)` calls may repeatedly scan from the beginning, making a
client loop quadratic. The library therefore needs a forward decoder cursor.

A cursor records at least:

- the byte offset of the next scalar value;
- the one-based model index of the next scalar value;
- whether the cursor is at the end.

The source string should normally remain an explicit parameter:

```ada
procedure Next
  (S      : String;
   Cursor : in out Cursor_Type;
   Value  : out Scalar_Value)
with
  Pre  => Is_Valid_UTF_8 (S) and then Has_Element (S, Cursor),
  Post => Value = Get (Model (S), Model_Index (Cursor'Old));
```

Additional postconditions specify advancement by one model element, advancement
by the encoded width in bytes, and strict progress. This makes loop termination
and one-visit-per-code-point proofs straightforward.

Reverse iteration may be added later. UTF-8 permits finding the preceding
leading octet by scanning backward over at most three continuation octets.

## 11. Byte spans and slicing

A byte span represents a half-open range of a separate source string:

```ada
type Byte_Span is record
   First     : Natural;
   Past_Last : Natural;
end record;
```

For source `S`, a valid span satisfies:

```text
First <= Past_Last <= S'Length
First is a UTF-8 boundary in S
Past_Last is a UTF-8 boundary in S.
```

Offsets are relative to `S'First`, not absolute Ada indices. A span owns no
storage and contains no access value. It can therefore be returned by search
and split operations without allocation or ownership complications.

The high-level slicing operation uses code-point coordinates:

```ada
function Slice
  (S     : String;
   First : Positive;
   Count : Natural) return String
with
  Pre  =>
    Is_Valid_UTF_8 (S)
    and then First <= Code_Point_Length (S) + 1
    and then Count <= Code_Point_Length (S) - (First - 1),
  Post =>
    Is_Valid_UTF_8 (Slice'Result)
    and then Is_Slice
      (Model (S), First, Count, Model (Slice'Result));
```

A lower-level operation may map a code-point slice to a `Byte_Span`, allowing
clients to defer or avoid copying. Raw byte slicing requires boundary
preconditions on both endpoints.

## 12. Bounded strings

The bounded representation has fixed byte capacity:

```ada
generic
   Capacity : Natural;
package Unicode_Text.Bounded is

   type Bounded_String is private
   with Default_Initial_Condition => Is_Empty (Bounded_String);

private

   type Bounded_String is record
      Data : String (1 .. Capacity);
      Used : Natural range 0 .. Capacity := 0;
   end record;

end Unicode_Text.Bounded;
```

Its representation invariant is:

```text
Used <= Capacity

and the active prefix Data(1 .. Used) is valid UTF-8.
```

For `Used = 0`, the active prefix is the empty string. Unused bytes are not part
of the logical value. The model is exactly:

```text
Model(S) = Model(Active_Bytes(S)).
```

Bounded-string equality must compare active bytes or models, not the entire
record, because unused bytes have no semantic meaning.

Core operations include:

- empty construction;
- construction from a valid Ada string;
- conversion to an Ada string by copying;
- byte length and code-point length;
- append one scalar value;
- append a valid Ada string;
- append another bounded string;
- clear;
- element access and iteration;
- slice and search;
- equality, prefix, and suffix.

Append contracts have the following shape:

```ada
procedure Append
  (S : in out Bounded_String; C : Scalar_Value)
with
  Pre  => Byte_Length (S) + Encoded_Width (C) <= Capacity,
  Post => Is_Append (Model (S)'Old, C, Model (S));

procedure Append
  (S : in out Bounded_String; Other : String)
with
  Pre  =>
    Is_Valid_UTF_8 (Other)
    and then Byte_Length (S) + Other'Length <= Capacity,
  Post => Is_Concatenation
    (Model (S)'Old, Model (Other), Model (S));
```

Code-point length should not be cached initially. Caching adds a second mutable
representation invariant and should be justified by measured runtime evidence.

## 13. Access values and views

Named access helpers may be provided:

```ada
type String_Access is access all String;
type Constant_String_Access is access constant String;
```

Their model is simply `Model(P.all)`, subject to non-nullness and UTF-8 validity.
They do not create a new text representation.

The bounded representation must not return an escaping mutable access to its
internal `Data`, because a caller could invalidate UTF-8 or mutate bytes beyond
the library's contracts.

The first release should prefer:

- `To_String`, which returns a copy;
- byte spans referring to a separately supplied source;
- cursor operations that take the source as a parameter.

A zero-copy constant view can be added later using a scoped SPARK borrowing
pattern after its lifetime and mutation restrictions have been validated in
real client code.

## 14. Possible owned unbounded strings

An owning resizable representation can use the same model. Capacity and
allocation are representation details, and resizing has the simple abstract
contract:

```text
Model(S) = Model(S)'Old.
```

The difficult part is allocator ownership, alias exclusion, reclamation, and
the boundary around any operation not supported in SPARK. These difficulties
do not require a different text model. An owning representation should be
deferred until the bounded API and client proof suite are stable.

## 15. Operations

Operations are introduced in tiers. Advancement to the next tier requires both
implementation proof and client-side proof-performance evidence.

### 15.1 Foundation operations

- UTF-8 validity predicate.
- Validation with error information.
- Byte length.
- Code-point length.
- Encoded width of a scalar value.
- Decode one scalar value.
- Forward cursor and iteration.
- Element access by code-point index.
- Encode one scalar value.
- Model and byte/model bridge lemmas.

`Validation_Result` should distinguish success from failure and report at least
the first invalid byte offset. A detailed error kind may be useful but is not
required by the mathematical model.

### 15.2 Algebra operations

- Append one scalar value.
- Append valid text.
- Concatenate valid texts.
- Slice by code-point first index and count.
- Produce a byte span for a code-point slice.
- Equality.
- Prefix and suffix.
- Lexicographic comparison by scalar value.

Concatenation copies bytes directly. Concatenating complete valid UTF-8 strings
preserves validity. UTF-8 bytewise lexicographic order also preserves scalar
value order; this equivalence should be proved before using byte comparison to
implement the model-level ordering. This ordering is not locale collation.

### 15.3 Search operations

The initial search API should include:

```ada
function Find
  (S     : String;
   Value : Scalar_Value;
   From  : Positive := 1) return Natural;

function Reverse_Find
  (S     : String;
   Value : Scalar_Value) return Natural;

function Find
  (Haystack : String;
   Needle   : String;
   From     : Positive := 1) return Natural;

function Contains
  (Haystack : String;
   Needle   : String) return Boolean;
```

Search results are one-based code-point indices. Zero means not found.

Character search establishes:

```text
Result = 0
  iff no eligible model element equals Value.

Result > 0
  implies Model(S)[Result] = Value.

Result > 0
  implies no earlier eligible position contains Value.
```

Substring search establishes:

```text
Result > 0
  implies the needle model is the corresponding haystack model slice.

Result = 0
  iff no eligible starting position has that slice.

Result > 0
  implies no earlier eligible position matches.
```

Empty-needle semantics are explicit:

```text
Find(Haystack, "") = 1
```

For a search beginning at `From`, an empty needle is found at `From`, provided
`From` is a valid boundary position in `1 .. Length(Haystack) + 1`.

Valid UTF-8 permits byte-oriented substring search. The first byte of a
nonempty valid needle is never a continuation byte, so a byte match cannot
start inside a multibyte scalar value. Canonical encoding then gives:

```text
Octets(Needle) occurs in Octets(Haystack)
  iff
Model(Needle) occurs in Model(Haystack).
```

This bridge should be proved once. The first implementation can use a simple
byte search; a linear-time algorithm can replace it later without changing the
public contract.

### 15.4 Split operations

Split should initially be an iterator returning byte spans rather than an
allocated unbounded vector of strings:

```ada
procedure Next
  (Source    : String;
   Separator : String;
   State     : in out Split_State;
   Segment   : out Byte_Span;
   Has_Value : out Boolean);
```

The separator must be valid UTF-8 and nonempty. Semantics are:

- matches are non-overlapping;
- leading separators produce an initial empty segment;
- trailing separators produce a final empty segment;
- adjacent separators produce empty segments;
- joining all segments with the separator reconstructs the source;
- no returned segment contains the separator.

A scalar-value delimiter specialization should also be provided. It has a
simpler implementation and proof and covers a common use case.

The reconstruction property is a key validation target for both specification
quality and client proof performance.

### 15.5 Deferred transformations

The following should be added only after the previous operations have stable
proof and runtime baselines:

- `Replace_First` and `Replace_All`;
- insertion and deletion;
- join over a caller-supplied collection or iterator;
- substring occurrence counts with explicitly chosen overlapping semantics;
- reverse iteration;
- trimming;
- normalization;
- case conversion and case-insensitive matching;
- grapheme-cluster iteration;
- Unicode property lookup;
- locale-sensitive collation.

Empty patterns, overlapping matches, and Unicode-version dependencies must be
specified before these operations enter the public API.

## 16. Proof architecture

### 16.1 Separate byte validity from text reasoning

The byte layer proves that validation and decoding establish the model. Client
operations then reason over `Text`. Proofs of concatenation, slicing, search,
and split should not repeatedly expose UTF-8 bit arithmetic.

The intended dependency is:

```text
UTF-8 bytes
  -> validator and decoder proofs
  -> Model bridge
  -> text algebra
  -> client contracts and proofs.
```

### 16.2 Public model relations

Public contracts should use focused relations such as `Is_Append`,
`Is_Concatenation`, `Is_Slice`, and range equality. These relations make
quantifier bounds and triggers more predictable than nested model construction.

Automatic lemmas should be introduced sparingly. A globally automatic lemma
that helps one client but creates many irrelevant instantiations elsewhere is a
proof-performance defect.

### 16.3 Implementation proofs versus client proofs

Two distinct suites are required:

- implementation proofs establish that each body satisfies its contract;
- client proofs establish that those contracts are usable without seeing the
  representation or decoder bodies.

Passing the implementation proof suite alone does not validate the library.

### 16.4 SMT-string lowering

The initial public model remains the functional scalar sequence. Vendored Why3
already supports native SMT string operations such as concatenation, length,
substring, and search, but its string indexing and element interface do not
directly match the one-based scalar-value model.

Later, `gnat2why` may recognize `Unicode_Text.Models` operations and lower some
of them to SMT strings. Such lowering is an optimization behind the same public
contracts. It must be evaluated with the client proof suite rather than assumed
to be faster merely because the solver has a native string theory.

## 17. Validation strategy

Validation has four independent dimensions:

1. UTF-8 conformance and runtime functional behavior.
2. Proof of the implementation.
3. Client provability and proof performance.
4. Runtime performance and scaling.

### 17.1 UTF-8 conformance tests

The runtime test suite includes at least:

- boundary scalar values U+0000, U+007F, U+0080, U+07FF, U+0800,
  U+D7FF, U+E000, U+FFFF, U+10000, and U+10FFFF;
- all malformed leading-octet classes;
- isolated continuation octets;
- truncation after every position of 2-, 3-, and 4-octet encodings;
- overlong encodings;
- encodings of surrogates;
- values greater than U+10FFFF;
- embedded zero octets;
- arbitrary Ada string lower bounds;
- empty strings and empty slices;
- bounded capacities exactly equal to, one less than, and one greater than the
  required encoded size;
- leading, trailing, adjacent, missing, and repeated split delimiters.

It is practical to exhaustively test:

```text
Decode(Encode(C)) = C
```

for every Unicode scalar value. Generated and randomized valid scalar sequences
should additionally test:

```text
Encode(Model(S)) = Octets(S)
Model(Encode(T)) = T.
```

Known independent encoding and decoding examples are necessary in addition to
round trips, so an implementation cannot pass by making two mutually incorrect
operations agree.

A vendored, version-identified external UTF-8 conformance corpus may supplement
the systematic local cases.

### 17.2 Internal proof suite

All library bodies must prove:

- absence of run-time errors;
- bounds safety for every lookahead;
- termination and strict cursor progress;
- every decoded value is a scalar value;
- every accepted byte sequence has the declared model;
- encode/decode inverse properties;
- validity preservation by concatenation and mutation;
- model preservation or transformation according to each contract;
- capacity preservation for bounded strings;
- independence from unused bounded storage;
- byte/model equivalences used by equality, ordering, and search.

The core accepts no `Assume` and no justification that suppresses a real proof
obligation. Exceptional low-level boundaries, if eventually necessary, must be
small, explicit, and separately justified and tested.

### 17.3 Client provability suite

Client cases import the public library specification and do not know the
representation. At least the following clients are required:

1. Validate and iterate over an arbitrary string, proving exactly one visit per
   model element.
2. Append arbitrary scalar values to a bounded string, proving that the final
   model is the appended input sequence.
3. Concatenate three strings and prove model associativity.
4. Slice a string into adjacent parts and prove recomposition.
5. Find a scalar value and prove the returned position is its first occurrence.
6. Find a substring and prove positive, negative, and empty-needle cases.
7. Split by a scalar value and prove reconstruction.
8. Split by a substring and prove reconstruction and delimiter absence.
9. Copy among ordinary strings with different lower bounds and bounded strings,
   proving model equality.
10. Implement a small tokenizer or word counter using only public cursors and
    spans.

The client suite is successful only when loop invariants refer to model
positions, spans, and sequence relations. A client should not need continuation
octet arithmetic to prove ordinary text behavior.

Library-provided focused lemma calls are acceptable. Client-specific axioms or
large collections of ad hoc lemmas indicate an inadequate public proof API.

### 17.4 Anti-vacuity validation

The proof suite must demonstrate that important preconditions are satisfiable:

- construct nonempty multibyte strings;
- exercise all encoded widths;
- reach both successful and unsuccessful search branches;
- produce empty and nonempty split segments;
- append at exact bounded capacity;
- establish boundary conditions for empty slices.

During development, deliberately false assertions and weakened loop invariants
should be checked to confirm that expected failures are detected. Negative
tests need not all remain in the ordinary regression suite, but the suite must
not rely solely on vacuous implications or circular round trips.

## 18. Proof-performance validation

### 18.1 Ordinary regression tests

The ordinary testsuite records whether every expected check is proved under:

- fixed prover versions;
- an explicit bounded solver-step limit;
- a modest timeout;
- a fixed proof mode and proof level;
- clean proof artifacts where cache behavior could affect the result.

Any previously proved client check becoming unproved is a hard regression.
Ordinary tests should avoid strict wall-clock thresholds because shared CI
timing is noisy. Solver-step limits and proof status are the primary stable
guards.

Feature-focused client tests may pin a primary prover. A secondary-prover run
should periodically ensure that contracts have not accidentally become tied to
one solver's behavior. Ordinary correctness tests need not report which prover
won unless prover capability is the point of the test.

### 18.2 Scheduled performance suite

A scheduled or dedicated proof-performance run records, per VC where available:

- proved or unproved status;
- prover name and version;
- solver steps;
- solver time;
- maximum and total steps;
- maximum and total solver time;
- peak memory;
- generated task size;
- total wall time for each client case;
- relevant generated `.spark` proof metadata.

Runs use a fixed machine class, fixed parallelism, fresh proof/session
directories, and repeated measurements. Medians and a high percentile are
reported instead of relying on a single wall-clock observation.

Initial numeric thresholds are established from the first stable pilot rather
than invented in advance. The policy is:

- loss of a previously proved VC is a failure;
- a material increase in maximum or total solver steps requires review;
- a sustained increase in repeated wall-time or memory measurements requires
  review;
- common client examples must remain within ordinary proof settings rather
  than requiring exceptional timeouts or step limits.

### 18.3 Proof-scaling cases

Fixed generated source variants exercise:

- 1, 2, 4, 8, and 16 chained concatenations;
- nested slice and recomposition expressions;
- repeated prefix and substring checks;
- 1, 2, 4, and 8 split iterations;
- combinations such as slicing a concatenation;
- bounded capacities of materially different sizes;
- ASCII-only, mixed-width, and four-octet client examples.

Proof complexity for a loop over an arbitrary runtime string should be largely
independent of the runtime string length. Statically chained model expressions
should show smooth scaling rather than sudden exponential behavior.

### 18.4 Specification experiments

The same client suite is used to compare:

- functional construction versus relational predicates;
- general quantifiers versus focused range and prefix relations;
- automatic versus explicit lemma instantiation;
- byte-oriented search with a bridge theorem versus decoded search;
- functional sequence models versus future native SMT-string lowering.

The selected design is the one that gives stable, understandable client proofs,
not merely the shortest specification or fastest proof of the library body.

## 19. Runtime-performance validation

Runtime benchmarks are separate from proof benchmarks. They cover:

- validation throughput;
- code-point counting;
- forward iteration;
- scalar search;
- substring search;
- concatenation and bounded append;
- code-point-to-byte-span conversion;
- split iteration.

Inputs include:

- empty and tiny strings;
- ASCII-only strings;
- two-, three-, and four-octet scalar values;
- mixed realistic text;
- malformed input failing near the start, middle, and end;
- repeated-prefix adversarial inputs for substring search;
- sizes from a few bytes through large buffers.

The initial targets are:

- validation, counting, and iteration linear in byte length;
- no allocation for validation, iteration, scalar search, or split iteration;
- bounded operations allocate no dynamic memory;
- code-point slice discovery linear in the bytes traversed;
- substring search behavior measured explicitly before choosing whether a
  linear-time implementation is required.

Proof-friendly simplicity is preferred initially, but an unexpectedly poor
runtime result must be visible rather than hidden behind proof success.

## 20. Versioning and compatibility

The library uses Semantic Versioning. `VERSION` contains the version of the
current source tree, and release tags have the form `vMAJOR.MINOR.PATCH`.
`CHANGELOG.md` records the user-visible changes in each release.

Before `1.0.0`, the public Ada API and its contracts are still experimental:

- `MINOR` is incremented for a change that can require a client source or
  proof change, and for a milestone-sized addition to the public API.
- `PATCH` is incremented for backward-compatible corrections, proof or
  performance improvements, and documentation changes.
- Development and release-candidate snapshots may use SemVer pre-release
  suffixes such as `-dev.1` and `-rc.1`.

`1.0.0` marks the first stable API after the release criteria below have been
met. From that point, incompatible public API or contract changes increment
`MAJOR`, backward-compatible additions increment `MINOR`, and compatible fixes
increment `PATCH`.

The library version is distinct from a Unicode data version. The foundational
scalar and UTF-8 packages do not depend on Unicode character-property data.
Any later package that does depend on such data exposes that data version
separately; changing it still affects the library version according to the
compatibility rules above.

Milestones describe implementation scope, not an independent version number.
Completion of Milestone 1 establishes version `0.1.0`; later release numbers
are chosen from their compatibility impact rather than copied mechanically
from the milestone number.

## 21. Stable release criteria

A `1.0.0` release requires:

- the scalar-value and common text model packages;
- plain-string validation and model mapping;
- forward iteration;
- bounded strings;
- append, concatenation, slicing, equality, prefix, and suffix;
- scalar search and substring search;
- split by a scalar value;
- complete internal proofs;
- exhaustive single-scalar encode/decode testing;
- systematic malformed-input testing;
- successful public-client provability cases within fixed step budgets;
- runtime evidence for linear scans and allocation-free bounded operations;
- no decoder details in ordinary client invariants.

Substring split is the final candidate validation feature before describing the
library as broadly useful. It composes validation, search, spans, cursor
progress, empty-segment behavior, and reconstruction. If its clients prove
reliably, the abstraction and lemma surface are likely adequate.

## 22. Implementation sequence

### Milestone 1: model

- Define `Code_Point` and `Scalar_Value`.
- Instantiate the functional sequence model.
- Define equality, append, concatenation, slice, prefix, and containment
  relations.
- Prove basic algebraic lemmas needed by clients.
- Create the first proof-scaling experiments for model expressions.

### Milestone 2: byte layer

- Define octet helpers and encoded width.
- Implement `Encode_One`, `Valid_At`, `Decode_One`, and whole-string validation.
- Implement the ghost `Model` mapping.
- Prove the byte/model bridge and encode/decode inverse properties.
- Complete scalar-boundary and malformed-input runtime tests.

### Milestone 3: plain strings and cursors

- Add code-point length and element access.
- Add the forward cursor.
- Add equality, prefix, suffix, and comparison bridge lemmas.
- Prove iteration client examples using only the public specification.

### Milestone 4: bounded strings

- Implement fixed-byte-capacity storage and its invariant.
- Add construction, conversion, clear, and append operations.
- Add model-based equality and iteration.
- Prove exact-capacity and repeated-append clients.

### Milestone 5: slices and search

- Add byte spans and code-point slice mapping.
- Add scalar and substring search.
- Prove byte-search/model-search equivalence.
- Establish ordinary and scheduled proof-performance baselines.

### Milestone 6: split

- Add scalar split iteration.
- Add substring split iteration.
- Prove reconstruction and delimiter-absence properties.
- Reassess the public model relations and proof budgets before freezing the
  first stable API.

### Milestone 7: optional optimizations and ownership

- Evaluate a more advanced substring-search algorithm if runtime evidence
  requires it.
- Evaluate native SMT-string lowering with the same client benchmarks.
- Prototype scoped constant views.
- Reconsider an owning resizable string without changing the common model.

## 23. Open design questions

The following choices should be settled by small implementation and proof
experiments:

- Whether plain UTF-8 operations live directly in `Unicode_Text` or in
  `Unicode_Text.UTF_8`.
- The exact shape and error detail of `Validation_Result`.
- Whether `Find` returns only a code-point index or optionally returns a cursor
  or byte span to avoid rescanning.
- Whether reverse iteration belongs in the first stable API.
- Whether bounded capacity zero is supported as a useful empty-only instance.
- Which model lemmas should be automatic and which should be explicit.
- The primary prover and initial step budgets for stable client regression
  tests.
- The measured point at which naive substring search must be replaced.
- Whether an official Unicode conformance corpus is vendored and, if so, how
  its version and provenance are recorded.

These questions do not alter the central design: concrete values are valid
UTF-8 byte sequences, every representation maps to the same finite sequence of
Unicode scalar values, and both correctness and usable proof performance are
part of the library's definition of success.
