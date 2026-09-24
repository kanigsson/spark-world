# BWT experiment

Two executable SPARK Ada reference transforms with explicit, **unfinished**
roundtrip proof targets. This is a starting point for verification, not a
proved codec.

- `Classical_Encode` returns the last column and a one-based primary row;
  `Classical_Decode` reconstructs the original string from that pair.
- `Bijective_Encode` uses Duval's nonincreasing Lyndon factorization and sorts
  the factors' rotations by their infinite periodic extensions (omega order).
  `Bijective_Decode` reconstructs factors from stable LF cycles and fills the
  output backwards. It accepts every supported last column, without metadata.
- `BWT.Theorems` states the classical decode-after-encode law and **both**
  bijective inverse laws. Its assertions are obligations, not established facts.

Inputs are Ada `String` byte sequences with first index 1 and length at most
`BWT.Max_Length` (1,024). All 256 `Character` values are data. Empty strings
are supported; classical empty output has primary index 0. Normalize slices
before passing them to the API. Results always start at index 1. Classical
decode accepts any in-range index, but its inverse law concerns encoder output;
arbitrary last-column/index pairs need not be canonical encodings.

The core has no I/O, heap allocation, external library dependency or non-SPARK
escape. Rotation descriptors and insertion sort use O(n) auxiliary storage
and O(n^3) worst-case encoding time. LF uses the direct stable-rank formula,
so decoding takes O(n^2) time and O(n) space. Duval itself is linear. These
choices favor inspectable proof obligations over throughput.

From this directory, with a matching Ada 2022 compiler/GPRbuild/GNATprove:

```sh
make test          # assertions enabled; includes independent definition oracle
make flow
make prove         # includes ghost theorem bodies; fails on unproved checks
make format-check
```

The Ada test harness uses the repository's ordinary-Ada `Test_Checks` package.
It exhausts all 9,841 words of lengths 0 through 8 over bytes 0, 128 and 255,
checking both encoders against an independent, materialized-rotation oracle.
The oracle obtains factors by repeatedly removing the least finite suffix,
instead of calling Duval. Tests also cover known vectors, periodic strings,
all byte values, and maximum-length blocks. All 49,232 checks passed in the
initial run. This is finite testing, not universal proof.

See [PLAN.md](PLAN.md) for the proof decomposition and [AGENTS.md](AGENTS.md)
for the measured proof boundary and remaining checks.

Algorithm references:
[Gil and Scott, A Bijective String Sorting Transform](https://arxiv.org/abs/1201.3077)
and [Kufleitner, On Bijective Variants of the Burrows-Wheeler Transform](https://arxiv.org/abs/0908.0239).
The finite comparator checks p + q characters for periods p and q; the
periodicity argument connecting this to omega order remains to be formalized.
