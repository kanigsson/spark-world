# Predicated document parameter crash

Verified on 2026-09-09 with the toolchain recorded in `toolchain.txt`.
This folder is self-contained: three Ada source files and one project file.
No pager or git-changes dependency is needed.

From this directory:

```sh
gnatprove -P repro.gpr -u repro.adb --mode=flow -j4
```

Expected: a normal flow analysis result. Actual: exit 1, with
`Assert_Failure failed precondition from einfo-entities.ads:1997` during
global generation. The complete diagnostic is in `crash.txt`.

`Document` has a dynamic predicate and contains a private, discriminated
`Index` that also has a dynamic predicate. Merely passing the document as
a subprogram parameter and reading its byte-array length triggers the crash.

The application workaround passes the buffer and index separately, keeping
the buffer/index relationship as an explicit precondition.
