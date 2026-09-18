#  Optional, untracked, per-developer tool locations. The project states
#  which tools it needs and never where they live; a developer whose
#  environment offers several toolchains pins the choice here.
-include local.mk

#  Tool versions are pinned for the whole repository; the formatter in
#  particular, because an unpinned one reformats every source it sees.
include ../../tools/toolchain.mk

GPRBUILD ?= gprbuild
GNATPROVE ?= gnatprove
JOBS ?= 4

.PHONY: build test test-contracts prove flow format format-check
build:
	$(GPRBUILD) -P tools.gpr -j$(JOBS)

test: build
	bin/test_diff
	python3 tests/test_cli.py

test-contracts:
	$(GPRBUILD) -P tools.gpr -XDIFF_BUILD=checks -j$(JOBS)
	bin/checks/test_diff
	DIFF_BIN=bin/checks/spark-diff python3 tests/test_cli.py

flow:
	$(GNATPROVE) -P spark_diff.gpr --mode=flow -j$(JOBS)

prove:
	$(GNATPROVE) -P spark_diff.gpr --level=2 --timeout=20 --prover=cvc5,z3 --counterexamples=off -j$(JOBS)

format:
	$(SPARK_WORLD_FORMAT) .
format-check:
	$(SPARK_WORLD_FORMAT) . --check
