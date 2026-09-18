#  The repository-wide preamble: the developer's own overrides, the tool pins,
#  the shared defaults and the format targets. Must come first.
include ../../tools/project.mk

#  Pinned: this project proves clean under the pinned prover, so it states
#  which prover that is rather than trusting PATH. See tools/toolchain.mk.
GNATPROVE ?= $(SPARK_WORLD_PROVE)

.PHONY: build test test-contracts prove flow bench
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
