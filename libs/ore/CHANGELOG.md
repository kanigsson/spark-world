# Changelog

All notable changes to this project will be documented in this file. Releases
follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `Ore.Images`, the character images of numbers. It is here because six
  programs in this repository had each written the same two things by hand:
  `Natural'Image` followed by a slice that drops the leading blank, in six
  places and three spellings, and a `"0123456789abcdef"` table in four more.
  None of them said what it produced, so every caller re-derived that the blank
  is exactly one character wide.
  - `Decimal` is that image with a contract: a bounded length, a bounded
    `'Last`, every character a digit, and no leading zero unless the value is
    zero. The bound on `'Last` is there for the caller that concatenates the
    image rather than measuring it: a function result carries its own bounds,
    so a length alone leaves a concatenation without a provable bound.
  - `Hex_Digit` is the table, `Hex_Pair` the fixed-width two-digit form an
    escape sequence needs, and `Hex` the minimal-width image. All take the
    letter case as a parameter, because the clients wanted both.

  The bounds come from the target's own attributes rather than from written
  constants, so they stay right on a target with a wider `Integer`.

  This package has no lemmas and so ships no proof client: nothing in it is
  meant to be reasoned about from outside, and its clients are ordinary Ada
  programs. Its contracts earn their keep inside the library.

## [0.5.0] - 2026-07-30

Client feedback on 0.4.0: the value view was adopted and did what it claimed,
but the bounds it comes with are equalities in the word type, and a client's own
contracts bound a code by `2 ** N` in `Natural`, because that is what a code
length means. With the exponent computed at run time nothing crosses between the
two, so the client wrote the crossing itself — twice, as a case with one branch
per width, beside operations whose purpose is to remove exactly that. This
release is that crossing.

### Added

- `Ore.Bit_Cursors.Field_Value` bounds its result by `2 ** Count` in `Natural`,
  in addition to the mask bound it already stated. A client that only reads
  fields now needs neither crossing lemma of its own: the bound is in the
  arithmetic of the type the operation returns.
- `Ore.Bits`: the crossing between a word-typed value clause and the same value
  as a `Natural`, stated once per width so no client enumerates it.
  - `Lemma_Low_Mask_8/16/32/64_Natural`: `Natural (Low_Mask_N (Count))` is
    `2 ** Count - 1`.
  - `Lemma_Power_Of_Two_8/16/32/64_Natural`: `Natural (Power_Of_Two_N (E))` is
    `2 ** E`, for the client that weighs code lengths or sizes a table with a
    power it got as a word.

  The wider two of each group stop at an exponent of thirty. The mask itself is
  a `Natural` up to thirty-one, but the power on the right of the equality is
  not, and a contract that overflows where its subject does not is a contract a
  client cannot use. Above that width the value is a word and stays one.
- The proof client under `tests/proof` bounds a code taken out of a word by
  `2 ** Length` in `Natural`, and evaluates a weight the same way. Both bodies
  are one call, which is the acceptance test: it is the case-per-width lemma the
  client had written, deleted.

### Changed

- The spec of `Ore.Bit_Cursors` says that adopting the value view means proving
  your own reader equal to `Field_Value`, not defining it as `Field_Value` — a
  reader whose postcondition is the recurrence its consumers are proved through
  cannot be defined by the field, and the equality is what the release before
  this one was for. It also says what the view does not give: the direction from
  a field's value back to which bits of the array its digits are, so a contract
  stated as bit equations stays `Set_Bit`'s.
- The same spec records why `Lemma_Bits_At_Frame` requires the two arrays to have
  identical bounds — a field is a function of the array, so its frame cannot be
  weaker than its subject — and that a client whose own frame is over bit
  positions, and for which threading equal-bounds hypotheses costs more than its
  own induction, is right to keep the induction. No change to the contract.

## [0.4.0] - 2026-07-29

Client feedback on 0.3.0: a field read out of a stream is a number, and nothing
in the library got from the bits a contract states to the number a client's own
specifications are written in. That step is this release.

### Added

- `Ore.Bit_Cursors`: the arithmetic view of a field.
  - `Field_Value`: the field as a `Natural`, with the bound the conversion needs
    already proved, so a client whose codes and lengths are `Natural` writes no
    conversion of its own. `Value_Count` stops at 30 bits: one bit because a
    32-bit field can exceed `Natural'Last`, and one because the recurrence
    doubles a field.
  - `Lemma_Bits_At_Recursion` and `Lemma_Field_Value_Recursion`: a field is twice
    the field without its least significant bit, plus that bit — the last bit
    taken under `High_Bit_First`, the first under `Low_Bit_First`, which is all
    the two orders differ by. This is the step a model that reads a field one bit
    at a time is proved through.
- `Ore.Bits`: the bridge between the bit view and the value view, which the
  recurrences above rest on and which a client assembling words needs directly.
  - `Lemma_Shift_Left_Value`, `Lemma_Shift_Right_Value`: a shift is a
    multiplication or a division by a power of two.
  - `Lemma_Extract_Value`: a field is a shifted remainder.
  - `Bits_Value` and `Lemma_Bits_Value`: what the low bits of a word are worth,
    as a recurrence, and that it agrees with the field — the value analogue of
    `Count_Bits` and `Population_Count`.
  - `Power_Of_Two_8/16/32/64`: one bit set, at an exponent, with the value as a
    `Runtime` clause and the bit as a `Static` one, so a client weighing a code
    length or sizing a table needs no table of powers.
  - `Lemma_Low_Mask_8/16/32/64_Monotonic`: a wider mask is a bigger number. The
    names carry the width because the parameters are counts, which would
    otherwise make the four one profile.
- The proof client under `tests/proof` now proves a client's own `Prefix_Value`
  recursion equal to `Field_Value` at every width, by an induction that mentions
  no bits. The concrete-width version of the same theorem lost its bit-level
  proof and became two calls.
- Runtime tests for the powers, for a field as a number, and for the recurrence
  as arithmetic in both orders.

### Changed

- The spec of `Ore.Bit_Cursors` states what the package is not: every operation
  costs a step per bit, and a throughput-oriented reader — a word-sized
  accumulator refilled a byte at a time — is out of scope rather than slow here,
  because the accumulator's state is not something a position in an array can
  represent. Where the body defended the per-bit loop with a Huffman tree walk, it
  now says that the loop around the tree walk is the case the argument does not
  cover. `ROADMAP.md` records the decision.
- The same spec records that positions are `Natural`, so a stream with more bit
  positions than a `Natural` holds is out of the layer's range even where the
  array holding it is not.

## [0.3.0] - 2026-07-28

### Added

- `Ore.Bit_Cursors`: bit-addressed access to a plain byte array — a cursor is a
  position and an array the caller owns, not a container, so an input longer
  than `Max_Capacity` is addressable and every bound is a division rather than
  the product of a length and eight.
  - `Bit` and `Bit_Value`: the bit at a position across the whole array, as a
    Boolean and as a number, in either bit numbering.
  - `Fits`, `Byte_Of`, `Bit_In_Byte`, `Is_Byte_Aligned` and `Align_To_Byte`:
    the bounds check and the two numberings.
  - `Bits_At`: the field of up to 32 bits at a position, assembled low bit
    first or high bit first — two orders that alternate on one cursor rather
    than being chosen once per stream.
  - `Set_Bit`, `Take_Bits` and `Put_Bits`: the write of one bit, and the cursor
    operations, which report that the array does not hold the field and leave
    the cursor and the array as they were.
  - `Bits_Unchanged_Outside`: the frame vocabulary, over bit positions and with
    a count rather than a one-past-the-end position.
  - Lemmas: `Lemma_Bit_Frame`, from "one byte changed and one bit within it" to
    "one bit position changed" — the array-level analogue of
    `Lemma_Insert_Frame`; and `Lemma_Bits_At_Frame`, that a field over unchanged
    bits is an unchanged field.
- `Ore.Bits.Lemma_Bound_Bits`: from the arithmetic bound `Value <= Low_Mask_*`
  to the bit-wise fact that nothing above the field is set — the direction
  `Extract` does not give.
- A proof client under `tests/proof` for a two-field header written and read
  back over a caller's array, the arithmetic view of a code, and a client that
  writes its own bytes and still inherits the array-level frame.
- Runtime tests for `Ore.Bit_Cursors` under `tests/runtime`.

### Changed

- `Low_Mask_8/16/32/64` and `Field_Mask_8/16/32/64` now state their value as
  well as their bits: a `Runtime` clause gives the number the mask is, so a
  mask serves as an arithmetic bound and not only as something to mask with.
  `Extract`'s bound inherits this, since its right-hand side is a mask. This is
  what lets a client drop a table of `2 ** N - 1` it kept because a bit-by-bit
  postcondition could not be evaluated to a number.
- The proof timeout in both projects is 180 seconds, up from 60. The 64-bit
  field goals are bit-vector problems with a variable shift amount and sit
  close to the old limit when a whole run competes for the cores.
- The comment on `Max_Capacity` no longer claims that the bit-addressed layers
  share the ceiling: they take arrays a caller owns and impose none.

## [0.2.0] - 2026-07-28

### Added

- `Ore.Bits`: bit-level operations on `Byte`, `Word16`, `Word32` and `Word64`,
  with contracts stated bit by bit through the `Bit` accessor.
  - `Intrinsics`: the machine shift and rotate instructions, unconstrained in
    their amount, which GNATprove translates to bit-vector operations.
  - Checked shifts and rotates: `Shift_Left`, `Shift_Right`, `Rotate_Left`,
    `Rotate_Right`, with the amount bounded by the width of the type.
  - Masks: `Low_Mask_8/16/32/64` and `Field_Mask_8/16/32/64`, including the
    full-width mask that `2 ** Count - 1` cannot form.
  - Bit fields: `Extract` and `Insert`, the latter with the frame condition
    that no bit outside the field moved.
  - Counting: `Population_Count`, `Leading_Zeroes`, `Trailing_Zeroes`, and the
    ghost recurrence `Count_Bits` they are specified against.
  - Byte order within a word: `Byte_At` in either order, and `Byte_Swap`.
  - Explicit width changes: `Truncate_To_Byte/Word16/Word32` and
    `Extend_To_Word16/Word32/Word64`.
  - Lemmas: `Lemma_Bits_Equal` and `Lemma_Bytes_Equal`, from agreement bit by
    bit or byte by byte to equality of the values; `Lemma_And/Or/Xor/Not_Bits`
    for the bitwise operators; `Lemma_Insert_Frame`, that inserting one field
    leaves a disjoint one alone; `Lemma_Byte_Swap_Involutive`.
- A proof client under `tests/proof` for the packed-header round trip and the
  significant-bit width of a value.
- Runtime tests for `Ore.Bits` under `tests/runtime`.
- A bindable restrictions smoke test that checks a complete partition.
- Exhaustive small-capacity and back-reference runtime cases, plus endian stores
  at both legal array boundaries.

### Changed

- Clarified that the exception-free design excludes application-level
  exception paths for calls that satisfy their preconditions; assertion-enabled
  builds can still raise `Assertion_Error` for contract violations.
- Strengthened the external `Drain` proof client to prove the content and order
  of transferred bytes as well as cursor progress.

## [0.1.0] - 2026-07-27

### Added

- `Ore`: the shared physical types — `Byte`, `Word16`, `Word32`, `Word64`, the
  unconstrained `Byte_Array` over 1-based positions, `Byte_Order`, and the
  `Max_Capacity` ceiling that keeps bit positions inside `Natural`.
- `Ore.Byte_Buffers`: bounded byte buffers with a write and a read cursor,
  capacity as a discriminant, and a default-initialized empty state.
  - Producing: `Append` (byte, array), `Append_Fill`, `Append_16/32/64`, and
    `Put` for short transfers.
  - Consuming: `Peek`, `Consume`, `Read` (byte, exact array),
    `Read_16/32/64`, `Get` for short transfers, and `Move` between buffers.
  - Cursor and content management: `Clear`, `Rewind`, `Truncate`, `Compact`.
  - Subviews: `Span`, `Written_Span`, `Unread_Span`, `Slice`, `Append_Slice`.
  - Copies: `Append_Copy`, the back-reference copy, specified for overlapping
    as well as disjoint ranges.
  - Checked multi-byte access on plain arrays: `Load_16/32/64` as expression
    functions and `Store_16/32/64` with the store/load round trip as a
    postcondition.
  - Proof vocabulary: `Contents` (ghost model), `Same_Prefix`, `Matches_At`,
    `Copies_Back`, `Equal_Ranges`, `Unchanged_Outside`.
  - Lemmas: `Lemma_Equal_Ranges_Trans`, `Lemma_Load_16/32/64_Frame`,
    `Lemma_Same_Prefix_Trans`, `Lemma_Matches_At_Frame`,
    `Lemma_Matches_At_Concat`, `Lemma_Contents_Equal`,
    `Lemma_Copies_Back_Disjoint`, `Lemma_Copies_Back_Run`.
- Proof clients under `tests/proof`: tag/length/payload framing with read-back,
  run-length expansion through a distance-one copy, and a streaming drain loop.
- Runtime tests under `tests/runtime`, executed with contracts enabled.
