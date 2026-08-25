# git_changes

`git_changes` is an Ada library that captures Git comparisons as typed,
source-neutral change sets.  Its public model preserves endpoint identity,
old/new byte paths, modes, object IDs, non-text classifications, and
side-aware zero-context spans.  Git CLI interaction and owned containers stay
outside the SPARK core.

The implementation currently supports tree-to-tree, tree-to-index,
index-to-worktree, and tree-to-worktree comparisons.  Untracked files are
excluded.  Expected capture failures are returned as typed `Error_Info` values.

## Build and test

The committed build is location-independent and declares GNAT 16 through
Alire:

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/prove.sh
```

`scripts/prove.sh` runs one GNATprove process with internal parallelism and a
Silver (`--level=2`) target for the SPARK core.  See
[`docs/proof-boundary.md`](docs/proof-boundary.md) for the precise claim.

For this checkout only, `env.sh` is intentionally ignored.  It selects the
machine's Alire and Alire-installed GNATprove 16 without baking those paths into
the crate.

The diagnostic executable defaults to `HEAD` versus the tracked working tree:

```sh
alr run --args="/path/to/repository"
alr run --args="/path/to/repository tree-tree OLD NEW"
alr run --args="/path/to/repository tree-index TREE"
alr run --args="/path/to/repository index-worktree"
```

Paths are byte strings.  The diagnostic display escapes non-printing and
non-ASCII bytes; it is not a canonical serialization format.
