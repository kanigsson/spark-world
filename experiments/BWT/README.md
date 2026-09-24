# BWT experiment

Two executable SPARK Ada reference transforms, with their inverse laws proved
for every supported input.

- `Classical_Encode` returns the last column and a one-based primary row;
  `Classical_Decode` reconstructs the original string from that pair.
- `Bijective_Encode` uses Duval's nonincreasing Lyndon factorization and sorts
  the factors' rotations by their infinite periodic extensions (omega order).
  `Bijective_Decode` reconstructs factors from stable LF cycles and fills the
  output backwards. It accepts every supported last column, without metadata.
- `BWT.Search.Count` is backward search (FM-index count) on either last
  column. It is proved to count the circular occurrences of a pattern in S
  (classical), or its occurrences in the periodic words of S's Lyndon
  factors (bijective), for patterns up to twice the input length. It uses a
  naive rank, which scans the whole column for each pattern letter.
  `BWT.FM_Index` stores letter counts every 256 rows, at 4 bytes per input
  byte, and counts in O(|P| · 256) with the same guarantee.
- `BWT.Theorems` states and proves the classical decode-after-encode law and
  **both** bijective inverse laws: decode after encode, and encode after
  decode for an arbitrary last column. Together the latter two make the
  bijective transform a bijection on strings of each length.

Inputs are Ada `String` byte sequences with first index 1 and length at most
`BWT.Max_Length` (2**24). Results and working tables live on the stack, so
the practical limit is lower: a few hundred KiB with an 8 MiB stack. All 256 `Character` values are data. Empty strings
are supported; classical empty output has primary index 0. Normalize slices
before passing them to the API. Results always start at index 1. Classical
decode accepts any in-range index, but its inverse law concerns encoder output;
arbitrary last-column/index pairs need not be canonical encodings.

The core has no I/O, heap allocation, external library dependency or non-SPARK
escape. Both encoders sort rotations by prefix doubling. Each round is one
counting sort, so encoding takes O(n log n) time and O(n) space. There are at
most ⌈log₂ 2m⌉ rounds for a longest factor of m letters (m = n for the
classical transform), and doubling stops early once all ranks differ. LF is a
counting sort, so both decoders take O(n + σ) time and O(n + σ) space for an
alphabet of σ bytes. Duval itself is linear.

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
