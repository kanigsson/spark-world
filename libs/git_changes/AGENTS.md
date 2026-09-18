# git_changes

Git comparisons as typed, source-neutral change sets, plus the read-only
questions a reviewing client asks around them: revision resolution, snapshot
inventory, content and search, and filtered history. A library by design from
the start, which is why it is in `libs/` with one client rather than waiting
for a second.

## It reads; it never writes

**The library never mutates a repository** — no clone, fetch, push, commit,
checkout or index write — and a client must be able to rely on that without
reading the code. Adding a write here is a change of contract, not a feature.
Untracked files are excluded from comparisons on purpose. Expected capture
failures come back as typed `Error_Info` values rather than exceptions.

## The CLI is not the product

`git_changes_cli.gpr` builds a `git-changes` executable, which is why this
library has an executable at all despite being in `libs/`. It is a diagnostic
front end and the machine-protocol emitter (`--format=json`), for non-Ada
consumers; the Ada API is the canonical representation. Keep it that way — a
feature that exists only in the CLI is in the wrong place.

The JSON output is a **versioned** protocol: see `docs/machine-protocol.md`
before changing a field, since it was added for consumers outside this
repository.

## The one dependency

`git_changes.gpr` withs `../../libs/ore/ore_lib.gpr`, for `Ore.Images` alone:
the decimal image the JSON writer and the temp-file namer both need, and the
hexadecimal pair the `\u00XX` escape needs. Nothing else here uses Ore, and the
proved units do not touch it.

That escape is worth keeping in view when changing it. This library emits
byte-transparent JSON — input byte `16#XX#` becomes U+00XX — because a git
path is not required to be UTF-8, which is why the escape wants a fixed-width
two-digit image and not a minimal-width one.

## Proof covers three units, not the library

`scripts/prove.sh` names `Git_Changes.Core.Validation`, `.Core.Raw` and
`.Core.Hunks` explicitly and proves those to Silver (`--level=2`, 189 checks).
"All proved" here means those three — not the whole library, and not a
functional-correctness claim about Git's formats. `docs/proof-boundary.md`
states what is deliberately outside the claim: process creation, the
filesystem, owned containers and `Unbounded_String`, SHA-256, Git's own diff
algorithm, `Storage_Error`, and a concurrently changing index.

That boundary is the design: Git CLI interaction and owned containers stay
outside the SPARK core, and the adapter validates every raw record and hunk
before copying it into the owned model. Parsing added anywhere else should be
moved into `Core` and proved instead.

## Build, test, prove

```sh
./scripts/build.sh
./scripts/test.sh     # 183 core checks, 55 integration scenarios
./scripts/prove.sh
```

Scripts rather than a Makefile, unlike the rest of the repository; converting
them is a later job and not urgent.

**This project proves with a different prover from every other one here.**
`scripts/prove.sh` requires GNATprove 16 specifically and finds it under
`~/.alire/`, while everything else proves with whatever is on `PATH`. So the
repository currently proves with two provers depending on which project you
are in. That is a known incoherence, recorded in `docs/STATUS.md`, and is for
the consolidation phase — do not "fix" it here by loosening the version check,
which would silently change what the proof result means.

`env.sh` is ignored by git on purpose: it selects this machine's Alire and
GNATprove 16 without baking those paths into the crate.

## Clients

`git_view` withs `../../libs/git_changes/git_changes.gpr` and issues no git
commands of its own — every repository query it makes comes through here. A
gap in this library shows up there as a temptation to shell out; fix it here
instead.
