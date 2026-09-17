# spark_diff

A proved sequence diff and exact apply library, with an ordinary Ada CLI that
renders line-oriented unified diffs on top of it. The executable is
`spark-diff`; there is no patch program.

## Two theorems, and they are the product

`src/` is the whole proof boundary, and the proof goes past run-time safety to
two functional results:

- **Roundtrip.** `Apply (S (1 .. Last), A) = B` for every script `Diff`
  returns — including the whole-sequence replacement it falls back to when the
  distance budget is exhausted.
- **Minimality.** When `Diff` sets `Minimal`, `Lemma_Minimal` proves no valid
  script for the same inputs has fewer insertions and deletions, against an
  arbitrary competitor that need not come from this implementation.

There are no assumed lemmas, imported axioms, suppressed checks or unproved
bodies. A change to the Myers search, the certificate or the script
representation is a change to these theorems; re-prove rather than re-test.
`docs/minimality.md` carries the proof argument — keep it in step with the code.

The converse claim — that *every* within-budget optimum is certified — is
**tested, not proved**, against an independent dynamic-programming oracle. Do
not write it up as proved.

## The fallback is not a failure path

Budget exhaustion or a rejected candidate yields all deletions followed by all
insertions, with the same proved roundtrip and `Minimal = False`. A rejected
certificate does **not** trigger the fallback: the accepted script is returned
unchanged and only the optimality claim is withheld. Keep those two outcomes
distinct.

## Where SPARK stops

The line interner, file I/O, option handling and unified renderer in `cli/` are
ordinary Ada outside SPARK. The library takes natural-number symbols and knows
nothing of lines, so equal IDs must mean equal elements — the CLI's dictionary
checks string equality even when hashes collide, and that check is what makes
the theorem apply to text.

The library performs no I/O, uses no access types and allocates nothing; the
CLI heap-allocates the search buffers. Keep new storage on the CLI side.

## Build, test, prove

```sh
make build            # library, CLI, tests
make test             # core suite, then the CLI suite
make test-contracts   # the same with library runtime contracts enabled
make flow
make prove            # --level=2, cvc5 and z3
```

`Prove` sets `--warnings=error` and `--checks-as-errors=on`, so anything
outstanding fails the run. The baseline has this project fully proved at 546
checks.

The CLI tests apply generated diffs with both GNU `patch --fuzz=0` and `git
apply`, so byte fidelity is checked against real consumers rather than against
this project's own renderer.

## Dependencies

None.
