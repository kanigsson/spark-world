# Review of `inflate`

## Verdict

The absence-of-run-time-errors proof and the stored-gzip round-trip theorem
are genuine. Successful raw DEFLATE results are now also proved to satisfy an
independent executable canonical model. This is functional correctness relative
to that model; RFC and external-format compatibility remain supported by
differential testing rather than a separately formalized wire specification.

Most of that boundary is stated accurately in the README. The debug/release
artifact-separation and ZIP consistency issues identified by this review are
now resolved. Project debug builds also disable proof-contract execution while
retaining language run-time checks, closing the recursive-contract stack issue.

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

### 2. Medium (resolved): a checks-enabled build could overflow the stack on valid input

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

This did not contradict SPARK's formal AoRTE result: stack and other resource
exhaustion are outside that claim. It meant that the README's broad statements
that the library had no recursion and reported malformed input as a status
rather than an exception needed qualification for assertion-enabled builds.
The reproducer was valid input, not malformed input.

This is resolved in the project debug path. `debug.adc` sets the assertion
policy to `Ignore` and ignores later source-local `Assertion_Policy` pragmas;
the library, CLI, and test projects use that configuration without `-gnata`.
Range, overflow, index, and other language run-time checks remain enabled. The
former 32,768-empty-block reproducer is now a permanent differential test and
completes without `Storage_Error`.

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

### 4. Medium (partially resolved): format semantics remain model-relative

`Inflate.Model` now also covers stored, fixed-Huffman, and dynamic-Huffman
foreign streams through `Is_Decoding`:

- `src/inflate-model.ads:1-13`

The full model independently parses block framing and dynamic headers, builds
canonical tables from code lengths, decodes symbols bit by bit, and checks
literal and LZ77 output. `Raw.Decompress` returns `OK` only when the optimized
decoder's exact result passes this model, and the public postcondition states
that fact. This resolves the earlier lack of a functional contract on general
DEFLATE output, but by runtime checked refinement rather than a static proof of
the fast decoder against the canonical parser.

The CRC-specific part of this finding is resolved. `Inflate.CRC32` now defines
a table-independent reflected GF(2) specification: one bit of polynomial
division using the standard generator, compositions for eight bits, and a byte
step. The table builder proves that every cached entry equals that direct byte
remainder, and the optimized update loop proves equality with a fold over the
polynomial step:

- `src/inflate-crc32.ads:14-108`
- `src/inflate-crc32.adb:18-124`

Thus a table-generation or table-lookup mistake cannot satisfy the proof merely
because the model repeats the same table walk. The remaining issue is the
compressor-image wire format: the fixed-Huffman and stored branches are
still composed through the library's own executable relations rather than an
independently formalized RFC semantics. A shared format mistake could satisfy the formal
round-trip theorem while failing an independent gzip implementation. The tests
against C zlib provide useful evidence against such a mistake, but they are not
a proof that every conforming gzip decoder accepts every output.

### 5. Low (partially resolved): some prose was stronger than the contracts

The gzip decoder contract proves that a correct stored-member trailer is
sufficient for `Status = OK`; it does not state the converse. The README now
uses that one-way wording instead of describing acceptance as "exactly when"
the trailer matches:

- `src/inflate-gzip.ads:58-64`
- `src/inflate-gzip.ads:78-98`

Likewise, termination proofs do not establish the project prose's
linear-complexity claim. The code structure makes linear behavior plausible
for normal release execution, but no complexity bound is formalized.

The earlier M6a productization gap is resolved: `inflate_cli.gpr` builds the
`bin/inflate` compression/decompression command, with end-to-end CLI tests in
`tests/run_cli_tests.py`.

## What is actually proved

A current run of:

```sh
gnatprove -P inflate.gpr --mode=all -j0 --timeout=30
```

completed successfully with 5,100 checks, all proved. The generated summary
reported zero `pragma Assume` statements for every analyzed unit, and the
source contains no proof justifications.

Subject to public preconditions, the proof establishes:

- language-level overflow, range, index, division, and related run-time checks;
- initialization and data-dependency properties;
- termination of analyzed loops, recursive model functions, and subprograms;
- input and output cursor bounds for all decoders;
- every successful raw DEFLATE result satisfies the executable full model over
  its exact consumed input and produced output;
- adaptive compressor totality and its exact selected-branch size within the
  public allocation bound;
- the fixed-Huffman relation, including boundary-based longest matches of
  length three through ten at distances one through four and their local M4
  window witness, or the stored-block relation between compressor input and
  emitted body;
- bounded dynamic-Huffman length construction: every nonzero-frequency symbol
  is assigned a code of length at most nine and the resulting code is complete
  by exact scaled Kraft equality, without an optimality claim;
- fixed and canonical encoder codebooks satisfy one ready/length/code boundary,
  and the shared token-payload writer emits the selected literal or match codes
  plus end-of-block at exact offsets while preserving bits outside its result;
- compressor-image decode success, exact consumption and production, and
  agreement with the selected relation when the decoded data fits the output;
- gzip framing values used by the compressor, including the input length and a
  checksum proved equal to the reflected polynomial CRC model;
- Adler-32 checksum computation as a byte-by-byte fold of the two direct
  modulus-65521 running sums used by zlib;
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

- static equivalence of the shipping fast decoder and canonical model without
  the runtime validation pass;
- integration of the isolated M1/M2 proofs into the shipping table builder;
- general or optimal LZ77 selection in the compressor: fixed-Huffman matching
  remains limited to lengths three through ten and distances one through four,
  without extra-bit length or distance codes;
- a serialized dynamic-Huffman block header or dynamic-Huffman output from the
  top-level compressor (only the local canonical-codebook payload path exists);
- zlib or ZIP byte-level functional semantics;
- rejection of every malformed or inconsistent stream;
- stored-DEFLATE, zlib, gzip, or ZIP wire semantics against an independently
  formalized format specification;
- gzip/DEFLATE interoperability with arbitrary third-party implementations;
- time-complexity or stack-usage bounds;
- compiler, run-time library, prover, or hardware correctness;
- the recorded performance figures.

## Test evidence

With language checks enabled and proof contracts disabled, the full debug test
suite completed successfully with:

```text
generated 6445 cases
cases: 6445  failures: 0
compress differential: 18 cases, 0 failures
```

This is substantial evidence for general DEFLATE/zlib/gzip behavior, malformed
input handling over the generated corpus, and interoperability of the sampled
compressor outputs with C zlib. It remains finite testing rather than a proof
of the properties listed in the preceding section.

The performance benchmark was not rerun as part of this review.
