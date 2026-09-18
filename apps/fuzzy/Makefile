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

.PHONY: build test test-contracts prove flow bench format format-check
build:
	$(GPRBUILD) -P tools.gpr -j$(JOBS)

test: build
	bin/test_fuzzy
	python3 tests/test_cli.py
	python3 tests/test_pick.py

test-contracts:
	$(GPRBUILD) -P tools.gpr -XFUZZY_BUILD=checks -j$(JOBS)
	bin/checks/test_fuzzy
	FUZZY_BIN=bin/checks/fuzzy python3 tests/test_cli.py
	FUZZY_BIN=bin/checks/fuzzy python3 tests/test_pick.py

flow:
	$(GNATPROVE) -P fuzzy.gpr --mode=flow -j$(JOBS)

prove:
	$(GNATPROVE) -P fuzzy.gpr --level=2 --proof=per_path --timeout=20 --prover=cvc5,z3 --counterexamples=off -j$(JOBS)

bench: build
	bin/bench_fuzzy

format:
	$(SPARK_WORLD_FORMAT) .
format-check:
	$(SPARK_WORLD_FORMAT) . --check
