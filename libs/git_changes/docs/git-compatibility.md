# Git compatibility and span semantics

The initial backend is tested with Git 2.43 and relies on documented plumbing
that has been stable across Git 2.x:

- `git rev-parse` for repository and tree resolution;
- `git diff --raw -z --no-abbrev` for the file inventory;
- `git diff --unified=0` hunk headers for canonical changed spans;
- `git cat-file blob` for object-backed content.

All invocations disable color, external diff commands, and text conversion.
The chosen span authority is therefore Git itself.  An XDiff dependency is not
introduced: it could disagree under algorithm, whitespace, attribute, or
custom-driver policy, which would silently mix two definitions of a change.
The public options make the Git algorithm and whitespace policy explicit.

Raw paths are NUL-delimited byte strings and are never decoded or normalized.
The parser accepts full SHA-1 and SHA-256 object IDs and does not expose a
fixed-width object-ID type.  Untracked files are not part of any comparison.

The supported matrix is:

| API comparison | Git comparison |
|---|---|
| tree to tree | `git diff OLD NEW` |
| tree to index | `git diff --cached TREE` |
| index to worktree | `git diff` |
| tree to worktree | `git diff TREE` |

Rename and copy detection are explicit options.  Binary, submodule, mode-only,
and type changes stay in the inventory even when they have no textual spans.
