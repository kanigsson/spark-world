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

## Bit and endian utilities

* Rotate left/right
* Extract and insert bit fields
* Safe masks
* Count leading/trailing zeroes
* Population count
* Byte swap
* Endian load/store
* Checked shifts
* Explicit truncation and extension
* Conversion between byte arrays and modular integers

## Bit-addressed buffers

* Read/write bit cursors, LSB-first and MSB-first
* Take/put N bits
* Bit position and byte alignment
* Value of the bit at a position
* Framing: a write leaves bits outside its span alone

## Simpler containers for small systems

* Sorted-array map
* Flat hash map with open addressing
* Direct-index map
* Fixed-capacity set
* Small-vector optimisation

## Arenas

Undecided.
