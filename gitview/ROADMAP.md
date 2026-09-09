# git_view roadmap

## Temporal explorer MVP

Implemented as the default frontend: snapshot tree and full-file change lenses,
first-parent/root/index/worktree comparisons, scoped history and pins, complete
back/forward locations, snapshot search, and asynchronous repository loading.
The original viewer remains available through `--legacy`.

Follow-ups: incremental history loading and a lane graph; cancellation of active
Git subprocesses; rename-following pins; split-pane resizing and clipboard
selection in the explorer; semantic adapters after the text/Git workflow.

The entries below describe the original two-pane viewer.

This roadmap collects improvements beyond the follow-ups already recorded in
the parent TUI ecosystem roadmap: asynchronous diff loading and load-on-move,
`--graph` support, richer Git features, and preserving search patterns across
diff swaps.

## Near-term improvements

### Responsive and controllable panes

Status: implemented.

The current 45/55 split only collapses when the terminal is fewer than three
columns wide, so narrow terminals do not yet degrade gracefully.

- A 57-column breakpoint provides a useful single-pane layout.
- `z` maximizes or restores the focused pane.
- `,` and `.`, or separator dragging, resize the split.
- A blue half-block separator points into the focused pane.
- A resize that hides the diff returns focus to the list; Tab opens the diff
  maximized when the terminal remains narrow.

This is likely the highest-value small improvement.

### Preserve navigation state

Opening a commit currently creates a fresh pager engine, losing its viewport
and search state. In addition to preserving the search pattern, retain a small
per-commit state cache containing:

- The last line and horizontal offset.
- The current file or hunk.
- The search pattern.
- The selected parent and diff presentation mode.

Returning to a previously viewed commit should restore the same location.

### Discoverability and keyboard actions

As the keymap grows, add an F1 help overlay. Useful small actions include:

- Copy the abbreviated or full commit ID.
- Copy the current filename.
- Copy the complete patch.
- Jump directly to a line or commit.
- Bookmark commits and jump between bookmarks.

Mutating operations such as checkout or reset should remain outside the first
iteration, or require an explicit confirmation layer.

### Focused behavioral tests

The PTY test provides strong end-to-end coverage, but it is one large,
sleep-driven script. Add deterministic functional tests for:

- Commit-ID and ref-decoration parsing.
- Landmark navigation.
- Syntax and diff-line classification.
- Key policy.
- Responsive layout breakpoints.
- Status formatting.

Proof establishes safety; these tests should pin the intended semantics.

## Architectural foundation

### Introduce a structured commit model

The commit list is currently formatted text whose first token must be a commit
ID. Replace that prose boundary with bounded commit records containing:

- Full and abbreviated object IDs.
- Parent IDs.
- Author, date, subject, and decorations.
- Whether the row is selectable.
- Optional graph-column information.

The display document can still be generated from these records. This removes
repeated parsing during painting, avoids reliance on abbreviated IDs when
opening a commit, and provides a cleaner foundation for graph and merge
features.

This architectural step should precede graph rendering, file outlines, and
merge-parent navigation.

### Harden loading and failure handling

Tighten the temporary-file capture edge with controlled cleanup and explicit
states for:

- Loading.
- A cancelled or superseded request.
- A diff that is too large.
- Truncated history or document content.
- A Git command failure, retaining its actual diagnostic.

This work fits naturally with asynchronous diff loading.

## History browsing

### Interactive queries and refresh

History filters currently exist only as command-line options. Add interactive
support for:

- `r` to refresh after repository changes.
- Author, date, message, and path filters.
- Pickaxe searches using `-S` or `-G`.
- A visible summary of active filters.
- Back and forward navigation through previous queries.

For large repositories, load commits in pages instead of running an unlimited
`git log` at startup.

### File-oriented diff navigation

The existing previous/next-file jumps are useful but do not show the shape of
a large commit. Add a changed-file picker or compact outline showing:

- Filename and modification status.
- Added and removed line counts.
- The current file.
- Fuzzy filtering.
- Enter-to-jump behavior.

An overlay is preferable to permanently adding a third pane.

### Merge-aware diffs

Provide explicit control over how merge commits are displayed:

- Cycle through individual parents.
- Switch between combined and first-parent diffs.
- Show a status indicator such as `parent 1/2`.
- Optionally compare against the merge base.

## Diff presentation

Add per-view controls for:

- Increasing or decreasing context.
- Ignoring whitespace.
- Patch, stat, and metadata-only modes.
- Word-diff mode.
- Hiding commit metadata to maximize patch space.
- Toggling syntax, row backgrounds, and all color independently.

These options should form part of the diff-cache key so cached documents are
not reused under incompatible presentation settings.

## Suggested milestone order

1. Responsive and maximized panes.
2. Per-commit view-state retention.
3. Keyboard help and copy actions.
4. Focused behavioral tests.
5. Structured commit records.
6. Interactive filtering and paginated history.
7. File outline and merge-aware diff modes.
8. Additional diff presentation controls.
