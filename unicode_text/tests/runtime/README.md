# UTF-8 runtime conformance tests

`utf_8_tests.adb` checks independent encodings at every scalar boundary,
exhaustively round-trips every Unicode scalar value, and systematically varies
lead and continuation octets across the valid and malformed UTF-8 classes. It
also covers truncation, overlong forms, surrogates, values above U+10FFFF,
embedded zero octets, validation error offsets, empty strings, and non-default
Ada string bounds.

`plain_string_tests.adb` covers Milestone 3 code-point length, indexed access,
forward cursor progress, prefix, suffix, comparison, mixed-width text, and
non-default Ada string bounds.

Run it from the repository root with:

```sh
gprbuild -P tests/runtime/runtime_tests.gpr
./obj/runtime_tests/utf_8_tests
./obj/runtime_tests/plain_string_tests
```
