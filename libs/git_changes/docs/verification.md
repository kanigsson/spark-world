# Verification snapshot

Validated on 2026-08-25 with the project-local Alire environment:

- Alire 2.1.1;
- GNAT FSF 16.1.0 (`gnat_native=16.1.0`);
- GPRbuild toolchain crate 26.0.1;
- GNATprove FSF 16.1.0 and Why3 1.8.2+git.

`./scripts/test.sh` passes 183 Ada core assertions and 32 integration scenario
checks.  The latter use disposable repositories and include complete raw
inventory and supported-hunk comparisons with the exact Git CLI authority,
all four comparison modes, copies/renames, pathspecs, binary and non-text
changes, non-UTF-8 names, lazy content access/staleness, a bare repository, and
Git SHA-256 when available.

`./scripts/prove.sh` reports `Success: all checks proved (189 checks)` at Silver
level.  The proved checks break down as 75 in hunk parsing, 53 in raw record and
slice parsing, and 20 in validation/range/line-count operations; the remainder
are flow/package checks.  There are no `pragma Assume` statements in the SPARK
units.  The exact assurance exclusions remain those in `proof-boundary.md`.
