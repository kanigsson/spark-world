# git_changes

`git_changes` is an Ada library that captures Git comparisons as typed,
source-neutral change sets.  Its public model preserves endpoint identity,
old/new byte paths, modes, object IDs, non-text classifications, and
side-aware zero-context spans.  Git CLI interaction and owned containers stay
outside the SPARK core.

The implementation currently supports tree-to-tree, tree-to-index,
index-to-worktree, and tree-to-worktree comparisons.  Untracked files are
excluded from comparisons.  Expected capture failures are returned as typed
`Error_Info` values.

Beyond comparisons, the library answers the read-only questions a reviewing
client asks around them, so that such a client needs no Git of its own:

- `Git_Changes.Revisions` resolves revision expressions, first parents, and
  the empty tree.
- `Git_Changes.Snapshots` lists the paths of a tree, the index, or the
  working tree, loads the content of any one of them — changed or not — and
  runs a fixed-string content search over a snapshot.
- `Git_Changes.History` walks filtered commit history as typed records and
  returns the patch text of a single commit.

These are reads. The library never writes to a repository: no clone, fetch,
push, commit, checkout, or index mutation.

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

Non-Ada consumers use the versioned machine protocol:

```sh
git-changes --format=json /path/to/repository tree-worktree HEAD
git-changes --format=json --include-contents /path/to/repository tree-tree OLD NEW
```

See [`docs/machine-protocol.md`](docs/machine-protocol.md). The JSON boundary
was added for the concrete `semdiff` and XPL migrations; the Ada API remains the
canonical in-memory representation.
