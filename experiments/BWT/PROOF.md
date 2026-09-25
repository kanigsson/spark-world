# How the inverse laws are proved

The three procedures in `BWT.Theorems` are proved for **every** supported byte
string. Nothing is assumed, imported or justified, and no check is silenced.
Duplicate bytes, periodic inputs and repeated Lyndon factors are all covered.
The bijective laws are proved in `BWT`'s body, where the implementation is
visible, through two ghost procedures in its private part. `BWT.Theorems` only
calls them.

## Functional specifications

`BWT` states what each encoder computes, not only that it inverts.
`Is_Classical_BWT` and `Is_Bijective_BWT` read the last column of a sorted
rotation table, and the encoders' postconditions assert them. The tables are
ghost functions characterised by their postconditions: `Classical_Rows` sorts
`Rotations_Of (S)` with earlier starts first, and `Bijective_Rows` sorts the
rotations of `Lyndon_Factors (S)` with later starts first. The factorization
is stated in the periodic order alone: each factor precedes its other
rotations, and factors never increase. `Factorizations.Spec_Form` derives
that from Duval's `Factorization`, through `Lyndon_Least` and `Lyndon_Omega`.

`Classical_Rows_Unique` and `Bijective_Rows_Unique` show that the tables are
determined: any distinct, sorted arrangement of the same rows is the table.
Both reduce to `Sorting.Sorted_Unique`. A faster encoder is therefore proved
by producing such an arrangement, without reference to the selection sort.

The rotation vocabulary (`Rotation`, `Letter`, `LE`, `Key_LE`, `Sorted`, ...)
lives in `BWT` itself, because a parent's postconditions cannot name its
children's declarations. `Rotations` and `Sorting` keep the lemmas.

## Shared machinery

- `Rotations`: a rotation is a descriptor `(First, Length, Offset)` into the
  input, read periodically. `LE` and `Equal_Prefix` compare two rotations'
  periodic words up to a horizon. The sort uses `2 * N`, which
  `Extend_Equality` shows is enough. `Key_LE` breaks ties between equal
  words by start position, in either direction (`Tie_Order`).
- `Ranks`: `LF` is the stable rank of each last letter, computed by a
  counting sort and proved equal to `Rank` pointwise. It is a permutation
  and it orders rows as `Ordered` does. `Walk` is the LF orbit that the
  classical decoder follows.
- `Sorting`: selection sort, which yields a key-sorted permutation of its
  input, and the uniqueness of such permutations. It now only defines the
  specified tables; no encoder runs it.
- `Key_Sort`: LF's counting sort over integer keys `0 .. Buckets - 1`, with
  the same proof: each element's place is its stable rank, so places form a
  permutation ordered as (key, position). Doubling uses it for the first
  letter and for the final pass when ranks tie; the rounds place elements
  from class runs instead.

## Encoding by prefix doubling

Both encoders build their tables with `Doubling.Sorted_Rows`. It sorts any
*cycle table*: row P is the rotation, starting at P, of the factor that
contains P. `Doubling.Cycles` states this, in the same words as the first
part of `Lyndon_Factorization`. The classical table is one factor of length
N, from `Initial_Rows`. The bijective one is the Lyndon factors, from
Duval. `Classical_Rows_Unique`, and the same two lemmas in
`Bijective.Encode`, then show that the result is the specified table. The
proof never mentions the selection sort.

The invariant is `Ranked (S, F, R, H)`: for every pair of positions,
`R (A) <= R (B)` is `LE` over H letters of their rows, and `R (A) = R (B)` is
`Equal_Prefix` over H letters. A round goes from H to 2H.

- `Rotations.Skip_Split` says that comparing H + M letters means comparing H
  letters, then M letters of the rotations skipped by H. `Skip` reduces the
  offset modulo the factor length, so H may exceed a short factor. The row
  of `Jump (P, H)` is `Skip (F (P), H)`. So the pair (rank, rank of the
  jump) in lexicographic order is `LE` at 2H (`Double_Pair`).
- Sorting by pairs takes one stable pass per round. The previous order,
  with every position moved back by H (`Back`, proved through
  `Skip_Unskip`), is already sorted by the second key. A stable sort by the
  first key therefore sorts by the pair.
- Ranks are class heads: a row's rank is the number of rows in lower
  classes. `V` holds the ranks in the order of SA, and `Runs (V)` states
  the shape: V never decreases, and `V (P) < P` with `V (V (P) + 1) = V (P)`,
  so the run of rank C starts at C + 1. The stable pass (`Slots`) therefore
  needs no counting pass: each element goes to the next free place of its
  class's run. `Next_Free` shows that place stays inside the run. If the
  run were full, its owners and the element to place would be more
  elements of that class than the run has places, and `No_Injection` (a
  pigeonhole argument from `Permutations.Inverse`) rules that out. The
  scatter keeps every place in its old class, so V stays valid for the new
  SA.
- `Dense_Runs` numbers the classes of equal pairs as runs, in place along
  SA. Its loop keeps the pairwise fact "ranks compare as pairs" for the
  prefix it has numbered. If there are N classes, `V (P) = P - 1`, the ranks
  are distinct, and `Read_Off` lays the table out as `F (SA (P))`. `Spread`
  writes the new ranks back to positions.
- The round keeps each random access in a loop of its own (moving back,
  gathering the first key, finding slots, scattering, gathering the second
  key, spreading ranks). A slot and its scatter in one loop made each store
  wait for a cache-missing load, which was 7 times slower at 4 MiB.
  `Back` reads no factor table in the classical case (`Back_Single`), and
  only a 4-byte start array when the position is at least H letters into
  its factor (`Back_Inside`).
- The loop stops when H reaches twice the longest factor or the ranks are
  distinct. `Rotations.Settled` lifts either case to the horizon 2N. Past
  both periods, equal prefixes stay equal (`Extend_Equality`). A mismatch
  decides every longer horizon, and it cannot lie beyond both periods.
- The loop also stops after a round that splits no class. `Dense_Runs`
  reports whether some class of first keys met two second keys. If none
  did, rows that agree on H letters still agree on H letters after H more
  (`Closed`). `Closed_Extend` then walks along the cycles, H letters at a
  time, to any horizon. Without this case, input whose rows have equal
  words (periodic input, or repeated Lyndon factors) would run until H
  reaches twice the longest factor.
- After the loop, when some ranks are equal, `Lay_Out` sorts once more by
  (rank, position), with positions reversed for `Later_First`. That order is
  `Key_LE`.

Only the final pass needs the tie order. The rounds may leave equal ranks in
any order. `Reduce` is a division-free `mod` for arguments below twice the
modulus, which is nearly every call. Without it the classical encoder ran
about twice as slowly.

## Backward search

`Search.Count (Last, P)` is the FM-index count. It reads P backwards and
keeps two row bounds, `Lo` and `Hi`. Each letter C moves a bound T to the
number of rows whose last letter is below C, or is C at a row up to T. Its
contract is `Bound`, which is that recursion stated on `Last` alone.
`Count_Rows` proves it exact for the last column of any sorted cycle table.
`Classical_Count` and `Bijective_Count` instantiate it, because both
specified tables are such rows (`Doubling.Cycles`).

The invariant (`Characterized`) says that, after reading P (J .. M), row I is
at most the strict bound exactly when its first M - J + 1 letters are below
that part of P, and at most the other bound when they are at most it.
`Below_Pattern` defines both orders from the front, one letter and then
`Next_Rot`, which matches how a backward step prepends a letter.

- A step is two counts over a renumbering (`Count_Perm`). Numbered by the
  position its row starts at, a row satisfies the new condition exactly when
  its predecessor rotation satisfies the step's condition. That uses
  `Shift_Letter`: the last letter of a row is the first letter of the
  rotation before it. So the step's count is the number of rows below the
  longer pattern. Positions are a permutation because rows are distinct
  rotations of a cycle table (`Rows_At`), and `Prev_Pos` is one because
  `Next_Pos` undoes it.
- Sorted rows below a bound form a prefix of the table (`Mono`,
  `Prefix_Set`). That turns the count back into a bound on row indices.
- At the end, rows between the bounds are those whose words start with P
  (`Exact`). There are `Hi - Lo` of them, and renumbering by position counts
  `Occurrences`.

Patterns up to 2N letters are covered, the horizon at which rows are sorted.
The rank is a scan of the column, so a count costs O(|P| · N).

`FM_Index` is a refinement of `Count`. It stores the column, how many letters
sort below each letter, and the letter counts at every 256th row. Its
`Count` is proved equal to `Search.Count` (`Step_Split` splits a backward step
into those two counts), so the theorems above carry over unchanged.

## Locate

`Locate` reports the positions of the rows backward search finds. Rows are
sampled where their offset in the factor is a multiple of `Rate` (32), so
factor starts are sampled. Any other row follows LF (`FM_Index.LF`, proved
equal to `Walk (Last, Row, 1)` through `Walk_Once`) until it reaches a
sampled row, and adds the steps taken (`Resolve`).

`Locate_Rows` needs LF to be exact: `Rows (Walk (Last, K, 1)) = Previous
(Rows (K))`. Then each step lowers the offset by one without wrapping, so the
walk ends within `Rate - 1` steps at the row's own position
(`Resolve_Exact`). `Search.Matching_Rows` identifies the rows found, and
`Count_Rows` counts them. The result lists every occurrence once
(`Reports`). Exactness comes from `Bijective_LF_Exact`, exported from
`Bijective_Proofs.Exact_LF`, and from `Classical_LF_Exact` for a primitive S.
For a periodic S, classical LF cannot be exact.

## Least rotation

`Circular.Least_Rotation` keeps two candidate offsets, I and J, whose
rotations agree for K letters. A ghost `Best`, the least offset found by a
naive scan (`Naive_Least`), names the answer. The invariant is that `Best` is
I, J, or above both.

- A mismatch at K rules out the offsets from the candidate with the larger
  letter, say I, to I + K. For each T up to K, the rotation from I + T agrees with the one
  from J + T for K - T letters and then is larger (`Worse`, by `Decide` and
  `Skip_Split`). So none of them is least (`Eliminate`).
- If K reaches N, the two rotations are equal, so S has period |I - J|.
  An offset above both would have an equal rotation |I - J| earlier
  (`Same_Length_Extend`, then `Skip_Split`), so `Best` is the smaller
  candidate (`Settle`).
- Otherwise one candidate has run past N, and `Best` is the other.

## Classical

`Matrices` proves the classical case up to equal periodic words. That weaker
form is necessary, because a periodic input like `abab` has equal rotations,
so LF cannot be exact on rows. `LF_Shifts` shows that LF maps each sorted row
to a row whose word equals its predecessor rotation's. `Classical_Thread`
then follows the orbit from the primary row and reads the input backwards.
`Classical_Round_Trip` matches that against the decoder's contract, one
position at a time. The decoder packs each row's LF link and letter into one
32-bit word (`Pack`, `Next_Of`, `Letter_Of`), which relies on `Max_Length`
being 2**24: lifting the bound past it means widening that word.

## Bijective, decode after encode

1. `Words`: finite words, their lexicographic order, and Lyndon words
   (strictly below every proper suffix). `Lyndon_Extend` is Duval's key
   step: a periodic repetition of a Lyndon word followed by a larger letter
   is Lyndon.
2. `Bijective.Factor_Rotations` (Duval) produces a table recording a
   nonincreasing Lyndon factorization (`Factorizations.Factorization`). The
   outer loop keeps a *dominated* witness: the text from the next factor
   start agrees with the previous factor for a while, then falls below it.
   `Factorizations.Unique` proves the factorization unique.
3. `Lyndon_Order` connects the two orders. A Lyndon word precedes its other
   rotations. For Lyndon words, lexicographic order implies periodic order.
   A word preceding its other rotations is Lyndon. Rotations of one Lyndon
   word never have equal periodic words (`Primitive`).
4. With later positions first among equal words, LF is **exact** on the
   bijective table: it moves each row to the row of its predecessor
   rotation (`Bijective_Proofs.Exact_LF`). This is why the bijective sort
   uses `Later_First`. Rows only tie across equal factors, and a
   predecessor stays in its factor.
5. `Orders.Is_Order` characterises the decoder's visiting order position by
   position. Follow LF while that leads somewhere new; otherwise restart at
   the least unwritten row. `Order_Unique` shows that this determines the
   order. `Model_Order` checks the order predicted from the factorization
   against it. Its key fact is `Key_Min`: the last remaining factor's Lyndon
   rotation is the least remaining row. Hence the decoder writes back the
   input.

## Bijective, encode after decode

For an arbitrary last column, `Onto_Proofs` recovers the decoder's blocks
from `Is_Order` (`Block_Starts`, `Block_Ends`). It shows that each block is a
whole LF cycle (`Closure`) whose last-written row is the least row written up
to it (`Block_Min`). Laid out as rotations, rows are in periodic order
(`Monotone`). Equal words sit in blocks from right to left (`Tie`), so the
layout is key-sorted. From that, the blocks are Lyndon and nonincreasing.
By uniqueness, Duval finds exactly these blocks, and the sorted table is the
layout itself (`Sorted_Equal`). Its last letters are the input column.

## Proof engineering that mattered

- Quantify over positions, not offsets. `for all X in A .. A + N - 1 =>
  S (X) = ...` instantiates reliably; `S (A + K)` under `for all K` does not,
  because the provers get no trigger on the bare variable.
- Accumulate facts as opaque atoms. A per-element predicate is proved by its
  own lemma, and the loop that collects it keeps the predicate hidden.
  Unfold it once, at the end.
- Hiding an expression function in a body also hides it from the checks on
  that subprogram's *own* contract. Keep the contract's bounds and index
  facts outside the hidden predicate.
- Ada array `=` does not fix bounds, so state `First = 1` separately. Record
  `=` is logical equality and passes through any function.
