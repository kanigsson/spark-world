include ../../tools/project.mk

#  Pinned: this project proves clean under the pinned prover, so it states
#  which prover that is rather than trusting PATH. See tools/toolchain.mk.
GNATPROVE ?= $(SPARK_WORLD_PROVE)

.PHONY: build test test-contracts flow prove bench
build:
	$(GPRBUILD) -P tests.gpr -j$(JOBS)

# Recursive ghost proofs are erased; ordinary Ada run-time checks stay enabled.
test: build
	bin/runtime/test_bwt

# Execute proof contracts too, on a small corpus; quantified ghost checks are costly.
test-contracts:
	$(GPRBUILD) -P tests.gpr -XBWT_BUILD=checks -j$(JOBS)
	bin/checks/test_bwt --contracts

flow:
	$(GNATPROVE) -P bwt.gpr -U --mode=flow -j$(JOBS)

#  A short budget on purpose: every check is meant to prove quickly, and one
#  that needs longer is a sign its lemma wants splitting, not more time.
prove:
	$(GNATPROVE) -P bwt.gpr -U --level=2 --timeout=5 --prover=cvc5,z3 --counterexamples=off -j$(JOBS)

#  A production build on purpose: contracts and run-time checks off, so the
#  timings measure the transforms and not their verification.
bench:
	$(GPRBUILD) -P bench.gpr -XBWT_BUILD=bench -j$(JOBS)
	bin/bench/bench_bwt
