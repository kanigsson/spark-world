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

#  The prover memory limit applies per process, so the default 2 GB times one
#  job per core exceeds what a many-core machine has, and the hardest checks
#  here are exactly the ones that reach it. Bound the parallelism instead of
#  passing -j0; starving those checks is what makes them look unprovable.
PROVE_JOBS ?= 16

.PHONY: build test test-cli prove bench format format-check
build:
	$(GPRBUILD) -P inflate.gpr -j$(JOBS)
	$(GPRBUILD) -P inflate_cli.gpr -j$(JOBS)

#  The test build runs with language checks on and proof contracts off; see
#  debug.adc.
test:
	$(GPRBUILD) -P tests/tests.gpr -XMODE=debug -j$(JOBS)
	cd tests && python3 run_tests.py

test-cli: build
	python3 tests/run_cli_tests.py

#  --no-subprojects leaves Ore to its own proof run.
prove:
	$(GNATPROVE) -P inflate.gpr -j$(PROVE_JOBS) --no-subprojects

#  Needs libz.a.
bench:
	$(GPRBUILD) -P bench/bench.gpr -j$(JOBS)
	cd bench && python3 run_bench.py

format:
	$(SPARK_WORLD_FORMAT) .
format-check:
	$(SPARK_WORLD_FORMAT) . --check
