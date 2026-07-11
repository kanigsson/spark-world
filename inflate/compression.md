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
| M1 | Bit-reader functional model + Huffman decode equivalence | Medium | M0 | High |
| M2 | Canonical Huffman construction: prefix-free + complete (Kraft) | **Hard** | M1 | Medium — the crux |
| M3 | Huffman round-trip (encode/decode mutual inverse), standalone | Medium | M2 | High once M2 lands |
| M4 | LZ77 back-reference decode correctness (window model) | Medium | M1 | High |
| M5 | Full DEFLATE decode functional correctness vs ghost model | Medium | M1,M2,M4 | Medium |
| M6a | Stored-only compressor + full gzip round-trip + CLI | Medium | M1,M7 | High |
| M6 | Huffman/LZ77 compressor upgrade, same round-trip theorem | Medium–Hard | M2,M3,M4,M6a | Medium |
| M7 | CRC32/Adler32 = mathematical spec; container framing | Low | — | High |

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

### M4 — LZ77 back-reference decode
Window model: `output[i] = output[i - distance]`. The interesting case is
overlapping copies where `distance < length` (RLE-style) — the code already handles
the `Dist = 1` run and the general overlap loop; prove they realize the intended
byte relation. **Medium.**

### M5 — Full DEFLATE decode correctness
Assemble M1+M2+M4 against a ghost decode model over block framing. Carries the
spec-faithfulness caveat — trustworthy only up to the ghost model, so make the
ghost model executable and run it through the zlib differential suite (see the
mechanization section). **Medium once the pieces exist.**

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

**Current status: proof core complete, CLI pending.** The stored compressor,
executable relation, exact size/totality contracts, and full gzip round-trip
theorem are in the library. The repository still has no user-facing command;
the CLI bullet remains productization work rather than part of the proved core.

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

M1, the isolated M2 pressure test, M6a's stored-compressor/round-trip core, and
M7 are now complete. The remaining work naturally splits into proof depth and
productization:

1. **M3, standalone Huffman round-trip.** Reuse the proved canonical-table
   material from the M1/M2 spikes to establish the clean symbols-to-bits-to-symbols
   inverse before integrating more of the shipping decoder.
2. **M4, LZ77 back-reference semantics.** Model overlapping copies and connect
   the shipping output loop to that model; this is the other independent input
   needed by M5.
3. **Finish M6a productization.** The stored compressor and full gzip theorem
   exist, but the planned command-line wrapper does not. It remains an unproved
   I/O layer with buffer-growth, ceiling, argument, and exit-status behavior.
