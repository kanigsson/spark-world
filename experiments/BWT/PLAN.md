# Proof completion plan

Target: discharge the three existing `BWT.Theorems` procedures for **every**
supported byte string. Preserve the algorithms' standard definitions as well
as their inverse laws. No assumptions, imported axioms, unproved-check
annotations, runtime roundtrip guards, or restrictions to distinct bytes or
primitive inputs. Keep each step bounded; a higher timeout cannot replace
missing mathematical contracts.

1. **Representation and safety.** Close the remaining bounds and invariants in
   `Classical_Encode` and `Bijective_Decode`; reuse the already-proved shape
   and safety contracts of `Sort`, `Factor_Rotations` and LF.
   Strengthen sorting with a multiset/permutation relation over descriptors:
   validity alone cannot show that the primary row survives. Maintain a ghost
   count of visited positions in the inverse; `Next = n - visited_count`
   establishes output bounds and the final `Next = 0`. Establish termination
   alongside these invariants. Exit: all runtime, flow, length and primary
   index obligations discharged, with functional theorem failures still visible.

2. **Stable ranks and periodic order.** Model
   `LF(i) = count(j: Last(j) < Last(i) or
   (Last(j) = Last(i) and j <= i))`. Prove range and injectivity, hence
   permutation, using the strict total order on `(byte, position)`. Export the
   character/rank relation, not only bijectivity: arbitrary permutations do
   not reconstruct Lyndon factors. Define periodic letter lookup and prove
   that comparing p + q characters decides infinite periodic order. Establish
   transitivity and equivalence for equal infinite words. For equal-length
   rotations this agrees with ordinary lexicographic order. Exit: usable LF
   and comparator contracts independent of either encoder.

3. **Classical roundtrip.** Give `Sort` stable sorted-permutation postconditions
   and preserve them through insertion. Relate its first and last columns to
   rotation descriptors. Prove the LF step yields an equivalent predecessor
   rotation, then induct on the decoder's reconstructed suffix, starting at
   `Primary`. Equal rotations make exact descriptor identity too strong:
   e.g. `abab` may have shorter LF cycles. Never assume one cycle of size n.
   Exit: `Classical_Round_Trip` proved, including empty and periodic inputs.

4. **Duval and forward semantics.** Introduce ghost factor boundaries and a
   Lyndon predicate: nonempty and strictly smaller than each nontrivial cyclic
   rotation. Prove factors partition the input without gaps, are Lyndon and
   nonincreasing, and occur with the correct multiplicities. Prove uniqueness
   of this factorization. Then connect `Factor_Rotations` to exactly one
   descriptor per factor position and the last-column definition after Sort.
   Exit: a complete forward BBWT specification; do not infer it from tests.

5. **LF cycle reconstruction.** Prove an unvisited cycle returns to its start,
   visits no earlier cycle, and that scanning the least unvisited row yields
   the least remaining Lyndon factor. Equal factors must remain separate
   occurrences. Show backwards writes concatenate the factors in nonincreasing
   order. Combine with step 4 for decode-after-encode. For encode-after-decode,
   start from an *arbitrary* last column and prove that reconstructed factors'
   sorted rotations reproduce that column, including duplicates. Exit:
   `Bijective_Round_Trip` and `Bijective_Onto` proved.

6. **Final receipt.** Run full `make prove`, `make flow`, `make test` and
   `make format-check`; require clean exits and zero unproved checks. Record
   tool versions, check totals and theorem boundaries in `AGENTS.md`. Only
   then describe this implementation as proved. Consider faster sorting and
   counting-based LF construction as a separate change with these contracts
   preserved.

Trust boundary: SPARK/GNATprove and its provers, Ada's byte/array semantics and
the compiler/runtime. The literature supplies the mathematical strategy;
citations are not formal axioms. The ordinary-Ada test oracle and test counter
are validation infrastructure outside the proof. All executable transform
code is in the proof project; `-U` also includes uncalled ghost theorem bodies.
