# Proof Status: Unicode Text Milestone 5
<!-- Reflect the top-level goal given. Items in the list below are moved from
     Not Started to In Progress to Reviewed and finally to Proved and Finalized. -->

Milestone 5 is complete. The final forced fresh whole-project run proved all
2,433 checks, and all runtime suites pass.

## Proved and Finalized
<!-- Before marking an item complete here, follow the Widen Scope step
     (Strategic Loop Step 5) in workflow.md in the /gnatprove Skill.
     Remember: changes to types used by or called subprograms in a given
     subprogram may cause it to regress to an unproved state. Reproving at the
     wider scope is thus a critical means to detect these situations. -->

- [x] Unicode Text Milestone 5
  - [x] byte spans and complete-range UTF-8 validity
  - [x] byte-span and code-point slicing
  - [x] scalar, substring, reverse, and containment search
  - [x] byte/model slice and search equivalence
  - [x] bounded slice and search wrappers
  - [x] ordinary, bounded, and repeated-search proof clients
  - [x] Milestones 1 through 4 reverified at whole-project scope

## Acceptance Evidence

- `gnatprove -P unicode_text.gpr -f -j16 --prover=cvc5,z3,altergo
  --timeout=30`: 2,433/2,433 checks proved.
- UTF-8 runtime suite: 4,450,793 checks passed.
- Plain-string runtime suite: 66 checks passed.
- Bounded-string runtime suite: passed.
- No assumptions, suppressed checks, or concurrent GNATprove processes were
  used.
