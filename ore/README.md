# Ore

`Ore` is a SPARK library of proved building blocks for bounded, heap-free
systems code: no heap, no access types, no tasking, no OS. Every operation is
bounded and total on its precondition, and nothing raises to report a full or
an empty container.

The current version is `0.1.0`. Releases follow
[Semantic Versioning](https://semver.org/); see [`VERSION`](VERSION) and
[`CHANGELOG.md`](CHANGELOG.md). The planned scope is listed in
[`all.txt`](all.txt).

## What is in 0.1.0

* `Ore` — the physical types the hierarchy shares: `Byte`, `Word16/32/64`,
  the unconstrained `Byte_Array`, `Byte_Order`, and the capacity ceiling.
* `Ore.Byte_Buffers` — bounded byte buffers with a write and a read cursor:
  append, fill, consume, peek, checked multi-byte access in either byte order,
  spans and subview append, short bulk transfers reporting consumed/produced
  counts, compaction, and back-reference copies that may overlap their own
  output.

The point of the package is less the cursor bookkeeping than the proof
vocabulary that comes with it, which is what clients of a byte buffer normally
re-derive for themselves:

| Vocabulary | What it states |
| --- | --- |
| `Same_Prefix` | a produce operation left the earlier bytes alone |
| `Matches_At` | the bytes at a position are exactly this array |
| `Equal_Ranges`, `Unchanged_Outside` | the same two ideas on plain arrays |
| `Load_16/32/64`, `Store_16/32/64` | a multi-byte field reads back as stored |
| `Copies_Back` | the forward-copy equation of a back-reference, overlap included |
| `Contents` | the ghost model: the produced bytes as a `Byte_Array` |

with lemmas for the steps provers do not take on their own: prefix
transitivity, carrying a match across a later append, loads depending only on
their own bytes, and the induction behind a distance-one (run-length) copy.

Contracts are element-wise rather than slice- or sequence-valued, because that
is what provers handle at scale, and all ghost entities sit at the `Static`
assertion level, so an assertion-enabled build pays only for the cheap
`Runtime` clauses and never copies a buffer to evaluate a `'Old`.

## Building and proving

```sh
gprbuild -P ore_lib.gpr                 # the library
gnatprove -P ore_lib.gpr                # the library's own proof
gnatprove -P ore.gpr                    # library plus proof clients
```

Run the tests, which execute with contracts enabled:

```sh
gprbuild -P tests/runtime/runtime_tests.gpr
./obj/runtime_tests/byte_buffer_tests
```

`ore_lib.gpr` is the production project; `ore.gpr` adds the proof clients under
`tests/proof`, which exist to check that the exported vocabulary is usable —
they frame, write and read back a tag/length/payload record and expand a run,
and they must prove without reaching inside the library.

Everything in 0.1.0 is proved at `--level=2` with no unproved checks and no
justifications.

## Licence

Apache License 2.0; see [`LICENSE`](LICENSE).
