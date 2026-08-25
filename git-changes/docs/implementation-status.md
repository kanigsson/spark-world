# Version 1 implementation status

The library implements the reusable in-repository portion of milestones 0-3
and the milestone-5 standalone inspection consumer:

- owned, immutable-by-interface Ada change sets and typed errors;
- all four tree/index/worktree comparison modes and bare tree comparisons;
- proved raw `-z`, hunk, decimal, mode, object-ID, and range validation;
- SHA-1/SHA-256 IDs, arbitrary byte paths, rename/copy policy, and pathspecs;
- canonical Git zero-context spans with content-bound validation;
- lazy object/index/worktree content access and worktree freshness checks;
- binary, executable-mode, symlink/type, submodule, empty/no-final-newline,
  non-UTF-8, and SHA-256 integration coverage;
- deterministic SHA-256 `File_Id` and `Span_Id` values independent of
  enumeration order;
- explicit output/content limits and typed limit failures.

Public values own their containers and strings; clients receive a normal Ada
value whose mutation surface is private.  Paths remain raw Ada byte strings.
`File_Id` hashes the comparison kind, resolved endpoints, delta kind, paths,
modes, object IDs, and captured worktree fingerprint.  `Span_Id` additionally
hashes the side-aware range.  These are join keys, not cross-capture identity
claims.

The default limits are 16 MiB per Git command output and 64 MiB per loaded
content.  Git output is captured through a binary temporary file before bounded
parsing; a future pipe-backed streaming implementation can replace this inside
`Git_Changes.Backends` without changing the API.

Milestone 4 belongs in the separate `ada_review` repository and is not coupled
into this crate.  The libgit2 measurement in milestone 6 is intentionally not
performed before a consumer demonstrates a latency problem.  Neither item is
required for this library release, and neither changes its public model.
