# Client feedback

What using `Ore` from a real client looks like from the client's side: what it
replaced, what it did not, and where a gap made the client keep code that this
library was supposed to remove. Kept as a file rather than as issues because
most entries are about a shape of contract rather than a defect.

Each entry names the client and the version it was written against. An entry
stays until the gap closes or the answer is "no, and here is why", either being
better than leaving it to be rediscovered.

---

## `pager/inflate` against 0.4.0 — 2026-07-30

The same client as the entry below, taking up what 0.4.0 added in answer to it.
Result first: the value view worked, the write side moved onto `Put_Bits`, and
the client's reader is now proved to be Ore's field — but it is still there, and
two lemmas had to be written to carry a bound across the word/`Natural` boundary.
The whole project re-proved at `--level=4` with 7,770 checks, down from 7,833.

### Adopted, and it did what it claimed

* **`Field_Value` and `Lemma_Field_Value_Recursion`.** The client's field reader
  now carries `Result = Field_Value (…, Lsb_First, High_Bit_First)` in its
  postcondition, proved from the recurrence lemma. This is exactly the step the
  entry below asked for, and the `High_Bit_First` form matched the client's
  recurrence without restating it.
* **`Put_Bits`.** With that equality available, the code writer — a bit-at-a-time
  recursion that re-proved at every step that the bits already placed had not
  moved — became one call. Two helpers went with it: the recurrence lemma it
  needed, and a copy of the single-bit write. The unit lost 46 checks and gained
  nothing to prove by hand. This is the largest single simplification any Ore
  release has produced in this client.
* **The field bound.** The reader's `< 2 ** Length` clause used to need a local
  trick that turned a symbolic exponent into a concrete bound. It now comes from
  the bound Ore states on the field — modulo the new gap below.

### Gap 1 — the bounds are in word arithmetic, and clients' contracts are not

This is the one thing to fix, and it is the same shape as the mask table 0.3.0
retired, one type boundary over.

`Field_Value` returns a `Natural` and bounds it by
`Natural (Low_Mask_32 (Count))`. The value clauses of `Low_Mask_*` and of the new
`Power_Of_Two_*` are equalities in the *word* type, so `2 ** Count` there is
modular exponentiation. A client's own contracts bound a code by `2 ** N` or by a
`Pow2` table in `Natural`, because that is what a code length means. With the
exponent computed at run time, no prover crosses between the two — so the client
wrote two lemmas, each a `case` with one branch per width and `null` in every
branch, because a concrete exponent is the only thing that makes the equality
trivial:

```ada
procedure Lemma_Mask_Power (Length : Natural)     --  in the client
with Pre  => Length <= 15,
     Post => Natural (Bits.Low_Mask_32 (Length)) = 2 ** Length - 1;

procedure Lemma_Pow2_Mask (Length : Natural)      --  and again, for its table
with Pre  => Length <= 15,
     Post => Natural (Bits.Low_Mask_32 (Length)) = Pow2 (Length) - 1;
```

Sixteen `null` branches each, sitting beside operations whose purpose is to
remove exactly that kind of boilerplate. Two ways to close it, either enough:

* state `Field_Value`'s bound in the arithmetic of its own result —
  `Field_Value'Result < 2 ** Count`, a `Natural` power, no word type involved;
* or add the crossing as a lemma —
  `Natural (Low_Mask_32 (Count)) = 2 ** Count - 1`, once per width, so no client
  enumerates it.

The first is better: it puts the bound in the type the operation already returns.
`Power_Of_Two_*` has the same issue seen from the other side — it was added so
clients stop tabulating powers, but a client tabulates powers to use them as
`Natural`s, and the operation gives a word.

**Closed in 0.5.0, both ways.** `Field_Value` states
`Field_Value'Result < 2 ** Count` as well as the mask bound, so a client that
reads fields needs no lemma of its own; and the crossing itself is
`Lemma_Low_Mask_*_Natural` and `Lemma_Power_Of_Two_*_Natural`, one per width, for
a client holding a mask or a weight that has to meet a bound in `Natural`. The
wider two of each group stop at an exponent of thirty, because it is the power on
the right of the equality that leaves `Natural` first, not the mask on the left.
The acceptance test is in `tests/proof`: the two case-per-width lemmas this entry
shows, each now a body of one call.

### Gap 2 — a field frame requires identical bounds

`Lemma_Bits_At_Frame` was not adopted. It requires `Before'First = After'First`
and `Before'Last = After'Last`, while a bit position is counted from `'First`, so
a client's own frame lemma over bit positions holds between two arrays of equal
length whatever their bounds — and the client's is stated and proved that way,
with the equal-bounds facts nowhere in the preconditions of the lemmas that call
it. Adopting Ore's would mean threading equal-bounds preconditions up through
several proved units to replace an eight-line induction, so the induction stayed.

Not a defect: `Bits_At` is a function of the array, and its frame cannot be
weaker than its subject. Worth knowing that the array-identity requirement is
what kept the frame vocabulary out, when the accessor and the writes went in
without friction.

**Recorded in 0.5.0**, in the spec beside the lemma, including that a client for
which threading the hypotheses costs more than its own induction is right to keep
the induction. No change to the contract, for the reason this entry gives.

### Note — a field's value does not give a field's bits

One four-bit header field stayed on `Set_Bit`, because the contract it has to
establish is four individual bit equations rather than a value: the format
defines those bits, and the client's decoder reads them as bits. Going from
`Bits_At (…) = V` back to which bits of the array `V`'s digits are is the
direction nothing provides, and the operation is four calls, so this is a note
rather than a request.

**Recorded in 0.5.0**, in the spec: the direction back is not provided, and a
contract stated as bit equations is `Set_Bit`'s.

### Note — adopting the value view means proving your reader equal to it

Worth saying in the spec, because it is the difference between what the entry
below asked for and what it got. The client's reader could not be *defined* as
`Field_Value`: its postcondition names itself — the recurrence its consumers are
proved through — and inside its own body the shorter field is not available from
its own contract, so the recursive clause becomes unprovable the moment the body
stops recursing. Keeping the recurrence and proving the equality is the shape
that works, and it is the shape `tests/proof` already demonstrates. So the reader
stays, about thirty lines of it; what the value view actually buys is everything
downstream of the equality, which in this client was the whole write side.

**Said in the spec in 0.5.0**, in the words of this entry, next to the recurrence
a client's model is proved through.

---

## `pager/inflate` against 0.3.0 — 2026-07-28

A one-shot DEFLATE/zlib/gzip/ZIP codec in SPARK, proved at `--level=4`, with a
round-trip theorem over its compressor. It is the closest thing to a stress test
this library has: bit-packed fields in two orders, Huffman codes read one bit at
a time, and a decoder whose hot loop is benchmarked against C zlib.

### Adopted, and it did what it claimed

* **`Set_Bit`.** Three byte-identical single-bit writes — one each in the fixed,
  dynamic and shared-payload encoders — became three calls. Each had been
  proving by hand the step from "this byte changed, and one bit within it" to
  "one bit position of the stream changed", which is the postcondition. This was
  the single largest reduction, and the framing was the reason.
* **`Bit_Value` / `Bit`.** The client's stream-bit accessor, which every encoder
  model is stated through, is now the arithmetic view of the bit-addressed
  accessor rather than of a byte-and-offset split written out locally. Roughly
  eighty contracts stated through it needed no change, because only the
  definition moved. Before, the position arithmetic was the client's and the
  lemmas about it were Ore's, so they applied by resemblance.
* **The mask value clauses.** A `2 ** N - 1` lookup table sat beside the
  decoder's bit reader for exactly the reason 0.3.0 records, and it is deleted:
  the reader masks with `Low_Mask_32` and states its value bound as
  `Natural (Low_Mask_32 (N))`. Worth recording that the conversion out of the
  word type proved without help at `--level=4` — the concern that a symbolic
  `2 ** Count` would need a monotonicity lemma did not materialise for counts
  bounded well under the width.

### Gap 1 — `Bits_At` has no arithmetic view, and that is what blocked the biggest win

The client's field reader and field writer are `Bits_At` and `Put_Bits` in both
of DEFLATE's orders, down to the two orders being independent arguments. They
were not adopted, and the reason is not preference.

`Bits_At` is specified bit by bit: which bit of the result each stream position
became, and that the bits above the field are clear. The bound is the only
arithmetic, and it is an inequality. The client's `Prefix_Value` is a `Natural`
whose postcondition is the recursion over the field width,

```ada
Prefix_Value (Input, Start, Length) =
  2 * Prefix_Value (Input, Start, Length - 1)
    + Bit_Value (Input, Start + Length - 1)
```

and about ninety contracts across three packages are proved through that
recursion — because a field in a compression format is read to be *used as a
number*: a code value indexes a symbol table, a length becomes a match length, a
distance becomes an offset. Getting from the bit-wise specification to that
recursion needs a bits-to-value bridge across two field widths, and neither
`Ore.Bits` nor `Ore.Bit_Cursors` has one. Writing it in the client is writing,
in the client, the reasoning the library exists to hold — so the client kept its
own reader, and the duplication the migration was meant to remove is still
there.

What would close it, at the `Bit_Cursors` level, is the recursion itself as a
lemma — one direction per order, both true of the current implementation:

```ada
--  High_Bit_First: the last bit taken is the least significant.
Bits_At (A, Position, Count, Numbering, High_Bit_First) =
  2 * Bits_At (A, Position, Count - 1, Numbering, High_Bit_First)
    + Bit_Value (A, Position + Count - 1, Numbering)

--  Low_Bit_First: the last bit taken is the most significant.
Bits_At (A, Position, Count, Numbering, Low_Bit_First) =
  Bits_At (A, Position, Count - 1, Numbering, Low_Bit_First)
    + 2 ** (Count - 1) * Bit_Value (A, Position + Count - 1, Numbering)
```

A weaker form would also do the job: the field one bit shorter is the field
shifted, stated as values. The general shape underneath it is a value-of-bits
bridge at the word layer, which `Ore.Bits` also lacks — `Extract` produces the
bound from the bits but nothing produces the number from them. `Lemma_Bound_Bits`
went the other direction for the same reason, and this is the same missing
direction one level up.

Until then, a client that does arithmetic on the fields it reads cannot adopt
`Bits_At`, and that is most clients: a bit-packed format is packed *because* its
fields are numbers.

**Closed in 0.4.0.** `Lemma_Bits_At_Recursion` and `Lemma_Field_Value_Recursion`
state the recursion, and `Field_Value` is the field as a `Natural` with its bound
proved. Underneath them `Ore.Bits` gained the bridge this entry names: a shift is
a multiplication or a division (`Lemma_Shift_Left_Value`,
`Lemma_Shift_Right_Value`), a field at the bottom of a word is a remainder
(`Lemma_Extract_Value`), and `Bits_Value` with `Lemma_Bits_Value` is the value of
a word's low bits as a recurrence — the analogue of `Count_Bits` for a value
rather than a count.

One deviation from the form proposed here. The `Low_Bit_First` direction drops
the *first* bit rather than the last, so both orders read `2 * shorter + bit` and
the bit dropped is in both cases the least significant one of the value — which
is all the two orders differ by. The form above is equivalent, but its contract
carries `2 ** (Count - 1)`, and bounding a symbolic power put the arithmetic of
the contract outside `Natural` at widths the operation itself allows. The
acceptance test is in `tests/proof`: a client's `Prefix_Value` recursion, proved
equal to `Field_Value` at every width by an induction that mentions no bits.

### Gap 2 — `Take_Bits` cannot serve a decoder's hot path

The implementation is one bit at a time, and 0.3.0 defends that: a Huffman tree
walk reads its bits one at a time anyway. That is true of the tree walk and not
true of the loop around it. This decoder keeps a 32-bit accumulator with a
buffered-bit count, refills it a byte at a time, and takes a field with a mask
and a shift; it is benchmarked against C zlib, so a per-bit take in the block and
symbol loops is not an option. `Take_Bits` also has no way to express the
refill — the accumulator's state is exactly the bits that are consumed from the
input but not yet from the stream, which a bare position cannot represent.

Not a defect, and possibly not worth fixing — but it bounds where the package
gets adopted, and the client's decoder is precisely the code that reads bits
most. If it is not going to be fixed, the spec's comment about the tree walk is
the place to say that a throughput-oriented reader is out of scope, so the next
client does not benchmark it to find out.

Secondary friction in the same operations: the value is a `Word32`, while the
client's codes, lengths and symbols are all `Natural`. Every adoption site would
carry a conversion whose range check needs the mask bound, which is provable but
is noise at the boundary of a package whose whole job is that boundary.

**Answered in 0.4.0, and the answer is no.** A throughput-oriented reader is out
of scope, for the reason this entry gives: the accumulator's state is the bits
consumed from the array and not yet from the stream, and a position in the array
cannot represent it, so such a reader is not a different implementation of these
operations but a different interface. The spec now says so where it used to
defend the per-bit loop with the tree walk, and names what the reader is built
from instead — `Load_32` and the shifts and masks of `Ore.Bits`. The friction is
gone: `Field_Value` returns a `Natural`, with the bound the conversion needed.

### Gap 3 — no power vocabulary, so `2 ** N` tables stay

Three `Pow2` tables remain in the client (`Raw`, `Codebooks`, `Dynamic`).
`Low_Mask_32 (N) + 1` is that value now, but these tables do not mask anything —
they measure Kraft sums over code lengths, where the exponent is symbolic and a
concrete constant array is what lets the provers case-split. Swapping in a
symbolic power would be proof risk for no correctness gain, so they stayed.

This may be out of scope for a bit library. But "keep a table of `2 ** N` beside
the arithmetic that needs it" is the same client behaviour 0.3.0 removed for
masks, one step over, and the fix looks similar: a bounded `2 ** N` whose
postcondition is stated per width so no client writes the table.

**Closed in 0.4.0.** `Power_Of_Two_8/16/32/64`, with the value as a `Runtime`
clause and the single bit as a `Static` one, so neither view has to be recovered
from the other. Whether it retires the tables is the client's call: the exponent
stays symbolic, and if what those proofs need is the case split a concrete array
gives, this operation supplies the value and not the split.
`Lemma_Low_Mask_*_Monotonic` was added in the same release for the step these
sums also want — a wider mask is a bigger number.

### Note — `Natural` positions vs a model that counts bits in a wider type

`Bit_Cursors` avoids the product of length and eight, and the reasoning for it is
right. The client meets the same problem from the other end and answers it
differently: its encoders cap a stream at `Natural'Last / 8` so that `8 * Length`
is a `Natural` and every bound is written as that product, while its decode
*model* counts bit positions in `Long_Long_Integer` because it accepts inputs
that have more bit positions than a `Natural` holds.

Consequences, neither of which needs action: the encoders could adopt `Fits` only
by restating bounds they already have in product form, and the model cannot use
`Bit_Cursors` at all, since its positions do not fit the parameter type. If a
client whose positions are wider ever matters, the division-and-subtraction style
here is the part that generalises; the `Natural` in the profile is the part that
does not.

**Recorded in 0.4.0**, in the spec, in the words of the last sentence above. No
change: a wider position type would be a second profile for every operation, and
one client's model is not enough to know whether it should be a generic formal, a
`Long_Long_Integer` throughout, or nothing.

---

## `pager/inflate` against 0.1.0 and 0.2.0 — 2026-07-28

The same client, before the entry above: about 14,500 lines, proved at
`--level=4` with no unproved checks and no justifications. It migrated from its
own `Interfaces`-based types to `Ore` 0.1.0, and then to `Ore.Bits` in 0.2.0.
What it took up was the physical types, `Load_16/32` and `Store_32` on plain
arrays, `Intrinsics`, `Bit`, `Insert` and `Truncate_To_Byte`.

Kept here because the two adoptions that worked say which conventions carry
their weight, and because all three gaps were closed in one release, which is
worth being able to check.

### Adopted, and it did what it claimed

* **Single-bit `Insert`.** It replaced three byte-identical hand-written masked
  writes and proved with no bridging lemma at all — including the
  `Field <= Low_Mask_8 (Count)` precondition, which looked like it would need
  `Lemma_Bits_Equal` to discharge.
* **`Bit` as an expression function.** Because it is an expression function over
  the intrinsic rather than a subprogram with a contract, the client's central
  stream-bit accessor could be restated in terms of it without disturbing any of
  the proofs that consume it.

### Gap 1 — `Low_Mask_*` needs the value, not only the bits

The bit reader carried a table of `2 ** N - 1` and `2 ** N` as lookup arrays,
because the provers reason about a concrete array by case enumeration where a
variable exponent would need power lemmas they do not reliably find. That table
is `Low_Mask_32`, except that the client used it two ways in the same
contracts — once to mask, and once as an arithmetic bound — and a postcondition
stated bit by bit serves only the first. A partial replacement leaves the table
in place, so the client kept all of it. The same gap applied to `Field_Mask_*`,
and `Extract` inherited it through a bound whose right-hand side a client could
not evaluate to a number.

**Closed in 0.3.0**, as the `Runtime` value clauses on the masks. Adopted and
the table deleted; see the entry above.

### Gap 2 — `Bit` over a `Byte_Array`

`Ore.Bits` gave the bit of a word and `Ore.Byte_Buffers` the byte of an array;
the composition — the bit of an array, at a position counted across the whole
array — is what a bit-oriented format addresses, and every client writes it. The
client's own was referenced about sixty times across its encoder, decoder and
their models, in two shapes, since a model that sums bits into a code value needs
the arithmetic view as well as the Boolean one. What mattered more than the
accessor was the frame lemma: the step from "one byte of the array changed, and
within it one bit" to "one bit position of the array changed", which three
procedures were each stating by hand.

**Closed in 0.3.0**, as `Bit`, `Bit_Value`, `Set_Bit` and `Lemma_Bit_Frame` in
`Ore.Bit_Cursors`. Both were adopted; see the entry above.

### Gap 3 — bit-addressed buffers, with two constraints

Ranked by how much proved client code it would retire, the roadmap's
bit-addressed buffers were far ahead of anything else on the list: a seventy-line
`Get_Bits`, a write side spread across three units, and the bit-position
bookkeeping the encoders' size bounds are proved against — all written, all
proved, none of it specific to DEFLATE. Two constraints came with it. It had to
work on a caller-provided array, because a bounded owning container cannot wrap
memory it did not allocate and `Max_Capacity` of 2\*\*27 is below the client's own
input ceiling; and LSB-first and MSB-first are both needed in one stream, not as
a configuration made once per buffer but as two operations used alternately on
one cursor.

**Closed in 0.3.0**, as `Ore.Bit_Cursors`, over caller-provided arrays and with
both orders as arguments of each operation. The scope question — whether a cursor
over a caller's array belongs in a library of bounded containers — is answered in
the roadmap rather than left to be rediscovered. What the client then could not
adopt is Gap 1 of the entry above.
