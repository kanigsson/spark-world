#  Optional, untracked, per-developer tool locations. The project states
#  which tools it needs and never where they live; a developer whose
#  environment offers several toolchains pins the choice here.
-include local.mk

#  Tool versions are pinned for the whole repository; the formatter in
#  particular, because an unpinned one reformats every source it sees.
include ../../tools/toolchain.mk

GPRBUILD ?= gprbuild
#  Pinned: this project proves clean under the pinned prover, so it states
#  which prover that is rather than trusting PATH. See tools/toolchain.mk.
GNATPROVE ?= $(SPARK_WORLD_PROVE)
JOBS ?= 4
.PHONY: build test test-contracts flow prove format format-check
build:
	$(GPRBUILD) -P tools.gpr -j$(JOBS)
test: build
	bin/test_regex
	python3 tests/test_cli.py
	python3 tests/test_rg.py
	python3 tests/test_matcher.py
#  Assertions follow the build mode, so both the library and the vendored
#  CLI support crate must be switched over together.
CHECKS_VARS = -XSPARK_RE_BUILD=checks -XSPARK_CLI_BUILD=checks
test-contracts:
	$(GPRBUILD) -P tools.gpr $(CHECKS_VARS) -j$(JOBS)
	bin/checks/test_regex
	SPARK_GREP=bin/checks/spark-grep python3 tests/test_cli.py
	SPARK_RG=bin/checks/spark-rg python3 tests/test_rg.py
	SPARK_MATCHER_TEST=bin/checks/test_matcher python3 tests/test_matcher.py
flow:
	$(GNATPROVE) -P spark_re.gpr --mode=flow -j$(JOBS)
prove:
	$(GNATPROVE) -P spark_re.gpr --level=4 --counterexamples=off -j$(JOBS)
format:
	$(SPARK_WORLD_FORMAT) .
format-check:
	$(SPARK_WORLD_FORMAT) . --check
