# Unicode_Text integration handoff

## Purpose

Integrate the sibling `../../unicode_text` library into this JSON parser so
that successful parsing and decoding expose client-usable SPARK guarantees
about UTF-8 validity.

This is not merely a replacement of one byte scanner with another. The result
must let a proved client use a decoded key or string value with
`Unicode_Text.UTF_8` operations without inserting its own validation call or
unproved assertion.

The implementation should preserve the defining properties of this crate:

- caller-owned input and output buffers;
- no heap allocation, access types, recursion, OS dependency, or package
  state in the parser;
- status-based rejection of hostile input;
- zero-copy pull events;
- no global limit on document, member, or string length;
- a single fixed nesting-depth limit;
- proof of absence of run-time errors and termination.

## Repositories and starting points

- JSON parser: `/home/kanig/tools/pager/json`
- Unicode library: `/home/kanig/tools/unicode_text`

At the time this handoff was written:

- `pager/json` is on branch `main` at `45db9c1`;
- `unicode_text` is on branch `main` at `8c8fa6a`;
- both worktrees are clean;
- `pager/json` records 639 checks proved at level 2;
- `unicode_text` is version 0.5.0 and provides both plain-`String` UTF-8
  operations and `Unicode_Text.Bounded`.

Recheck these facts before editing. Do not assume the recorded proof counts
remain current.

Primary files:

- `src/json-pull.ads`, `src/json-pull.adb`
- `src/json-strings.ads`, `src/json-strings.adb`
- `src/json-walk.ads`, `src/json-walk.adb`
- `src/json.ads`
- `json.gpr`, `alire.toml`
- `tests/src/test_json.adb`
- `tests/src/test_walk.adb`
- `tests/run_tests.py`
- `README.md`

Relevant Unicode_Text interfaces:

- `../../unicode_text/src/unicode_text.ads`
- `../../unicode_text/src/unicode_text-utf_8.ads`
- `../../unicode_text/src/unicode_text-bounded.ads`
- `../../unicode_text/unicode_text.gpr`
- `../../unicode_text/design.md`

## Current behavior

### Pull parser

`JSON.Pull.Next` scans a caller-provided `String` and returns events whose
payloads are slices of that input. `Scan_String` validates:

- JSON escape syntax;
- UTF-16 surrogate pairing in `\uXXXX` escapes;
- unescaped control characters;
- raw UTF-8 byte sequences.

Raw UTF-8 validation is implemented locally by `Scan_UTF8` and `Take_Cont`.
The accepted lead and continuation ranges agree with strict UTF-8:

- no `C0` or `C1` overlong encodings;
- no overlong three- or four-byte encodings;
- no surrogate code points;
- no values beyond U+10FFFF;
- no isolated continuation bytes or truncated sequences.

This is operationally correct, but the successful-event contract currently
guarantees only that the payload span lies within `Input`. It does not state
that the payload is valid UTF-8.

### String decoder

`JSON.Strings.Decode` accepts the bytes between JSON string quotes, validates
them again, resolves JSON escapes, and writes decoded UTF-8 into a
caller-provided buffer.

The implementation contains a second local UTF-8 validator and encoder:

- `Copy_Cont`
- `Encode`
- the multi-byte branch in `Decode`

Its public postcondition guarantees only:

```ada
Length <= Input'Length
```

It does not guarantee that the active output prefix is valid UTF-8. Therefore
a SPARK client cannot call `Unicode_Text.UTF_8.Code_Point_Length`, `Element`,
`Model`, or another operation requiring valid UTF-8 without separately proving
or checking validity.

### Walk helpers

`JSON.Walk.Span` carries an input slice and an `Escaped` flag.
`JSON.Walk.Matches` performs raw byte comparison and deliberately rejects every
escaped key. Consequently:

```json
{"a\u0062c": 1}
```

does not match the plain UTF-8 name `"abc"`. This is not JSON string equality
and must be corrected as part of the user-facing Unicode work.

## Required design decisions

### 1. Preserve hostile-input validation

Do not add an `Is_Valid_UTF_8 (Input)` precondition to `JSON.Pull.Next` or
`JSON.Strings.Decode` as a replacement for validation.

The parser is intentionally usable on arbitrary untrusted bytes and reports
`Invalid_UTF8`. It is acceptable to add a separate proof-oriented entry point
or overload that assumes valid UTF-8, but the existing status-returning
boundary must remain.

### 2. Preserve zero-copy events

Do not replace pull-event spans with owned or copied Unicode strings.

For an unescaped `Member_Key` or `String_Value`, the input slice is already the
decoded text. For an escaped payload, the event remains a source span and the
caller decodes it explicitly.

### 3. Use Unicode_Text as the normative UTF-8 implementation

After this work, `pager/json` should not maintain independent copies of the
UTF-8 lead-byte table or UTF-8 encoder arithmetic.

Use, as appropriate:

- `Unicode_Text.UTF_8.Valid_At`
- `Unicode_Text.UTF_8.Sequence_Width_At`
- `Unicode_Text.UTF_8.Decode_One`
- `Unicode_Text.UTF_8.Encode_One`
- `Unicode_Text.UTF_8.Is_Valid_UTF_8`
- `Unicode_Text.UTF_8.Validate`
- `Unicode_Text.UTF_8.Lemma_Encode_Decode`
- `Unicode_Text.UTF_8.Lemma_Concatenation`
- the byte-range helpers and models already supplied by `unicode_text`

JSON escape recognition remains in this crate. UTF-8 validity, scalar
decoding, and scalar encoding belong to `unicode_text`.

### 4. Make validity available in public contracts

The primary deliverable is a contract, not merely runtime behavior.

Define a bounds-safe helper for the active prefix of a caller buffer. Its exact
name is open, but its semantics should be equivalent to:

```ada
function Active_Prefix
  (Buffer : String;
   Length : Natural) return String
with
  Pre => Length <= Buffer'Length;
```

It must handle `Length = 0` without unsafe bound arithmetic.

Strengthen `JSON.Strings.Decode` along these lines:

```ada
Post =>
  Length <= Input'Length
  and then
    (if Status = OK then
       Unicode_Text.UTF_8.Is_Valid_UTF_8
         (Active_Prefix (Output, Length))
     else
       Length = 0);
```

Retain the existing capacity and bound guarantees.

For a successful pull event of kind `Member_Key` or `String_Value`, export
that its raw payload slice is valid UTF-8. This is true even when `Escaped` is
set: JSON escape syntax is ASCII, and every unescaped non-ASCII sequence was
validated by the scanner. The raw payload is not necessarily the logical
decoded value, so name the helper and documentation carefully.

Avoid writing contracts using repeated ad hoc slices with fragile empty-range
arithmetic. Introduce one public or private payload/prefix helper and use it
consistently.

### 5. Compare keys after JSON decoding

Change `JSON.Walk.Matches` and therefore `Find_Member` to compare logical
decoded keys rather than raw source spelling.

Required behavior includes:

```text
raw key "abc"       = expected name "abc"
raw key "a\u0062c" = expected name "abc"
raw key "\u00e9"   = expected UTF-8 U+00E9
raw key "\ud834\udd1e" = expected UTF-8 U+1D11E
```

Do not allocate a temporary string merely to compare a key. Implement a
streaming comparison between:

- scalars decoded from the JSON string payload; and
- scalars decoded from the expected valid UTF-8 name.

A fast path for `not Span.Escaped` is encouraged, followed by the decoded
comparison when necessary.

`Name` should either:

- have `Unicode_Text.UTF_8.Is_Valid_UTF_8 (Name)` as a precondition; or
- be validated by the comparison operation and report invalid input
  separately.

For `JSON.Walk`, a precondition is the cleaner choice: `Name` is application
schema data, not hostile JSON input.

## Scope

### Required

1. Establish a build/proof dependency from `pager/json` to `unicode_text`.
2. Replace the local pull-parser UTF-8 byte scanner with calls to
   `Unicode_Text.UTF_8`.
3. Rework `JSON.Strings.Decode` to use Unicode_Text decoding and encoding
   primitives.
4. Prove successful decoded output is valid UTF-8.
5. Expose validity of successful string/key payload spans where applicable.
6. Make `JSON.Walk.Matches` and `Find_Member` compare decoded key values.
7. Add proof clients demonstrating that callers can consume these guarantees.
8. Add focused runtime tests and pass the full differential suite.
9. Update the README, proof status, dependency metadata, and recorded proof
   counts.

### Optional follow-on

Add a generic decoder adapter for applications using
`Unicode_Text.Bounded`:

```ada
generic
   with package Text is new Unicode_Text.Bounded (<>);
package JSON.Strings.Bounded_Decoding is
   ...
end JSON.Strings.Bounded_Decoding;
```

Such an adapter can decode by appending scalar values to a
`Text.Bounded_String`, with an input-length/capacity precondition. It gives
clients a valid-by-construction result with a compile-time capacity.

Do not make this adapter a prerequisite for the core integration. The current
caller-buffer API supports runtime-sized documents and is part of the
allocation-free design.

### Non-goals

- Do not add a DOM or materialize a document tree.
- Do not add heap allocation or file I/O to the library.
- Do not add a JSON writer or serializer.
- Do not change number conversion semantics.
- Do not change the nesting-depth policy.
- Do not require that an entire input be prevalidated before pull parsing.
- Do not weaken the distinction between malformed JSON and a known-shape
  mismatch in `JSON.Walk`.
- Do not copy Unicode_Text implementation code into this repository.

## Dependency setup

`pager/json` is already an Alire library crate. `unicode_text` currently has a
project file but no Alire manifest, and its `unicode_text.gpr` includes
`tests/proof` in `Source_Dirs`.

Resolve this deliberately rather than hiding the dependency through copied
sources or ambient `ADA_PROJECT_PATH`.

Preferred durable solution:

1. Add a library-only GPR project and Alire crate metadata to
   `unicode_text`.
2. Make `unicode_text`'s proof project extend or import that library project.
3. Add a normal Alire dependency from `pager/json`.

Acceptable first local step:

- import `../../unicode_text/unicode_text.gpr` explicitly from `json.gpr`.

If the local step is used, record the packaging limitation in the commit and
do not describe the crate as independently consumable until the durable
dependency exists.

Do not make `pager/json` depend directly on `sparklib` merely because the
current Unicode_Text proof project does. The production dependency should
expose only the Unicode_Text library units needed at runtime and proof time.

## Suggested implementation sequence

Keep commits reviewable and leave the tree building and proving at each major
boundary.

### Step 1: dependency and a proof-only smoke client

- Establish the explicit project dependency.
- Add a small proof client or package that calls
  `Unicode_Text.UTF_8.Validate` and `Sequence_Width_At`.
- Build and prove before changing parser behavior.

This confirms project closure, language mode, assertion policy, and proof
visibility.

### Step 2: pull-parser UTF-8 scanning

- Replace `Take_Cont` and the range table in `Scan_UTF8`.
- At a non-ASCII input position, use `Valid_At` or
  `Sequence_Width_At`.
- Advance `Pos` by the returned width on success.
- Preserve `Invalid_UTF8` and `Truncated` behavior as closely as practical.
  If Unicode_Text reports both through a zero width, decide and document the
  status mapping; tests must pin it.
- Remove obsolete local helpers after all callers are migrated.

Do not alter escape parsing in this step.

### Step 3: decoded-output validity

- Introduce the active-prefix helper.
- Add the `Decode` validity postcondition.
- Maintain a loop invariant that the active decoded prefix is valid UTF-8.
- Process output one complete encoded scalar at a time. Do not expose a
  temporarily incomplete multi-byte sequence as the active prefix.
- Decode a valid raw scalar with `Decode_One`.
- Encode raw and escaped scalars with `Encode_One`.
- Use Unicode_Text's concatenation relation/lemma to establish that appending
  the complete encoding preserves validity.
- Preserve the bound `Out_Pos <= In_Pos`, or an equivalent invariant proving
  that `Output'Length >= Input'Length` is sufficient.
- Remove the local `Encode` and continuation-copy logic after the proof is
  complete.

The implementation may continue to write into the caller's `Output`; it does
not need to construct a `Unicode_Text.Bounded.Bounded_String`.

### Step 4: event-span contracts

- Add a helper that denotes a valid event payload without unsafe empty-slice
  expressions.
- Strengthen `Scan_String`, `Do_Key`, `Do_Value`, and `Next` contracts enough
  to export raw-payload UTF-8 validity for successful string/key events.
- Add a proof client that receives an unescaped string event and calls a
  Unicode_Text operation on its payload without a new validation guard.

Avoid adding a recursive or whole-document ghost model at this stage. The
small event-level property is sufficient.

### Step 5: decoded key matching

- Give `Matches` a valid-UTF-8 precondition on `Name`.
- Retain the unescaped byte-equality fast path.
- Add a streaming decoded comparison for escaped keys.
- Change the existing test that says an escaped twin is skipped.
- Verify that `Find_Member` stops on the first logically equal name, regardless
  of its source escape spelling.

If a reusable JSON-string scalar iterator makes this cleaner, put it in
`JSON.Strings` rather than duplicating escape decoding in `JSON.Walk`.

### Step 6: documentation and acceptance

- Update the package comments and README.
- Explain the distinction between:
  - raw payload bytes;
  - an unescaped payload that is already the logical UTF-8 text;
  - an escaped payload requiring `Decode`;
  - the valid active prefix of the decode buffer.
- Update proof counts from a fresh result.
- Run all acceptance commands sequentially.

## Proof clients

Add focused SPARK clients to prevent contracts from becoming implementation-only
facts.

At minimum prove:

1. After `JSON.Strings.Decode` returns `OK`, the active output prefix can be
   passed directly to `Unicode_Text.UTF_8.Code_Point_Length`.
2. The empty decoded string is valid.
3. A successfully returned unescaped pull-event payload can be passed directly
   to a Unicode_Text operation.
4. A client loop using `JSON.Walk` retains its existing progress proof after
   logical key matching is introduced.
5. No proof client needs `pragma Assume`, an unproved assertion, or a second
   call to `Is_Valid_UTF_8`.

The client should exercise both lower bounds and empty strings where the API
allows them.

## Runtime tests

Keep the existing differential corpus and add focused cases for the properties
that Python comparison alone does not prove.

### UTF-8 validation

- empty and ASCII strings;
- valid two-, three-, and four-byte scalars;
- isolated continuation byte;
- `C0`/`C1` overlong lead;
- overlong three- and four-byte sequences;
- UTF-8 encoding of a surrogate;
- sequence beyond U+10FFFF;
- truncated sequence at every possible byte;
- invalid UTF-8 before and after a valid escape.

### Escape decoding

- all short escapes;
- `\u0000`;
- `\u00E9`;
- `\u20AC`;
- a valid surrogate pair such as `\uD834\uDD1E`;
- lone high and low surrogates;
- high surrogate followed by a non-low code unit;
- raw UTF-8 mixed with escaped scalars;
- empty decoded output.

### Key equality

- plain key against the same plain name;
- `a\u0062c` against `abc`;
- an escaped reverse solidus against its raw UTF-8 name;
- escaped BMP and supplementary names;
- two source spellings of the same key;
- a genuinely different escaped key;
- valid non-ASCII `Name`;
- invalid `Name` behavior, according to the chosen precondition policy.

The current `test_walk.adb` case asserting that an escaped twin is skipped must
be replaced. Its expected behavior is contrary to decoded JSON string
equality.

## Acceptance commands

Run tools sequentially. Do not launch concurrent GNATprove processes against
the same object/proof directories. Use GNATprove's internal job parallelism.

From `/home/kanig/tools/pager/json`:

```sh
gprbuild -P json.gpr -XMODE=debug
gnatprove -P json.gpr -j16 --level=2 --report=fail -f
```

Then:

```sh
cd tests
gprbuild -P tests.gpr
./test_walk
./run_tests.py
```

If the full differential suite is too slow during development, use
`./run_tests.py --quick` for intermediate iterations, but the final acceptance
must run the full suite.

Also run the Unicode_Text proof and runtime suites if that repository is
modified. Follow its current README and project configuration rather than
copying stale commands from this handoff.

## Proof and implementation hazards

### Incomplete multi-byte output

An invariant saying the current output prefix is valid cannot hold after
writing only the leading byte of a multi-byte scalar. Build or copy one
complete `Encode_One` result and advance the logical output length only after
the complete sequence is present.

### Empty prefixes

Avoid `Buffer (Buffer'First .. Buffer'First + Length - 1)` without a guarded
`Length = 0` case. Null strings and extreme bounds are frequent sources of
otherwise unnecessary overflow obligations.

### Concatenation

Raw Ada `Left & Right` often produces array-bound and overflow proof
obligations. Prefer Unicode_Text's explicit `Is_Byte_Concatenation` and
`Lemma_Concatenation` with a caller-provided result buffer.

### Ghost model boundary

`Unicode_Text.Models.Model` is a decoded scalar model, not an independent
normative specification of UTF-8 bytes. Use `Is_Valid_UTF_8`, `Valid_At`,
`Decode_One`, and the byte-level lemmas for executable validity. Use `Model`
for semantic key equality only after validity has been established.

### Status preservation

Replacing the local scanner may collapse the distinction between a truncated
sequence and another invalid sequence. Decide whether exact status
compatibility matters before changing it. Keep the public status enumeration
stable unless there is a compelling reason and focused tests.

### Proof cache

After changing predicates, representation helpers, or public contracts, finish
with a forced fresh whole-project proof. A cache-fast or narrowly scoped run is
not final evidence.

### Packaging

Do not accidentally make the runtime crate compile Unicode_Text proof clients
or acquire an application-owned SPARKlib configuration. Split the sibling
project cleanly if necessary.

## Definition of done

The work is complete when:

- the parser and decoder use Unicode_Text as the UTF-8 implementation;
- there is no duplicate UTF-8 range table or scalar encoder in `pager/json`;
- arbitrary invalid input is still rejected through status values;
- successful `Decode` has a proved valid-UTF-8 active-prefix postcondition;
- successful event contracts expose the promised payload validity;
- escaped and unescaped spellings of the same object key match identically;
- proof clients consume the new validity guarantees directly;
- no heap allocation or new global capacity limit was introduced;
- all focused and differential runtime tests pass;
- one fresh whole-project GNATprove run proves every check with no
  justifications or assumptions;
- README and proof counts describe the final implementation accurately.

