# git_view

A **git-history viewer** — and the proof-of-ecosystem application (Phase 5 of
the parent `ROADMAP.md`): it embeds the proved `tui_pager` engine **twice**,
as a commit-list pane and a diff pane composited into one surface, on the
`tui_term` driver. The engine knows nothing about git; this host supplies
content from git subprocesses at a trusted edge while all state and policy
stay proved SPARK.

## Use

```sh
git_view          # browse the history of the repository at $PWD
```

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
 / text ⏎        search forward in the focused pane     n  repeat
 ? text ⏎        search backward in the focused pane    N  repeat reversed
 q / Ctrl-C      quit
```

The bottom row is a status bar for the focused pane: `[commits] 3/14 a2b8ad2`
or `[diff] a2b8ad2 1-39/1033 3%`, the search prompt while one is typed, and
transient notes (`Pattern not found`, `No commit on this line`). Resize the
window and the split re-layouts; a too-narrow window degrades to the list
alone; quit and the terminal is restored.

The interface is coloured the way git's own porcelain colours it: added and
removed diff lines green and red, hunk headers cyan, file-level metadata
bold, the `commit` line — and the commit list's abbreviated ids — yellow,
dates cyan. The status bar's accent tracks what it is saying (blue position,
yellow search prompt, red note). Everything is drawn from the base-16
palette, so the colours follow the terminal's theme and survive any
colour-depth downgrade — down to a plain inverse bar on a monochrome
terminal.

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
selection rules (`Git_View_List`), the commit-id parser (`Git_View_Sha`), the
colour scheme and diff-line classifier (`Git_View_Theme`), the search editor
and status formatter. Only the OS edges are trusted
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
alire.toml      crate manifest (depends on tui_pager, tui_term, tui_text)
git_view.gpr    executable project (Main renamed to `git_view`)
src/
  git_view_main.adb           entry point: startup checks + Event_Loop   [Off]
  git_view_source.ads/adb     git subprocess edge (spec proved, body Off)
  git_view_app.ads/adb        state + Paint/On_Key callbacks            [proved]
  git_view_policy.ads/adb     focus-aware keymap                        [proved]
  git_view_list.ads/adb       selection/viewport coupling               [proved]
  git_view_sha.ads/adb        commit-list line -> commit id             [proved]
  git_view_theme.ads/adb      colour scheme + diff-line classifier      [proved]
  git_view_search_input.*     search-pattern editor                     [proved]
  git_view_status.ads/adb     status-line formatter                     [proved]
```
