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

Four values decide everything on screen.

A **snapshot** is what you are looking at: a commit, the working tree, or the
index. A **base** is what it is compared against, either derived automatically
or set explicitly. The snapshot alone supplies the source text; the base only
adds annotations to it.

A **pane** is one of three vertical strips, in the order one determines the
next: history picks the snapshot, the tree picks the path, the source shows the
file. Each pane keeps its own viewport, selection, and search pattern.

**Tree visibility** selects which files the tree lists. **A lens** selects which
lines of the file the source shows, from the plain file through gutter
annotations, changed lines, hunks, and before/after. The two are independent:
one filters files, the other filters lines within whichever file is open.

Everything else is a transition on those values, and the whole set — snapshot,
base, scope, pin, filters, visibility, lens, focus, per-pane selections,
viewports, and search patterns — is a single value. That is why back and forward
restore a location completely rather than approximately, and why a **pin**,
which holds one path fixed while the snapshot moves, is enough to walk a file
through history.

## Navigation

| Key | Action |
| --- | --- |
| Tab | Cycle history, tree, source focus |
| j/k, arrows | Move selected row or scroll source |
| Enter, left click | Follow a commit, file, or search result |
| Left drag | Select pane text; releasing copies it to the clipboard |
| Drag a pane boundary | Resize the two panes on either side of it |
| Wheel | Scroll the pane under the cursor, which also takes the keyboard |
| PageUp/PageDown, Space, Home/End | Page or jump within the focused pane |
| h/l, left/right | Horizontal scrolling |
| z | Maximize/restore; a terminal too narrow for three panes drops the most disposable one, and never the focused one |
| a | Tree: changed and ancestors → changed only → all files |
| d | Lens: gutter → changed lines → hunks → before/after → plain |
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
| w / i | Working tree / index snapshot |
| r | Refresh repository data |
| q | Quit |

Enter a prompt value and press Enter; Escape cancels. Selecting a directory
filters history to that directory. File history uses Git path history;
renames are marked in comparisons but pins do not heuristically follow them.
An absent pinned file stays selected and is explicitly reported as absent.

Commits compare with their first parent; roots compare with the empty tree.
History marks ordinary commits with `*` and merges with `M`, and includes
parent IDs and ref decorations. Selecting a historical commit does not
restrict the history list to that commit's ancestors: you can move both
backward and forward through the original history scope.

The source always comes from the selected snapshot. Changing the base changes
annotations. Removed lines use italic, pale red `- [base]` ghost rows;
deleted files are labeled base-only. Gutter and changed-lines lenses retain
the full file. Hunk lenses retain nearby context. Binary files and changed
submodules have placeholders. Untracked, nonignored files are available in
the working-tree view.

Back/forward restores the snapshot, comparison, path, pin, filters, tree
visibility, lens, focus, selections, search patterns, and pane scroll offsets.
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
makes goes through the sibling [`git-changes`](../../git-changes) Ada
library: change kinds, old/new paths, metadata, changed spans, snapshot
inventories and contents, snapshot search, revision resolution, and history.
No Git process is started in this project, and no repository path is read
directly. Document assembly, caching, and the worker mailbox are outside
SPARK and covered by integration tests. Silver does not establish Git's
behavior or the semantic correctness of the rendered diff.

Repository requests run on a worker. Results carry a generation and obsolete
results are discarded. Commit content, tree listings, history, and comparisons
are cached separately. The terminal keeps processing input while loading.
The worker finishes an active repository query before stopping; terminal
state is restored when the UI exits.

```sh
gprbuild -P git_view.gpr -j4
gnatprove -P git_view.gpr --level=2 -j4
gprbuild -P tests/explorer_tests.gpr -j4
obj/tests/model_tests
obj/tests/behavior_tests
python3 tests/run_explorer_tests.py
python3 tests/run_explorer_pty_tests.py
python3 tests/run_mouse_tests.py        # legacy regression suite
```

Use one matching GNAT/GNATprove toolchain for the application and dependencies.
The project uses Ada 2022. Alire pins the sibling TUI crates and git-changes.
`-XMODE=debug` builds the TUI without optimization; release is the default.

This implements the text/Git MVP from
[temporal_code_explorer_design.md](temporal_code_explorer_design.md). Semantic
analysis, review annotations, combined merge views, and side-by-side rendering
remain deferred. History is loaded in full, within the capture limit; files
and command captures are limited to 64 MiB and path identities to 4096 bytes.
Unborn repositories are not yet supported. Repository search is the
library's fixed-string snapshot search over tracked files; untracked files
can be opened and searched individually.

The original two-pane diff viewer is available with `--legacy`; see
[LEGACY.md](LEGACY.md) for its syntax highlighting and its own key bindings.
Both frontends now share one pane layer — layout, hit-testing, gesture
recognition, selection and clipboard encoding all live in `Tui.Panes` — so
mouse selection, clipboard copy and pane resizing behave the same in each.
