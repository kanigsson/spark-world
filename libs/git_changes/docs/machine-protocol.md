# Machine protocol

`git-changes --format=json` emits exactly one JSON document on standard output.
Diagnostics go to standard error, and failures emit no partial document.
Consumers must reject unsupported `schema_version` values.

Schema version 1 contains the resolved repository, comparison and endpoints,
freshness state, typed file deltas, stable file/span IDs, old/new identities,
and side-aware zero-context spans. `--include-contents` additionally loads each
available side and adds its `content` field. A side-local load failure is
reported as `content: null` plus `content_error` without corrupting the rest of
the capture.

Git paths and contents are byte strings, not necessarily UTF-8. The document's
`byte_encoding` is `json-code-point-u00xx`: each input byte is represented by
the JSON character with the same numeric value. Bytes outside printable ASCII
are emitted as `\u00XX`. A consumer reconstructs the original bytes by requiring
every decoded code point to be at most 255 and converting it to one byte.

Examples:

```sh
git-changes --format=json . tree-worktree HEAD
git-changes --format=json --include-contents . tree-tree BASE HEAD
```

The human-readable default remains diagnostic output and is not a protocol.
