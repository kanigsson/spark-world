# git_view

A **git-history viewer** — and the proof-of-ecosystem application (Phase 5 of
the parent `ROADMAP.md`): it embeds the proved `tui_pager` engine **twice**,
as a commit-list pane and a diff pane composited into one surface, on the
`tui_term` driver. The engine knows nothing about git; this host supplies
content from git subprocesses at a trusted edge while all state and policy
stay proved SPARK.

## Use

```sh
git_view              # browse the history of the repository at $PWD
git_view main         # browse a branch, tag, object, or revision expression
git_view --no-mouse   # ... without claiming the mouse from the terminal
git_view --author AdaCore --since 2026-01-01
git_view --grep parser --first-parent main
git_view main -- src/   # only commits touching this path
```

History filters are passed as separate Git arguments: `--author VALUE`,
`--since DATE`, `--until DATE`, and `--grep TEXT`. `--all` includes every ref,
`--first-parent` follows the mainline of merges, and the optional path after
`--` restricts history to that path. Filters can be combined with a revision.

## Keys

```
                 commit list (left pane)        diff (right pane)
 j / ↓           select next commit             line down
 k / ↑           select previous commit         line up
 space / f       page of commits down           page down
 b               page of commits up             page up
 g / Home        first commit                   top
 G / End         last commit                    bottom
 h / ←  l / →    scroll long subjects           scroll left / right
 d / u           —                              half page down / up
 Enter           show this commit's diff        line down

 Tab             move the keyboard to the other pane
 s               toggle source syntax colours
 [ / ]           previous / next diff hunk
 { / }           previous / next changed file
 / text ⏎        search forward in the focused pane     n  repeat
 ? text ⏎        search backward in the focused pane    N  repeat reversed
 q / Ctrl-C      quit
```

## Mouse

A left click in the list selects and immediately opens the commit under the
cursor; clicking either pane gives it the keyboard. The scroll wheel scrolls
the pane **under the cursor** — without
moving the keyboard focus, so hovering to scroll never changes what the keys
do. Wheel-scrolling the list drags the selection along, exactly like paging.

Drag with the left button in either pane to retain a text selection and copy
it to the clipboard through OSC 52 (copies are capped at 65,536 bytes, with a
status note if truncated). Shift-drag still asks the terminal for its native
selection; start with `--no-mouse` to leave the mouse entirely to the
terminal.

The bottom row is a status bar for the focused pane: `[commits] 3/14 a2b8ad2`
or `[diff] a2b8ad2 1-39/1033 3%`, the search prompt while one is typed, and
transient notes (`Pattern not found`, `No commit on this line`). Resize the
window and the split re-layouts; a too-narrow window degrades to the list
alone; quit and the terminal is restored.

Diff polarity and source syntax use separate visual channels: the leading
`+`/`-` gutter is green/red while source foregrounds carry syntax colours.
Press `s` to toggle syntax without losing the diff cue. Hunk headers are cyan, file-level metadata
bold, the `commit` line — and the commit list's abbreviated ids — yellow,
dates cyan. The status bar's accent tracks what it is saying (blue position,
yellow search prompt, red note). Everything is drawn from the base-16
palette, so the colours follow the terminal's theme and survive any
colour-depth downgrade — down to a plain inverse bar on a monochrome
terminal.

In the diff pane, `[`/`]` jump between hunk headers and `{`/`}` jump between
changed-file headers. These structural jumps preserve the current `/` search.

The commit list decorates commits with short ref names, including `HEAD`, local
and remote branches, and tags. Decorations are supplied by `git log` but
defensively located and coloured by proved code; the commit ID remains the
first token used to open a diff.

Inside unified-diff hunks, a proved dependency-free lexer adds keyword,
string, comment, and number colours. File extensions select Ada; C, C++,
Rust, Go, Java, JavaScript/TypeScript, Swift and Kotlin; Python and Ruby;
shell; or JSON/TOML/YAML rules. This is lexical highlighting rather than a
full parser, which keeps the executable self-contained and the highlighting
policy inside the Silver proof boundary.

## How it fits together

```
 git log ──▶ Tui.Text Document (commit list; loaded once)
 git show ──▶ Tui.Text Document (diff; swapped per commit)
                  │                          │
 Git_View_App ───▶│ Tui.Pager.Engine (list)  │ Tui.Pager.Engine (diff)
 (selection, keymap,        │                          │
  status, search)           ▼                          ▼
                    pane Surface ──┐          ┌── pane Surface
                                   ▼          ▼
                          Tui.Surface.Copy composites both
                          (plus separator + status row)
                                       │
                          Tui.Term.Event_Loop / Output / Input
```

This is the multi-pane case the engine's component model exists for, and it
exercises two things the standalone pager does not:

- **Two independent engine instances** over two documents, one of which is
  **swapped at run time** (Enter frees the old diff document and loads the
  new one through the subprocess edge — the document predicate keeps the
  engines' content contracts discharged across the swap).
- **A selection.** The engine is a pure viewport; the highlighted "current
  commit" is app state, kept inside the visible slice by proved coupling
  rules (moving the selection drags the viewport only at the screen edges;
  viewport jumps pull the selection back into view).

## SPARK

All app logic is proved (`SPARK_Mode => On`, free of run-time errors): the
state and callbacks (`Git_View_App`), the keymap (`Git_View_Policy`), the
selection rules (`Git_View_List`, `Git_View_Selection`), clipboard extraction
and encoding (`Git_View_Clipboard`), the commit-id parser (`Git_View_Sha`), the
colour scheme and diff-line classifier (`Git_View_Theme`), the multi-language
lexer (`Git_View_Syntax`), and the
app-specific status texts (`Git_View_Status`). The search-pattern editor and
the status `Line` buffer come from the shared
[`tui_app_kit`](../appkit/README.md) crate — this app was their second
consumer, which by the ecosystem's rule triggered the extraction — and are
proved there. Only the OS edges are trusted
(`SPARK_Mode => Off` bodies): the entry point (`Git_View_Main`) and the git
subprocess glue behind the proved `Git_View_Source` spec, which captures
output through a temporary file and never hands back a null diff document.

One contract is prose, not machine-checked: the log format the source uses
keeps the abbreviated commit id as the first space-terminated token of every
line, which is exactly what the proved parser expects.

## Build & prove

```sh
gprbuild -P git_view.gpr                 # builds ./git_view
gprbuild -P git_view.gpr -XMODE=debug    # contracts run
gnatprove -P git_view.gpr --level=2      # the proofs
```

## Layout

```
alire.toml      crate manifest (depends on tui_pager, tui_term, tui_text,
                tui_app_kit)
git_view.gpr    executable project (Main renamed to `git_view`)
src/
  git_view_main.adb           entry point: startup checks + Event_Loop   [Off]
  git_view_source.ads/adb     git subprocess edge (spec proved, body Off)
  git_view_app.ads/adb        state + Paint/On_Key callbacks            [proved]
  git_view_policy.ads/adb     focus-aware keymap                        [proved]
  git_view_list.ads/adb       selection/viewport coupling               [proved]
  git_view_selection.ads/adb  mouse selection ordering                  [proved]
  git_view_navigation.ads/adb structural file/hunk scanning             [proved]
  git_view_refs.ads/adb       commit-list ref decoration span            [proved]
  git_view_clipboard.ads/adb  bounded extraction + OSC 52 encoding      [proved]
  git_view_sha.ads/adb        commit-list line -> commit id             [proved]
  git_view_theme.ads/adb      colour scheme + diff-line classifier      [proved]
  git_view_syntax.ads/adb     source language + lexical highlighting    [proved]
  git_view_status.ads/adb     status-line texts (notes, read-outs)      [proved]
```

The search-pattern editor and the status `Line` buffer come from the
shared `tui_app_kit` crate.
