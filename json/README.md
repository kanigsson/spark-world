# json - an RFC 8259 JSON parser in SPARK

A pull-cursor JSON parser over caller-provided buffers: one event per
call, payloads returned as slices into the input, nothing materialized.
The entire library is SPARK. The current proof work covers absence of
run-time errors, termination, and initialization/data-flow checks (see
Proof Status below). Functional behavior is covered by differential tests
against Python's `json` module on 1914 valid and invalid documents —
including this crate's own GNATprove `result.json` and SARIF output,
compared event by event.

The library is meant for callers that need to parse JSON from untrusted
input without dynamic allocation. There is no heap, no access type, no
recursion, no OS dependency, and no package state. Malformed input is
reported as a status value instead of being handled by raising an
exception. Every byte is validated on the way through: strings are
checked for well-formed UTF-8 (overlong forms, surrogate code points and
sequences above U+10FFFF are rejected) and for complete escapes including
surrogate pairs; numbers are checked against the RFC grammar; a document
that parses to `Document_End` conforms to RFC 8259.

## Packages

| Package        | Contents |
|----------------|----------|
| `JSON`         | `Max_Depth`, the `Status_Type` all layers report through |
| `JSON.Pull`    | the cursor: `Next` delivers one event per call, `Validate` runs the whole document |
| `JSON.Strings` | decoding of string payloads (escapes, `\uXXXX`, surrogate pairs) into a caller buffer |
| `JSON.Numbers` | conversion of number tokens to `Integer_64` / `Long_Float` |

The shape of a client:

```ada
P  : JSON.Pull.Parser;            --  default value = start of document
Ev : JSON.Pull.Event;
St : JSON.Status_Type;
loop
   JSON.Pull.Next (Doc, P, Ev, St);
   exit when St /= OK or else Ev.Kind = JSON.Pull.Document_End;
   case Ev.Kind is ... end case;  --  payload = Doc (Ev.First .. Ev.Last)
end loop;
```

String and key payloads arrive undecoded (the bytes between the quotes);
the event's `Escaped` flag says whether `JSON.Strings.Decode` is needed
at all — when it is, an output buffer the size of the payload provably
suffices, because every escape shrinks. Number payloads arrive as the
token slice with an `Is_Integer` flag; the typed accessors revalidate, so
they are also safe on slices from elsewhere.

## Limits — by design, not by accident

- **Nesting depth is capped at `Max_Depth` (1024).** The parser keeps an
  explicit stack of container kinds instead of recursing, so pathological
  nesting is rejected with `Nesting_Too_Deep` instead of exhausting the
  call stack — the limit RFC 8259 section 9 explicitly permits, and every
  production parser imposes (serde_json: 128, Jackson: 1000). Real-world
  JSON lives below depth 20.
- **The document must fit in memory.** The cursor walks one buffer; there
  is no incremental feed.
- **Typed number accessors are bounded by their machine types.** The
  grammar accepts numbers of any length; `To_Integer` reports overflow
  beyond `Integer_64` as `OK = False`, and `To_Float` is faithful to
  about 1.0E-13 relative error (exact for 53-bit integers), flushes
  below-subnormal magnitudes to zero, and conservatively rejects the last
  decade below `Long_Float'Last`. Callers needing the digits keep the
  token slice.

Everything else — string lengths, member counts, document size — is
bounded only by the input buffer.

Departures from Python's `json` (both deliberate): lone surrogates in
`\uXXXX` escapes are rejected (they have no UTF-8 encoding; Python lets
them into `str` and fails on encode), and `NaN`/`Infinity` literals are
rejected (RFC 8259 has no such tokens; Python accepts them by default).

## Proof Status

The most recent recorded `gnatprove --level=2` run reported **549 checks,
all proved, no justifications, no assumptions** (machine-readable verdict
in `obj/gnatprove/result.json`: `overall = all_proved`). This covers
run-time checks such as overflow, index, range, and division checks, plus
termination of all loops and subprograms, full initialization and
data-flow correctness, and the contracts in the specs — among them: every
payload slice an event delivers lies within the input buffer; every event
except `Document_End` consumes input (so client loops terminate); the
decoded form of a string never exceeds its raw payload's length.

```
gnatprove -P json.gpr -j0
```

## Build

```
gprbuild -P json.gpr                  # release: -O2, checks suppressed
gprbuild -P json.gpr -XMODE=debug    # debug: -gnata, -O0
```

Suppressing checks in release is the point of the proof: the run-time
checks are discharged statically, so the release library runs at
unchecked speed with checked-build safety.

## Tests

```
cd tests && ./run_tests.py            # full corpus (~1900 documents)
cd tests && ./run_tests.py --quick
```

The driver generates handcrafted, random, truncated and bit-flipped
documents, plus real proof-result files, and compares the harness's full
event stream (structure, decoded strings, converted numbers) against
Python's `json` on the same bytes. The harness runs with assertions
enabled; any propagated exception is a failure.
