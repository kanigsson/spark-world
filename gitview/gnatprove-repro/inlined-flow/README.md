# Inlined callback flow-analysis crash

Verified on 2026-09-09 with the toolchain recorded in `toolchain.txt`.
This is an application-level reproducer, not a minimal standalone case.
It freezes the failing frontend and repository adapter here and inherits
the remaining sources and sibling TUI/git-changes projects from gitview.
Run it in this checkout, with the sibling libraries available.

From this directory:

```sh
gnatprove -P repro.gpr -u git_view_explorer.adb --mode=flow -j4
```

Expected: diagnostics for missing global contracts. Actual: exit 1, with
`Assert_Failure failed precondition from flow_types.ads:544` during flow
analysis. The complete captured diagnostic is in `crash.txt`.

The callback calls local navigation helpers that GNATprove analyzes inline.
Those helpers reach a SPARK-Off repository adapter whose private worker and
mailbox state has no public abstract-state contract in this reproducer.
Normal missing-global diagnostics appear alongside the internal error.
This describes the observed trigger; it is not a diagnosis of the prover's
internal defect.

The application supplies explicit global contracts for helper boundaries
and a repository abstract state. The failing sources are isolated here and
are excluded from the application's build and proof project.
