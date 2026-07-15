#!/usr/bin/env python3
"""Test driver for the SPARK inflate crate.

Generates a corpus of DEFLATE/zlib/gzip streams — valid, exotic-valid,
malformed, truncated and bit-flipped — and checks the Ada harness against
the verdict of C zlib (via Python's zlib module) on the very same bytes.
For accepted streams the decoded output must match byte for byte; for
rejected streams the crate must reject too (any status). The harness runs
with Ada checks enabled, so any propagated exception surfaces as a FAIL.

Usage: run_tests.py [--quick]
"""

import gzip as gzip_mod
import io
import os
import random
import struct
import subprocess
import sys
import tarfile
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
CORPUS = os.path.join(HERE, "corpus")
HARNESS = os.path.join(HERE, "test_inflate")
CANTERBURY_URL = "https://corpus.canterbury.ac.nz/resources/cantrbry.tar.gz"

QUICK = "--quick" in sys.argv

manifest = []   # (mode, input_path, expected_path_or_-, out_cap, consumed)
n_files = 0


def put(name, data):
    path = os.path.join(WORK, name)
    with open(path, "wb") as f:
        f.write(data)
    return path


def case(mode, comp, expect, consumed=-1, tag=None):
    """Register one test case. expect=None means 'must be rejected';
    expect="?" means 'any status is accepted as long as the harness returns'."""
    global n_files
    n_files += 1
    inp = put("c%05d.in" % n_files, comp)
    if expect is None:
        exp = "-"
        cap = max(4 * len(comp), 1 << 20)
    elif expect == "?":
        exp = "?"
        cap = max(4 * len(comp), 1 << 20)
    else:
        exp = put("c%05d.exp" % n_files, expect)
        cap = len(expect) + 64
    manifest.append((mode, inp, exp, str(cap), str(consumed)))


compress_checks = []  # (input_path, original_bytes)
TRIPLE_RUN = b"ABC" * 1000


def gen_compress(files):
    """Round-trip cases for the adaptive compressor: the harness
    compresses each file, checks its own round trip and the decode-model
    relation, and writes <input>.gz; the driver then decodes that member
    with C zlib and compares, so the compressor is differentially tested
    from both sides."""
    global n_files
    inputs = dict(files)
    inputs["triple-run.bin"] = TRIPLE_RUN
    for name, data in sorted(inputs.items()):
        n_files += 1
        inp = put("c%05d.in" % n_files, data)
        manifest.append(("compress", inp, "-", str(len(data) + 64), "-1"))
        compress_checks.append((inp, data))


def check_compress_outputs():
    def stream_prefix(raw, start, length):
        value = 0
        for i in range(length):
            value = (value << 1) | ((raw[(start + i) // 8]
                                     >> ((start + i) % 8)) & 1)
        return value

    bad = 0
    for inp, data in compress_checks:
        gz = inp + ".gz"
        try:
            member = open(gz, "rb").read()
            out = gzip_mod.decompress(member)
        except (OSError, EOFError, zlib.error, struct.error) as e:
            print("FAIL compress %s: zlib rejects our gzip: %s" % (inp, e))
            bad += 1
            continue
        if out != data:
            print("FAIL compress %s: zlib decodes %d bytes, expected %d"
                  % (inp, len(out), len(data)))
            bad += 1
        if (member[10] & 7) != 3:
            print("FAIL compress %s: input did not use final fixed block"
                  % inp)
            bad += 1
        if len(data) >= 6 and not any(data):
            raw = member[10:-8]
            # Header (3 bits), then one fixed-code zero literal (8 bits).
            # Position 1 is an unaligned token boundary; the selector emits
            # fixed length symbol 258 (length 4, code 2), then distance 1.
            if (stream_prefix(raw, 11, 7) != 2
                    or stream_prefix(raw, 18, 5) != 0):
                print("FAIL compress %s: zero run did not emit the "
                      "unaligned length-4/distance-1 match" % inp)
                bad += 1
            if len(member) * 4 >= len(data) * 3:
                print("FAIL compress %s: zero-run ratio did not improve"
                      % inp)
                bad += 1
        if data == TRIPLE_RUN:
            raw = member[10:-8]
            # Header and three literals consume 27 bits.  The next token is
            # length 3 followed by fixed distance code 2 (distance 3).
            if (stream_prefix(raw, 27, 7) != 1
                    or stream_prefix(raw, 34, 5) != 2):
                print("FAIL compress %s: repeated triple did not emit the "
                      "length-3/distance-3 match" % inp)
                bad += 1
    print("compress differential: %d cases, %d failures"
          % (len(compress_checks), bad))
    return bad


def zlib_verdict_raw(comp):
    """C zlib's one-shot verdict on a raw deflate stream.

    Returns (accepted, output_bytes). A stream that zlib does not finish
    (no final block reached) counts as rejected, matching the one-shot
    'whole stream must be present' semantics.
    """
    d = zlib.decompressobj(wbits=-15)
    try:
        out = d.decompress(comp, 1 << 26)
        if not d.eof:
            return (False, out)
        return (True, out)
    except zlib.error:
        return (False, b"")


def zlib_verdict_gzip(comp):
    try:
        return (True, gzip_mod.decompress(comp))
    except (zlib.error, EOFError, gzip_mod.BadGzipFile, struct.error):
        return (False, b"")


def differential_raw(comp, tag):
    ok, out = zlib_verdict_raw(comp)
    case("raw", comp, out if ok else None, tag=tag)


# ----------------------------------------------------------------------
#  Corpus
# ----------------------------------------------------------------------

def fetch_corpus():
    os.makedirs(CORPUS, exist_ok=True)
    marker = os.path.join(CORPUS, ".ok")
    if not os.path.exists(marker):
        print("fetching Canterbury corpus ...")
        tgz = os.path.join(CORPUS, "cantrbry.tar.gz")
        subprocess.run(["curl", "-sSL", "-o", tgz, CANTERBURY_URL],
                       check=True)
        with tarfile.open(tgz) as t:
            t.extractall(CORPUS, filter="data")
        os.unlink(tgz)
        open(marker, "w").close()
    files = {}
    for name in sorted(os.listdir(CORPUS)):
        p = os.path.join(CORPUS, name)
        if os.path.isfile(p) and not name.startswith("."):
            files[name] = open(p, "rb").read()
    # Synthetic additions: incompressible, constant, structured
    rng = random.Random(20260610)
    files["random.bin"] = bytes(rng.randrange(256) for _ in range(200_000))
    files["zeros.bin"] = bytes(300_000)
    files["pattern.bin"] = bytes(range(256)) * 800
    files["empty.bin"] = b""
    files["tiny.bin"] = b"a"
    return files


# ----------------------------------------------------------------------
#  Valid streams in all shapes zlib can produce
# ----------------------------------------------------------------------

def gen_valid(files):
    levels = [0, 1, 6, 9] if not QUICK else [0, 9]
    wbits_list = [9, 12, 15] if not QUICK else [15]
    strategies = [zlib.Z_DEFAULT_STRATEGY, zlib.Z_FILTERED, zlib.Z_RLE,
                  zlib.Z_FIXED, zlib.Z_HUFFMAN_ONLY]
    for name, data in files.items():
        for level in levels:
            for w in wbits_list:
                co = zlib.compressobj(level=level, wbits=-w)
                comp = co.compress(data) + co.flush()
                case("raw", comp, data, consumed=len(comp))
            co = zlib.compressobj(level=level, wbits=15)
            comp = co.compress(data) + co.flush()
            case("zlib", comp, data, consumed=len(comp))
            comp = gzip_mod.compress(data, compresslevel=level)
            case("gzip", comp, data, consumed=len(comp))
            case("gzip_all", comp, data)
        # Strategies exercise unusual block/code shapes (fixed codes,
        # huffman-only, RLE) that default compression rarely emits.
        for strat in strategies:
            co = zlib.compressobj(level=6, wbits=-15, strategy=strat)
            comp = co.compress(data) + co.flush()
            case("raw", comp, data, consumed=len(comp))
    # Multi-member gzip (pigz/gzip concatenation semantics)
    a, b = files["tiny.bin"], files["pattern.bin"]
    comp = gzip_mod.compress(a) + gzip_mod.compress(b)
    case("gzip_all", comp, a + b)
    comp = gzip_mod.compress(b) + gzip_mod.compress(b) + gzip_mod.compress(a)
    case("gzip_all", comp, b + b + a)
    # Flush points produce multiple deflate blocks incl. empty stored ones
    data = files["pattern.bin"]
    co = zlib.compressobj(level=6, wbits=-15)
    comp = b""
    for i in range(0, len(data), 5000):
        comp += co.compress(data[i:i + 5000])
        comp += co.flush(zlib.Z_FULL_FLUSH)
    comp += co.flush()
    case("raw", comp, data, consumed=len(comp))


# ----------------------------------------------------------------------
#  Gzip header features
# ----------------------------------------------------------------------

def gen_gzip_headers():
    payload = b"the quick brown fox jumps over the lazy dog" * 10
    co = zlib.compressobj(level=9, wbits=-15)
    deflated = co.compress(payload) + co.flush()
    trailer = struct.pack("<II", zlib.crc32(payload), len(payload) & 0xFFFFFFFF)

    def member(flg, extra=b"", name=b"", comment=b"", hcrc=False):
        hdr = struct.pack("<BBBBIBB", 0x1F, 0x8B, 8, flg, 0, 0, 3)
        if flg & 4:
            hdr += struct.pack("<H", len(extra)) + extra
        if flg & 8:
            hdr += name + b"\0"
        if flg & 16:
            hdr += comment + b"\0"
        if flg & 2:
            hdr += struct.pack("<H", zlib.crc32(hdr) & 0xFFFF)
        return hdr + deflated + trailer

    # Every flag combination, checked against C zlib/gzip
    for flg in range(32):
        comp = member(flg, extra=b"\x01\x02subfield", name=b"file.txt",
                      comment=b"a comment", hcrc=bool(flg & 2))
        ok, out = zlib_verdict_gzip(comp)
        assert ok and out == payload, "self-check failed for FLG=%d" % flg
        case("gzip", comp, payload, consumed=len(comp))

    # Reserved flag bits must be rejected
    for flg in (0x20, 0x40, 0x80):
        case("gzip", member(0) [:3] + bytes([flg]) + member(0)[4:], None)
    # Bad magic, bad method
    good = member(0)
    case("gzip", b"\x1f\x8c" + good[2:], None)
    case("gzip", good[:2] + b"\x07" + good[3:], None)
    # Corrupted header CRC
    bad = bytearray(member(2, hcrc=True))
    bad[10] ^= 0xFF
    case("gzip", bytes(bad), None)
    # Corrupted data CRC, corrupted ISIZE
    bad = bytearray(good); bad[-5] ^= 0xFF
    case("gzip", bytes(bad), None)
    bad = bytearray(good); bad[-1] ^= 0xFF
    case("gzip", bytes(bad), None)
    # Truncations at every byte of a small member
    for i in range(len(good)):
        case("gzip", good[:i], None)


# ----------------------------------------------------------------------
#  Hand-crafted DEFLATE streams (a bit writer, LSB first)
# ----------------------------------------------------------------------

class BitWriter:
    def __init__(self):
        self.bits = []

    def b(self, value, n):
        for i in range(n):
            self.bits.append((value >> i) & 1)
        return self

    def huff(self, code, n):
        # Huffman codes are packed MSB first
        for i in reversed(range(n)):
            self.bits.append((code >> i) & 1)
        return self

    def bytes(self):
        out = bytearray((len(self.bits) + 7) // 8)
        for i, bit in enumerate(self.bits):
            out[i >> 3] |= bit << (i & 7)
        return bytes(out)


def gen_crafted():
    # Each crafted stream goes through the differential check, so the
    # expectation is C zlib's, not ours.

    # BTYPE = 3 (reserved)
    differential_raw(BitWriter().b(1, 1).b(3, 2).bytes(), "btype3")

    # Stored block: bad NLEN
    differential_raw(b"\x01\x05\x00\x05\x00hello", "bad-nlen")
    # Stored block: good, exercising the aligned path
    differential_raw(b"\x01\x05\x00\xfa\xffhello", "stored")
    # Stored, LEN = 0
    differential_raw(b"\x01\x00\x00\xff\xff", "stored-empty")
    # Stored, truncated payload
    differential_raw(b"\x01\x06\x00\xf9\xffhello", "stored-short")

    # A deep chain of valid empty stored blocks used to exhaust the stack
    # when debug builds executed the recursive proof relation in public
    # postconditions. The shipping decoder is iterative; the debug project
    # must keep contracts disabled so this remains an ordinary linear case.
    deep_stored = b"\x00\x00\x00\xff\xff" * 32_767 + b"\x01\x00\x00\xff\xff"
    case("raw", deep_stored, b"", consumed=len(deep_stored),
         tag="deep-stored-chain")

    # Fixed block, just end-of-block (symbol 256 = 0000000 in 7 bits)
    differential_raw(BitWriter().b(1, 1).b(1, 2).huff(0, 7).bytes(), "fixed-empty")
    # Fixed block: literal 'A' (65 -> code 0x30+65=113, 8 bits), then EOB
    differential_raw(
        BitWriter().b(1, 1).b(1, 2).huff(0x30 + 65, 8).huff(0, 7).bytes(),
        "fixed-lit")
    # Fixed block: length symbol 257 (len 3) + distance too far (dist 1
    # with nothing produced... actually emit lit then match dist 2 > 1)
    w = BitWriter().b(1, 1).b(1, 2)
    w.huff(0x30 + 65, 8)          # literal 'A'
    w.huff(1, 7)                  # length symbol 257 -> length 3
    w.huff(1, 5)                  # distance symbol 1 -> distance 2 (too far)
    w.huff(0, 7)
    differential_raw(w.bytes(), "dist-too-far")
    # Same but distance 1: valid run 'AAAA'
    w = BitWriter().b(1, 1).b(1, 2)
    w.huff(0x30 + 65, 8).huff(1, 7).huff(0, 5).huff(0, 7)
    differential_raw(w.bytes(), "fixed-run")
    # Fixed block: reserved length symbols 286/287, reserved dist 30/31
    for sym, bits in ((0b11000110, 8), (0b11000111, 8)):  # 286, 287
        w = BitWriter().b(1, 1).b(1, 2).huff(sym, bits)
        differential_raw(w.bytes(), "reserved-len")
    w = BitWriter().b(1, 1).b(1, 2)
    w.huff(0x30 + 65, 8).huff(1, 7).huff(30, 5)
    differential_raw(w.bytes(), "reserved-dist")

    # Dynamic block templates
    def dyn_header(w, hlit, hdist, hclen, cl_lens):
        w.b(1, 1).b(2, 2)
        w.b(hlit - 257, 5).b(hdist - 1, 5).b(hclen - 4, 4)
        for v in cl_lens:
            w.b(v, 3)

    # HLIT too large (30 -> 287), HDIST too large (31)
    w = BitWriter(); dyn_header(w, 287, 1, 4, [0, 0, 0, 0])
    differential_raw(w.bytes(), "hlit-too-big")
    w = BitWriter(); dyn_header(w, 257, 31, 4, [0, 0, 0, 0])
    differential_raw(w.bytes(), "hdist-too-big")

    # Code-length code completely empty -> must be rejected
    w = BitWriter(); dyn_header(w, 257, 1, 4, [0, 0, 0, 0])
    differential_raw(w.bytes(), "empty-clc")

    # Over-subscribed code-length code (three 1-bit lengths)
    w = BitWriter(); dyn_header(w, 257, 1, 6, [1, 1, 0, 0, 0, 1])
    differential_raw(w.bytes(), "oversub-clc")

    # A minimal complete dynamic stream:
    #   CL code: sym16=x sym17=x sym18=1bit '0' sym0=2bit? Use:
    #   lengths: 18->1, 1->2? Keep it simple: CL lens for syms
    #   (16,17,18,0,8,...) = [0,0,1,2,0,...,2?]
    #   Instead craft with code-length code over {18:1, 8:2, ...}
    # CL order: 16 17 18 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1 15
    # Give: 18 -> len 1 (code 0), 8 -> len 2 (code 10), 0 -> len 2 (code 11)
    w = BitWriter(); dyn_header(w, 257, 1, 5, [0, 0, 1, 2, 2])
    # lit/len lengths: 256 zeros... no: 0..255 zero via 18-runs, 256 -> 8
    # 18-run covers 11..138 zeros: 138 + 118 = 256
    w.huff(0, 1).b(138 - 11, 7)      # 18: 138 zeros
    w.huff(0, 1).b(118 - 11, 7)      # 18: 118 zeros
    w.huff(0b10, 2)                  # symbol 8: literal 256 len 8?? -> len-8 code for sym 256
    w.huff(0b11, 2)                  # symbol 0 for the single distance code -> dist sym 0 len... 0 means absent
    # 256 has the only code (length 8 -> code 00000000); distance table empty
    w.huff(0, 8)                     # end of block
    differential_raw(w.bytes(), "dyn-minimal")

    # Same but the distance table gets one 1-bit code (incomplete dist =
    # legal); reuse CL sym 8? distance length 8 -> fine too.
    w = BitWriter(); dyn_header(w, 257, 1, 5, [0, 0, 1, 2, 2])
    w.huff(0, 1).b(138 - 11, 7)
    w.huff(0, 1).b(118 - 11, 7)
    w.huff(0b10, 2)                  # 256 -> len 8
    w.huff(0b10, 2)                  # dist 0 -> len 8 (single dist code, incomplete)
    w.huff(0, 8)
    differential_raw(w.bytes(), "dyn-one-dist")

    # Repeat (16) with no previous length
    w = BitWriter(); dyn_header(w, 257, 1, 5, [1, 0, 1, 0, 0])
    # CL code: 16 -> 1 bit (code 0), 18 -> 1 bit (code 1)
    w.huff(0, 1).b(0, 2)             # 16 first -> invalid
    differential_raw(w.bytes(), "repeat-first")

    # Repeat running past HLIT+HDIST
    w = BitWriter(); dyn_header(w, 257, 1, 5, [0, 0, 1, 2, 2])
    for _ in range(2):
        w.huff(0, 1).b(138 - 11, 7)  # 2 x 138 zeros = 276... ok
    w.huff(0, 1).b(127, 7)           # +138 -> 414 > 258 -> overrun
    differential_raw(w.bytes(), "repeat-overrun")

    # Truncations mid-everything of a real stream
    data = b"abracadabra" * 30
    comp = zlib.compress(data, 9)[2:-4]
    for i in range(len(comp)):
        differential_raw(comp[:i], "trunc")

    # Empty input
    differential_raw(b"", "empty")


# ----------------------------------------------------------------------
#  Mutations: bit flips over valid streams, random garbage
# ----------------------------------------------------------------------

def gen_mutations(files):
    rng = random.Random(987654321)
    base = files["alice29.txt"][:4000] if "alice29.txt" in files else \
        (b"mutation base text " * 200)
    src = []
    for level in (1, 6, 9):
        co = zlib.compressobj(level=level, wbits=-15)
        src.append(co.compress(base) + co.flush())
    n_flips = 60 if QUICK else 600
    for comp in src:
        for _ in range(n_flips):
            buf = bytearray(comp)
            for _ in range(rng.choice((1, 1, 1, 2, 4))):
                pos = rng.randrange(len(buf))
                buf[pos] ^= 1 << rng.randrange(8)
            differential_raw(bytes(buf), "flip")
    n_rand = 50 if QUICK else 400
    for _ in range(n_rand):
        differential_raw(bytes(rng.randrange(256)
                                for _ in range(rng.randrange(1, 300))), "rand")
    # zlib container mutations
    zcomp = zlib.compress(base, 6)
    for _ in range(n_flips):
        buf = bytearray(zcomp)
        buf[rng.randrange(len(buf))] ^= 1 << rng.randrange(8)
        comp = bytes(buf)
        try:
            out = zlib.decompress(comp)
            case("zlib", comp, out)
        except zlib.error:
            case("zlib", comp, None)


# ----------------------------------------------------------------------
#  ZIP archives
# ----------------------------------------------------------------------

def zip_make(entries, comment=b"", method=zipfile.ZIP_DEFLATED, level=None,
             force_zip64=False):
    bio = io.BytesIO()
    with zipfile.ZipFile(bio, "w", method, compresslevel=level) as zf:
        for name, data in entries:
            zf.writestr(name, data, compress_type=method)
        if comment:
            zf.comment = comment
    return bio.getvalue()


def zip_make_streaming(entries):
    """Write to an unseekable sink so zipfile uses data descriptors."""
    class Unseekable(io.BytesIO):
        def seekable(self):
            return False

        def seek(self, *args):
            raise io.UnsupportedOperation("seek")

    bio = Unseekable()
    with zipfile.ZipFile(bio, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data in entries:
            zf.writestr(name, data)
    return bio.getvalue()


def zip_case_ok(entries, **kw):
    comp = zip_make(entries, **kw)
    expect = b"".join(d for _, d in entries)
    case("zip", comp, expect, consumed=len(comp))
    return comp


def gen_zip(files):
    text = files.get("alice29.txt", b"fallback text " * 1000)[:30_000]
    rng = random.Random(13579)
    entries = [
        ("hello.txt", b"hello, zip"),
        ("empty", b""),
        ("dir/", b""),
        ("dir/nested.bin", bytes(range(256)) * 40),
        ("text.txt", text),
        ("incompressible.bin", bytes(rng.randrange(256) for _ in range(5000))),
    ]
    zip_case_ok(entries)                                    # deflated
    zip_case_ok(entries, method=zipfile.ZIP_STORED)         # stored
    zip_case_ok(entries, level=1)
    zip_case_ok(entries, level=9)
    zip_case_ok(entries, comment=b"an archive comment")     # EOCD scan-back
    zip_case_ok(entries, comment=b"x" * 65535)              # maximal comment
    zip_case_ok([("one", b"1")])
    zip_case_ok([("many%04d" % i, bytes([i % 256]) * i) for i in range(200)])
    case("zip", zip_make_streaming(entries),
         b"".join(d for _, d in entries))                  # data descriptors

    good = zip_make(entries)
    # Truncations: every prefix must be rejected unless it still parses.
    # The EOCD lives at the end, so all of these lose it -> reject.
    for i in range(0, len(good), 7):
        case("zip", good[:i], None)
    # Bit flips: no oracle here (zipfile's leniencies differ from ours in
    # both directions), so these only check that the harness completes.
    for _ in range(400 if not QUICK else 60):
        buf = bytearray(good)
        for _ in range(rng.choice((1, 1, 2))):
            buf[rng.randrange(len(buf))] ^= 1 << rng.randrange(8)
        case("zip", bytes(buf), "?", tag="zipflip")
    # Not a zip at all / empty
    case("zip", b"", None)
    case("zip", b"PK\x05\x06", None)
    case("zip", bytes(100), None)
    # force_zip64 on a small entry still writes a classic-readable central
    # directory (no 0xFFFFFFFF markers needed), so it must decode; real
    # ZIP64 marker values are covered by the hand-patched case below.
    bio = io.BytesIO()
    with zipfile.ZipFile(bio, "w", zipfile.ZIP_DEFLATED) as zf:
        with zf.open(zipfile.ZipInfo("big"), "w", force_zip64=True) as f:
            f.write(b"data")
    case("zip", bio.getvalue(), b"data")
    # Hand-set ZIP64 marker: uncompressed size 0xFFFFFFFF in the central
    # entry -> ZIP_Unsupported
    one64 = zip_make([("m.bin", b"payload")], method=zipfile.ZIP_STORED)
    cd64 = one64.rfind(b"PK\x01\x02")
    buf64 = bytearray(one64)
    buf64[cd64 + 24:cd64 + 28] = b"\xff\xff\xff\xff"
    case("zip", bytes(buf64), None)
    # bzip2-compressed entry (method 12) -> ZIP_Unsupported
    try:
        comp = zip_make([("b", text)], method=zipfile.ZIP_BZIP2)
        case("zip", comp, None)
    except RuntimeError:
        pass
    # Encryption flag set (bit 0 of the central entry's flags)
    one = zip_make([("e.txt", b"secret-ish")], method=zipfile.ZIP_STORED)
    cd = one.rfind(b"PK\x01\x02")
    eocd = one.rfind(b"PK\x05\x06")
    # The EOCD count and central-directory size must describe exactly the
    # entries walked by the library, rather than merely point somewhere
    # before the EOCD.
    buf = bytearray(one)
    buf[eocd + 12:eocd + 16] = struct.pack("<I", 0)
    case("zip", bytes(buf), None)
    buf = bytearray(one)
    cd_size = struct.unpack_from("<I", buf, eocd + 12)[0]
    buf[eocd + 12:eocd + 16] = struct.pack("<I", cd_size - 1)
    case("zip", bytes(buf), None)
    buf = bytearray(one)
    buf[eocd + 8:eocd + 12] = b"\0\0\0\0"
    case("zip", bytes(buf), None)
    buf = bytearray(one)
    buf[eocd + 8:eocd + 12] = b"\2\0\2\0"
    case("zip", bytes(buf), None)

    # The local header must agree with its central entry. These cases used
    # to extract successfully because only the central values were used.
    local = struct.unpack_from("<I", one, cd + 42)[0]
    for field in (6, 8, 14, 18, 22):
        buf = bytearray(one)
        buf[local + field] ^= 1
        case("zip", bytes(buf), None)
    buf = bytearray(one)
    buf[local + 30] ^= 1
    case("zip", bytes(buf), None)

    buf = bytearray(one)
    buf[cd + 8] |= 1
    case("zip", bytes(buf), None)
    # CRC corrupted in the central directory
    buf = bytearray(one)
    buf[cd + 16] ^= 0xFF
    case("zip", bytes(buf), None)


# ----------------------------------------------------------------------

def main():
    os.makedirs(WORK, exist_ok=True)
    for f in os.listdir(WORK):
        os.unlink(os.path.join(WORK, f))

    files = fetch_corpus()
    gen_valid(files)
    gen_gzip_headers()
    gen_crafted()
    gen_mutations(files)
    gen_zip(files)
    gen_compress(files)

    mpath = os.path.join(WORK, "manifest")
    with open(mpath, "w") as f:
        for row in manifest:
            f.write("\t".join(row) + "\n")
    print("generated %d cases" % len(manifest))

    r = subprocess.run([HARNESS, mpath], capture_output=True, text=True)
    sys.stdout.write(r.stdout[-4000:])
    sys.stderr.write(r.stderr[-2000:])
    bad = check_compress_outputs()
    return r.returncode or (1 if bad else 0)


if __name__ == "__main__":
    sys.exit(main())
