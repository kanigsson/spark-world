# git_view

A read-only project, source, diff, and history explorer. Select a snapshot,
browse its complete tree, and overlay a comparison without checking anything
out. History, tree, and source share one navigation state.

```sh
./git_view                            # HEAD, compared with its first parent
./git_view feature                    # any commit, branch, or tag
./git_view --base v1.0 v2.0            # arbitrary comparison
./git_view --worktree                 # HEAD -> working tree
./git_view --index                    # HEAD -> index
./git_view --all --author NAME        # history across refs, filtered by author
./git_view main -- src/               # directory-scoped history
```

`--since`, `--until`, `--grep`, and `--first-parent` filter history. Start from
any directory in the repository. Paths inside the explorer are repository
relative. `--no-mouse` leaves mouse handling to the terminal.

## The model

Independent values decide what each pane shows.

A **snapshot** is what you are looking at: a commit, the working tree, or the
index. A **base** is what it is compared against, either derived automatically
or set explicitly. The comparison therefore has a target side and a base
side; the source pane can read either exact file or interleave both.

A **pane** is one of three vertical strips, in the order one determines the
next: history picks the snapshot, the tree picks the path, the source shows the
file. Each pane keeps its own viewport, selection, and search pattern. A
selection made anywhere else -- at startup, from a prompt, by a pin, or by back
and forward -- is shown on the row that names it, so the panes and the values
they stand for never disagree.

History lists the working tree and the index above the commits when their
respective categories contain changes, so uncommitted and staged work is a
snapshot reached by moving the selection like any other.
The tree lists the commit message as its first row, `COMMIT_MSG`, above the
files: what the commit says about itself is read the same way as what it
changed. A working tree and an index have no message to show.

**Tree visibility** selects which files the tree lists. Source **side** selects
target, base, or both. A source presentation preset independently selects a
full plain file, a full file with gutter or emphasized changes, or hunks with
nearby context. Change navigation is independent of presentation: plain files
retain every comparison landmark even though they draw no change decoration.

At startup the snapshot is `HEAD`, the base is its first parent, the tree lists
the changed files only with the first of them in scope, and the source shows
target-side hunks. A comparison with no file to open falls back to the commit
message.

Everything else is a transition on those values, and the whole set — snapshot,
base, scope, pin, filters, visibility, source side and presentation, focus,
per-pane selections, viewports, and search patterns — is a single value. That
is why back and forward
restore a location completely rather than approximately, and why a **pin**,
which holds one path fixed while the snapshot moves, is enough to walk a file
through history.

## Navigation

| Key | Action |
| --- | --- |
| Tab | Cycle history, tree, source focus |
| j/k, arrows | Move the selection, which the panes to its right follow at once, or scroll the source |
| Enter, left click | Open a commit, file, or search result: a directory filters history, a file takes the keyboard |
| Left drag | Select pane text; releasing copies it to the clipboard |
| Drag a pane boundary | Resize the two panes on either side of it |
| Wheel | Scroll the pane under the cursor, which also takes the keyboard |
| PageUp/PageDown, Space, Home/End | Page or jump within the focused pane |
| h/l, left/right | Horizontal scrolling |
| z | Maximize/restore; a terminal too narrow for three panes drops the most disposable one, and never the focused one |
| a | Tree: changed only ↔ all files |
| d | Source presentation: hunks → plain → gutter → changed lines |
| v | Source side: target → base → both |
| [ / ] | Previous/next hunk |
| { / } | Previous/next changed file |
| f / F | Filter history to scope / clear path and repository-search filters |
| p | Pin/unpin the current path across snapshots |
| Backspace / Alt-Left | Back |
| Alt-Right | Forward |
| /, n/N | Literal search in the focused pane; next/previous match |
| S | Literal search throughout the snapshot; Enter opens a result |
| c | Select snapshot and history root by revision |
| b | Set comparison base; empty input restores the automatic base |
| w / i | Working tree / index snapshot, which are also the first two history rows |
| r | Refresh repository data |
| q | Quit |

Enter a prompt value and press Enter; Escape cancels. Selecting a directory
filters history to that directory. File history uses Git path history;
renames are marked in comparisons but pins do not heuristically follow them.
An absent pinned file stays selected and is explicitly reported as absent.

A commit message reads as the commit's own account of itself: the object name,
who wrote it and when, then the message as Git stored it. It is a row like a
file, so it can be pinned and followed through history; it names no path, so
it scopes no history filter.

Commits compare with their first parent; roots compare with the empty tree.
History marks ordinary commits with `*` and merges with `M`, and includes
parent IDs and ref decorations. Selecting a historical commit does not
restrict the history list to that commit's ancestors: you can move both
backward and forward through the original history scope.

Target and base sides are exact files from the two comparison endpoints.
`PLAIN` displays the selected file without gutters or opposite-side rows;
`GUTTER` and `CHANGED_LINES` retain the full selected file and annotate it;
`HUNKS` retains nearby context. `[` and `]` navigate the same comparison
regions in every presentation and side.

The `BOTH` side interleaves base-only rows with the target file. Each row
carries a sign and the target line it shows, in a column as wide as the file
needs, so the text stays aligned throughout:

```
   40 | unchanged line
-     | line the base had here
+  41 | line the snapshot has instead
```

Removed lines have no target line to name, so they leave that column blank and
are drawn as italic, pale red ghost rows. New and deleted files report the side
on which they are absent, and their existing side remains readable as ordinary
source. Binary files and changed submodules have placeholders. Untracked,
nonignored files are available in the working-tree view.

Moving the selection is how the explorer is read: the history pane's row is
the snapshot and the tree pane's row is the scope, so arriving on a row shows
it. Enter keeps the row you arrived on -- it moves the keyboard to the source,
or filters history to a directory. A run of moves records one location, the
one it started from, so back leaves a browse rather than retracing it.

Back/forward restores the snapshot, comparison, path, pin, filters, tree
visibility, source side and presentation, focus, selections, search patterns,
and pane scroll offsets.
The stack retains 128 locations in each direction; a new navigation discards
the forward branch.

## Implementation and verification

`Git_View_Model` holds frontend-independent navigation values and transitions.
`Git_View_Explorer` derives three pager panes from those values. Both are
SPARK, with Silver verification of runtime safety. The existing proved pager,
input, search, and legacy viewer remain in use.

Panes themselves are no longer this project's code. `Tui.Panes` in the sibling
TUI crate owns the row of panes, hit-testing, gesture recognition, the
selection and its viewport coupling, the overlays and the clipboard encoder;
`Tui.Term.Clipboard` writes the OSC 52 sequence, because that is an effect and
effects live in the driver. What each frontend keeps is policy: what a click
means, which panes it declares and how disposable each is, and — now stated
rather than implied — whether the wheel moves the keyboard. It does in the
explorer and does not in the legacy viewer, which is the divergence the two
copies had before they became one.

`Behavior_Tests` pins the decisions those units make -- commit-id and
ref-decoration parsing, landmark navigation, diff-line and syntax
classification, the keymap, the pane row this frontend declares and the status
text -- from
literal inputs, with no repository, terminal or timing involved. Proof covers
safety; this suite covers intent, and is what a move of this code between
frontends or crates is checked against.

`Git_View_Repository` is a trusted repository adapter. Every Git query it
makes goes through the [`git_changes`](../../libs/git_changes) library in this
repository: change kinds, old/new paths, metadata, changed spans, snapshot
inventories and contents, snapshot search, revision resolution, and history.
No Git process is started in this project, and no repository path is read
directly. Document assembly, caching, and the worker mailbox are outside
SPARK and covered by integration tests. Silver does not establish Git's
behavior or the semantic correctness of the rendered diff.

Repository requests run on a worker. Results carry a generation and obsolete
results are discarded. The terminal keeps processing input while loading, and
a request submitted while one is running replaces it rather than queueing
behind it, so holding an arrow key down costs the frames it skips nothing.

What a keystroke costs is what it changes. The repository handle, revision
resolutions, comparisons, commit contents and the history walk are each kept
under the inputs they were made with, and so are the rendered history and tree
panes: moving the scope within one comparison rebuilds the source alone, and a
snapshot listing is asked for only when something needs it -- the complete
tree, a working tree's untracked files, or a path the comparison never
mentions. A row of a pane names its commit or path as a slice of one buffer
per pane, so a frame costs the identities it carries rather than a fixed size
per row. Pressing `r` drops all of it and asks Git again.
The worker finishes an active repository query before stopping; terminal
state is restored when the UI exits.

What reaches the terminal is the same economy. A frame already loaded stays
on screen while the next one is fetched, marked `[loading]` on the status
line, so a keystroke repaints the cells it changed rather than blanking the
panes and painting them back; the selected row moves at once and the panes
that follow it catch up. Only the first load, with no frame to hold, shows a
banner. Beneath that, only cells that differ from the last frame are written,
a run of neighbouring cells costs one cursor move rather than one per cell,
and the frame is wrapped in synchronized output so a terminal that
understands it never shows one half drawn.

```sh
gprbuild -P git_view.gpr -j4
gnatprove -P git_view.gpr --level=2 -j4
gprbuild -P tests/explorer_tests.gpr -j4
obj/tests/model_tests
obj/tests/behavior_tests
obj/tests/load_bench HEAD PATH      # frame timings in the current repository
python3 tests/run_explorer_tests.py
python3 tests/run_explorer_pty_tests.py
python3 tests/run_mouse_tests.py        # legacy regression suite
```

Use one matching GNAT/GNATprove toolchain for the application and dependencies.
The project uses Ada 2022. Alire pins the TUI libraries and git_changes by
path within this repository.
`-XMODE=debug` builds the TUI without optimization; release is the default.

This implements the text/Git MVP from
[docs/temporal_code_explorer_design.md](docs/temporal_code_explorer_design.md). Semantic
analysis, review annotations, combined merge views, and side-by-side rendering
remain deferred. History is loaded in full, within the capture limit; files
and command captures are limited to 64 MiB and path identities to 4096 bytes.
Unborn repositories are not yet supported. Repository search is the
library's fixed-string snapshot search over tracked files; untracked files
can be opened and searched individually.

The original two-pane diff viewer is available with `--legacy`; see
[LEGACY.md](docs/LEGACY.md) for its syntax highlighting and its own key bindings.
Both frontends now share one pane layer — layout, hit-testing, gesture
recognition, selection and clipboard encoding all live in `Tui.Panes` — so
mouse selection, clipboard copy and pane resizing behave the same in each.
