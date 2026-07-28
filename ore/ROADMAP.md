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

What is not there yet:

* A field wider than 32 bits in one take or put
* A take that reports how many bits it could supply, rather than only that it
  could not supply all of them
* A frame lemma for a whole span written by hand. `Put_Bits` states the span
  frame for its own write and `Lemma_Bit_Frame` states it for one bit; a client
  that writes a span with its own byte stores has to compose the two

## Simpler containers for small systems

* Sorted-array map
* Flat hash map with open addressing
* Direct-index map
* Fixed-capacity set
* Small-vector optimisation

## Arenas

Undecided.
