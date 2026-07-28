# Ore

`Ore` is a SPARK library of proved building blocks for bounded, heap-free
systems code: no heap, no access types, no tasking, no OS, no exceptions.

The current version is `0.1.0`. Releases follow
[Semantic Versioning](https://semver.org/); see [`VERSION`](VERSION) and
[`CHANGELOG.md`](CHANGELOG.md). The planned scope is listed in
[`ROADMAP.md`](ROADMAP.md).

## Overview

The library is a hierarchy rooted at `Ore`, which holds the physical types its
children share: `Byte`, `Word16/32/64`, the unconstrained `Byte_Array`,
`Byte_Order`, and the capacity ceiling. Each child package adds one bounded,
self-contained abstraction; 0.1.0 provides `Ore.Byte_Buffers`. See
[`ROADMAP.md`](ROADMAP.md) for what is planned.

What a package exports is not only an implementation but the proof vocabulary
for reasoning about it — the predicates and lemmas a client would otherwise
have to re-derive in order to say what an operation preserved, what a value
reads back as, or why a loop terminates in the state it claims. The proof
clients under `tests/proof` exist to check that this vocabulary is usable from
outside.

Two conventions hold throughout. Contracts are element-wise rather than slice-
or sequence-valued, because that is what provers handle at scale. And all ghost
entities sit at the `Static` assertion level, so an assertion-enabled build pays
only for the cheap `Runtime` clauses and never copies a data structure to
evaluate a `'Old`.

## Building and proving

```sh
gprbuild -P ore_lib.gpr                 # the library
gnatprove -P ore_lib.gpr                # the library's own proof
gnatprove -P ore.gpr                    # library plus proof clients
```

Run the tests, which execute with contracts enabled:

```sh
gprbuild -P tests/runtime/runtime_tests.gpr
./obj/runtime_tests/byte_buffer_tests
```

`ore_lib.gpr` is the production project; `ore.gpr` adds the proof clients under
`tests/proof`, which must prove without reaching inside the library.

Everything in 0.1.0 is proved at `--level=2` with no unproved checks and no
justifications.

## Build modes

`ore_lib.gpr` takes an external variable `ORE_BUILD_MODE`:

| Value | Effect |
| --- | --- |
| `debug` (default) | `-gnata`: the executable contracts are checked |
| `release` | `-O2`, no `-gnata`: the contracts have been proved instead |
| `restrictions` | `debug` plus the checks of [`restrictions.adc`](restrictions.adc) |

Ghost code is ignored in every mode; that comes from `gnat.adc`, not from the
mode. A client selects a mode on the command line, which reaches `Ore_Lib`
however deeply it is withed:

```sh
gprbuild -P my_app.gpr -XORE_BUILD_MODE=release
```

A project file cannot set an external for a project it withs — only an
aggregate project can, with `for External ("ORE_BUILD_MODE") use "release";`.

### Checking the no-heap, no-access-types, no-tasking, no-OS, no-exceptions promise

```sh
gprbuild -P ore_lib.gpr -XORE_BUILD_MODE=restrictions
```

This compiles the library under the `pragma Restrictions` of
`restrictions.adc`, into its own object and library directories so that it
never replaces a build that was proved or installed. The restrictions are kept
out of the shipped configuration on purpose: most of them are partition-wide,
recorded in the ALI files and checked by the binder, so a library compiled with
them would force every client to obey them too. Keeping them to a build mode
checks the promise without exporting the obligation.

Two of the five claims are only partly enforceable this way. "No access types"
has no restriction identifier — the language does not let a restriction forbid
declaring one — so what is checked is that nothing is allocated, aliased or
reached through a subprogram pointer. "No OS" is checked as `No_Dependence` on
the runtime units that would signal one; the library in fact has no context
clauses at all.

## Using Ore from another project

### With the sources

```ada
with "<path>/ore_lib.gpr";
```

Every `gprbuild` then builds the library along with the client, and every
`gnatprove` run proves it along with the client. The proof results are cached,
so the cost is paid once, but `--no-subprojects` suppresses it entirely if the
library is proved separately in CI. Note that the library's summary files —
global effects and termination — are written to `lib/gnatprove` by a
`gnatprove` run on the library, not by a build; if a client only ever analyses
with `--no-subprojects` and the library has never been proved locally,
GNATprove falls back to assuming those properties of every call and says so.

### As an installed library

```sh
gnatprove  -P ore_lib.gpr                                  # populates lib/gnatprove
gprbuild   -P ore_lib.gpr -XORE_BUILD_MODE=release
gprinstall -P ore_lib.gpr -XORE_BUILD_MODE=release --prefix=<prefix>
```

`gprinstall` writes an installed project file with `Externally_Built` set to
`"true"`, so GNATprove skips the library's own sources when analysing a client.
The `Install` package in `ore_lib.gpr` additionally copies the `lib/gnatprove`
summary files to `<prefix>/lib/ore_lib/gnatprove`, so clients still get the
library's global effects and termination information rather than assumptions —
which is why the `gnatprove` run above has to come before the install. Without
those files a client proves just as well, but reports for every call that it
is assuming termination and absence of side effects. The build mode is fixed at
install time.

## Licence

Apache License 2.0; see [`LICENSE`](LICENSE).
