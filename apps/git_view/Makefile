#  The repository-wide preamble: the developer's own overrides, the tool pins,
#  the shared defaults and the format targets. Must come first.
include ../../tools/project.mk

#  Not pinned: this project still has unproved checks under the pinned
#  prover, so naming it here would promise a clean run it does not deliver.
#  Pin it (GNATPROVE ?= $(SPARK_WORLD_PROVE)) when the last one closes.
GNATPROVE ?= gnatprove

.PHONY: build test prove flow
#  Builds the three libraries along with the app; -XMODE=debug drops the
#  optimisation and keeps contracts.
build:
	$(GPRBUILD) -P git_view.gpr -j$(JOBS)

test: build
	$(GPRBUILD) -P tests/explorer_tests.gpr -j$(JOBS)
	obj/tests/model_tests
	obj/tests/behavior_tests
	python3 tests/run_explorer_tests.py
	python3 tests/run_explorer_pty_tests.py
	python3 tests/run_mouse_tests.py

flow:
	$(GNATPROVE) -P git_view.gpr --mode=flow -j$(JOBS)

#  Level and switches come from the Prove package in git_view.gpr.
prove:
	$(GNATPROVE) -P git_view.gpr -j$(JOBS)
