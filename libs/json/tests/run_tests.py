#!/usr/bin/env python3
"""Differential test driver for the SPARK json crate.

Generates a corpus of JSON documents — valid, exotic-valid, malformed,
truncated and bit-flipped — and checks the Ada harness against Python's
json module on the very same bytes. For accepted documents the full event
stream (structure, decoded strings, converted numbers) must match; for
rejected documents the crate must reject too (any status, unless a
specific one is asserted). The harness runs with Ada checks enabled, so
any propagated exception surfaces as a FAIL.

Known, deliberate divergences handled here:
  - lone surrogates in \\uXXXX escapes: Python accepts them into str;
    the crate rejects (they are not encodable UTF-8) — detected via
    str.encode failing, expectation flips to REJECT
  - nesting beyond Max_Depth (1024): the crate rejects by design;
    dedicated cases assert NESTING_TOO_DEEP
  - numbers: integers beyond Integer_64 fall back to float conversion
    (compared with tolerance); magnitudes within one decade of
    Long_Float'Last may conservatively report BIG

Usage: run_tests.py [--quick]
"""

import glob
import json
import math
import os
import random
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
HARNESS = os.path.join(HERE, "test_json")
GPRBUILD = shutil.which("gprbuild") or \
    "/home/kanig/sparkdev/wave/x86_64-linux/gnat/install/bin/gprbuild"

QUICK = "--quick" in sys.argv
sys.setrecursionlimit(100000)

cases = []      # (name, path, expect, status)  expect: 'auto'|'reject'
n_files = 0


def case(data, expect="auto", status=None, tag=None):
    global n_files
    n_files += 1
    name = "c%05d.in" % n_files
    path = os.path.join(WORK, name)
    with open(path, "wb") as f:
        f.write(data)
    cases.append((tag or name, path, expect, status))


# ----------------------------------------------------------------------
# Expected output, computed with Python's json on the same bytes
# ----------------------------------------------------------------------

def _no_const(s):
    raise ValueError("NaN/Infinity rejected")


def expected_tokens(data):
    """Token list the harness must produce, or None for 'must reject'."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return None
    try:
        obj = json.loads(text, parse_constant=_no_const,
                         object_pairs_hook=lambda p: ("__obj__", p))
    except Exception:
        return None
    out = []
    if not _walk(obj, out):
        return None
    out.append(("ACCEPT",))
    return out


def _walk(o, out):
    if isinstance(o, tuple) and len(o) == 2 and o[0] == "__obj__":
        out.append(("OBJ",))
        for k, v in o[1]:
            try:
                out.append(("KEY", k.encode("utf-8")))
            except UnicodeEncodeError:
                return False
            if not _walk(v, out):
                return False
        out.append(("ENDOBJ",))
    elif isinstance(o, list):
        out.append(("ARR",))
        for v in o:
            if not _walk(v, out):
                return False
        out.append(("ENDARR",))
    elif isinstance(o, str):
        try:
            out.append(("STR", o.encode("utf-8")))
        except UnicodeEncodeError:
            return False
    elif o is True:
        out.append(("BOOL", True))
    elif o is False:
        out.append(("BOOL", False))
    elif o is None:
        out.append(("NULL",))
    elif isinstance(o, int):
        out.append(("INT", o))
    elif isinstance(o, float):
        out.append(("FLT", o))
    else:
        raise AssertionError(o)
    return True


# ----------------------------------------------------------------------
# Harness output parsing and comparison
# ----------------------------------------------------------------------

def parse_out(b):
    """Parse a .out file into tokens; KEY/STR carry length-prefixed
    bytes that may contain newlines."""
    toks = []
    i = 0
    while i < len(b):
        nl = b.index(b"\n", i)
        line = b[i:nl]
        if line.startswith(b"KEY ") or line.startswith(b"STR "):
            tag = line[:3].decode()
            rest = b[i + 4:]
            sp = rest.index(b" ")
            n = int(rest[:sp])
            payload = rest[sp + 1:sp + 1 + n]
            toks.append((tag, payload))
            i = i + 4 + sp + 1 + n + 1   # past payload and its newline
        else:
            parts = line.decode("latin-1").split(None, 1)
            toks.append(tuple(parts))
            i = nl + 1
    return toks


I64_MIN, I64_MAX = -2**63, 2**63 - 1


def close(a, g):
    return math.isclose(a, g, rel_tol=1e-9, abs_tol=1e-310)


def num_match(exp, act):
    """exp: ('INT', i) or ('FLT', f); act: harness token."""
    kind, v = exp
    if kind == "INT":
        if act[0] == "INT":
            return int(act[1]) == v
        if not (I64_MIN <= v <= I64_MAX):
            try:
                f = float(v)
            except OverflowError:
                f = math.inf
            if act[0] == "FLT":
                return close(f, float(act[1]))
            if act == ("BIG",):
                return math.isinf(f) or abs(f) > 1e307
        return False
    else:
        if act[0] == "FLT":
            return close(v, float(act[1]))
        if act == ("BIG",):
            return math.isinf(v) or abs(v) > 1e307
        return False


def compare(exp, toks):
    """exp: token list or None; toks: parsed harness output.
    Returns None if matching, else a message."""
    if exp is None:
        if toks and toks[-1][0] == "REJECT":
            return None
        return "expected REJECT, got %r" % (toks[-3:],)
    if len(toks) != len(exp):
        if toks and toks[-1][0] == "REJECT":
            return "expected ACCEPT, got %r" % (toks[-1],)
        return "length mismatch: %d vs %d" % (len(toks), len(exp))
    for e, a in zip(exp, toks):
        if e[0] in ("INT", "FLT"):
            if not num_match(e, a):
                return "number mismatch: %r vs %r" % (e, a)
        elif e[0] == "BOOL":
            if a != ("BOOL", "true" if e[1] else "false"):
                return "bool mismatch: %r vs %r" % (e, a)
        elif e[0] in ("KEY", "STR"):
            if a != e:
                return "string mismatch: %r vs %r" % (e, a)
        else:
            if a != e:
                return "token mismatch: %r vs %r" % (e, a)
    return None


# ----------------------------------------------------------------------
# Corpus
# ----------------------------------------------------------------------

def build_corpus():
    rng = random.Random(20260611)

    # --- handcrafted valid ---------------------------------------------
    for s in [
        '{}', '[]', '""', '0', '-0', 'true', 'false', 'null',
        ' \t\r\n{ }\n', '[[[[[]]]]]', '{"a":{"b":{"c":[]}}}',
        '[1,2,3]', '{"a":1,"a":2}',          # duplicate keys: both kept
        '"\\u0000"', '"\\u001f"', '"\\"\\\\\\/\\b\\f\\n\\r\\t"',
        '"\\ud83d\\ude00"',                   # surrogate pair
        '"\xf0\x9f\x98\x80"',                 # the same, raw UTF-8
        '"\xc2\xa0\xe2\x82\xac\xf4\x8f\xbf\xbf"',  # 2/3/4-byte, U+10FFFF
        '"\x7f"',                             # DEL is legal unescaped
        '0.5', '-0.5', '1e0', '1E+0', '1e-0', '0e99', '-0e-99',
        '9223372036854775807', '-9223372036854775808',   # Integer_64 edges
        '9223372036854775808', '-9223372036854775809',   # just beyond
        '123456789012345678901234567890',     # 30 digits
        '1' + '0' * 400,                      # certain overflow: BIG
        '-1' + '0' * 400,
        '1e308', '1e-308', '1e-320', '1e-400', '2.2250738585072014e-308',
        '0.' + '0' * 300 + '1',
        '3.141592653589793', '1.7976931348623157e308',   # may be BIG
        '[0.1,0.2,0.3]', '{"x":1e5}',
        '"' + 'a' * 100000 + '"',             # long string
        '[' + ','.join('"k%d"' % i for i in range(2000)) + ']',
    ]:
        case(s.encode("latin-1") if any(ord(c) > 127 for c in s)
             else s.encode())

    # --- handcrafted invalid -------------------------------------------
    for s in [
        '', ' ', '\n\t', '{', '}', '[', ']', ',', ':', '"', "'a'",
        '01', '-01', '1.', '.5', '+1', '- 1', '1e', '1e+', '1.e5', '1..2',
        '0x10', '1f', 'tru', 'truex', 'TRUE', 'True', 'nul', 'nulll',
        'falsee', 'NaN', 'Infinity', '-Infinity',
        '[1,]', '[,1]', '[1 2]', '{,}', '{"a"}', '{"a":}', '{"a" 1}',
        '{"a":1,}', '{a:1}', '{1:2}', '{"a":1 "b":2}', '[1],',
        '{} {}', '{}x', '[]]', '{}}', '"a" "b"', '123 456',
        '"\\x"', '"\\u12"', '"\\u12g4"', '"unterminated',
        '"\\ud800"', '"\\udc00"', '"\\ud800\\u0041"', '"\\ud800\\ud800"',
        '"\n"', '"\t"', '"\x01"',             # raw control chars
        '["a]', '[--1]', '[+1]', '[01]',
    ]:
        case(s.encode("latin-1"), expect="reject")

    # invalid raw bytes (ill-formed UTF-8 inside strings, BOMs, noise)
    for b in [
        b'"\x80"', b'"\xc0\xaf"', b'"\xc2"', b'"\xe0\x80\x80"',
        b'"\xed\xa0\x80"', b'"\xf4\x90\x80\x80"', b'"\xf5\x80\x80\x80"',
        b'"\xff"', b'"\xe2\x82"', b'"\xf0\x9f\x98"',
        b'\xef\xbb\xbf{}',                    # UTF-8 BOM: not JSON text
        b'\xff\xfe{\x00}\x00',                # UTF-16 LE
        b'\x00', b'\xc3(',
    ]:
        case(b, expect="reject")

    # --- nesting depth --------------------------------------------------
    case(("[" * 100 + "]" * 100).encode())
    case(("[" * 1024 + "]" * 1024).encode(), tag="depth-1024")
    case(("[" * 1025 + "]" * 1025).encode(),
         expect="reject", status="NESTING_TOO_DEEP", tag="depth-1025")
    case(('{"k":[' * 512 + '1' + ']}' * 512).encode(), tag="depth-mixed")
    case(("[" * 5000).encode(),
         expect="reject", status="NESTING_TOO_DEEP", tag="depth-5000")

    # --- random documents, several serializations each -----------------
    def gen(depth):
        r = rng.random()
        if depth <= 0 or r < 0.45:
            k = rng.randrange(7)
            if k == 0:
                return rng.choice([
                    0, 1, -1, 7, 2**31, -2**63, 2**63 - 1,
                    rng.randrange(-10**18, 10**18),
                    rng.randrange(-10**25, 10**25)])
            if k == 1:
                return rng.choice([
                    0.0, -0.0, 0.5, 1e10, -2.5e-10,
                    rng.random(),
                    rng.random() * 10.0 ** rng.randrange(-200, 200)])
            if k == 2:
                n = rng.randrange(0, 12)
                return "".join(rng.choice(
                    'ab "\\\n\té€\U0001f600 z')
                    for _ in range(n))
            return rng.choice([True, False, None, "", "key"])
        if r < 0.75:
            return [gen(depth - 1) for _ in range(rng.randrange(0, 5))]
        return {g if isinstance(g := gen(0), str) else str(g):
                gen(depth - 1) for _ in range(rng.randrange(0, 5))}

    n_random = 60 if QUICK else 300
    for _ in range(n_random):
        doc = gen(4)
        case(json.dumps(doc, ensure_ascii=True).encode())
        case(json.dumps(doc, ensure_ascii=False).encode("utf-8"))
        case(json.dumps(doc, indent=2).encode())
        case(json.dumps(doc, separators=(" ,\n\t", "\t: ")).encode())

    # --- truncations: every prefix of a few small documents ------------
    for s in ['{"ab":[1,true,"x\\n"],"c":-1.5e-2}',
              '[123,"\\ud83d\\ude00",null]',
              '"\xe2\x82\xac\xf0\x9f\x98\x80"'.encode("latin-1").decode(
                  "latin-1")]:
        b = s.encode("latin-1")
        for i in range(len(b)):
            case(b[:i], expect="auto")

    # --- single-byte mutations of valid documents ----------------------
    n_mut = 5 if QUICK else 25
    base = json.dumps({"k": [1, 2.5, "stré", True, None],
                       "deep": {"x": [[]], "y": "€"}},
                      ensure_ascii=False).encode("utf-8")
    for _ in range(n_mut * 20):
        b = bytearray(base)
        i = rng.randrange(len(b))
        b[i] = rng.randrange(256)
        case(bytes(b), expect="auto")

    # --- real files: this crate's own proof results ---------------------
    # The third pattern reaches into another project's proof output, so it
    # tracks that project's location and whether it has been proved lately.
    # Both are wrong for a test to depend on; it is kept for now and is due
    # to be replaced by a fixture of this library's own.
    for pat in ["../obj/gnatprove/result.json", "../obj/gnatprove/*.sarif",
                "../../../inflate/obj/gnatprove/*.json"]:
        for p in glob.glob(os.path.join(HERE, pat)):
            with open(p, "rb") as f:
                case(f.read(), tag=os.path.basename(p))


# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------

def main():
    if os.path.isdir(WORK):
        shutil.rmtree(WORK)
    os.makedirs(WORK)

    print("building harness ...")
    subprocess.run(
        [GPRBUILD, "-P", os.path.join(HERE, "tests.gpr"),
         "-XMODE=debug", "-q"],
        check=True)

    print("generating corpus ...")
    build_corpus()
    manifest = os.path.join(WORK, "manifest")
    with open(manifest, "w") as f:
        for _, path, _, _ in cases:
            f.write(path + "\n")

    print("running harness on %d cases ..." % len(cases))
    r = subprocess.run([HARNESS, manifest])
    crashed = r.returncode != 0

    failures = []
    for tag, path, expect, status in cases:
        out_path = path + ".out"
        if not os.path.exists(out_path):
            failures.append((tag, "no output (harness died here?)"))
            continue
        with open(out_path, "rb") as f:
            toks = parse_out(f.read())
        if expect == "reject":
            if not toks or toks[-1][0] != "REJECT":
                failures.append(
                    (tag, "expected REJECT, got %r" % toks[-3:]))
            elif status and toks[-1][1] != status:
                failures.append(
                    (tag, "expected %s, got %r" % (status, toks[-1])))
        else:
            with open(path, "rb") as f:
                exp = expected_tokens(f.read())
            msg = compare(exp, toks)
            if msg:
                failures.append((tag, msg))

    print()
    if crashed:
        print("FAIL: harness exited with an error (exception?)")
    for tag, msg in failures[:25]:
        print("FAIL %s: %s" % (tag, msg))
    if len(failures) > 25:
        print("... and %d more" % (len(failures) - 25))
    print("%d cases, %d failures" % (len(cases), len(failures)))
    sys.exit(1 if failures or crashed else 0)


if __name__ == "__main__":
    main()
