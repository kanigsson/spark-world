#!/bin/sh
#  Proves the three core parsers with the repository's pinned prover.
#
#  This script used to resolve GNATprove 16 itself, because it was the only
#  place in the repository that pinned a prover at all. That search now lives
#  in tools/gnatprove and is shared, so a version moves in one place; what
#  stays here is the proof scope and switches, which are this project's own.
set -eu
cd "$(dirname "$0")/.."

#  Absolute, because alr exec runs the command with a working directory of
#  its own choosing and a relative one would not survive the hop.
prover=${GNATPROVE:-$(CDPATH= cd -- ../../tools && pwd)/gnatprove}

exec alr exec -- "$prover" -P git_changes_proof.gpr \
    --mode=all --level=2 --prover=all -j0 \
    git_changes-core-validation.adb \
    git_changes-core-raw.adb \
    git_changes-core-hunks.adb
