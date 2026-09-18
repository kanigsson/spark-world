#  The repository-wide preamble: the developer's own overrides, the tool pins,
#  the shared defaults and the format targets. Must come first.
include ../../tools/project.mk

#  Pinned: this project proves clean under the pinned prover, so it states
#  which prover that is rather than trusting PATH. See tools/toolchain.mk.
GNATPROVE ?= $(SPARK_WORLD_PROVE)
.PHONY: build test test-contracts flow prove prove-front
build:
	$(GPRBUILD) -P tools.gpr -j$(JOBS)
test: build
	bin/test_regex
	bin/test_front
	python3 tests/test_cli.py
	python3 tests/test_rg.py
	python3 tests/test_matcher.py
#  Assertions follow the build mode, so both the library and the vendored
#  CLI support crate must be switched over together.
CHECKS_VARS = -XSPARK_RE_BUILD=checks -XSPARK_CLI_BUILD=checks
test-contracts:
	$(GPRBUILD) -P tools.gpr $(CHECKS_VARS) -j$(JOBS)
	bin/checks/test_regex
	bin/checks/test_front
	SPARK_GREP=bin/checks/spark-grep python3 tests/test_cli.py
	SPARK_RG=bin/checks/spark-rg python3 tests/test_rg.py
	SPARK_MATCHER_TEST=bin/checks/test_matcher python3 tests/test_matcher.py
flow:
	$(GNATPROVE) -P spark_re.gpr --mode=flow -j$(JOBS)
prove:
	$(GNATPROVE) -P spark_re.gpr --level=4 --counterexamples=off -j$(JOBS)

#  The shared CLI front end, proved away from the library's run: level 2
#  discharges all of it in seconds, and keeping it separate means a clean
#  result here is not buried inside a run that the library's one open check
#  makes fail. The crate depends on nothing, which is what keeps this run to
#  its own units and lets an unproved check be an error here.
prove-front:
	$(GNATPROVE) -P common/grep_front/grep_front.gpr --level=2 -j$(JOBS)
