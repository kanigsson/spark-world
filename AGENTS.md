# spark-world

A mono-repo of Ada/SPARK projects: proved libraries and the programs built on
them. Eleven projects, previously eleven separate repositories, merged with
their full history on 2026-09-17 (see `MIGRATION.md`).

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

> **Migration in progress.** The projects are still at the top level; they move
> into the tiers in phases. `docs/STATUS.md` records what builds and proves.
> Delete this note when the last project has moved.

## Cross-project references

Always write a cross-project `with` in full, from the repository root:

```ada
with "../../libs/tui/tui.gpr";
```

Even between two projects in the same tier, where `../tui/tui.gpr` would also
resolve. One shape everywhere means there is never a question of which form to
write, and a tier change touches one path component.

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
side. Fix it where it lives, and say so.** This was the rule when these were
separate repositories and a fix meant a second checkout; in one repository
there is no excuse left. A workaround in a client hides a defect in a library
that other clients still have.

When a change to a library breaks a client, both are in this repository, so
both get fixed in the same commit.

## Per-project `AGENTS.md`

Each project carries its own, covering:

- **What it is** — one paragraph, and what it deliberately is not.
- **Dependencies** — which projects, and why each one is there.
- **Build, test, prove** — the exact commands (see below).
- **SPARK posture** — what is proved, what is deliberately not, what is
  `SPARK_Mode => Off` and why. `libs/tui_term` is the clearest case: it is
  `Off` on purpose because it owns termios, signals and controlled types, and
  keeping it separate is what makes "the rest performs no I/O" structural.
- **Anything an agent would otherwise get wrong** — a proof that is known
  incomplete, a test that needs a fixture, a generated file not to hand-edit.

Keep it short. The README explains the project to a user; `AGENTS.md` covers
what someone changing it needs and would not infer.

## Build, test and prove

Each project exposes a `Makefile` with these targets:

| Target | Meaning |
| --- | --- |
| `build` | the library and any executables |
| `test` | the full suite, including Python differential drivers |
| `prove` | the project's own proof run, at its own level and switches |
| `flow` | `--mode=flow` only |

Optional where they apply: `test-contracts` (the suite again with `-gnata`, so
contracts execute), `bench`.

Three projects have this already (`fuzzy_matcher`, `spark_diff`, `spark_re`);
`git-changes` has the equivalent in `scripts/`; the rest document raw
`gprbuild` / `gnatprove` lines in their README. Convert a project when you touch
it, not in a sweep.

The proof level and switches are a per-project decision recorded in that
project's `Makefile` and `AGENTS.md` — they vary on purpose, from `--level=2`
to `--level=4`.

**Do not suppress an unproved check to obtain a passing run.** If a check does
not prove, either prove it or record it — in `docs/STATUS.md` for a baseline,
in the project's `AGENTS.md` for a standing exception, with the reason. A green
run that was made green by silencing is worse than a red one, because it stops
anyone from looking again.

## Toolchain

One matching GNAT/GPRbuild/GNATprove installation for a project and all its
dependencies. Ada 2022 throughout.

Note one inconsistency: `git-changes/scripts/prove.sh` requires GNATprove 16
specifically and finds it under `~/.alire/`, while every other project proves
with whatever is on `PATH`. Until that is reconciled, the repository proves
with two different provers depending on which project you are in.
