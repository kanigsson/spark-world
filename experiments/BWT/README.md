# BWT experiment

Two executable SPARK Ada reference transforms, with their inverse laws proved
for every supported input.

- `Classical_Encode` returns the last column and a one-based primary row;
  `Classical_Decode` reconstructs the original string from that pair.
- `Bijective_Encode` uses Duval's nonincreasing Lyndon factorization and sorts
  the factors' rotations by their infinite periodic extensions (omega order).
  `Bijective_Decode` reconstructs factors from stable LF cycles and fills the
  output backwards. It accepts every supported last column, without metadata.
- `BWT.Theorems` states and proves the classical decode-after-encode law and
  **both** bijective inverse laws: decode after encode, and encode after
  decode for an arbitrary last column. Together the latter two make the
  bijective transform a bijection on strings of each length.

Inputs are Ada `String` byte sequences with first index 1 and length at most
`BWT.Max_Length` (1,024). All 256 `Character` values are data. Empty strings
are supported; classical empty output has primary index 0. Normalize slices
before passing them to the API. Results always start at index 1. Classical
decode accepts any in-range index, but its inverse law concerns encoder output;
arbitrary last-column/index pairs need not be canonical encodings.

The core has no I/O, heap allocation, external library dependency or non-SPARK
escape. Rotation descriptors and selection sort use O(n) auxiliary storage
and O(n^3) worst-case encoding time. LF is a counting sort, so both decoders
take O(n + σ) time and O(n + σ) space for an alphabet of σ bytes. Duval itself
is linear. The encoders favor inspectable proof obligations over throughput.

From this directory, with a matching Ada 2022 compiler/GPRbuild/GNATprove:

```sh
make test          # assertions enabled; includes independent definition oracle
make test-contracts
make flow
make prove         # every check, including the theorems; pinned GNATprove
make format-check
make bench         # production build: no contracts, no run-time checks
```

The Ada test harness uses the repository's ordinary-Ada `Test_Checks` package.
It exhausts all 9,841 words of lengths 0 through 8 over bytes 0, 128 and 255,
checking both encoders against an independent, materialized-rotation oracle.
The oracle obtains factors by repeatedly removing the least finite suffix,
instead of calling Duval. Tests also cover known vectors, periodic strings,
all byte values, and maximum-length blocks.

See [PROOF.md](PROOF.md) for how the proof is put together and
[AGENTS.md](AGENTS.md) for what to know before changing it.
[ROADMAP.md](ROADMAP.md) lists the planned work toward efficiency and
applications.

Algorithm references:
[Gil and Scott, A Bijective String Sorting Transform](https://arxiv.org/abs/1201.3077)
and [Kufleitner, On Bijective Variants of the Burrows-Wheeler Transform](https://arxiv.org/abs/0908.0239).
