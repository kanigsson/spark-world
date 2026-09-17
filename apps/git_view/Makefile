#  Optional, untracked, per-developer tool locations. The project states
#  which tools it needs and never where they live; a developer whose
#  environment offers several toolchains pins the choice here.
-include local.mk

GPRBUILD ?= gprbuild
GNATPROVE ?= gnatprove
JOBS ?= 4

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
