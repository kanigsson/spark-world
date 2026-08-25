# Proof boundary and Silver objective

The Silver objective applies to `Git_Changes.Core.Validation`,
`Git_Changes.Core.Raw`, and `Git_Changes.Core.Hunks`.  These units parse and
validate bounded byte strings, advance cursors, convert decimal fields, and
construct side-aware ranges.  Their normal control flow does not use
exceptions, allocation, unchecked conversion, operating-system state, or
foreign code.

The following are deliberately outside the claim:

- process creation, temporary files, filesystem and environment access;
- owned `Ada.Containers` and `Unbounded_String` values;
- GNAT's SHA-256 implementation used for stable join keys;
- Git's diff algorithm and the correctness of Git output;
- resource exhaustion and `Storage_Error`;
- atomicity of a concurrently changing index or working tree.

The adapter validates every raw record and hunk before copying it into the
owned model.  It fingerprints the index around worktree captures and reports
visible staleness according to the configured policy.  GNATprove evidence is
produced by `scripts/prove.sh`; compiler warnings, tests, and differential
checks remain necessary because Silver is not a functional-correctness claim
for Git's formats.
