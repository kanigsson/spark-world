#  What every project's Makefile needs before it states anything of its own:
#  the developer's untracked overrides, the repository's tool pins, and the
#  defaults and targets that do not vary between projects.
#
#  Include it first, on the first line. Two orderings depend on that. local.mk
#  is read before any default here, so a developer's own choice wins over
#  them; and every default is set with `?=`, so a project can still state its
#  own after the include — which is how a project says that it proves clean
#  under the pinned prover.
#
#  What is deliberately NOT here: GNATPROVE. Whether a project names the
#  pinned prover is a per-project claim about that project's proof, and the
#  comment beside it says which claim, so it stays where it is made. Proof
#  level and switches are per-project for the same reason.

#  Optional, untracked, per-developer tool locations. The project states
#  which tools it needs and never where they live; a developer whose
#  environment offers several toolchains pins the choice here.
-include local.mk

#  Tool versions are pinned for the whole repository; the formatter in
#  particular, because an unpinned one reformats every source it sees.
include $(dir $(lastword $(MAKEFILE_LIST)))toolchain.mk

GPRBUILD ?= gprbuild
JOBS ?= 4

#  The first target seen would otherwise be `format`, because this file is
#  included before the project states anything. Every project in the
#  repository builds by default, so say so rather than depend on the order.
.DEFAULT_GOAL := build

#  The one exception to per-project variation: both call tools/format-repo, so
#  every project formats through one traversal and one set of switches.
#  format-check reports and exits non-zero instead of rewriting, which is what
#  a pre-commit hook or CI wants.
.PHONY: format format-check
format:
	$(SPARK_WORLD_FORMAT) .
format-check:
	$(SPARK_WORLD_FORMAT) . --check
