# Changelog

All notable changes to this project will be documented in this file. Releases
follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
