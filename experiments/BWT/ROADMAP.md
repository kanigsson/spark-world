# Roadmap

From a proved reference to something applications can build on. bzip2-style
compression is deliberately out of scope: it is well trodden and needs only
the inverse, which is already proved.

The ordering follows one principle. A change that keeps today's contracts is a
*refinement*: the new code is proved equal to the reference, and the
theorems carry over unchanged. A change that widens the contracts is a
*project*: it reopens the proof. Do refinements first, and state each
project's specification before writing any of its code.

Unchecked items are proposals. None of them is needed for what is proved today.

## Tier 0: specification shape (do first; everything below depends on it)

- [x] **Export functional specifications.** `Is_Classical_BWT (S, Last,
  Primary)` and `Is_Bijective_BWT (S, Last)` in `BWT`, stated with sorted
  rotation tables and a Lyndon factorization in the periodic order, are the
  encoders' postconditions. `Classical_Rows_Unique` and
  `Bijective_Rows_Unique` show that any sorted arrangement of the same rows
  is the specified table, so a fast encoder is one theorem: "produces such
  an arrangement". The rotation vocabulary had to move into `BWT`, since a
  parent's contracts cannot name its children. Not done: a fast bijective
  encoder must still sort the rows of `Lyndon_Factors`, that is, Duval's
  table. Proving that any factorization meeting the spec is Duval's would
  need the converse of `Factorizations.Spec_Form`, plus `Unique`.
- [ ] **Unify both transforms as a "cycle BWT".** *Encoding side done:*
  `Doubling.Cycles` is the successor framing, and both encoders sort
  through it. The decoders, the LF lemma sets and the specifications are
  still separate. Both sort the positions of a
  string by the infinite word read along a successor permutation that is a
  union of cycles. The classical transform has one cycle of length N. The
  bijective one has one cycle per Lyndon factor. The extended BWT (Tier 3)
  has one cycle per input word. The code already works this way, through
  `Rotation` descriptors and `Letter`. Making the successor map explicit
  gives one sort, one LF lemma set and one decoder skeleton. Keep the
  existing theorems as corollaries.
- [ ] **Generic alphabet.** Several applications need symbols other than
  `Character`:
  - DNA over {A,C,G,T};
  - an end marker `$` outside the byte range, for the FM-index;
  - integer alphabets, for the reduced strings of recursive suffix sorting;
  - token sequences.

  Make the core generic over a discrete, totally ordered symbol type and an
  array type. Instantiate it for `Character` to keep today's API.
- [x] **Lift `Max_Length` to 2**24.** One real overflow: `Words.Shift_Back`
  multiplied a period count by a period, now bounded by `S'Length / P`. The
  tightest check, an invariant after `Decode_Order`'s inner loop, stopped
  proving under a full `-j16` load. That loop now exits after its invariants,
  so they describe the exit state. CVC5 and Z3 stopped proving three
  easy-looking checks (the `Bijective_Rows` post, a `Same_Rows_Trans`
  precondition in `Bijective_Rows_Unique`, a post of
  `Onto_Proofs.Get_Rows_Ctx`), even at level 4 with a minute each. Alt-Ergo
  proves them in under 130 steps, so it joined the prover list. Why the bound
  affects them is not understood. A forced proof now takes 6¾ min at `-j16`.
- [ ] **Lift `Max_Length` to 2**30.** `4 * Max_Length` must fit in
  `Integer`, so the horizons need `Long_Long_Integer`, or a bound of 2**28.
- [ ] **Caller-provided storage.** Unconstrained function results and local
  tables live on the secondary stack or the primary stack, which fails at
  large N. Add procedure forms with `out` buffers and a reusable workspace
  record, as `spark_re`'s `Matcher` does. Keep the functions as the spec,
  proved equal to the procedures. This is a usability problem, not only a
  speed one: with the default 8 MiB stack, the encoders raise `Storage_Error`
  from about 1 MiB, so `Max_Length` is only reachable with an unlimited stack.
  Peak memory is about 56 bytes per input byte, mostly 12-byte `Rotation`
  tables and fresh key arrays in every round.

## Tier 1: fast decoders (refinements, cheap)

- [x] **Counting-sort LF.** Counts, prefix sums and one stable pass, proved
  equal to `Rank` pointwise; the order and permutation posts come from the
  existing `Strict_Ranks`, in a ghost procedure the production build drops.
- [x] **Classical decode in O(N)** followed from the item above.
- [x] **`bench` target** (`make bench`, a production build). At 1,024 bytes
  on 2026-09-24, both decoders went from 1 to 3 ms to 4 to 6 µs. The
  encoders are the bottleneck: 7 ms on random bytes, but about 1 s (classical)
  and 6.6 s (bijective) on `abcabc...`, and 14 to 18 s on a single repeated
  byte. Selection sort makes O(N²) comparisons, each up to 2N letters long.
  Past the old bound, the decoders take 1.3 to 3.8 ms at 256 KiB and grow
  linearly. Classical encoding of random bytes is quadratic, at 1.8 s for
  16 KiB, and text at 4 KiB takes 1.7 s (classical) and 10 s (bijective).
  The "text" there is one 110-byte sentence repeated, which is much harder
  for doubling than real text.
- [x] **Pack each letter with its LF link** (classical decoder, 2026-09-25).
  With `Max_Length` = 2**24, an LF index fits in 24 bits, so one 32-bit word
  per row (`Pack`, `Next_Of`, `Letter_Of` in `BWT`'s body) makes each step of
  the walk miss once instead of twice. At 4 MiB the classical decoder went
  from 1.86× to 1.17× the time of `libsais_unbwt` (geometric mean over the
  public corpora; `dickens` 134 → 87 ms). At 1 MiB, where the arrays fit in
  the cache, the extra packing pass costs about 1 ms. The word must widen if
  `Max_Length` grows past 2**24. Open: `Decode_Order` could pack `Seen` with
  `Map` the same way; the bijective decoder is 1.25× Bannai et al.'s
  `unbbwt` at 4 MiB.

## Tier 2: fast encoders (refinements, projects)

- [x] **Prefix doubling over the successor permutation** (2026-09-24).
  `Doubling.Sorted_Rows` sorts any cycle table (`Doubling.Cycles`), so one
  proof covers both encoders. They are proved through `Classical_Rows_Unique`
  and `Bijective_Rows_Unique`, with no reference to the selection sort. Each
  round ranks positions by their first H letters and doubles H with one
  stable counting sort (`Key_Sort`). The previous order, shifted back by H,
  already sorts the second key. Jumps come from the factor table, H mod the
  factor length, rather than from pointer doubling. Doubling stops when H
  reaches twice the longest factor, or as soon as all ranks differ.
  O(n log n) time, O(n) space. At 1 KiB, encoding went from 7 ms to 18 s,
  depending on shape, down to 0.03 to 0.12 ms. At 256 KiB, classical
  encoding takes 14 to 64 ms and bijective 8 to 33 ms, against 1.5 to 3.5 ms
  for either decoder. Open performance points:
  - The classical transform could stop at H ≥ N (`Same_Length_Extend`)
    rather than 2N, saving one round on periodic input. A classical-only
    version was 15–25% faster at 256 KiB.
  - Each round declares six N-sized arrays on the stack. They are no longer
    zero-filled (`Relaxed_Initialization`), so declaring them costs nothing,
    but they still count against the stack. Buffers reused across rounds
    belong to "caller-provided storage" (Tier 0).
  - The ghost `Ranked` invariant is quadratic, which makes the `checks`
    build unusable beyond small inputs. That is expected, and `test-contracts`
    uses a small corpus.

  A performance review on 2026-09-25 (callgrind, and unproved prototypes
  checked against the proved encoders) gave the items below.
- [x] **Stop doubling when a round splits no class** (2026-09-25). When two
  rows have
  equal infinite words, the ranks never all differ, and the loop runs until
  H reaches twice the longest factor. That is 19 rounds instead of 1 for
  periodic or constant classical input at 256 KiB. On 16 MiB of random bytes,
  whose Lyndon factorization has two equal factors, bijective encoding took
  41.8 s against 4.4 s for classical. When a round splits nothing, equal
  prefixes of H letters extend to every horizon along the successor
  permutation, so the ranking is final. `Dense_Ranks` reports the split, and
  `Closed_Extend` proves the extension. Constant classical input now takes
  7.7 ms at 256 KiB, down from 62 ms, and 0.15 s at 4 MiB, down from 1.3 s.
  The 16 MiB random case now takes 7.8 s, down from 41.8 s.
- [x] **Benchmark realistic data at larger sizes** (2026-09-25). `SOURCE` is
  the repository's own tracked sources and documents (3.6 MB, so it stops at
  1 MiB unless `CORPUS=` names a larger file). The old `TEXT` is now
  `PROSE_LOOP`, and sizes go up to 4 MiB, with the stack limit lifted. At
  1 MiB, both encoders take 0.32 s on `SOURCE`, against 0.1 s on random
  bytes. In the prototype, source code at 4 MiB took about 1 µs per byte:
  long duplicated regions need 14 rounds.
- [x] **Public corpora and reference implementations** (2026-09-25).
  `make bench-corpora` times the four transforms on the corpora that
  suffix-sorting libraries are benchmarked on:
  - Silesia and Large Canterbury;
  - the Gauntlet, built to defeat suffix sorters;
  - Pizza&Chili DNA, proteins and repetitive collections;
  - bzip2's samples.

  `bench/fetch-corpora.sh` downloads them into `obj/corpora` and cuts 1 MiB
  and 4 MiB prefixes. They are never committed. A one-off comparison against
  libsais, bzip2's block sort and Bannai et al.'s linear-time BBWT
  (github.com/mmpiatkowski/bbwt) found byte-identical output on 57 inputs.
  Only the classical primary index differs on periodic input, where it
  depends on the tie order. The same run measured how much slower the
  encoders are, as a geometric mean:
  - classical: 8.7× at 1 MiB and 13× at 4 MiB, against the best of bzip2 and
    libsais on S·S; up to 59× on the Gauntlet's `abba`;
  - bijective: 4.7× and 8.5×, against Bannai et al.

  The gap is the log factor: 13–15 rounds on text and code at 4 MiB, 22 on
  Fibonacci strings. The reference drivers stay outside the repository.
  Measured and ruled out for the encoders:
  - SIMD: every round is gathers and scatters; AVX2 has no scatter, and its
    gather is no faster than scalar loads on Zen 2;
  - software prefetch: no gain, sometimes slower;
  - huge pages: no change;
  - 4-byte initial keys: saves 2 rounds, but costs as much;
  - threads: libsais itself gains only 1.2–1.5× from 16 threads.

  At 4 MiB a round is bound by DRAM latency, and even an unproved C port of
  today's algorithm is no faster than the proved code.
- [x] **Gauntlet `test3` is slow for the classical encoder** (2026-09-25). It is
  the round count. `test3` is a 16-bit little-endian counter, so its 1 MiB
  prefix is nearly periodic: classical doubling needs 20 rounds before all
  ranks differ, while the bijective transform stops after 7 rounds on
  repeated Lyndon factors. After the leaner round below, it takes 0.28 s
  classical (from 1.6 s) and 0.14 s bijective, against 0.08 s in libsais.
- [x] **A leaner doubling round** (2026-09-25). Ranks are now class heads,
  kept in SA order as runs (`Runs`), so each class's run in SA tells where
  its elements go: the counting sort became one slot pass and one scatter
  (`Slots`, proved with a pigeonhole lemma). The first key along the new
  order is read sequentially, `Back` needs no factor table for the
  classical transform and only a 4-byte start array for the bijective one,
  the table is read off SA when all ranks differ (`Read_Off`), and no array
  is zero-filled. Each random access has a loop of its own. Computing the
  slot and scattering in one loop made every store wait for a missing load,
  7× slower at 4 MiB. The expectation that nothing would help at 4 MiB was
  wrong: the reading of the factor table and the fused loops were the
  bottleneck, not DRAM. On the public corpora (geometric means, against the
  reference timings recorded on 2026-09-25):
  - classical: 2.1× faster at 1 MiB and 3.0× at 4 MiB; from 8.9× to 4.3×
    the best cyclic reference at 1 MiB, and from 14× to 4.7× at 4 MiB;
  - bijective: 1.8× and 2.5× faster; from 5.0× to 2.7× Bannai et al. at
    1 MiB, and from 9.0× to 3.6× at 4 MiB.

  At 4 MiB a round now takes about 95 ms for 4 M elements (classical), in
  six random-access passes. `Initial` (about 100 ms at 4 MiB) and the
  bijective `Back` (24 ms a round, for its start-array reads) are the next
  constant factors.
- [ ] **Less fixed overhead around the rounds.** Done: when the ranks end up
  distinct, the rows are `F (SA (I))` with no second sort (`Read_Off`), and
  the last column is read without a division (`Rotations.Last_Letter`).
  Since 2026-09-25 (at 4 MiB):
  - `Initial` sorts the first letter with `Ranks.LF`, and no longer builds
    three N-sized arrays of its own: from about 97 ms to 48 ms.
  - With a single factor, `Read_Off` builds each row without reading the
    factor table (from 37 ms to 5 ms), and the second keys of a round are
    two block copies of the ranks.

  Open: the classical encoder still builds a 12-byte rotation table
  (`Initial_Rows`, about 20 ms) only to hand it to `Sorted_Rows`. Reading
  the last column from SA directly would need `Sorted_Rows` to return SA,
  with the table kept ghost; `Classical_Rows_Unique` and the matrix lemmas
  are phrased over the table.
- [x] **Skip settled groups** (Larsson–Sadakane, 2026-09-25). Once at most
  a quarter of the rows are unsettled, `Sparse_Double` replaces the global
  round. It has the same contract, so nothing downstream changed. It sorts
  each class that still holds several rows by its second key, in place in
  SA, with a proved introsort (quicksort, heapsort after too many
  partitions, insertion sort for short ranges). All the second keys of a
  round are read before any rank changes, so the round goes from exactly H
  letters to 2H. Larsson and Sadakane update ranks in place, which mixes
  horizons and would have needed a new `Ranked`. A `Skip` array lets both
  scans jump over stretches of settled rows, so a late round costs well
  under 1 ms at 4 MiB instead of two full scans (10 ms). Switching when a
  quarter, an eighth or a sixteenth of the rows are unsettled measured
  within noise on text, and the later switches were up to 50% slower on
  `mozilla`. The worst case is now O(n log² n): a sparse round sorts up to
  n/2 rows by comparison.

  On the public corpora (geometric means, against the same reference
  timings as below), together with the fixed-overhead items above:
  - classical: from 4.3× to 2.7× the best cyclic reference at 1 MiB, and
    from 4.7× to 2.6× at 4 MiB; 1.4–2.2× on real text at 4 MiB, and faster
    than libsais on `x-ray`;
  - bijective: from 2.7× to 1.9× Bannai et al. at 1 MiB, and from 3.6× to
    2.2× at 4 MiB; on par or faster on `dna`, `sao`, `x-ray` and `ooffice`
    at 1 MiB.

  As predicted, the Gauntlet (Fibonacci strings, `fss`, `abba`,
  `book1x20`) gains nothing from this and stays 5–9× behind: nearly every
  row stays unsettled until the last rounds.
- [ ] **Proved merge sort** (or LSD radix sort on rank pairs) replacing
  selection sort. Doubling no longer needs it. Each round is one stable
  counting sort, because the previous order, shifted back by H, already sorts
  the second key. It remains a standalone refinement of `Sorting.Sort`.
- [ ] **Linear-time construction (later, optional).** After doubling,
  encoders are 5–20× slower than decoders at 256 KiB, and within a factor of
  log n of linear. SA-IS for the
  end-marker BWT. For the bijective BWT and eBWT, the method in Bannai,
  Kärkkäinen, Köppl and Piątkowski, *Constructing the bijective and the
  extended BWT in linear time* (CPM 2021, arXiv:1911.06985). Only worth it
  if the benchmarks show that doubling is the bottleneck. Try skipping
  settled groups first. Done: that brought real text to within about 2× of
  the references. What is left is the Gauntlet, 5–9× behind, and only a
  linear-time construction closes that gap. At 4 MiB libsais takes 20–30 ns
  per byte, and even the untuned linear BBWT is up to 9.6× faster than
  doubling on the Gauntlet (it was 2.4–38× before settled groups were
  skipped). Bannai et al.'s
  circular SA-IS would cover the bijective transform and the eBWT with one
  proof, which fits the cycle BWT of Tier 0. The classical transform could
  use the same circular sort, or SA-IS with the end marker from the generic
  alphabet.

## Tier 3: applications beyond compression

Listed roughly by payoff over effort. Each one names the specification to
prove first.

- [x] **Canonical rotations of circular sequences** (2026-09-25).
  `Circular.Least_Rotation (S)` returns the earliest offset of a least
  rotation (`Is_Least_Rotation`), and `Circular.Canonical (S)` returns that
  rotation. It is a canonical key for circular data, such as plasmids,
  mitochondrial DNA and ring structures, and for de-duplicating rotations.
  The roadmap proposed Duval on S·S. The two-candidate search (a mismatch
  after K equal letters rules out K + 1 offsets) is linear with constant
  space and proves from `Rotations` alone, so it was used instead. At
  256 KiB it takes 0.4 to 1 ms, about as long as a decoder. Open:
  - State and prove that `Canonical` is invariant under rotation, and that
    equal canonical forms mean rotations of each other. `make test` checks
    the first on every test input.
- [x] **Backward search (FM-index "count")** (2026-09-24). Store the BWT
  plus the counting table C and a rank structure. Then the number of
  occurrences of a pattern P costs O(|P|) rank queries, reusing the LF
  lemmas. Spec: `Count (Index, P)` = the number of rotations/rows whose
  infinite word has prefix P. `Search.Count` uses a naive rank, and is proved
  through `Count_Rows` for any sorted cycle table, with the classical and
  bijective corollaries. `FM_Index` adds rank checkpoints every 256 rows, and
  its `Count` is proved equal. On 256 KiB of text, one count of a 17-letter
  pattern takes 0.47 µs, against 2.5 ms with the scanned rank. Building the
  index takes 0.46 ms. What the cyclic transforms here give:
  - on the classical BWT, occurrences of P in *circular* S;
  - on the bijective BWT, occurrences in the ω-words of the Lyndon factors
    (Bannai et al., *Indexing the bijective BWT*, CPM 2019).
- [ ] **End-marker backward search**, for ordinary linear text. It needs the
  generic alphabet from Tier 0.
- [x] **Locate** (2026-09-24). Sample the suffix array (every k-th row's
  position) and walk LF to the nearest sample. Spec: it returns exactly the
  positions that `Count` counts. `Locate.Locate` is proved (`Locate_Rows`) on
  any sorted cycle table where LF is exact. That covers the bijective table,
  and the classical one for primitive S.
- [ ] **Locate, remaining work.**
  - Bit-packed sample flags, since they now take one byte per row.
  - A benchmark.
  - A classical locate for periodic S, which needs the end marker.
- [ ] **Extended BWT of a string collection** (Mantaci, Restivo, Rosone and
  Sciortino). It sorts all rotations of a *multiset* of words by ω-order.
  It is used for collections of reads, metagenomics and comparing sequence
  sets. The bijective machinery is almost this already: replace Duval's
  blocks with caller-given blocks, and require each word to be primitive
  (or handle powers). Spec, following Gessel–Reutenauer: decoding returns the
  multiset of conjugacy classes (necklaces), each as its Lyndon rotation.
  The existing `Onto_Proofs` block recovery is the core of that proof.
- [ ] **De Bruijn / necklace generation.** Applying the inverse eBWT to
  particular sorted words yields de Bruijn sequences (Higgins,
  *Burrows-Wheeler transformations and de Bruijn words*, arXiv:1901.08392).
  The same holds for the FKM concatenation of Lyndon words. A proved
  generator gives test-pattern generation and covering sequences. Spec:
  every word of length k over σ occurs exactly once, circularly.
- [ ] **A bijective compression pipeline.** BBWT → move-to-front → a bijective
  entropy stage, with *every* stage proved bijective, so that every byte
  string decodes. This is Scott's motivation of compressing before
  encryption without format redundancy. MTF is an easy bijection. A bijective
  entropy coder is the research part: the known ones are Scott's bijective
  arithmetic coding and bijective Huffman variants. The novelty is the
  end-to-end surjectivity theorem, which nobody states for real compressors.
- [ ] **Reference oracle for external implementations.** Differential-test
  existing BWT and BBWT libraries against the proved reference, on
  exhaustive small inputs and random larger ones. Candidates are
  libdivsufsort, sais and published BBWT code. This is cheap, useful now,
  and does not need Tier 1 or 2. Done once by hand on 2026-09-25 against
  libsais, bzip2 and Bannai et al.'s BBWT, on the public corpora (see
  "Public corpora and reference implementations"). All matched. What
  remains is an automated, repeatable harness, including exhaustive small
  inputs.

## Proof engineering

- [ ] A forced `make prove` takes about 8½ min at `-j16` (2026-09-24, at
  `Max_Length` = 2**24, with prefix doubling for both encoders; it was 3½ min
  at 1,024). `Doubling` alone took about 1 min; with the leaner round
  (1,474 checks) it takes 4½ min from scratch at `-j16` under a parallel
  load (2026-09-25). `Onto_Proofs` is 1,870
  lines. Record per-unit times with `--report=statistics`, so that
  regressions are visible.
- [ ] The generic alphabet and the cycle BWT will move lemmas between units.
  Carry the "quantify over positions, not offsets" and "opaque atoms"
  practices from PROOF.md into the new units from the start.
