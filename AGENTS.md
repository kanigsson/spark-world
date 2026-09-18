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

> **Migration in progress.** Every project has reached its tier;
> `experiments/` does not exist yet, and `docs/` still has
> repo-wide material to absorb. `docs/STATUS.md` records what builds and
> proves, in the flat layout it was measured in. Delete this note when those
> are settled.

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

`tools/toolchain.mk` holds the repository's tool pins and is included by every
project's `Makefile`. A version lives there and nowhere else; a path to a
binary lives nowhere at all. **Never commit a tool location** — a developer's
own choice belongs in an untracked `local.mk`.

### The formatter is pinned, and why

No two releases of GNATformat agree about how to lay out Ada, so an unpinned
run rewrites every source it is pointed at. That turns formatting one project
into a repo-wide diff whenever a developer's `PATH` offers a different build —
a development wavefront, say. So `tools/gnatformat` resolves a formatter at run
time and verifies its `--version`, refusing to run on a mismatch rather than
reformatting the world. It searches `PATH` first, then the places Alire
installs into.

The pin is `GNATFORMAT_VERSION`, currently the formatter that ships alongside
FSF GNAT 16. **Mind the numbering: that formatter calls itself 26.0.** The
number tracks the release year, not the compiler, so a pin of `16.` matches
nothing.

The formatting switches live in `tools/gnatformat` too, stated explicitly even
where they match today's defaults — a default that moves in a later release
would otherwise reflow the repository silently, whereas stated there it becomes
a visible edit. `--charset utf-8` is not one of the negotiable ones: sources
hold UTF-8 punctuation and the formatter decodes as ISO-8859-1 unless told
otherwise, turning it into mojibake.

Raise the pin deliberately, in its own commit, separate from the reformat it
causes.

### The prover is pinned where the proof is clean

`tools/gnatprove` is a resolver of the same shape as `tools/gnatformat`: it
finds a GNATprove matching `GNATPROVE_VERSION` at run time, checks its
`--version`, and refuses rather than proving with whatever `PATH` offers. It
passes no switches of its own — level, provers and timeouts stay a per-project
decision.

Unlike the formatter, the pin is **opt-in per project**, because a prover pin
is a claim. A project that names the pinned prover is saying it proves clean
against it, so only the projects that do have been pinned:

| Project | Pinned | Why not |
| --- | --- | --- |
| `libs/tui` | yes | |
| `libs/unicode_text` | yes | |
| `libs/git_changes` | yes | |
| `apps/fuzzy` | yes | |
| `apps/spark_diff` | yes | |
| `apps/spark_re` | yes | |
| `libs/ore` | no | bit-level `2**N` lemmas time out |
| `apps/inflate` | no | outstanding checks of its own, plus Ore's |
| `apps/git_view` | no | proves `git_changes` with weaker switches than `git_changes` uses on itself |
| `libs/json` | no | a few checks unproved inside SPARKlib's own float lemmas, not in `json` |
| `libs/tui_term` | n/a | `SPARK_Mode => Off` by design |

Pinning one of the rest is a one-line edit — `GNATPROVE ?= $(SPARK_WORLD_PROVE)`
in its `Makefile` — made when its last check closes, not before. Pinning a
project with outstanding checks would promise a clean run it does not deliver,
which is the same failure as silencing a check.

A project without a `Makefile` states the resolver in the `gnatprove` line its
`README` and `AGENTS.md` document, until it is converted.
