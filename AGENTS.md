# spark-world

A mono-repo of Ada/SPARK projects: proved libraries and programs.

## Layout

```
apps/           programs: a CLI or a TUI, each carrying its own library
libs/           libraries: no executable, a stated API, external clients
experiments/    unfinished, or unclear direction/application
docs/           cross-cutting documentation
tools/          repo-wide build and proof drivers
```

**Every project sits at exactly `<tier>/<name>/`, two levels below the root.**
That uniform depth is load-bearing: it makes every cross-project reference the
same shape, so moving a project between tiers is a one-token edit.

> **Migration in progress.** Most projects are still at the top level; they
> move into the tiers one commit at a time, libraries first. A reference to a
> project that has not moved yet is one level shorter than the shape above.
> `docs/STATUS.md` records what builds and proves. Delete this note when the
> last project has moved.

## Cross-project references

Always write a cross-project `with` in full, from the repository root:

```ada
with "../../libs/tui/tui.gpr";
```

The same applies to Alire path pins (`{ path = "../../libs/tui" }`) and to
documentation links between projects.

## Which tier

- **`libs/`** — designed as a library from the start, or has become useful to
  more than one client. No executable of its own.
- **`apps/`** — ships a program. Its internal library stays inside the app:
  the regex engine lives in `apps/spark_re`, the diff core in `apps/spark_diff`,
  the DEFLATE codec in `apps/inflate`.
- **`experiments/`** — unfinished, or with unclear direction or application.

**The promotion rule: code moves to `libs/` when a second client wants it**, not
when it looks reusable. A library with one client is that client's code. The
exception is a project that was a library by design from the beginning, like
`git_changes` — those start in `libs/` regardless of client count.

Do not promote code to `libs/` as a side effect of another task. It is a
deliberate change: new directory, new reference paths for every client, and a
wider compatibility obligation.

## Working across projects

**Do not work around a bug or a shortcoming of another project from the calling
side. Fix it where it lives, and say so.** 

When a change to a library breaks a client, both are in this repository, so
both get fixed in the same commit.

## Per-project `AGENTS.md`

Each project carries its own; copy the shape from a neighbour. It covers what
someone changing the project needs and would not infer — the README already
explains it to a user. Keep it short.

Worth stating explicitly wherever it applies: a proof known to be incomplete, a
deliberate `SPARK_Mode => Off` and the reason for it, a generated file not to
hand-edit.

## Build, test and prove

Each project exposes a `Makefile` with `build`, `test`, `prove` and `flow`
targets, plus `test-contracts` and `bench` where they apply. `fuzzy_matcher`,
`spark_diff` and `spark_re` are closest to this, though their build target is
spelled `all`, not `build` — renaming it is part of adopting the convention.
`libs/git_changes` has the equivalent in `scripts/`; the rest still document
raw `gprbuild` / `gnatprove` lines in their README. Convert a project when you
touch it, not in a sweep.

Proof level and switches are a per-project decision — they vary on purpose,
from `--level=2` to `--level=4`.

**Do not suppress an unproved check to obtain a passing run.** If a check does
not prove, either prove it or record it — in `docs/STATUS.md` for a baseline,
in the project's `AGENTS.md` for a standing exception, with the reason. A green
run that was made green by silencing is worse than a red one, because it stops
anyone from looking again.

## Toolchain

One matching GNAT/GPRbuild/GNATprove installation for a project and all its
dependencies. Ada 2022 throughout.

Note one inconsistency: `libs/git_changes/scripts/prove.sh` requires GNATprove 16
specifically and finds it under `~/.alire/`, while every other project proves
with whatever is on `PATH`. Until that is reconciled, the repository proves
with two different provers depending on which project you are in.
