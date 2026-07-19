# A Fully Proved DEFLATE/gzip Codec in SPARK — Milestone Plan

Summer project scoping. Starting point: the existing `inflate/` library is an
**AoRTE-only** proof of a DEFLATE/zlib/gzip/ZIP *decoder* (701 checks, `--level=2`,
no manual lemmas, no assumptions). The README is explicit that decoded bytes are
*tested* against C zlib, **not proved correct**. This plan layers functional
correctness and round-trip on top, and adds a validity-preserving compressor.

## Verdict

Ignoring time, this is **realistic with no fundamental blocker** — provided:

1. Correctness is anchored on **round-trip / identity** properties (spec-free)
   rather than "decode matches the RFC" (which smuggles a debatable spec into the
   trusted base), and
2. We never try to prove the compressor **optimal** — only that it produces
   **valid** output. Optimality is where scope explodes and buys round-trip nothing.

Everything in DEFLATE is finite-alphabet: no heap, no reals, no unbounded
quantifier alternation. It is "hard but bounded." The one place real proof-research
difficulty concentrates is the **canonical-Huffman completeness (Kraft) lemma** —
which is exactly the lemma the current AoRTE proof *deliberately dodged* with a
defensive runtime check (`followup.txt`: "offsets never exceed 288 … needs ghost
summation and induction lemmas"). That dodge is now the load-bearing proof.

## The reframe: two meanings of "proved"

- **Decode-matches-spec.** The spec of DEFLATE *is* essentially another decoder, so
  this collapses to "fast decoder agrees with my ghost reference decoder." Real
  value (catches fast-path bugs) but only as trustworthy as the ghost model.
- **Round-trip / identity: `Decompress(Compress(x)) = x`.** Spec-free — a
  self-contained property between two of our own programs, nothing debatable in the
  trusted base. **This is the target.**

Asymmetry to respect: `Decompress ∘ Compress = id` is true and provable; the other
direction `Compress ∘ Decompress = id` is **false** (encoding is not canonical) —
do not chase it. The DEFLATE decode quirks the README lists (deliberately-incomplete
fixed distance code, one-code incomplete tables) live *outside* the image of any
compressor we write, so they are outside the round-trip domain — ignorable for M6,
but must be modeled for full decode-correctness (M5).

Precision the eventual tool's claims must keep: the round-trip lemma is spec-free
and unconditional, but it says nothing about streams outside our compressor's
image. Decode correctness on *foreign* streams (someone else's `gzip -9` output)
is provable only relative to our ghost DEFLATE model (M5) — say so explicitly
rather than letting "fully proved" blur the two.

## How the round-trip theorem is mechanized

One ghost reference function `Decode_Model : Byte_Array → Byte_Array` (partial,
via a status) is the pivot for everything:

- `Compress` gets post `Decode_Model (Output (1 .. Produced)) = Input`,
- `Decompress` gets post `Status = OK ⟹ Output (1 .. Produced) = Decode_Model (Input)`,
- round-trip is then a trivial ghost lemma by transitivity.

Design decisions to make early:

- **The ghost model may recurse.** SPARK ghost functions can use recursion (with a
  termination measure) even though the library code has none — a recursive
  reference decoder is the natural shape; don't contort it into loops.
- **Executable ghost, tested spec.** Ghost code can be compiled and executed: run
  `Decode_Model` itself against the existing 6415-stream zlib differential suite.
  That converts "trustworthy only up to the ghost model" from a shrug into a
  tested claim, cheaply. The ghost model is the trusted base of M5 — keep it small
  and validate it.
- **Side conditions are part of the theorem.** The lemma holds only for *output
  buffer large enough* and *input under the size cap*. So M6/M6a also owe:
  - a proved **size bound** — `Compress` needs at most `Input'Length + overhead`
    bytes of output (easy for a stored-block base: ~5 bytes per 64 KiB + framing),
  - proved **totality** — `Status = OK` for *every* input given a big-enough
    buffer. Validity alone makes the theorem vacuous on inputs where `Compress`
    bails.

## Milestone ladder

| # | Milestone | Difficulty | Depends on | Confidence |
|---|-----------|-----------|-----------|-----------|
| M0 | AoRTE for inflate/DEFLATE/gz/zlib/zip | — (done) | — | done |
| M1 | Bit-reader functional model + Huffman decode equivalence | — (done) | M0 | done |
| M2 | Canonical Huffman construction: prefix-free + complete (Kraft) | — (done) | M1 | done |
| M3 | Huffman round-trip (encode/decode mutual inverse), standalone | — (done) | M2 | done |
| M4 | LZ77 back-reference decode correctness (window model) | — (done) | M1 | done |
| M5 | Full DEFLATE decode functional correctness vs ghost model | — (done) | M1,M2,M4 | done |
| M6a | Stored-only compressor + full gzip round-trip + CLI | — (done) | M1,M7 | done |
| M6 | Huffman/LZ77 compressor upgrade, same round-trip theorem | Medium–Hard | M2,M3,M4,M6a | Medium |
| M7 | CRC32/Adler32 = mathematical spec; container framing | — (done) | — | done |

Numbering is by topic, not by schedule. The recommended *order* is:
M1 → M7 → **M6a** (theorem + tool exist, end to end) — with **M2 pressure-tested
in parallel** — then M3, M4, M5, M6 as ratio/coverage upgrades that must
preserve the already-stated theorem.

### M1 — Bit reader + Huffman decode equivalence
Prove the fast 1024-entry table lookup returns the same symbol as a canonical
bit-by-bit walk of the code defined by the length array. The existing `First <= Code`
invariant already does much of the load-bearing work. **High confidence.**

### M2 — Canonical Huffman construction correctness ⬅ project crux
Prove that from a code-length histogram, the RFC 1951 §3.2.2 assignment yields a
code that is **prefix-free** and **complete** (Kraft equality). Requires ghost
summation over the length counts and induction. Tractable in SPARK (all finite) but
**this is where the "no manual lemmas" luxury ends** — expect ghost functions and
lemma procedures. If M2 discharges, everything downstream is careful work rather
than unknown feasibility. **Pressure-test this milestone early** (in parallel with
the M6a bootstrap) before committing the summer to the full ladder.

### M3 — Huffman round-trip (standalone) — the headline deliverable
A pure `symbols → bits → symbols` module over a code-length assignment, decoupled
from LZ77 and block framing. A finite-alphabet **prefix-code bijection**:
- encode injective ⟸ canonical code is prefix-free (from M2),
- decode inverts encode ⟸ per-length interval-containment,
- completeness (every bit pattern used) ⟸ Kraft equality (M2).

Cleanest, most self-contained, most defensible result in the plan. Land it first
after M2. **Directly answers "is Huffman round-trip realistic?" — yes, gated on M2.**

**Current status: complete as a standalone proved module.**
`spikes/m3_huffman` reuses M2's exact histogram and scaled-Kraft result to admit
only complete canonical codebooks, then proves an ordinary executable
`Round_Trip` procedure for every sequence of up to 32 symbols (480 encoded bits).
The encoder writes canonical code integers most-significant bit first; the
decoder consumes only the resulting bit buffer and bit count and recovers each
symbol through the canonical per-length interval and rank.  The original input
appears on the decode side only in ghost assertions, not in executable control
flow.  The proof includes the prefix-separation, code-prefix shortening,
rank-uniqueness, and sequence-framing lemmas needed to compose individual
codewords.  The complete M3/M2 project proves all 615 checks at `--level=2`;
the executable harness covers a mixed `0, 10, 110, 111` code, the RFC 1951 fixed
literal/length code over all 288 symbols, and the empty sequence.

The bound is deliberately a proof-harness capacity rather than a Huffman
limitation: the theorem is universal over every sequence fitting those buffers.
Lifting it for integration into M6 is a buffer/API generalization, not new
prefix-code mathematics.

### M4 — LZ77 back-reference decode
Window model: `output[i] = output[i - distance]`. The interesting case is
overlapping copies where `distance < length` (RLE-style) — the code already handles
the `Dist = 1` run and the general overlap loop; prove they realize the intended
byte relation. **Medium.**

**Current status: complete and connected to the shipping decoder.**
`Inflate.Model.Copies_Match` is the executable relation: it preserves the
already-produced prefix and states each appended byte as either a byte from
that prefix or an earlier byte from the same match. `Inflate.LZ77.Copy_Match`
implements and proves all three concrete paths — distance-one fill,
non-overlapping slice copy, and forward byte-by-byte overlap — and
`Inflate.Raw.Codes` now calls that proved primitive after validating length,
distance, and output capacity. Thus M4 is a contract on the code users run,
not only on a duplicate proof spike.

The focused primitive proves 117 checks at `--level=2`; its combined M4/model
project proves 515, and the full shipping library proves all 1,942 checks. The
debug differential quick suite passes 3,337 generated streams plus
16 compressor interoperability cases, while the focused executable checks the
three copy shapes directly. Quantified proof assertions are ignored in library
executables to avoid quadratic debug instrumentation; project debug builds
disable proof contracts while the small M4 harness evaluates the executable
relation explicitly.

### M5 — Full DEFLATE decode correctness
Assemble M1+M2+M4 against a ghost decode model over block framing. Carries the
spec-faithfulness caveat — trustworthy only up to the ghost model, so make the
ghost model executable and run it through the zlib differential suite (see the
mechanization section). **Medium once the pieces exist.**

**Current status: complete as checked refinement.** `Inflate.Model.Is_Decoding`
is an independent executable canonical parser for stored, fixed-Huffman, and
dynamic-Huffman blocks. It reads dynamic length RLE, builds its own canonical
tables directly from the transmitted lengths, decodes symbols bit by bit, and
validates literals and overlapping LZ77 matches against the returned output;
it does not reuse the shipping fast table. `Inflate.Raw.Decompress` retains
`Status = OK` only when that exact consumed/produced result satisfies the model,
and its public postcondition exposes the relation. Thus the proof is
unconditional for successful foreign DEFLATE streams but remains explicitly
relative to this executable model, not to RFC prose.

At that milestone, the focused model proved all 685 checks and the full library
proved all 2,242 checks at `--level=2`. The debug differential suite passed
6,443 generated/corpus cases plus 16 compressor interoperability cases, with
language checks enabled and proof contracts disabled. The ordinary
model path is iterative; the older recursive stored-only relations remain for
the M6a proof but are not executed by project debug builds.

### M6a — Stored-only compressor + gzip round-trip + CLI ⬅ the bootstrap
DEFLATE has a gift the ladder should exploit: **stored blocks** (type 00). A
compressor emitting only stored blocks is a *valid* DEFLATE compressor — ratio
~1.0, but every stock `gunzip` consumes its output — and its round-trip proof
needs **no Huffman theory at all**: decode correctness restricted to the stored
fragment, plus gzip framing and checksums (M7). Deliver here, early and
independently of M2:

- the round-trip theorem, stated once with its side conditions (size bound,
  totality — see the mechanization section), proved end to end through gzip;
- the actual command-line tool over it.

**Current status: complete.** The stored compressor, executable relation, exact
size/totality contracts, and full gzip round-trip theorem are in the library.
The `inflate` command now compresses to stored-block gzip, decompresses gzip
(including concatenated members), grows its output buffer on
`Output_Too_Small`, and has focused interoperability and failure-path tests.
As planned, this file-I/O and allocation wrapper remains outside the SPARK proof
boundary.

Payoff: every later milestone becomes a **ratio upgrade that must preserve an
already-stated theorem**, not a prerequisite for stating it. If M2 fights back
harder than expected, a proved codec still ships. The theorem statement, ghost
decode model, and CLI plumbing all get debugged on the easy fragment first.
**High confidence.**

### M6 — Huffman/LZ77 compressor upgrade, same theorem
Swap the stored-only emitter for fixed-Huffman, then dynamic-Huffman + LZ77,
re-establishing M6a's round-trip theorem each time. The compressor's **AoRTE is
genuinely new work** (comparable in effort to the decoder). The round-trip
*proof* is then composition: `Compress` emits bits the decode-model maps back to
`x`, and `Decompress = decode-model`, so transitivity closes it — it *reuses*
M2–M5, it does not avoid them.

**Scope discipline (the trap that would blow up the timeline):**
- Match finder needs only "every emitted (length, distance) is a real
  back-reference into already-emitted output" — a locally checkable property.
  Emit only verified matches; ratio suffers, proof does not.
- Tree builder needs only "complete prefix code, lengths ≤ 15" — **not**
  minimum-redundancy. Proving length-limiting *optimal* (package-merge) is a
  research project of its own and buys round-trip nothing.

**Current status: in progress, with a verified fixed-Huffman LZ77 slice, a
proved local dynamic-Huffman body serializer, and a common stored/fixed body
boundary.**
`Inflate.Fixed` emits and recognizes one final fixed-code block containing
literals, selected matches, and end-of-block. Its compression plan is now
explicit: `Selected_Token`, `Next_Position`, and `Token_Bit_Cost` operate only
at positions reached by the deterministic token-boundary relation. At any such
boundary the bounded finder examines distances one through four and selects the
longest verified match of length three through ten, preferring the smaller
distance on a tie. These fixed literal/length and distance symbols need no
extra bits, so every match remains a twelve-bit token. Every selected match
carries a local `Match_Applies` witness for the M4 window equation, and one
forward-copy primitive establishes that equation for all overlapping and
non-overlapping shapes in the specialized decoder. All other bytes remain
literals.

The arbitrary 32-symbol M3 harness bound remains gone: `Max_Input` is derived
from the largest stream whose bit offsets plus gzip trailer fit in `Natural`
(238,609,285 input bytes on the current target). The analyzer, executable
encoding relation, and decoded-prefix checker are iterative; proof-only
recursive relations and framing lemmas are erased from checks-enabled builds.
`Inflate.GZip.Compress` selects this fixed coding throughout that domain and
uses the stored encoder above it. `Inflate.Raw.Decompress` retains a proved
success path for the expanded image. `Inflate.Bodies.Body_Encodes` now hides
the selected stored/fixed format from `Inflate.Raw`, `Inflate.GZip`, and
`Inflate.Theorems`: its recognition, framing, and functionality lemmas replace
the former member predicates and `GZip_Round_Trip` has no format branch. Match
lengths requiring extra bits, wider distances, and top-level dynamic-block
selection remain open M6 ratio work. `Inflate.Dynamic.Build_Lengths` is the
completed local tree-building step: it includes every symbol with nonzero frequency,
adds dummy leaves only for the degenerate zero/one-symbol cases, and produces a
balanced complete code. For alphabets of 2 through 286 symbols its contract
proves that all used symbols receive a code, all lengths are at most nine, and
the Kraft sum is exactly one. The construction is intentionally not optimal.
`Inflate.Codebooks` provides
constant fixed books and checked canonical books through one `Ready`,
`Length_Of`, and `Code_Of` interface. `Inflate.Payload.Serialize` consumes that
interface and owns the shared literal, length/distance, and end-of-block writer,
including exact bit-count, semantic-encoding, and frame contracts. The fixed
compressor delegates to it, while `Inflate.Dynamic.Build_Codebook` and
`Serialize_Payload` exercise the canonical path. `Serialize_Header` now emits a
complete RFC 1951 dynamic header around those books. It deliberately transmits
all 286 literal/length and 30 distance lengths directly through a complete
four-bit code-length alphabet: the header is larger than an RLE-optimized one,
but its reconstruction proof has no repeat-code cases. `Header_Encodes` states
the exact header bits and reconstructed lengths, while the local
`Inflate.Dynamic.Is_Encoding` relation composes that header with the shared
payload. `Serialize_Body` establishes the relation without yet widening the
gzip compressor branch. No append-only logical-stream layer was needed: the
concrete header and payload writers retain explicit frame contracts.

The common body boundary currently contains exactly the two images selected by
the top-level compressor. The dynamic witness-erasure prerequisite is now
complete: `Literal_Book_From_Header` and `Distance_Book_From_Header` rebuild
exact canonical records from the 316 transmitted lengths, and
`Lemma_Encoding_Uses_Header_Books` proves that the serializer's explicit-book
relation implies the three-argument `Inflate.Dynamic.Is_Encoding (Body,
Consumed, Data)` relation. Codebook and payload congruence lemmas establish
that ready/coverage facts, canonical codes, token bit counts, payload bits, and
the produced size are unchanged by recovery. Two more common-boundary
prerequisites are now complete. `Inflate.Payload.Lemma_Payload_Frame` preserves
the shared payload relation across differently sized arrays, and
`Inflate.Dynamic.Lemma_Encoding_Frame` combines it with header recovery to
preserve the witness-free dynamic relation when a container adds trailing
bytes. `Inflate.Dynamic.Lemma_Encoding_Functional` proves that one such body
cannot denote two different byte sequences: canonical prefix separation and
rank uniqueness identify each literal/length and distance symbol, while the M4
window equation makes matching back-references functional. The final local
prerequisite is now complete as well: `Inflate.Dynamic.Analyze` recovers the
canonical books and walks the bounded payload from the input alone, while
`Lemma_Encoding_Analyzes` proves that every self-describing dynamic relation is
recognized with its exact encoded byte count and decoded length. The dynamic
alternative can therefore join `Body_Encodes`; the common wrapper only needs
to route recognition, framing, and functionality to these local results.

The focused dynamic project proves all 5,810 checks at `--level=4`; the full
library proves all 6,618 checks at `--level=4`, with no justifications or
assumptions.
The dynamic runtime harness covers empty, singleton, sparse, and full DEFLATE
alphabets, an exact shared-payload bit pattern, and a complete dynamic body that
round trips through the shipping decoder and its independent model. The
input-side analyzer reports its exact encoded and decoded sizes before and
after the body is copied into a differently bounded larger buffer with
unrelated trailing bytes; the shipping decoder also round trips that framing.
C zlib independently decodes the body. The complete debug suite passes 6,445
cases and 18 compressor differential cases, including exact bit-level checks
for length-ten matches at distances one, three, and four.

The planned token-trace reassessment against this broader baseline is also
complete. A `Step` relation would restate `One_Token_Matches`, while `Trace`
would restate `Prefix_Matches`; the current framing, extension, closing, and
functionality lemmas would still need the same recursive token cases.
`Spec_Walk` cannot be replaced by that data-semantic trace because the analyzer
computes validity and decoded length before an output array exists. Sharing
that recursion would require a second structural trace and a bridge, adding a
layer without deleting proof logic. The acceptance criterion in `abstract.md`
is therefore not met, no source refactor is retained, and the current boundary
proof remains the baseline for dynamic-Huffman work.

### M7 — Checksums as math
CRC32 = polynomial division mod the generator; Adler32 = the mod-65521 running
sums. Self-contained and very tractable. No longer a bonus at the end: M6a needs
gzip framing, so this lands early and makes container round-trip almost free.

**Current status: complete.** CRC-32 is connected to a table-independent
reflected GF(2) model: the public contracts define a bit step using the standard
generator, compose eight steps into a byte remainder, prove the elaborated table
caches those remainders, and prove the table-driven update equals a fold over the
polynomial model. The gzip compressor already pins down its fixed header and
little-endian trailer bytes in its postcondition. Adler-32 now uses a direct
modulus-65521 state and its public `Update` postcondition equates the result with
a byte-by-byte fold of the two standard running sums. The implementation uses
that direct step rather than the former 5,552-byte reduction batching; restoring
batching would be a performance optimization with a new congruence proof, not a
gap in the checksum specification.

## Format choice

- **Target gzip = DEFLATE + CRC32 + framing**, built on the existing `inflate`.
  Right ambition; M7 gives container round-trip cheaply.
- **Avoid bzip2.** Round-trip there rests on the **inverse-BWT bijection**
  (LF-mapping / stable-sort-of-rotations permutation argument) — materially harder
  than anything in DEFLATE, a research project in itself. Only pick it if proving
  BWT *is* the goal.
- **Go deep on one format, not shallow on many.** Formats share almost nothing at
  the proof layer (each has its own entropy coder), so "multiple formats" multiplies
  the M2-class work rather than amortizing it.

## Expectation reset

The current headline (`--level=2`, no ghost code, sub-second VCs) is a property of
*AoRTE*. From M2 onward expect: ghost functions, explicit lemma procedures, the
"true-but-not-inductive" invariant-strengthening trick (the followup notes two such
instances already), likely `--level=4` with manual assertion stepping, and possibly
Why3-adjacent grind. Still SPARK-tractable — budget for it.

## Functionality & interoperability (for the eventual tool)

- The proved core is a **pure library** (no OS, no I/O). The CLI is an **unproved
  I/O rind** (file → `Decompress` → file) with the syscalls outside the SPARK
  boundary by design — but it is more than 30 lines. The security posture below
  ("never size from ISIZE") plus the one-shot API means the decompress path needs
  a **retry-with-larger-buffer loop under a user-settable ceiling**; the compress
  path allocates from the proved size bound (mechanization section). Budget a
  real, if modest, chunk for `Output_Too_Small` handling, exit codes, and
  argument parsing — it is the part users touch.
- **Decompression interop: full.** gzip is gzip; differential-tested against C zlib
  on 6415 streams. Any normal `.gz` decodes byte-identically to `gunzip`. Caveats:
  one-shot/in-memory (no streaming), zlib preset dictionaries (FDICT) reported not
  supported, ZIP is classic 32-bit stored+deflate only.
- **Compression interop: full, at a ratio cost.** A DEFLATE decoder does not care how
  well you compressed — any *valid* stream decodes everywhere. So a
  provably-correct-but-non-optimal compressor still emits standard `.gz` that stock
  `gunzip`/browsers consume; it is just larger than `gzip -9`. Correctness, not ratio.

## Security posture (informs the "safe by construction" story)

- **Amplification bomb:** defused structurally — no allocator exists; output is a
  caller-sized buffer; overflow returns `Output_Too_Small` (proved
  `Produced <= Output'Length`). Caller sets the ceiling — **never size from ISIZE or
  the ZIP size field** (attacker-controlled, ISIZE is mod 2³²).
- **CPU/time bomb:** killed by **proved termination** — work is linear in
  input bits + output bytes, both capped. No backtracking.
- **ZIP huge-directory:** iterative walk, entry count bounded by input size
  (≥46 bytes/entry), **no recursion, no auto-descent** into nested archives.
- **Zip-slip:** library is immune (no filesystem I/O); path sanitization is the
  I/O wrapper's responsibility.
- **Malformed input:** no crash by proof (AoRTE) — every failure is a defined
  `Status_Type`.
- **Residual (design limit, not a hole):** one-shot means input + output are held in
  memory at once (input capped ~2 GB); enforce an input-size limit before loading.

## Current next moves

M1 through M5, M6a, and M7 are complete. M6 now has a verified fixed-Huffman
literal/match slice with the same full-domain gzip theorem, plus a proved
local dynamic header and body serializer. The remaining ratio work is:

1. **Extend `Body_Encodes` from stored/fixed to dynamic.** The common relation
   already replaced the format-specific branches in raw, gzip, and the theorem.
   Dynamic header recovery and the witness-free three-argument local relation
   are complete, as are container-style framing, input-side recognition, and
   local functionality. Route those proved consequences through the common
   relation without weakening it.
2. **Add the dynamic gzip branch.** Select the proved dynamic body locally and
   lift it through the existing framing, decoder-success, and round-trip proof.
