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
  permutation ordered as (key, position).

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
- Sorting by pairs takes one counting sort per round. The previous order,
  with every position moved back by H (`Back`, proved through
  `Skip_Unskip`), is already sorted by the second key. A stable sort by the
  first key therefore sorts by the pair. Stability is used here and in the
  final pass, and `Key_Sort`'s (key, position) postcondition states it.
- `Dense_Ranks` numbers the classes along the sorted order. Its loop keeps
  the pairwise fact "ranks compare as pairs" for the prefix it has numbered.
  If there are N classes, the ranks are distinct.
- The loop stops when H reaches twice the longest factor or the ranks are
  distinct. `Rotations.Settled` lifts either case to the horizon 2N. Past
  both periods, equal prefixes stay equal (`Extend_Equality`). A mismatch
  decides every longer horizon, and it cannot lie beyond both periods.
  `Lay_Out` then sorts once more by (rank, position), with positions reversed
  for `Later_First`. That order is `Key_LE`.

Only the final pass needs the tie order. The rounds may leave equal ranks in
any order. `Reduce` is a division-free `mod` for arguments below twice the
modulus, which is nearly every call. Without it the classical encoder ran
about twice as slowly.

## Classical

`Matrices` proves the classical case up to equal periodic words. That weaker
form is necessary, because a periodic input like `abab` has equal rotations,
so LF cannot be exact on rows. `LF_Shifts` shows that LF maps each sorted row
to a row whose word equals its predecessor rotation's. `Classical_Thread`
then follows the orbit from the primary row and reads the input backwards.
`Classical_Round_Trip` matches that against the decoder's contract, one
position at a time.

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
