# Proof status

Recorded on 2026-07-26 with the active GNATprove toolchain.

## Library and dependency closure

```sh
gnatprove -P json.gpr -XSPARKLIB_EXTERNALLY_BUILT=true \
  -f -j16 --level=2 --report=fail
```

- JSON units: 472 checks proved.
- Full imported runtime closure, including Unicode Text: 2,044 checks proved.
- Flow errors: 0.
- Unproved checks: 0.
- Justifications: 0.
- `pragma Assume` statements: 0.

## Client usability

```sh
gnatprove -P tests/proof/proof_clients.gpr \
  -XSPARKLIB_EXTERNALLY_BUILT=true -f -j16 --level=2 --report=fail
```

The focused client unit contributes 18 proved checks. It demonstrates:

- direct `Code_Point_Length` use after successful `JSON.Strings.Decode`;
- the empty active decode prefix;
- direct Unicode use of a successful unescaped pull-event payload;
- a terminating `JSON.Walk` member loop using decoded key matching.

No client performs a second `Is_Valid_UTF_8` check and no client uses an
assumption or justification.

## Runtime acceptance

```sh
gprbuild -P json.gpr -XMODE=debug
cd tests
gprbuild -P tests.gpr
./test_unicode
./test_walk
./run_tests.py
```

The focused Unicode and walk suites pass. The differential suite passes all
1,918 generated and real-artifact cases.
