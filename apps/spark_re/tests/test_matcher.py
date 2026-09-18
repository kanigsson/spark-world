"""Compare mixed-mode workspace reuse with one-shot matching and GNU grep."""
import os
from pathlib import Path
import random
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
import clitest

rng = random.Random(20260916)
BIN = clitest.binary('SPARK_MATCHER_TEST', 'bin/test_matcher')
env = dict(os.environ, LC_ALL='C')
patterns = ['', '^$', '$', '^', '.', '(a?)*', '((a|)*)*b',
            '(^|a)*b$', '((a?|^)|($|b?))*', 'a{0,250}zzqqxx',
            'zzqqxxa{0,250}', '(ab|a){1,3}', '[]-]+', '[^a-b]*']


def expression(depth):
    if depth == 0:
        return rng.choice(['a', 'b', '.', '[ab]', '[^a]', '()'])
    x = expression(depth - 1)
    return rng.choice([f'({x})*', f'({x})+', f'({x})?', f'({x}){{0,2}}',
                       f'({x}|{expression(depth - 1)})', x + expression(depth - 1)])


patterns += [expression(3) for _ in range(150)]
checks = clitest.Checks()
for nul in (False, True):
    # Keep LF out of these records; direct library tests cover every byte.
    alphabet = b'abczqxyz\r\xff' + (b'\x01' if nul else b'\x00')
    records = [b'', b'a', b'', b'aaab', b'zzqqxx', b'x', b'aaa', b'']
    records += [bytes(rng.choice(alphabet) for _ in range(rng.randrange(60)))
                for _ in range(180)]
    delimiter = b'\0' if nul else b'\n'
    data = delimiter.join(records) + delimiter
    for pattern in patterns:
        for whole in (False, True):
            actual = subprocess.run(
                [BIN, 'whole' if whole else 'search', 'nul' if nul else 'lf', pattern],
                input=data, capture_output=True, env=env, timeout=60)
            reference = subprocess.run(
                ['grep', '-aE', *(['-z'] if nul else []), *(['-x'] if whole else []),
                 '-e', pattern], input=data, capture_output=True, env=env, timeout=60)
            assert (actual.returncode, actual.stdout, actual.stderr) == (
                reference.returncode, reference.stdout, reference.stderr), (
                    pattern, nul, whole, actual, reference)
            checks.counted()
checks.passed('workspace/one-shot/GNU grep differential checks')
