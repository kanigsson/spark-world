# spark-world

A mono-repo of Ada/SPARK projects: proved libraries and programs.

## Layout

```
apps/           programs: a CLI or a TUI, each carrying its own library
libs/           libraries: no executable, a stated API, external clients
experiments/    unfinished, or unclear direction/application
docs/           cross-cutting documentation
tools/          repo-wide build and proof drivers, and shared test scaffolding
```

**Every project sits at exactly `<tier>/<name>/`, two levels below the root.**
That uniform depth is load-bearing: it makes every cross-project reference the
same shape, so moving a project between tiers is a one-token edit.

> **Migration in progress.** Every project has reached its tier, and `docs/`
> still has repo-wide material to absorb. `docs/STATUS.md` records what builds
> and proves, in the flat layout it was measured in. Delete this note when
> those are settled.

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

## Shared scaffolding under `tools/`

Three things live there that projects share but no program ships. None is a
library in the `libs/` sense: nothing here has an external client, and the
promotion rule is about shipped code.

- **`tools/testing/`** — an Ada library project. `Test_Checks` is the
  assertion counter that every test main had its own copy of, and
  `Bench_Timing` the stopwatch the benchmarks did. A test project withs it by
  a path from the root like anything else. Ordinary Ada, deliberately: nothing
  proves the harness, and a contract there would describe the scaffolding
  rather than the library under test.
- **`tools/clitest.py`** — the same for the Python CLI drivers: how the
  program under test is located, and the count they close with. Each driver's
  own `run` stays in the driver, because they genuinely differ.
- **`tools/project.mk`** — the `Makefile` preamble, above.

## Build, test and prove

Each project exposes a `Makefile` with `build`, `test`, `prove` and `flow`
targets, plus `test-contracts` and `bench` where they apply. Every project in
`apps/` now has one. `libs/git_changes` has the equivalent in `scripts/`; the
rest of `libs/` still documents raw `gprbuild` / `gnatprove` lines in its
README. Convert a project when you touch it, not in a sweep.

A target that needs a non-obvious switch carries a comment saying why, not just
the command — `-XMODE=debug` for a test build, a bounded `-j` for a proof whose
provers are near their memory limit. The `Makefile` is where that reasoning
survives; a README line does not stop someone passing `-j0`.

Proof level and switches are a per-project decision — they vary on purpose,
from `--level=2` to `--level=4`.

`format` and `format-check` are the exception to per-project variation: both
call `tools/format-repo`, so every project formats through one traversal and
one set of switches. `format-check` reports and exits non-zero instead of
rewriting, which is what a pre-commit hook or CI wants. Run
`tools/format-repo` with no argument to format the whole repository.

That traversal names each project in turn with `--no-subprojects`, because a
project's sources belong to it alone: reaching them through a client would
format them under the client's settings, and once per client. Two projects are
left out on purpose — the Alire-generated ones under `config/`, and
`libs/unicode_text/sparklib.gpr`, whose sources are SPARKlib's own and live
outside this repository.

**Do not suppress an unproved check to obtain a passing run.** If a check does
not prove, either prove it or record it — in `docs/STATUS.md` for a baseline,
in the project's `AGENTS.md` for a standing exception, with the reason. A green
run that was made green by silencing is worse than a red one, because it stops
anyone from looking again.

## Commit messages

Keep commit messages short: most of the time, just a title will be enough. Add
a short paragraph if the commit is particularly complex.

## Toolchain

One matching GNAT/GPRbuild/GNATprove installation for a project and all its
dependencies. Ada 2022 throughout.

`tools/toolchain.mk` holds the repository's tool pins. A version lives there
and nowhere else; a path to a binary lives nowhere at all. **Never commit a
tool location** — a developer's own choice belongs in an untracked `local.mk`.

Every project's `Makefile` starts with `include ../../tools/project.mk`, which
pulls in `local.mk`, then `toolchain.mk`, then the defaults and the `format`
targets that do not vary. It deliberately does not set `GNATPROVE`: whether a
project names the pinned prover is a claim about that project's proof, so it
stays in the `Makefile` that makes it, beside the comment saying which claim.

### GNATformat

GNATformat is pinned to the version provided by GNAT FSF 16, which returns
version number 26.0 in its `--version` output.

### GNATprove

GNATprove is pinned to GNATprove FSF 16 for the subprojects for which it fully
proves. For the remaining ones, we use whatever is on PATH.
