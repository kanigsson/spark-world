# Git Changes: implementation plan

## Purpose

Build a small Ada library that turns Git comparisons into a typed, source-neutral
change set.  The library is intended to be the shared textual-change foundation
for `ada_review`, semantic-diff providers, coverage accounting, and future Ada
review clients.

The primary product is an Ada API.  A JSON or other serialized form is not part
of the first implementation unless a concrete non-Ada consumer requires it.
The important contract is the in-memory model: comparison endpoints, changed
files, old/new identities, and changed source spans.

The initial implementation should use the installed Git executable as its
repository backend.  `git diff --raw -z` already supplies most file-level facts,
and using Git preserves the command-line behavior users expect.  AdaCore's
`xdiff` crate is a candidate for computing structured line edits once exact
old/new contents have been obtained.  A focused libgit2 backend remains possible
later, behind the same Ada model.

## Outcome and value

The first useful release should let an Ada caller ask:

```ada
Changes := Git_Changes.Capture
  (Repository => Repo,
   Comparison => Git_Changes.Tree_To_Worktree ("HEAD"),
   Options    => (Detect_Renames => True, others => <>));
```

and then inspect, without parsing patch text:

- the resolved repository and comparison endpoints;
- every changed file, including additions, deletions, renames, copies, mode
  changes, binary files, and submodules;
- old and new paths, modes, and object IDs when those identities exist;
- side-aware zero-context changed spans;
- old and new contents on demand;
- diagnostics, unsupported cases, and worktree-staleness information.

This creates one place to test Git edge cases and removes Git invocation and
diff parsing from review renderers and semantic analyzers.  It does not attempt
to explain changes; it defines the authoritative surface that explanations must
cover.

## Assurance objective

The computational core should target SPARK Silver: absence of run-time errors
for parsing, validation, range arithmetic, cursor movement, and model queries.
The target applies to code that can meaningfully be verified, not to operating
system calls or foreign implementation internals.

The intended boundary is:

```text
normal Ada / trusted boundary
  process execution, filesystem and environment access
  collection allocation and ownership
  hashing implementation
  optional XDiff or libgit2 C binding
                 |
                 | bounded byte strings and validated records
                 v
SPARK core
  raw -z cursor and record parser
  object ID, mode, status, and path validation
  hunk/range parsing and arithmetic
  endpoint and file-change invariants
  deterministic identities and model queries
                 |
                 v
normal Ada adapter
  owned vectors, lazy content loading, public convenience API
```

Silver is realistic if the parser is streaming or cursor-based and returns
views or validated records rather than allocating while it parses.  An outer
Ada layer may copy those records into ordinary containers.  Foreign ranges from
XDiff must be checked against source bounds before entering the proved model.

The Silver claim will explicitly exclude:

- `Storage_Error` and resource exhaustion;
- failures and misbehavior inside Git, the operating system, or C libraries;
- the semantic correctness of Git's diff algorithm;
- atomicity of a working tree that another process changes during capture.

The last item is addressed operationally through fingerprints and freshness
checks, not by AoRTE proof.  Silver alone also does not prove that the parser
implements Git's format correctly, so important parser properties should have
functional contracts and be backed by differential tests against Git.

## Scope

### In scope for version 1

- repository discovery;
- explicit tree, index, and working-tree endpoints;
- tree-to-tree, tree-to-index, index-to-worktree, and tree-to-worktree
  comparisons;
- tracked changes, with an explicit default policy excluding untracked files;
- raw file deltas from a machine-readable Git command;
- configurable rename and copy detection;
- side-aware changed line spans with zero context;
- exact old/new content access where available;
- whole-snapshot access: the paths of a tree, index, or working tree, the
  content of any one of them, and content search over a snapshot;
- revision resolution: expressions, first parents, and the empty tree;
- filtered commit history and the patch text of a single commit;
- binary, symlink, executable-bit, type-change, and submodule classification;
- arbitrary Git path bytes except NUL, without assuming UTF-8;
- SHA-1 and SHA-256 object IDs without a hard-coded 40-character subtype;
- deterministic ordering and identities within a captured change set;
- SPARK Silver evidence for the computational core;
- adapters sufficient to migrate `ada_review` without changing its visible
  unified view.

### Explicit non-goals

The boundary is writing, not breadth.  A client that reviews a repository
needs to read more of it than the change set alone — unchanged files, the
history a comparison sits in, the names a user typed — and every one of those
reads belongs here rather than being reinvented, with its own process
spawning and its own quoting mistakes, in each consumer.  Reads are therefore
in scope as they are needed.  Writes never are:

- clone, fetch, push, commit, checkout, merge, or index mutation;
- anything that changes a repository, its index, or its working tree;
- GitHub, GitLab, or Gerrit APIs;
- semantic or AST differencing;
- review-document rendering or terminal interaction;
- story selection, coverage classification, or provider orchestration;
- binding the full libgit2 API;
- treating JSON as the canonical internal representation;
- silently including untracked or ignored files;
- guaranteeing a coherent snapshot while another process mutates the index or
  working tree.

## Architectural model

Keep four concepts distinct.

### Repository

An opened repository records its canonical worktree root, Git directory,
object-format capabilities, and backend.  Bare repositories are permitted for
tree-to-tree comparisons but cannot supply a working-tree endpoint.

Repository discovery and process invocation belong to the unproved adapter.
Normalized results enter the proved core only after validation.

### Endpoint

An endpoint is one of:

- `Tree`: a resolved tree or commit object ID plus the user's original revision;
- `Index`: the repository index, with a capture fingerprint;
- `Worktree`: tracked filesystem contents, with a capture fingerprint.

The API should expose convenience constructors rather than ask callers to
assemble invalid combinations.  Supported comparisons are:

| Comparison | Git meaning |
|---|---|
| tree to tree | two committed states |
| tree to index | staged changes against a tree |
| index to worktree | unstaged tracked changes |
| tree to worktree | staged plus unstaged tracked changes against a tree |

Endpoint descriptions must record the resolved state used by the capture, not
only the spelling supplied by the caller.

### File change

A file-change record contains:

- an opaque `File_Id`, stable within the captured change set;
- change kind and optional similarity score;
- old and new paths independently;
- old and new file modes;
- old and new object IDs when meaningful;
- binary, submodule, and content-availability flags;
- a sequence of side-aware changed spans;
- diagnostics attached to this file.

A rename or copy is one file-change record with both paths, not a delete/add
pair.  Mode-only and type changes remain visible even if they contain no source
line spans.

`File_Id` is a join key, not a claim of identity across unrelated captures.
It should be deterministic from the comparison identity and the file's
old/new identity, and must not depend on enumeration order.  The exact digest
scheme is an implementation decision recorded before the first consumer adopts
it.

### Changed span

A changed span represents one textual edit with independent old and new ranges.
Use a first line plus a natural line count, so an insertion or deletion does not
require a fictitious line on its absent side.  Spans are one-based where their
count is nonzero.

The model should enforce:

- at least one side has a nonzero count;
- all present ranges are within the corresponding content's line count when
  content is available;
- spans for a file are deterministically ordered;
- spans do not overlap on the same side after normalization;
- every span refers to its owning file rather than repeating paths.

This is the boundary needed by the existing review-evidence coverage ledger,
whose logical files already have stable IDs, old/new paths, and side-aware
changed line spans.

## Proposed package structure

The package names are provisional; the dependency direction is not.

```text
src/
  git_changes.ads                     public domain model and queries
  git_changes-repositories.ads        repository handle and discovery
  git_changes-comparisons.ads         safe endpoint constructors
  git_changes-contents.ads            lazy old/new content access
  git_changes-snapshots.ads           snapshot inventory, content, search
  git_changes-history.ads             filtered commit walk and patch text
  git_changes-revisions.ads           revision, parent, empty-tree resolution

  git_changes-core.ads                SPARK root
  git_changes-core-raw.ads            raw -z record parser
  git_changes-core-hunks.ads          hunk/edit range parser
  git_changes-core-validation.ads     invariants and checked conversions
  git_changes-core-identities.ads     deterministic identity inputs

  git_changes-backends.ads            narrow internal backend interface
  git_changes-backends-git_cli.ads    initial backend
  git_changes-backends-xdiff.ads      optional line-edit backend
  git_changes-backends-libgit2.ads    reserved, not version-1 work

tests/
  unit/                               pure parser/model/proof-oriented tests
  integration/                        temporary Git repositories
  fixtures/                           captured binary-safe command outputs
```

Avoid exposing backend handles or C-owned objects through the public API.  The
core model must remain usable if a later backend is libgit2 or a native Git
implementation.

## Backend strategy

### File inventory: Git CLI

Use a fixed, locale-independent Git invocation based on `git diff --raw -z`,
with explicit options for color, external diff drivers, abbreviation, rename
detection, algorithms, and pathspecs.  Parse NUL-delimited paths as bytes.

The raw parser is intentionally its own proved component.  It must recognize
and reject malformed modes, object IDs, status letters, scores, missing paths,
and trailing data without indexing outside the input.

Do not infer comparison endpoints from the raw output: the adapter constructs
them from the requested comparison and resolved revisions.

### Changed spans: time-boxed parity decision

Evaluate two approaches before committing the public span semantics:

1. Parse zero-context Git hunk headers, obtaining canonical spans from the same
   Git comparison that produced the file inventory.
2. Load exact old/new contents and use AdaCore XDiff to obtain structured edit
   ranges, validating every returned range in Ada/SPARK.

The evaluation fixture must include default, minimal, patience, histogram,
indent heuristic, whitespace options, `.gitattributes`, custom diff drivers,
binary detection, no-final-newline files, and unusual path bytes.

Current preference:

- use XDiff if its normalized ranges match Git for the supported option set;
- otherwise take canonical spans from Git patch hunks and keep XDiff available
  only as an explicitly different content-diff facility;
- do not silently mix file inventory from one comparison policy with spans from
  another.

If patch parsing is selected, invoke it in a way that does not require parsing
quoted header paths to correlate files.  Per-file hunk extraction is acceptable
for the first release; optimize only after measurement.

### Why libgit2 is deferred

The old `a-libgit2` project is useful as generated-binding reference material
but is not a current high-level dependency.  Binding only libgit2's diff subset
is possible, but it introduces C ownership, callback, ABI, and error-lifetime
work before the Ada model has been validated by consumers.

The backend interface should make a later libgit2 experiment possible.  Add it
only if measurements demonstrate that process startup, repeated content access,
or patch parsing is a material limitation.

## Errors and diagnostics

Expected failures should be values, not exceptions crossing the public API.
Distinguish at least:

- invalid repository or unsupported comparison;
- unresolved revision;
- Git command failure;
- malformed backend output;
- unsupported delta or content kind;
- content changed during capture;
- resource or configured-size limit;
- foreign-backend contract violation.

Programmer precondition violations may remain assertions.  The SPARK core must
not rely on unchecked conversions or exception handling for normal parse
control flow.

Diagnostics retain the operation, exit status, and stderr.  Exact command-line
arguments may be retained in debug provenance, but credentials and unrelated
environment values must never be captured.

## Worktree consistency

A working-tree comparison is not naturally immutable.  Version 1 should detect
obvious staleness rather than promise atomicity:

1. resolve tree endpoints and fingerprint the index;
2. obtain file inventory;
3. read required worktree contents;
4. fingerprint captured files and the index again;
5. mark the change set stale or fail according to caller policy if relevant
   state changed.

Fingerprinting should be content-based where identity is required.  Metadata
such as modification time and size may be used as a fast precheck but not as a
durable content identity.

Large files and repositories require explicit configurable limits and a
streaming path.  Limits are part of the public capture options and diagnostics,
not hidden assumptions in the proved parser.

## Incremental delivery

### Milestone 0 — executable specification and skeleton

- Create the Alire/GPR project, package skeleton, tests, and GNATprove project.
- Record the supported Git version assumptions and comparison matrix.
- Capture binary-safe raw-output fixtures for every status kind.
- Write the public type contracts before implementing a backend.
- Decide ownership style for returned change sets and content buffers.

Acceptance:

- the ordinary Ada build and empty test suite run from one documented command;
- GNATprove recognizes the intended core units as SPARK;
- the public spec can represent every required endpoint and file-change kind;
- no JSON schema or libgit2 dependency is introduced.

### Milestone 1 — proved raw file inventory

- Implement the cursor-based `--raw -z` parser in SPARK.
- Add checked parsers for modes, object IDs, statuses, and similarity scores.
- Implement Git repository discovery and the four comparison modes.
- Populate owned Ada file-change records without textual spans.
- Support explicit rename/copy policy and pathspec filtering.

Acceptance:

- all parser and model units achieve Silver or have a reviewed, narrow
  justification;
- differential tests compare every returned field with Git;
- tests cover NUL-delimited rename/copy paths and filenames containing spaces,
  tabs, newlines, quotes, and non-UTF-8 bytes;
- SHA-1 and SHA-256 fixtures do not require different public types;
- a small example program lists typed changes for all four comparison modes.

This is the first useful stopping point.

### Milestone 2 — content access and canonical changed spans

- Implement old/new content loading for trees, index, and worktree.
- Complete the Git-hunk versus XDiff parity evaluation.
- Record the decision and supported diff-option semantics.
- Implement normalized side-aware spans using the selected backend.
- Validate all backend-provided ranges before model insertion.
- Preserve binary and mode-only changes with zero textual spans.

Acceptance:

- normalized spans mechanically match the selected authoritative result;
- insertion, deletion, replacement, empty-file, and no-final-newline cases are
  covered;
- bounds and range arithmetic achieve Silver in the core;
- malformed Git output or invalid foreign ranges produce typed errors;
- `.gitattributes` and custom-driver behavior is documented and tested.

### Milestone 3 — worktree robustness and stable join keys

- Add index and captured-content fingerprints.
- Detect relevant mutation during capture.
- Finalize deterministic `File_Id` and `Span_Id` construction.
- Add limits and streaming behavior for large output and content.
- Complete binary, symlink, submodule, executable-bit, and type-change tests.

Acceptance:

- rerunning an unchanged capture produces the same IDs and ordering;
- unrelated enumeration-order changes do not alter existing file IDs;
- mutation tests either return a coherent capture or a visible stale result;
- all supported non-text changes remain present in the inventory;
- no freshness or resource-limit claim is hidden inside the Silver claim.

### Milestone 4 — first consumer: `ada_review`

- Add a narrow adapter from `Git_Changes.Change_Set` to the existing
  `Ada_Review_Changes` and review-document inputs.
- Move repository/reference ownership and line-status lookup to the shared
  library where appropriate.
- Retain the existing unified renderer and visible patch as a compatibility
  oracle during migration.
- Preserve default `HEAD` versus tracked working-tree behavior and the current
  exclusion of untracked files.

Acceptance:

- `ada_review`'s existing test suite and live smoke behavior remain unchanged;
- added/context status and old/new navigation agree with the current renderer;
- Git loading no longer belongs to the renderer;
- semantic-worker failure still leaves the authoritative textual review usable.

### Milestone 5 — second consumer and extraction check

Use one genuinely independent consumer to verify that the API is not shaped
only around `ada_review`.  Preferred candidates are:

- a direct Ada adapter for review-evidence changed spans;
- the Git-change discovery portion of an Ada semantic provider;
- a small standalone inspection command used only for diagnostics and tests.

Only at this point decide whether a versioned serialization is justified.  If
the selected consumer is non-Ada, add a thin serializer over the existing Ada
model; do not redesign the model around JSON.

Acceptance:

- both consumers use the same comparison and file/span identities;
- neither consumer parses Git output independently;
- consumer-specific presentation and semantic facts remain outside this
  library;
- any serialization round-trips the model and has explicit schema versioning.

### Milestone 6 — measure libgit2, do not assume it

Benchmark representative small interactive diffs and large repositories.  A
libgit2 spike is warranted only if the Git CLI backend is measurably responsible
for unacceptable latency or prevents a required deployment.

If warranted:

- bind only repository open, revision resolution, tree/index/workdir diff,
  delta, hunk, line, similarity, and disposal operations;
- place the complete C interface outside SPARK;
- copy and validate records before exposing them to the core;
- run backend-conformance tests against the Git CLI implementation.

The libgit2 backend must not change the public model or silently change diff
semantics.

## Verification and test strategy

### Proof

- Run one GNATprove process with internal parallelism.
- Make Silver the default proof target for `Git_Changes.Core.*`.
- Require loop invariants and variants for every parser scan.
- Prove cursor bounds, arithmetic, initialization, termination, range
  normalization, and query preconditions.
- Use stronger functional contracts for record consumption, such as monotonic
  cursor advance and delimiter preservation, where their cost is reasonable.
- List all unproved units and trusted subprograms in a checked-in proof-boundary
  document.

### Unit tests

- valid and malformed raw records;
- truncated records at every byte boundary;
- status and score combinations;
- object formats and all-zero object IDs;
- line-range normalization and overflow boundaries;
- deterministic IDs and ordering;
- foreign-range rejection;
- arbitrary path bytes represented without Unicode normalization.

### Temporary-repository integration tests

- clean comparison;
- added, deleted, modified, renamed, and copied files;
- staged-only, unstaged-only, and mixed staged/unstaged changes;
- mode-only, symlink, binary, submodule, and type changes;
- empty files and missing final newline;
- rename thresholds and disabled rename detection;
- pathspecs and `.gitattributes`;
- unborn branch and bare repository where applicable;
- index and worktree mutation during capture;
- SHA-256 repository when supported by the installed Git.

### Differential tests

For each integration fixture, compare the complete returned inventory and span
set mechanically with the exact Git commands used as the specification.  Do
not treat a pretty-printed snapshot alone as sufficient evidence.

## Estimated size

The estimate deliberately separates the first useful slice from production
hardening:

| Slice | Production Ada | Tests, fixtures, proof support |
|---|---:|---:|
| typed model plus raw parser | 500-800 lines | 600-1,000 lines |
| Git adapter and comparisons | 350-600 lines | 500-900 lines |
| content and changed spans | 350-700 lines | 500-900 lines |
| worktree identity and hard cases | 300-600 lines | 500-900 lines |
| consumer adapters | 150-350 lines each | 200-500 lines each |

Milestone 1 should therefore remain around 850-1,400 production lines, with a
similar or larger amount of tests and proof scaffolding.  A robust version 1 is
more likely 1,500-2,700 production lines than a 300-line wrapper.  Most of the
extra code buys explicit endpoint semantics, arbitrary-path correctness,
worktree freshness, proof, and reusable tests—not a new diff algorithm.

## Decision log

Initial decisions:

1. The Ada API is canonical; serialization is deferred.
2. The first repository backend is the Git CLI.
3. `git diff --raw -z` is the authoritative file-inventory input.
4. SPARK Silver is required for the computational core, with a documented
   normal-Ada/foreign boundary.
5. XDiff versus Git hunk parsing is decided by a parity spike, not preference.
6. libgit2 is a replaceable backend experiment, not the architecture.
7. Untracked files are excluded by default and may be added only through an
   explicit policy.
8. Textual changes are authoritative; semantic providers and renderers remain
   separate consumers.

Resolved for version 1:

- public values own their containers and are immutable through the public API;
- `File_Id` uses SHA-256 over resolved comparison, delta, path, mode, object,
  and worktree-fingerprint inputs; `Span_Id` adds its side-aware range;
- paths are exposed as raw byte strings and the diagnostic CLI alone escapes
  them for display;
- command output defaults to 16 MiB, content to 64 MiB, and staleness is marked
  by default with an opt-in fail policy;
- Git zero-context hunk headers are authoritative, so XDiff is not a required
  dependency.

## First implementation step

Start with Milestone 0 and stop after the public type sketch and binary fixture
matrix are reviewable.  In particular, do not begin by generating a libgit2
binding or designing JSON.  The first design review should answer:

1. Can the types represent every Git delta and endpoint without sentinel
   values?
2. Is the SPARK parser boundary small enough to prove at Silver?
3. Can `ada_review` consume the model without pulling presentation concepts
   into it?
4. Can the coverage ledger's file/span inputs be derived without losing rename
   or side identity?

Only then implement the raw parser and Git adapter.
