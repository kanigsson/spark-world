# inflate - a DEFLATE / zlib / gzip / ZIP codec in SPARK

A one-shot, no-heap compression library: DEFLATE itself (RFC 1951), the
zlib (RFC 1950) and gzip (RFC 1952) containers with their checksums, and a
ZIP central-directory walker with per-entry extraction. The entire library
is SPARK. Decoding is proved free of run-time errors, with termination and
initialization/data-flow checks included in the proof run described below.
Every successful raw DEFLATE decode is also proved to satisfy an executable
canonical decode model; that model and the returned bytes are differentially
tested against C zlib. The gzip compressor (fixed Huffman with verified
longest matches of length 3 through 10 at distances 1 through 4 throughout
the fixed encoder's arithmetic domain, stored blocks above it) and
decompressor additionally carry a **proved
round-trip theorem**: `Inflate.Theorems.GZip_Round_Trip` states — and the
proof establishes for every input — that decompressing the compressor's
output restores the input exactly, with `Status = OK` (see "Compression"
below). Compression-ratio upgrades are scoped in `compression.md`.

The library is meant for callers that need to parse compressed data from
untrusted input without dynamic allocation. There is no heap, no access
type, no OS dependency, and no package state in the library. The shipping
decoder and the ordinary full-model validation path are iterative; recursive
stored-fragment relations remain in the proof layer. Project debug builds keep
ordinary language run-time checks but disable execution of proof contracts via
`debug.adc`, so those recursive relations are not an additional run-time stack
path. Malformed input is normally reported as a status value instead of being
handled by raising an exception.

## Packages

| Package           | Contents |
|-------------------|----------|
| `Inflate`         | `Byte_Array`, the `Status_Type` all layers report through |
| `Inflate.Raw`     | DEFLATE (RFC 1951): stored/fixed/dynamic blocks, canonical Huffman decoding; `Compress_Stored` |
| `Inflate.LZ77`    | proved DEFLATE back-reference copying, including overlapping matches |
| `Inflate.Fixed`   | fixed-Huffman literal/match encoder, iterative analyzer, and executable relation |
| `Inflate.Codebooks` | shared fixed/canonical encoder codebook boundary with proved construction and validity |
| `Inflate.Payload` | shared literal, match, and end-of-block serializer over a ready codebook |
| `Inflate.Dynamic` | bounded dynamic-Huffman codebook, header, and local body serializer |
| `Inflate.Bodies`  | common stored/fixed compressor-image relation, recognition, framing, and functionality lemmas |
| `Inflate.ZLib`    | zlib container: header validation, Adler-32 verification |
| `Inflate.GZip`    | gzip container: all header features (EXTRA/NAME/COMMENT/HCRC), CRC-32 and length verification, multi-member `Decompress_All`; `Compress` |
| `Inflate.Model`   | executable canonical model for stored, fixed-Huffman, and dynamic-Huffman DEFLATE, plus the stored compressor relation |
| `Inflate.Theorems`| the proved gzip round-trip theorem, stated as an executable procedure |
| `Inflate.ZIP`     | ZIP archives: end-record lookup (comment scan-back), central-directory iteration, extraction with CRC/size verification |
| `Inflate.CRC32`   | CRC-32 (gzip/ZIP polynomial), table proved equal to a reflected GF(2) specification |
| `Inflate.Adler32` | Adler-32 over a direct modulus-65521 running-sums model |

All decoders share one shape:

```ada
procedure Decompress
  (Input    : in     Byte_Array;   --  the whole compressed stream
   Output   : in out Byte_Array;   --  caller-sized; bound known by protocol
   Consumed :    out Natural;      --  bytes of input the stream occupied
   Produced :    out Natural;      --  bytes of output written
   Status   :    out Status_Type)  --  OK, or the first violation found
with Global => null,
     Post   => Consumed <= Input'Length and then Produced <= Output'Length;
```

`Consumed` is byte-exact (including a final partially-used byte), so
trailers and concatenated members compose: the gzip/zlib wrappers and the
ZIP extractor are ordinary clients of `Inflate.Raw`.

## Compression

The library compresses to standard gzip. Inputs through
`Inflate.Fixed.Max_Input` use one final fixed-Huffman block. A deliberately
small match finder advances through explicit token boundaries. At every
reached boundary it searches distances 1 through 4 and selects the longest
verified match of length 3 through 10, preferring the smaller distance on a
tie; other bytes remain literals. This no-extra-bit fixed-code slice exercises
overlapping and non-overlapping LZ77 window equations, permits unaligned and
variable-length token selection, and makes no optimality claim.
`Max_Input` is derived from the largest stream whose bit offsets plus the gzip
trailer fit in `Natural` (238,609,285 input bytes on the current target). Still
larger inputs retain the stored-block encoder, so the public compressor and
theorem keep their original domain. `Inflate.Codebooks` now separates fixed
and canonical assignments from `Inflate.Payload`, which serializes the common
literal, length/distance, and end-of-block token payload. The fixed compressor
uses that shared writer, and `Inflate.Dynamic` constructs a proved balanced
complete codebook and a local dynamic body around the same payload path. The
dynamic header transmits all lengths directly through a complete four-bit
code-length alphabet; this is intentionally larger than an RLE-optimized header
but keeps reconstruction local and proved. The focused harness round trips that
body through the shipping decoder and independent model, and C zlib decodes the
same bytes. The serialized header now deterministically recovers the exact
canonical books, and a proved witness-erasure lemma lifts the serializer's
book-carrying relation to a three-argument dynamic relation over body, produced
size, and data. The top-level gzip compressor does not select the dynamic body
yet, so connecting that local relation to `Body_Encodes` recognition and
functionality, gzip integration, lengths requiring extra bits, and wider
distances remain M6 ratio work. Any gzip decoder consumes the current fixed or
stored output. The contract is preserved across both encodings:

- **Totality and size.** Under the stated preconditions there is no failure
  path. `GZip.Compressed_Size` is the allocation bound; the produced size is
  exact for the selected fixed or stored branch.
- **Round-trip, compress half.** The DEFLATE body stands in
  `Inflate.Bodies.Body_Encodes` to exactly the input bytes. Stored and fixed
  encoders establish that common relation locally. The gzip trailer provably
  holds `CRC32.Compute (Input)` — the same function the decoder recomputes.
- **Round-trip, decode half.** `Raw.Decompress` and `GZip.Decompress` carry
  postconditions stating that any recognized common-body image, characterized
  on the input side alone, decodes successfully and produces bytes in that
  relation. `GZip.Decompress_All` carries the same whole-file lifting contract.
  A trailer holding the CRC-32/length recomputed over the output is sufficient
  for the member to be accepted.
- **The theorem.** `Inflate.Theorems.GZip_Round_Trip` composes the two
  halves: for *every* input (within the size cap, given large enough
  buffers), `Decompress (Compress (Input))` returns `Status = OK` and
  exactly `Input`. The proof is spec-free — it trusts no external DEFLATE
  specification, only the agreement of the library's own compressor and
  decompressor through `Body_Encodes`, plus the functionality of that relation
  and the content-invariance of the CRC. Its proof body has no stored/fixed
  format branch.

The common stored/fixed relation is deliberately executable (not ghost): the
test suite runs the relation selected by the compressor, and C zlib
independently decodes every produced member back to the original bytes.

## Proof Status

The most recent recorded `gnatprove --level=4` run reported **5,857 checks,
all proved, no justifications, no assumptions**. This covers run-time
checks such as overflow, index, range, and division checks, plus
initialization, data dependencies, and termination checks — and the
functional contracts described above: the compressor's postcondition ties
its output to the decode model, and `Raw.Decompress` proves that every
`Status = OK` result satisfies the full model over the exact consumed input
and produced output. The decoder enforces this as a checked-refinement
boundary: after its optimized pass succeeds, an independent canonical model
validates the returned bytes; disagreement is a defined rejection. This is
functional correctness relative to the executable model, not a proof that
the model is RFC 1951. The proof also covers the M4 LZ77 contract: every validated
match used by the shipping decoder preserves the already-produced prefix
and appends bytes satisfying the back-reference window equation, including
the forward-copy overlap case. All recursion in the model and its lemmas is
proved terminating.

The full model independently reads block framing and dynamic headers, builds
canonical tables directly from code lengths, decodes codes bit by bit, and
checks literal and overlapping-match output. The differential suite tests this
trusted semantic base against C zlib. Container parsing beyond the raw DEFLATE
payload remains specified by its implementation contracts and runtime checksum
checks rather than a separate byte-level zlib/gzip/ZIP model.

Some proof-relevant structure:

- The bit reader's well-formedness (cursor within input, buffered bits
  backed by consumed bytes) travels through every pre/postcondition.
- Loop termination rests on the total bit position, which every path
  strictly increases.
- Masks and powers of two are concrete lookup tables instead of
  variable-exponent arithmetic.
- The local dynamic-Huffman builder selects every nonzero-frequency symbol,
  adds dummy leaves only for zero/one-symbol alphabets, and constructs a
  balanced complete tree. Its contract proves every selected symbol receives
  a code, all lengths are at most nine (stronger than DEFLATE's limit of
  fifteen), and the scaled Kraft sum is exactly complete. The resulting
  canonical book feeds the same proved payload serializer as the fixed book;
  the focused runtime harness exercises that path. The local header serializer
  emits exact `HLIT`, `HDIST`, and `HCLEN` fields, a complete code-length
  alphabet, and all reconstructed literal/length and distance lengths. Its
  body relation composes that header with the shared payload without making an
  optimality claim or adding a top-level gzip branch. Header-recovery functions
  rebuild both exact canonical records from the transmitted lengths, and the
  local relation is proved equivalent when those recovered books replace the
  serializer's explicit witnesses.
- The shared payload contract states exact bit consumption, the code selected
  for every reached token boundary, the end-of-block code, and preservation of
  every bit outside the returned half-open interval. Fixed and dynamic adapters
  therefore share the concrete writer and its framing proof.
- `Inflate.Bodies.Body_Encodes` hides the stored/fixed choice from the raw,
  gzip, and theorem layers. Its proved introduction, framing, recognition, and
  functionality lemmas replace the former member predicates and the duplicated
  format branches in `GZip_Round_Trip`. The local dynamic relation now has the
  required witness-free three-argument shape, but is not yet a case of this
  boundary; input-side recognition and cross-format functionality remain to be
  connected.
- The full model deliberately does not reuse the shipping Huffman table or
  fast map. Its canonical table builder and parser prove 685 checks in the
  focused model unit; the shipping decoder calls the model only after an
  otherwise successful decode.
- Two table-internal bounds that would need ghost summation to prove
  as invariants are handled as defensive checks instead. If reached, those
  paths return a defined error status. (`spikes/m2_kraft/` since proved,
  in isolation, that both checks are dead code — the ghost-summation and
  Kraft-equality lemmas discharge at `--level=2`; porting that proof into
  the library is part of the `compression.md` ladder.)
- The compressor emits blocks back to front: the decode-model relation
  recurses front to back over the remaining stream, so a backward loop
  makes each iteration exactly one unfolding of the relation and the
  loop invariant is the relation itself on the already-written tail.
- The decoder must walk forward, so its invariant uses a separate
  non-final-prefix relation, extended per block by a snoc lemma and
  closed against the final block by a composition lemma; a destructor
  lemma unfolds the input-side stream walk one block at a time.
- The CRC table is proved to cache eight direct reflected polynomial-division
  steps for each byte, and the optimized update loop is proved equal to a
  ghost fold over that table-independent model. The CRC's content-invariance
  (equal byte sequences from any state give equal CRCs) is proved against the
  same fold, whose recursion is as deep as the data.
- Adler-32 uses a modulus-65521 type for its two running sums and folds a
  direct byte-step model over the input. Its public `Update` postcondition
  exposes that fold, so zlib checksum verification is connected to the
  standard running-sums definition rather than only to an opaque checksum
  computation.
- Evaluating the proof machinery — ghost buffer snapshots, recursive
  lemmas, invariants that re-walk the model relation — costs time
  proportional to the data, which can make assertion-enabled executables
  quadratic or exhaust the stack. `debug.adc` therefore makes proof contracts
  non-executable and prevents source-local assertion policies from re-enabling
  them; GNATprove still proves the contracts in its normal release-mode proof
  build. The shipping decoder independently invokes the iterative full model
  before returning `Status = OK`, so the differential suite still exercises
  that semantic boundary on every successful stream.

Agreement with RFC 1951 and third-party implementations remains test evidence,
not a theorem: the test suite compares model-validated output against zlib and
checks rejection behavior on malformed inputs. Container checksums are also
checked at run time.

## Testing

`tests/run_tests.py` generates **6445 cases** and runs them through the debug
harness with language run-time checks enabled and proof contracts disabled;
the expected verdict comes from C zlib (Python's binding) on the same bytes,
so the suite is a differential test, not a self-test:

- Canterbury corpus plus synthetic extremes (incompressible, constant,
  empty), compressed at levels 0/1/6/9, window sizes 9/12/15, and all five
  encoder strategies, as raw/zlib/gzip — output compared byte-for-byte,
  `Consumed` compared exactly.
- All 32 gzip flag combinations (hand-built headers), multi-member files,
  corrupted CRCs/lengths, truncations at every byte.
- Hand-crafted DEFLATE streams via a bit writer: reserved block type 3,
  bad stored-NLEN, over-subscribed and empty code-length codes, repeat
  codes before any length and past the end, reserved symbols 286/287 and
  30/31, distance-too-far, the legal one-code incomplete distance table.
- ~2000 single/multi-bit flips over valid streams and random garbage:
  whatever zlib accepts we must accept with identical bytes; whatever it
  rejects we must reject.
- ZIP: stored/deflated archives, directory entries, empty files, archive
  comments (including the maximal 65535-byte one), 200-entry archives,
  truncations, bit flips (robustness-only: zipfile's leniencies differ),
  ZIP64 markers, bzip2 method, encryption flag, corrupted CRCs.
- Compression: each corpus file is gzip-compressed by the crate, round
  tripped through the crate's own decoder, checked against the executable
  common-body relation, and independently decompressed by C zlib —
  byte-for-byte in both directions.

The recorded test run had zero failures and no escaping exception.

## Performance

The table below predates M5's mandatory canonical validation pass and is kept
only as historical fast-decoder data; it is not representative of current
end-to-end throughput. `bench/run_bench.py`, release build (`-O2 -gnatp`).
Reference: zlib 1.3.1,
`-O2`, same machine, same buffers, best of 30. Throughput is decompressed
output per second.

| Payload                    | this crate | zlib 1.3.1 | ratio |
|----------------------------|-----------:|-----------:|------:|
| Canterbury corpus, level 1 |   216 MB/s |   522 MB/s | 0.41× |
| Canterbury corpus, level 6 |   279 MB/s |   544 MB/s | 0.51× |
| Canterbury corpus, level 9 |   280 MB/s |   563 MB/s | 0.50× |
| alice29 ×20, level 9       |   223 MB/s |   396 MB/s | 0.56× |
| zeros 8 MB (ratio 1028×)   | 10.4 GB/s  |  0.62 GB/s | 16.7× |
| random 4 MB (stored)       | 44.7 GB/s  | 47.7 GB/s  | 0.94× |

The first version used bit-at-a-time decoding and ran at 12-15 MB/s on
text. The current version uses a 1024-entry one-level Huffman lookup over
the next 10 bits with bit-by-bit fallback, plus slice-assignment copies for
stored blocks and non-overlapping matches. The remaining text-payload gap
comes mainly from zlib's `inflate_fast` design, which keeps more state in
registers and uses fused tables for length, distance, and extra bits.

## Building

```sh
gprbuild -P inflate.gpr                  # release: -O2
gprbuild -P inflate_cli.gpr              # builds bin/inflate
gprbuild -P inflate.gpr -XMODE=debug     # language checks on; contracts off
gnatprove -P inflate.gpr --mode=all -j0 --timeout=30  # reproduce the proof
cd tests && gprbuild -P tests.gpr -XMODE=debug && python3 run_tests.py
cd bench && gprbuild -P bench.gpr && python3 run_bench.py   # needs libz.a
```

## Command line

The command-line front end reads and writes whole files, like the one-shot
library API. Compression produces a standard gzip member using fixed Huffman
coding with verified length-3 through length-10 matches at distances 1 through
4 (and the stored fallback above the fixed domain); decompression accepts
ordinary gzip files and concatenated members.

```sh
bin/inflate compress input.dat output.gz
bin/inflate decompress output.gz restored.dat
```

Run the focused CLI round-trip and compatibility checks with:

```sh
python3 tests/run_cli_tests.py
```

## Authorship

The code in this library was written with a coding agent.

## Scope and limitations

- **One-shot only.** Input and output are whole buffers; there is no
  streaming API. A streaming layer would wrap `Inflate.Raw` with a window
  buffer.
- Buffers are capped at `Integer'Last - 1` bytes (the index subtype leaves
  one position of headroom so end-cursors never overflow).
- zlib preset dictionaries (`FDICT`) are reported, not supported.
- ZIP: classic 32-bit format, methods stored and deflate. ZIP64,
  encryption, multi-disk and other methods are detected and reported as
  `ZIP_Unsupported`. Self-extracting archives (data prepended before the
  first local header) are not slid to.
- The decoder follows the tested reference implementations' acceptance
  rules (puff/zlib), including the deliberately incomplete fixed distance
  code and the one-code incomplete dynamic table.
