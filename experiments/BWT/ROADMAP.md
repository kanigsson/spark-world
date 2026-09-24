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
- [ ] **Unify both transforms as a "cycle BWT".** Both sort the positions of a
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
  proved equal to the procedures.

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

## Tier 2: fast encoders (refinements, projects)

- [ ] **Prefix doubling over the successor permutation.** *Classical: done
  (2026-09-24).* `BWT.Doubling` ranks positions by their first H letters and
  doubles H with one stable counting sort per round (`Key_Sort`). It stops at
  H ≥ N, or as soon as all ranks differ. It is proved through
  `Classical_Rows_Unique` with no reference to the selection sort. At 1 KiB,
  classical encoding went from 7 ms to 18 s, depending on shape, down to
  0.02 to 0.09 ms. At 256 KiB it takes 12 ms (random) to 53 ms (a constant
  byte). The forced proof grew from 6¾ to 8 min. Bijective: not done.
  Original proposal: Rank positions by
  their first 2^k letters, from the pair (rank at length k, rank at length k
  of the position k steps on). The k-step jumps come from pointer doubling.
  With the "cycle BWT" framing, this covers both variants at once, and
  log₂(2N) rounds reach the horizon that `Extend_Equality` already justifies.
  It costs O(N log² N) with a proved merge sort, or O(N log N) with radix
  passes, and its invariant is much simpler than SA-IS's. This is the
  recommended first fast encoder. It need not wait for the cycle BWT: start
  with the classical transform, proved through `Classical_Rows_Unique`
  (produce a distinct, sorted arrangement of `Rotations_Of (S)`), then
  extend it to the bijective one through `Bijective_Rows_Unique`.
- [ ] **Proved merge sort** (or LSD radix sort on rank pairs) replacing
  selection sort. Doubling no longer needs it. Each round is one stable
  counting sort, because the previous order, shifted back by H, already sorts
  the second key. It remains a standalone refinement of `Sorting.Sort`.
- [ ] **Linear-time construction (later, optional).** SA-IS for the
  end-marker BWT. For the bijective BWT and eBWT, the method in Bannai,
  Kärkkäinen, Köppl and Piątkowski, *Constructing the bijective and the
  extended BWT in linear time* (CPM 2021, arXiv:1911.06985). Only worth it
  if the benchmarks show that doubling is the bottleneck.

## Tier 3: applications beyond compression

Listed roughly by payoff over effort. Each one names the specification to
prove first.

- [ ] **Canonical rotations of circular sequences (cheap, uses Duval
  directly).** The least rotation of S starts where the last Lyndon factor of
  S·S that begins inside the first copy of S begins. This gives a canonical
  key for circular data, such as plasmids, mitochondrial DNA and ring
  structures, and for de-duplicating rotations. Spec: `Least_Rotation (S)` is
  a rotation of S and ≤ every rotation. Most of the lemmas are already in `Words` and
  `Lyndon_Order`.
- [ ] **Backward search (FM-index "count").** Store the BWT plus the counting
  table C and a rank structure. Then the number of occurrences of a pattern
  P costs O(|P|) rank queries. This reuses the LF lemmas. What the cyclic
  transforms here give:
  - on the classical BWT, occurrences of P in *circular* S;
  - on the bijective BWT, occurrences in the ω-words of the Lyndon factors
    (Bannai et al., *Indexing the bijective BWT*, CPM 2019).

  Spec: `Count (Index, P)` = the number of rotations/rows whose infinite
  word has prefix P. Start with a naive rank (a scan), then sampled rank
  blocks as a refinement. An end-marker variant, for ordinary linear
  text, needs the generic alphabet from Tier 0.
- [ ] **Locate.** Sample the suffix array (every k-th row's position) and walk
  LF to the nearest sample. Spec: it returns exactly the positions that
  `Count` counts. It depends on backward search.
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
  and does not need Tier 1 or 2.

## Proof engineering

- [ ] A forced `make prove` takes about 8 min at `-j16` (2026-09-24, at
  `Max_Length` = 2**24, with the classical doubling; it was 3½ min at
  1,024). `Onto_Proofs` is 1,870
  lines. Record per-unit times with `--report=statistics`, so that
  regressions are visible.
- [ ] The generic alphabet and the cycle BWT will move lemmas between units.
  Carry the "quantify over positions, not offsets" and "opaque atoms"
  practices from PROOF.md into the new units from the start.
