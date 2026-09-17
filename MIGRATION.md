# Import of spark-world

This repository is the union of eleven previously separate repositories,
imported on 2026-09-17 with their full history replayed. Nothing was
reconciled: each project sits in its own top-level directory exactly as it
stood in its own repository. The eventual layout (`libs/`, `apps/`,
`experiments/`, ...) is a later concern.

## How the import was done

Each source repository was mirror-cloned, rewritten so every path in every
commit moved under a directory named after the project, and then merged into
this repository's trunk with `--allow-unrelated-histories`. The root commit
here is empty so that no single project had to become the first parent.

Consequences worth knowing:

- Commit hashes differ from the sources; the trees are byte-identical.
- The trunk therefore has eleven roots. `git log -- <dir>` works as expected
  for any project.
- Every branch of every source was kept, renamed to `<project>/<branch>`,
  and the one tag became `fuzzy_matcher/v0.1.0`.
- Uncommitted work in the sources was deliberately **not** imported (see
  below).

## What was imported

| Directory | Source path | Branch merged into trunk | Source tip |
| --- | --- | --- | --- |
| `git-changes/` | `~/tools/git-changes` | `main` | `e9e20a4` |
| `fuzzy_matcher/` | `~/tools/fuzzy_matcher` | `main` | `027bb36` |
| `spark_diff/` | `~/tools/spark_diff` | `main` | `b3a0503` |
| `spark_re/` | `~/tools/spark_re` | `rg-front-end` | `9fdf427` |
| `unicode_text/` | `~/tools/unicode_text` | `main` | `eda0817` |
| `ore/` | `~/tools/ore` | `main` | `52352dc` |
| `inflate/` | `~/tools/pager/inflate` | `ore-migration` | `f4a40a9` |
| `gitview/` | `~/tools/pager/gitview` | `main` | `307bc91` |
| `json/` | `~/tools/pager/json` | `main` | `8aa16cb` |
| `term/` | `~/tools/pager/term` | `main` | `357ca86` |
| `tui/` | `~/tools/pager/tui` | `main` | `28a60c2` |

`spark_re` and `inflate` were merged from the branch that was checked out in
the source working tree, not from `main`, so the trunk reflects the state
actually being worked on. Their `main` is present as `spark_re/main` and
`inflate/main`.

`ore` was not in the original import list. It was added because
`inflate/inflate.gpr` reaches out to `../../ore/ore_lib.gpr`, which would
otherwise dangle.

## Projects that still have a GitHub upstream

These five keep a remote in their source repository. Until the upstreams are
archived or redirected, a push from the old clone and a commit here can
diverge silently, so decide per project which side is authoritative.

| Directory | Upstream |
| --- | --- |
| `fuzzy_matcher/` | `git@github.com:kanigsson/fuzzy.git` |
| `spark_diff/` | `git@github.com:kanigsson/spark_diff.git` |
| `spark_re/` | `git@github.com:kanigsson/spark_re.git` |
| `unicode_text/` | `git@github.com:kanigsson/unicode_text.git` |
| `inflate/` | `git@github.com:kanigsson/inflate.git` (plus an `origin` on the internal proxy, `http://e3-auth-proxy:8081/kanig/inflate.git`) |

The other six had no remote at all.

## What was left behind

The source repositories were not modified and still hold work that is not
here:

- Uncommitted files, by explicit choice: `goal.txt`, `html/` and `plans/` in
  `pager/inflate`; `plans/` and a deleted `unicode-text-integration-handoff.md`
  in `pager/json`; `spark_string_library_design.md` and `tests/spikes/` in
  `unicode_text`; `byte_buffers.txt` in `ore`.
- Five further repositories under `~/tools/pager`, not part of this import:
  `app` (the pager CLI, 14 commits), `string` (9), `docs` (13), `httpd` (1)
  and `proof` (1).

## Known breakage

Nothing was adjusted to fit the new layout, so cross-project paths that used
to escape a repository are now wrong. The one known case is
`inflate/inflate.gpr`, whose `with "../../ore/ore_lib.gpr"` resolved to
`~/tools/ore` and now points outside this repository; `ore/` is one level up
from `inflate/`, not two.
