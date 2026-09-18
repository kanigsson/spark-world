#  The repository-wide preamble: the developer's own overrides, the tool pins,
#  the shared defaults and the format targets. Must come first.
include ../../tools/project.mk

#  Pinned: this project proves clean under the pinned prover, so it states
#  which prover that is rather than trusting PATH. See tools/toolchain.mk.
GNATPROVE ?= $(SPARK_WORLD_PROVE)

.PHONY: build test test-contracts prove flow
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
