# Roadmap

Planned scope for `Ore`. Items are unordered; nothing here is a commitment to a
particular release.

## Bounded strings (no UTF-8 yet)

* Construction from `String`
* Append character/string
* Slice or substring
* Equality and lexicographic comparison
* Starts with / ends with
* Find character/subsequence
* Trim
* ASCII case conversion
* Replace
* Safe numeric conversion
* Integer formatting
* A builder-style API

## Optional and result types

## Bounded queue, deque, ring buffer

## Array algorithms (generic)

* Linear search
* Binary search
* Lower/upper bound
* Sort, stable sort
* Reverse
* Rotate
* Copy, move with overlap
* Fill
* Equality, lexicographic comparison
* Partition
* Unique adjacent elements
* Min/max
* Count
* All/any

## Bit-addressed buffers

Delivered in 0.3.0 as `Ore.Bit_Cursors`: bit and field accessors, read and
write cursors in both orders, byte alignment, and the framing lemmas.

The open question was whether a cursor over an array the caller owns is in
scope for a library of bounded containers. It is, and it is the only form the
layer takes: a cursor is a position and a `Byte_Array`, as the endian loads
are, because a bounded owning container cannot wrap memory it did not allocate
and its capacity ceiling is not the ceiling of an input a caller mapped or
read. There is no bit-addressed container type, and none is planned. Reading
the bits of a `Buffer` means reading the bits of a `Slice` of it.

0.4.0 added the arithmetic view of a field, which is what a client that computes
with what it reads needs: `Field_Value`, the recurrence lemmas, and the
bits-to-value bridge they rest on in `Ore.Bits`.

0.5.0 put the bounds of that view in the arithmetic a client's contracts are
written in: `Field_Value` bounds its result by `2 ** Count` in `Natural`, and the
crossing from a word-typed mask or weight to the same number as a `Natural` is a
lemma per width rather than something a client enumerates.

What is not there yet:

* A field wider than 32 bits in one take or put, or wider than 30 as a `Natural`
* A take that reports how many bits it could supply, rather than only that it
  could not supply all of them
* A frame lemma for a whole span written by hand. `Put_Bits` states the span
  frame for its own write and `Lemma_Bit_Frame` states it for one bit; a client
  that writes a span with its own byte stores has to compose the two

Decided against, so that it is not proposed again: a throughput-oriented reader,
the kind that keeps a word-sized accumulator, refills it a byte at a time and
takes a field with one shift and one mask. Every operation here costs a step per
bit, and that is not an implementation to improve — the accumulator's state is
the bits consumed from the array but not yet from the stream, which a position in
an array cannot represent, so such a reader is a different interface and its own
invariant. `Load_32` and the shifts and masks of `Ore.Bits` are what it is built
from. The spec of `Ore.Bit_Cursors` says this too, where a reader looking for
throughput will see it.

## Simpler containers for small systems

* Sorted-array map
* Flat hash map with open addressing
* Direct-index map
* Fixed-capacity set
* Small-vector optimisation

## Arenas

Undecided.
