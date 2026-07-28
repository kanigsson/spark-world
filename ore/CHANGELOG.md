# Changelog

All notable changes to this project will be documented in this file. Releases
follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
