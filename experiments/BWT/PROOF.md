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
- `Ranks`: `LF` is the stable rank of each last letter. It is a permutation
  and it orders rows as `Ordered` does. `Walk` is the LF orbit that the
  classical decoder follows.
- `Sorting`: selection sort, which yields a key-sorted permutation of its
  input, and the uniqueness of such permutations.

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
