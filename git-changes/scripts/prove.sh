#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

prover=${GNATPROVE:-}
if [ -z "$prover" ] && command -v gnatprove >/dev/null 2>&1; then
    candidate=$(command -v gnatprove)
    case "$("$candidate" --version | sed -n '1p')" in
        *16.*) prover=$candidate ;;
    esac
fi
if [ -z "$prover" ]; then
    for candidate in "$HOME"/.alire/gnatprove_16*/bin/gnatprove; do
        if [ -x "$candidate" ]; then
            prover=$candidate
        fi
    done
fi
if [ -z "$prover" ]; then
    echo "GNATprove 16 is not available" >&2
    exit 1
fi
case "$("$prover" --version | sed -n '1p')" in
    *16.*) ;;
    *) echo "GNATprove 16 is required (selected: $prover)" >&2; exit 1 ;;
esac

exec alr exec -- "$prover" -P git_changes_proof.gpr \
    --mode=all --level=2 --prover=all -j0 \
    git_changes-core-validation.adb \
    git_changes-core-raw.adb \
    git_changes-core-hunks.adb
