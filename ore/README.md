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

Each package, in addition to the spec and implementation of a primitive and its
operations, also contains predicates and lemmas intended to help client code
prove their own checks. The proof clients under `tests/proof` exist to check
that these predicates and lemmas are usable from outside.

Two conventions hold throughout.

Contracts state facts element by element rather than as slice equalities or
over a sequence model. Element-wise is the form a client's own checks need them
in: nothing has to bridge a slice equality to the byte it is about, and no
functional-sequence model sits in between — which would in any case be
unbounded and pointer-based. What that costs is that the steps such a model
would give for free, transitivity and carrying a fact across a later write, have
to be supplied explicitly; the lemmas in each package are those steps.

A contract that is checked at run time must not be asymptotically more
expensive than the operation it describes. Postconditions are therefore split
by assertion level: cursor arithmetic and single elements are `Runtime`
clauses, while anything quantified over a buffer — and every `'Old` that would
copy one — is a `Static` clause and is never executed. So an assertion-enabled
build checks that an append moved the cursors, but appending in a loop stays
linear. Where the operation is itself linear, as for `Slice`, the quantified
postcondition does run.

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
justifications. [`PROOF_STATUS.md`](PROOF_STATUS.md) carries the per-unit
figures; regenerate it after a proof run with

```sh
tools/proof_status.py           # or --check, to fail if it is out of date
```

## Formatting

Sources are formatted with `gnatformat` at its defaults: 79 columns, three
spaces of indentation. Every project has to be named in turn, since each one
covers a different source directory:

```sh
for p in ore_lib.gpr ore.gpr tests/runtime/runtime_tests.gpr; do
    gnatformat -P "$p" --no-subprojects --charset utf-8
done
```

`--charset utf-8` is not optional. The comments use UTF-8 punctuation, and
`gnatformat` decodes sources as ISO-8859-1 by default, which rewrites those
characters into mojibake. Add `--check` to report unformatted files and exit
non-zero instead of rewriting them.

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
