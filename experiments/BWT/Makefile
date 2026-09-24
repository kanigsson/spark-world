include ../../tools/project.mk

# Proof is incomplete; use the caller's matching toolchain, not the clean-proof pin.
GNATPROVE ?= gnatprove

.PHONY: build test test-contracts flow prove
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

# Short baseline budget: unresolved obligations must remain visible and fail.
prove:
	$(GNATPROVE) -P bwt.gpr -U --level=2 --timeout=5 --prover=cvc5,z3 --counterexamples=off -j$(JOBS)
