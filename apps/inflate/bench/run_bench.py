#!/usr/bin/env python3
"""Benchmark the SPARK inflate against C zlib on representative payloads.

Builds raw-deflate inputs from the test corpus, runs both harnesses on the
same bytes, reports output-throughput side by side.
"""

import os
import random
import subprocess
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(HERE, "..", "tests", "corpus")
WORK = os.path.join(HERE, "work")

ITERS = int(os.environ.get("ITERS", "30"))


def corpus_cat():
    #  The corpus is not in the repository; the test suite downloads it on its
    #  first run. Say so rather than failing on a missing directory.
    if not os.path.isdir(CORPUS) or not os.listdir(CORPUS):
        sys.exit("no test corpus: run ../tests/run_tests.py once to fetch it")
    blobs = []
    for name in sorted(os.listdir(CORPUS)):
        p = os.path.join(CORPUS, name)
        if os.path.isfile(p) and not name.startswith("."):
            blobs.append(open(p, "rb").read())
    return b"".join(blobs)


def payloads():
    cat = corpus_cat()
    rng = random.Random(42)
    rnd = bytes(rng.randrange(256) for _ in range(4_000_000))
    yield "canterbury level=1", cat, 1
    yield "canterbury level=6", cat, 6
    yield "canterbury level=9", cat, 9
    yield "zeros 8M level=6", bytes(8_000_000), 6
    yield "random 4M (stored)", rnd, 6
    yield "alice29 x20 level=9", open(os.path.join(CORPUS, "alice29.txt"), "rb").read() * 20, 9


def main():
    os.makedirs(WORK, exist_ok=True)
    for label, data, level in payloads():
        co = zlib.compressobj(level=level, wbits=-15)
        comp = co.compress(data) + co.flush()
        path = os.path.join(WORK, "bench.raw")
        with open(path, "wb") as f:
            f.write(comp)
        cap = str(len(data) + 64)
        print("== %s: %d -> %d bytes (ratio %.2f)" %
              (label, len(comp), len(data), len(data) / max(len(comp), 1)))
        for exe in (os.path.join(HERE, "bench_inflate"),
                    os.path.join(HERE, "bench_zlib")):
            r = subprocess.run([exe, path, cap, str(ITERS)],
                               capture_output=True, text=True)
            sys.stdout.write(r.stdout)
            if r.returncode != 0:
                sys.stdout.write(r.stderr)
                return r.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
