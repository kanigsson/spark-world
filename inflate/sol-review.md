# Review of `inflate`

## Verdict

The absence-of-run-time-errors proof and the stored-gzip round-trip theorem
are genuine. The project does not, however, prove full functional correctness
of its DEFLATE, zlib, gzip, or ZIP decoders. General decoding and external
format compatibility are supported by differential testing.

Most of that boundary is stated accurately in the README. The debug/release
artifact-separation and ZIP consistency issues identified by this review are
now resolved. The main remaining substantive gap is recursive executable
contracts that can exhaust the stack in checks-enabled builds.

## Findings

### 1. High (resolved): debug and release builds reused incompatible artifacts

`inflate.gpr` selects materially different compiler switches through `MODE`.
It previously used the same `obj/` and `lib/` directories for both modes:

- `inflate.gpr:11-20`
- `inflate.gpr:22-30`

After a forced release build, running the documented command with
`-XMODE=debug` did not recompile the library. The resulting test executable
continued to use the release library built with `-gnatp`, so contracts were
still disabled even though debug mode had been requested.

This could silently weaken the assertion-enabled test run. It could also work
in the other direction and contaminate performance measurements with debug
objects.

This is resolved: the project now derives mode-specific object and library
directories (`obj/debug`, `obj/release`, `lib/debug`, and `lib/release`) from
`MODE`. Both variants can coexist, and switching modes selects the matching
artifacts without requiring a forced or clean rebuild.

### 2. Medium: a checks-enabled build can overflow the stack on valid input

The implementation decoder is iterative, but the executable stored-block
model is recursive:

- `src/inflate-model.ads:41-67`
- `src/inflate-model.ads:85-133`

That model is referenced by public decoder postconditions:

- `src/inflate-raw.ads:48-69`
- `src/inflate-gzip.ads:73-98`

On this machine, a valid raw stream of roughly 32,768 empty stored blocks,
about 164 KB of input and zero bytes of output, raised `Storage_Error` in a
forced debug build. A forced release build decoded a much larger version of
the stream successfully.

This does not contradict SPARK's formal AoRTE result: stack and other resource
exhaustion are outside that claim. It does mean that the README's broad
statements that the library has no recursion and reports malformed input as a
status rather than an exception need to be qualified for assertion-enabled
builds. The reproducer is valid input, not malformed input.

### 3. Medium (resolved): ZIP consistency validation was incomplete

`Inflate.ZIP.Open` previously read the central-directory size from the EOCD but
only checked that the declared range fit before the EOCD.

The size was not retained in `Cursor`, iteration was not bounded by it, and the
entry count was not reconciled with it. A one-entry archive whose EOCD
central-directory size was changed to zero was still accepted and extracted.

The statement that `Entry_Info` need not be trusted because every field was
revalidated was also stronger than the implementation.

`Extract` validated bounds, the local signature, data placement, output size,
and CRC, but it could not link a caller-fabricated `Entry_Info` back to a
central-directory entry. It also did not reconcile the local fields relevant
to extraction with the central fields.

This is resolved. `Cursor` and `Entry_Info` are now opaque. The cursor retains
the declared central-directory bounds, `Next` cannot cross them, and the last
declared entry must end exactly at the declared limit. `Open` also rejects
entry counts that cannot fit in the declared size. `Extract` re-reads the EOCD
and central record carried by the opaque descriptor, then reconciles the local
flags, method, name, and (when there is no data descriptor) CRC and sizes.

Focused tests now reject inconsistent EOCD sizes/counts and mismatched local
metadata. A streaming ZIP case confirms that valid data-descriptor archives
remain accepted:

- `src/inflate-zip.ads:21-76`
- `src/inflate-zip.adb:110-216`
- `src/inflate-zip.adb:237-353`
- `tests/run_tests.py:442-560`

### 4. Medium: the formal round trip proves self-consistency, not RFC compliance

`Inflate.Model` covers only the stored-block fragment emitted by the
compressor:

- `src/inflate-model.ads:1-13`

The compressor is proved to emit bytes satisfying that relation, and the
decoder is proved to recover bytes satisfying the same relation. The
functionality lemma then establishes equality. This is a real end-to-end
theorem for the library's own compressor image.

The checksum argument similarly proves agreement through the library's own
CRC function. `CRC32.Fold` steps through the same generated table used by the
implementation; there is no separate polynomial specification proving that
the result is the standardized CRC-32:

- `src/inflate-crc32.ads:14-24`
- `src/inflate-crc32.adb:38-54`

Consequently, a shared wire-format or checksum mistake could satisfy the
formal round-trip theorem while failing an independent gzip implementation.
The tests against C zlib provide useful evidence against such a mistake, but
they are not a proof that every conforming gzip decoder accepts every output.

### 5. Low: some prose is stronger than the contracts

The gzip decoder contract proves that a correct stored-member trailer is
sufficient for `Status = OK`; it does not state the converse, despite prose
describing acceptance as "exactly when" the trailer matches:

- `src/inflate-gzip.ads:58-64`
- `src/inflate-gzip.ads:78-98`

Likewise, termination proofs do not establish the README's linear-complexity
claim. The code structure makes linear behavior plausible for normal release
execution, but no complexity bound is formalized.

Finally, `compression.md` includes a CLI in the M6a deliverable, but the current
repository supplies a library, test harness, and benchmark harness rather than
a user-facing compression/decompression command.

## What is actually proved

A current run of:

```sh
gnatprove -P inflate.gpr --mode=all -j0
```

completed successfully with 1,791 checks, all proved. The generated summary
reported zero `pragma Assume` statements for every analyzed unit, and the
source contains no proof justifications.

Subject to public preconditions, the proof establishes:

- language-level overflow, range, index, division, and related run-time checks;
- initialization and data-dependency properties;
- termination of analyzed loops, recursive model functions, and subprograms;
- input and output cursor bounds for all decoders;
- exact stored-compression size and compressor totality;
- the stored-block relation between compressor input and emitted body;
- stored-stream decode success, exact consumption and production, and
  agreement with the model when the decoded data fits the output buffer;
- gzip framing values used by the compressor, including the checksum computed
  by the library's CRC function and the input length;
- end-to-end restoration of the input by
  `Inflate.Theorems.GZip_Round_Trip` under its input-size and buffer-size
  preconditions.

The theorem's public postcondition exposes compressed size, restored size, and
byte equality (`src/inflate-theorems.ads:35-51`). `Status = OK` is a local
assertion proved in the theorem body (`src/inflate-theorems.adb:63-82`), rather
than an output of the theorem procedure.

The isolated Kraft spike also reproduced successfully:

```sh
gnatprove -P spikes/m2_kraft/m2_kraft.gpr --mode=all
```

It proved 138 checks. Those lemmas demonstrate the relevant histogram, prefix
sum, Kraft, and decoder-slot bounds in the spike, but are not integrated into
the shipping Huffman decoder. The shipping decoder still uses defensive error
branches for the difficult whole-table bounds.

The new M1 fast-table spike now also completes its isolated equivalence
result:

```sh
gnatprove -P spikes/m1_fast/m1_fast.gpr --mode=all
```

It proved 470 checks. For every histogram satisfying the spike's validity
predicate, `Build_Fast` now proves exact equality of all 1,024 table entries
with a recursive shortest-code-first reference lookup over the first ten
stream bits. The proof includes coverage as well as soundness: a zero table
entry means that no code of length at most ten matches. This result is still
isolated from `Inflate.Raw`, so it does not by itself establish equivalence of
the shipping `Decode_Fast` and `Decode` procedures.

## What is not proved

The formal result does not establish:

- functional correctness of general fixed- or dynamic-Huffman decoding;
- correctness of LZ77 back-reference output against an independent model;
- integration of the isolated fast-table equivalence proof into the shipping
  bit reader and Huffman decoder;
- zlib or ZIP byte-level functional semantics;
- rejection of every malformed or inconsistent stream;
- CRC-32 or Adler-32 equivalence to an independent mathematical standard;
- gzip/DEFLATE interoperability with arbitrary third-party implementations;
- time-complexity or stack-usage bounds;
- compiler, run-time library, prover, or hardware correctness;
- the recorded performance figures.

## Test evidence

After a forced debug rebuild, the full test suite completed with:

```text
generated 6442 cases
cases: 6442  failures: 0
compress differential: 16 cases, 0 failures
```

This is substantial evidence for general DEFLATE/zlib/gzip behavior, malformed
input handling over the generated corpus, and interoperability of the sampled
compressor outputs with C zlib. It remains finite testing rather than a proof
of the properties listed in the preceding section.

The performance benchmark was not rerun as part of this review.
