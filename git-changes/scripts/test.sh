#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
alr build
alr exec -- gprbuild -P tests/tests.gpr -p -j0
alr exec -- tests/bin/test_core
python3 tests/integration/test_git_changes.py
