# Compression roadmap

This is the living plan for improving `inflate`'s compression ratio. The
correctness foundations and the end-to-end gzip round-trip theorem are already
complete. M6 is now a compressor-quality milestone: every step below must
preserve the theorem, but none is a prerequisite for the theorem as it stands.

## Current boundary

`Inflate.Theorems.GZip_Round_Trip` proves, for every input within the public size
cap and with sufficiently large caller-provided buffers, that gzip compression
followed by decompression returns the input exactly. The proof is branch-free at
the theorem layer. `Inflate.Bodies.Body_Encodes` hides whether the compressor
selected a stored, fixed-Huffman, or dynamic-Huffman body.

The current compressor selects:

- a sparse dynamic-Huffman block for profitable constant-byte runs of at least
  4,096 bytes;
- a fixed-Huffman block otherwise, while the input fits the fixed encoder's
  arithmetic domain; or
- stored blocks above that domain.

The shared token plan currently finds the longest match of length 3 through 10
at distances 1 through 4. These symbols require no RFC 1951 extra bits. This is
enough to exercise and prove the complete Huffman/LZ77 round-trip path, but it is
not enough for competitive compression on ordinary files.

The last recorded proof and test baseline is:

- 7,695 checks proved at `--level=4`, with no assumptions or justifications;
- 6,449 debug/runtime cases and 22 compressor interoperability cases passing;
- C zlib independently accepting every focused compressor output.

On commit `83fa4aa`, aggregating the 12 checked-in `tests/corpus` files gave:

| Compressor | Compressed/input size |
|---|---:|
| current `bin/inflate` | 86.8% |
| Python gzip level 6 | 26.0% |

This is a baseline, not a zlib-parity promise. M6 must materially close that gap
without adding compression optimality to the proof claim.

## Completed foundations

| Milestone | Result |
|---|---|
| M0 | Absence of run-time errors for the decoder |
| M1 | Bit-reader model and Huffman lookup equivalence |
| M2 | Complete, prefix-free canonical Huffman construction |
| M3 | Standalone Huffman encode/decode round-trip |
| M4 | LZ77 back-reference correctness, including overlap |
| M5 | Successful raw DEFLATE decoding satisfies the executable full model |
| M6a | Stored gzip compressor, CLI, size/totality contracts, and full round-trip theorem |
| M7 | CRC-32 and Adler-32 connected to mathematical specifications |

Completed M6 infrastructure includes the verified fixed-Huffman token path,
balanced dynamic codebook builder, shared codebook/payload writer, complete
dynamic header/body serializer, dynamic analyzer and specialized decoder,
stored/fixed/dynamic semantic body boundary, exact dynamic-versus-fixed size
comparison, and the constant-byte-run dynamic gzip branch.

## M6 roadmap

### M6-1 — General dynamic candidates

Replace the constant-byte specialization with a pass over the deterministic
token plan for eligible nonconstant inputs.

Work:

- collect literal/length and distance symbol coverage and counts without
  overflow;
- prove that every selected token is covered by the resulting codebooks;
- build and serialize the dynamic candidate through the existing shared
  header/payload path;
- retain it only when its exact body is smaller than the fixed alternative;
- preserve the fixed fallback if construction fails or dynamic coding loses;
- add a reproducible aggregate corpus-ratio command or script.

Acceptance:

- at least one nonconstant corpus input selects dynamic coding profitably;
- no selected dynamic body is larger than its exact fixed alternative;
- the full round-trip theorem, full proof, runtime suite, CLI suite, and zlib
  interoperability checks remain clean;
- the before/after aggregate corpus ratio is recorded.

Expected complexity: **medium**. The semantic, serializer, decoder, framing, and
fallback machinery already exists. The main proof obligation is connecting the
collector to `Inflate.Payload.Covers`.

The current `Build_Lengths` uses frequency only as a used/unused test and emits a
balanced complete tree. M6-1 may retain that valid heuristic. Frequency-weighted
length selection is deferred to M6-5 unless measurement shows it is needed
earlier.

### M6-2 — Full RFC token representation

Generalize the shared payload boundary from the no-extra-bit subset to all RFC
1951 length and distance symbols.

Work:

- define shared, table-driven mappings between lengths/distances and their base
  symbol, extra-bit count, and extra-bit value;
- prove the mappings' ranges and encode/decode correspondence;
- include extra bits in exact token cost and output bounds;
- extend payload serialization, analyzers, semantic relations, and specialized
  decoders to write and read those bits;
- keep the existing matcher restricted initially, so this step changes the
  representation boundary without simultaneously changing match selection.

Acceptance:

- focused cases cover every length/distance coding boundary, including length
  258 and distance 32,768;
- existing short-match encodings remain valid;
- fixed and dynamic serializer images round trip through the shipping decoder;
- full proof and interoperability validation remain clean.

Expected complexity: **medium-hard**. This removes a simplification repeated
through `Inflate.Fixed`, `Inflate.Payload`, and `Inflate.Dynamic`, but it does not
yet require a new match-finder design.

### M6-3 — Longer matches

Raise the selected match length from 10 to the DEFLATE maximum of 258 while
retaining the current small distance window.

Work:

- extend `Matching_Length`, `Selected_Token`, and token-plan bounds;
- generalize the plan's remaining-length and bit-cost arithmetic;
- prove every longer emitted match still carries the local `Match_Applies`
  witness used by the M4 copy primitive;
- collect the newly reachable length symbols in dynamic candidates.

Acceptance:

- focused overlapping and non-overlapping matches exercise all length-symbol
  ranges and length 258;
- long runs improve materially over the M6-2 baseline;
- the full theorem and validation gates remain unchanged.

Expected complexity: **medium** after M6-2. This should deliver a large gain on
runs without introducing match-finder state.

### M6-4 — Wider, efficient match search

Widen the distance-four window enough to find repeated substrings in ordinary
files. Do not implement this as a scan of all 32,768 distances at every input
position.

Work:

- introduce a bounded, no-heap candidate index, likely based on short-prefix
  hashing with a fixed candidate budget;
- validate candidate bytes before emitting a match, making `Match_Applies` the
  only semantic obligation exported by the finder;
- increase the window incrementally, measuring ratio and run time at each
  useful boundary;
- support the full 32 KiB DEFLATE distance domain if the bounded representation
  and performance justify it;
- make no claim that the selected match is globally longest or optimal.

Acceptance:

- repeated substrings at distances well beyond four are selected and round
  trip, including overlapping and non-overlapping cases;
- compressor execution remains bounded and scales acceptably on incompressible
  input;
- corpus ratio closes most of the gap between the M6-1 baseline and gzip level
  6;
- full proof, runtime, CLI, and interoperability validation remain clean.

Expected complexity: **hard**. The local match-validity proof is simple; the
main design risk is an efficient stateful finder that fits the current pure
token-plan and no-heap architecture.

### M6-5 — Ratio gate and targeted refinements

Measure the result of M6-1 through M6-4 before adding more proof surface. If the
ratio is still not respectable, choose the smallest measured bottleneck from:

- assigning shorter balanced-tree positions to more frequent symbols, or a
  stronger frequency-sensitive but non-optimal tree heuristic;
- RFC 1951 repeat codes 16 through 18 for compressing the dynamic header;
- lazy or bounded-lookahead token selection;
- multiple blocks when one global codebook is demonstrably poor.

M6 is complete when the repository records a repeatable corpus measurement,
the compressor produces a substantial real-world reduction rather than merely
exercising compressed block types, and the existing full-domain theorem and
validation gates remain intact. Matching zlib's ratio or proving compression
optimality is explicitly outside the milestone.

## Rules for every M6 subgoal

- Preserve `Inflate.Theorems.GZip_Round_Trip` for the complete public input
  domain; stored and fixed fallbacks remain valid design choices.
- Prove only that every emitted match is valid. Do not prove match-search or
  Huffman-tree optimality.
- Keep exact size/totality contracts and caller-provided output bounds.
- Keep the SPARK library no-heap and free of package state.
- Keep wire-format compatibility independently checked against zlib; the
  theorem relates this library's compressor and decoder through its executable
  model, not through a separately formalized RFC specification.
- Prefer incremental proof boundaries that delete an old restriction before
  adding abstraction layers.

The standard completion gate is:

```sh
gnatprove -P inflate.gpr --level=4 -j0 --timeout=60 --report=fail
(cd tests && gprbuild -P tests.gpr -XMODE=debug && python3 run_tests.py)
python3 tests/run_cli_tests.py
```

Run focused proof and interoperability tests first, then the full gate. Update
the recorded proof/test counts and corpus ratio only from actual runs.
