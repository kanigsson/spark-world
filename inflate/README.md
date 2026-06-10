# inflate - a DEFLATE / zlib / gzip / ZIP decoder in SPARK

A one-shot, no-heap decompression library: DEFLATE itself (RFC 1951), the
zlib (RFC 1950) and gzip (RFC 1952) containers with their checksums, and a
ZIP central-directory walker with per-entry extraction. The entire library
is SPARK. The current proof work is focused on absence of run-time errors,
with termination and initialization/data-flow checks included in the proof
run described below. Functional behavior is covered by differential tests
against C zlib on 6415 valid and invalid streams.

The library is meant for callers that need to parse compressed data from
untrusted input without dynamic allocation. There is no heap, no access
type, no recursion, no OS dependency, and no package state in the library.
Malformed input is reported as a status value instead of being handled by
raising an exception.

## Packages

| Package           | Contents |
|-------------------|----------|
| `Inflate`         | `Byte_Array`, the `Status_Type` all layers report through |
| `Inflate.Raw`     | DEFLATE (RFC 1951): stored/fixed/dynamic blocks, canonical Huffman decoding |
| `Inflate.ZLib`    | zlib container: header validation, Adler-32 verification |
| `Inflate.GZip`    | gzip container: all header features (EXTRA/NAME/COMMENT/HCRC), CRC-32 and length verification, multi-member `Decompress_All` |
| `Inflate.ZIP`     | ZIP archives: end-record lookup (comment scan-back), central-directory iteration, extraction with CRC/size verification |
| `Inflate.CRC32`   | CRC-32 (gzip/ZIP polynomial), table computed at elaboration |
| `Inflate.Adler32` | Adler-32 with the zlib batching bound |

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

## Proof Status

The most recent recorded `gnatprove --level=2` run reported **701 checks,
all proved, no justifications, no assumptions**. This covers run-time
checks such as overflow, index, range, and division checks, plus
initialization, data dependencies, and termination checks.

The proof is mainly about showing that the implementation does not raise
run-time errors when called within its contracts. It is not a proof that the
decoded bytes are the correct DEFLATE/zlib/gzip/ZIP result.

Some proof-relevant structure:

- The bit reader's well-formedness (cursor within input, buffered bits
  backed by consumed bytes) travels through every pre/postcondition.
- Loop termination rests on the total bit position, which every path
  strictly increases.
- Masks and powers of two are concrete lookup tables instead of
  variable-exponent arithmetic.
- Two table-internal bounds that would need ghost summation to prove
  as invariants are handled as defensive checks instead. If reached, those
  paths return a defined error status.

Functional correctness is tested, not proved. The test suite compares
accepted output against zlib and checks rejection behavior on malformed
inputs. Container checksums are also checked at run time.

## Testing

`tests/run_tests.py` generates **6415 cases** and runs them through the
harness built with all checks on (`-gnata`); the expected verdict comes
from C zlib (Python's binding) on the same bytes, so the suite is a
differential test, not a self-test:

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

The recorded test run had zero failures and no escaping exception.

## Performance

`bench/run_bench.py`, release build (`-O2 -gnatp`). Reference: zlib 1.3.1,
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
gprbuild -P inflate.gpr -XMODE=debug     # contracts as run-time assertions
gnatprove -P inflate.gpr --mode=all      # reproduce the proof
cd tests && gprbuild -P tests.gpr -XMODE=debug && python3 run_tests.py
cd bench && gprbuild -P bench.gpr && python3 run_bench.py   # needs libz.a
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
