# git_view roadmap

Completed entries are deleted from this file rather than kept with a
"done" marker, so everything here is work that remains. What was built
and why is recorded in the commit history and, where it is user-visible,
in the README.

## Temporal explorer MVP

Implemented as the default frontend: snapshot tree and full-file change lenses,
first-parent/root/index/worktree comparisons, scoped history and pins, complete
back/forward locations, snapshot search, and asynchronous repository loading.
The original viewer remains available through `--legacy`.

Follow-ups: incremental history loading and a lane graph; cancellation of
active repository queries; rename-following pins; semantic adapters after the
text/Git workflow.

## The tree pane as a working set

Status: proposed.

The middle pane currently cycles through three visibilities: changed files with
their ancestor directories, changed files only, and the complete tree. Three
modes exist because none of them is the right default, but they do not answer
three questions. Changed-only and changed-with-ancestors are two renderings of
one answer, "what is in this comparison?"; the complete tree answers a
different question, "what else does this repository contain?".

The pane's real subject is the set of files the user currently cares about.
That set is seeded by the comparison but must not be limited to it, because a
central product goal is inspecting unchanged definitions, callers, and tests
without leaving the review. The proposed default contents are therefore:

- The changed files of the active comparison, recomputed when the snapshot or
  base changes.
- Pinned files, which survive snapshot and comparison changes.
- Recently opened files, transient and capped, promotable to pins.

Rows stay grouped under their directories rather than flattening to full paths,
because directory rows are how history is scoped to a subtree. Pins and recents
form a group visually separated from the changed set, so the boundary between
the comparison and material dragged in by hand stays legible. With one default
composition, the visibility key either selects only grouped or flat rendering,
or disappears.

The complete tree remains available, but as an explicit browse action rather
than a third of a cycle: a repository is sometimes unfamiliar enough that no
search term is available. Expanding a single directory to all of its files,
reachable from a directory row, covers the common case of looking for siblings
of a changed file and is more useful than the global tree.

Search becomes the ordinary way to reach an arbitrary file. In-pane search
currently filters rows already displayed; it should instead match every path in
the snapshot regardless of the active filter, and opening a result should add
that file to the working set. Snapshot content search should feed the same
mechanism. This makes searching, not mode switching, the gesture that widens
the pane.

Multiple pins are a prerequisite and worth doing on their own. A single pin
slot forces the user to re-find their anchors after every base change, whereas
review typically needs several at once: the changed file, its test, its
specification, and a caller.

The risk of a minimal default is losing the sense of how large a change is
relative to the repository, and hiding neighboring files that should have been
touched. Directory grouping and per-directory expansion address most of it.

Order: multiple persistent pins; snapshot-wide path search that adds to the
set; the composed default with grouping; demotion of the complete tree and
per-directory expansion.

## Syntax highlighting in the explorer

Status: proposed. Defect, not an enhancement.

The explorer has no syntax highlighting at all. The lexical syntax policy
exists and is proved — five language families, keyword and comment
classification, and the display-column arithmetic that maps tokens onto
cells — but only the legacy viewer ever calls it. The explorer's pane painter
applies change marks and the selection bar and nothing else, so the source
pane, which is the pane the product is built around, shows uncoloured text.
The `s` toggle that enables and disables source colouring exists only in the
legacy viewer and is absent from the README key table.

Wiring the existing package up unchanged would not work, and the reason is
structural: language detection is driven by unified-diff headers. The
detector reads `--- a/path` and `+++ b/path`, and the per-line lookup scans
backwards through the document for the nearest such header. The explorer's
source pane holds a whole file, which contains no headers, so every line
would classify as plain.

What is needed is a second detection route, from a path rather than from a
header. The explorer already knows the path of what it is showing, so this is
plumbing plus a filename-extension table, and it belongs beside the existing
header route rather than replacing it: the legacy patch view still needs the
header route while it exists, and a future patch pane would too.

Order: extension-to-language mapping in the syntax package; the explorer
passes the resolved path when it requests a snapshot; the pane painter calls
the token classifier for source rows; then restore the enable/disable toggle
and document it.

## Diff highlighting

Status: proposed. Partly defect, partly enhancement.

The two frontends colour changes by unrelated means and the explorer's is the
weaker one. The legacy viewer classifies a patch line by its leading bytes
into six kinds and layers presentation deliberately: polarity is confined to
the leading gutter column so that syntax foregrounds can carry token colour
without erasing the meaning of the row. The explorer instead receives a mark
per line from the repository worker with four values — normal, addition,
ghost and hunk header — and colours whole rows from them, with no layering
and no notion of file metadata or a commit header.

Four concrete problems.

**The pale washes assume a light terminal.** The theme's own rationale is that
the scheme is written against the sixteen-entry base palette precisely so that
colours follow the user's terminal theme instead of imposing one — and then
the added and removed row backgrounds are hardcoded near-white pastels. On a
dark terminal they read as near-white blocks rather than as a tint. They need
either a light and a dark variant selected from the terminal's background, or
to be expressed as a blend against it, or to fall back to the base palette.

**The explorer duplicates the theme by hand.** Its painter contains four
colour literals which are byte-identical copies of theme constants, so the
theme is no longer the single place a colour decision is recorded. This is
cheap to fix and worth fixing before anything else here, because every
improvement below otherwise has to be made twice.

**Lens handling is asymmetric.** Under the gutter lens an addition is tinted
only in its first column, but a ghost row still takes a full-row background
regardless of lens, so the two polarities do not respond to the same control.

**Syntax and lens have no defined precedence.** The changed-lines lens
recolours unchanged rows to grey, which would also flatten any token colour
those rows carry once syntax highlighting reaches the explorer. Which of the
two wins, per lens, has to be decided rather than left to statement order.

Beyond the defects, the enhancement worth having is intra-line difference:
highlighting the changed span within a modified line rather than the whole
row. This is the single largest readability gain available in the diff view
and it is what the mark array cannot currently express, since it carries one
value per line. It needs a column range per mark, which is a change to the
repository worker's output rather than to the painter alone, and it therefore
wants the structured-record work below to land first.

Order: the explorer adopts the theme; a dark-terminal-aware background
decision shared by both frontends; symmetric lens handling; a stated
syntax-versus-lens precedence; then intra-line spans.

## Working tree and index as history rows

Status: proposed.

The working tree and the index are reachable only as modes. Two keys switch
the snapshot kind, the whole view changes underneath, and nothing on screen
says that uncommitted work exists at all — so the first question a reviewer
asks, "what have I not committed yet?", is answered by a key you have to know
about rather than by looking.

They should instead be two rows at the top of the history pane, above the most
recent commit, selected like any other row. History already reads as "the
snapshots you can look at", and these are two more snapshots; making them
modal states rather than rows is what hides them. The navigation model is
already shaped for this — snapshot selection takes a kind alongside a
revision — so choosing such a row maps onto the existing state directly, and
the two keys become shortcuts rather than the only route.

What blocks it is row identity. History rows carry their commit through a
field typed as a path, and a synthetic row has no object name to put there.
This is the same limitation the structured commit records below exist to fix,
so that work should land first; afterwards a row kind distinguishes the two
synthetic rows from real commits and from the non-selectable rows a lane graph
would add.

One design question to settle rather than default: whether the rows are
always present or appear only when they have content. Two permanently dead
rows at the top of every history is a poor default, but rows that come and go
change what the row beneath the cursor means when the repository is refreshed.
Showing them only when non-empty, and refusing to move the selection when the
set changes, is the likely answer.

## The commit message is not visible anywhere

Status: proposed. Defect.

The explorer never shows a commit message. The history pane has room for a
subject and spends it on one, alongside the abbreviated id, the date, the
decorations and the parent list; the body is nowhere. For a tool built for
reviewing changes this is a real omission — the message is the author's own
account of why the change was made, and it is currently the one thing the
viewer cannot show. The legacy viewer showed it only incidentally, because
patch text happens to begin with the commit header.

It belongs in the source pane, and there is already a slot for it: with no
file selected, that pane shows a placeholder telling the reader to pick one.
That state is the snapshot's own view, and the message is what should fill
it — full body, with the author, date, parents and decorations that currently
have to share a history row. Selecting a file replaces it as it does now, so
nothing is displaced; the message becomes what the source pane shows before a
file narrows it.

This needs one addition below the app. The history query exposes the subject
and no body accessor, and the only other route to the message is the
whole-patch call, which would mean fetching an entire diff to read its header
and then parsing presentation text back into fields — precisely the boundary
the repository worker was written to avoid. So: a body accessor on the history
query first, then the empty-scope rendering.

The entries below describe the original two-pane viewer.

This roadmap collects improvements beyond the follow-ups already recorded in
the parent TUI ecosystem roadmap: asynchronous diff loading and load-on-move,
`--graph` support, richer Git features, and preserving search patterns across
diff swaps.

## Near-term improvements

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

Revised. Two structural facts reordered everything above, both analysed in
`~/aireports/2026-09-10-tui-panes-extraction.md`: the pane, mouse and
clipboard machinery existed twice in incompatible forms, and the two frontends
have separate backends of which the explorer's is a strict superset. Until
both are resolved, every feature listed here must either be written twice or
be written for the frontend that should be deleted. That is why the original
ordering, which was drawn up for the two-pane viewer, no longer applies: most
of its entries are not wrong, they are homeless.

The first of the two is now resolved. `Tui.Panes` owns layout, hit-testing
with pane-local coordinates, gesture recognition under a declared policy, the
selection and its viewport coupling, the overlays and the clipboard encoder,
with emission in `Tui.Term.Clipboard` where effects belong; both frontends use
it, and the explorer gained drag-select, clipboard copy and separator resizing
as a by-product rather than as a third implementation. What remains below is
the backend half.

### Blocking sequence

Each step here unblocks the next.

1. **Structured commit records and a narrowed backend query key.** The commit
   row type the section above already asks for, plus splitting the view state
   into the part that determines what the repository is asked and the part
   that determines only how it is drawn. Today the whole view state is the
   cache key, including focus and viewport fields that cannot affect the
   answer. Prerequisite for the next step, for intra-line diff spans, and for
   working-tree and index rows, all three of which need a row identity that a
   field typed as a path cannot carry.

2. **Backend unification.** The legacy frontend moves onto the explorer's
   repository worker through its existing synchronous entry point, which
   avoids converting it to the asynchronous protocol at the same time. Needs
   one addition: an optional patch document in the frame, since the explorer
   replaced patches with annotated source and the legacy diff pane, its
   landmark navigation and its colouring all read patch text directly.

3. **Retire the legacy frontend.** With the pane layer and one backend in
   place it is a layout preset — two panes and a lens choice — not a second
   program. This is the step that re-homes the entries above: per-location
   view-state retention, help overlay and copy actions, interactive filtering
   and paginated history, the file outline, merge-aware diffs and the diff
   presentation controls all become explorer work with one implementation
   each, and the `--legacy` flag goes away.

### Parallel track

Independent of the sequence above; schedule by appetite. The highlighting work
is user-visible defect repair in the default frontend and should not wait
behind a refactor.

- The explorer adopting the theme instead of duplicating its colour literals.
  Do this first of anything in this track: it is small and it stops every
  later highlighting change from needing to be made twice.
- Dark-terminal-aware diff backgrounds, symmetric lens handling, and a stated
  syntax-versus-lens precedence.
- Syntax highlighting in the explorer, via path-based language detection.
- The commit message in the source pane's empty-scope state. Independent of
  every step above, but gated below the app: it needs a body accessor on the
  history query first. Worth doing early — it is a visible omission, and the
  smallest of the items here once that accessor exists.
- Intra-line diff spans, and working-tree and index rows in the history pane.
  The two exceptions in this track: both need step 1, the first because the
  mark array carries one value per line and cannot express a column range, the
  second because a synthetic row has no object name to carry.
- Multiple persistent pins, and snapshot-wide path search that adds to the
  working set. Both are prerequisites for the tree-pane composition above and
  neither touches the pane or backend work.
