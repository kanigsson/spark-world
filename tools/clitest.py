"""The parts every CLI test driver in this repository repeats.

Deliberately small, and smaller than it first looks like it should be. Each
driver's own ``run`` stays in the driver: one needs a working directory, one a
pty, one drives the program as a byte channel and one as text, so a shared
wrapper would take the union of their parameters and be longer to read than
the four lines it replaced. What is the same in every driver is how the
program under test is located and how the run reports what it checked.

A driver finds this module by repository position -- every project sits at
``<tier>/<name>/``, so a driver under ``<tier>/<name>/tests/`` reaches the
repository root by three parents:

    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
    import clitest

That is two lines rather than an environment variable because a driver is
also run directly, not only through ``make``.
"""

from __future__ import annotations

import os
from pathlib import Path


def binary(env_var: str, default: str | os.PathLike[str]) -> str:
    """The program under test, as an absolute path.

    The environment variable wins over the default, which is how
    ``make test-contracts`` points an unchanged driver at the
    assertion-enabled build instead of the ordinary one.
    """
    return str(Path(os.environ.get(env_var) or default).resolve())


class Checks:
    """What a driver verified, and the one line it prints at the end.

    Counting rather than hard-coding the total is the point: a written-in
    number goes stale the first time a case is added, and the count is what a
    reader uses to tell "the suite ran" from "the suite ran and did nothing".

    ``ok`` covers the common case. A driver whose own check does more --
    running the program, comparing against an oracle, looping over fixtures --
    keeps that check and calls ``counted`` from inside it, which is the same
    bookkeeping without a ``global`` declaration in every function.
    """

    def __init__(self) -> None:
        self.count = 0

    def ok(self, condition, message: object = "") -> None:
        assert condition, message
        self.count += 1

    def counted(self, n: int = 1) -> None:
        self.count += n

    def passed(self, what: str) -> None:
        print(f"PASS: {self.count} {what}")
