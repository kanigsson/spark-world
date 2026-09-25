include ../../tools/project.mk

#  Pinned: this project proves clean under the pinned prover, so it states
#  which prover that is rather than trusting PATH. See tools/toolchain.mk.
GNATPROVE ?= $(SPARK_WORLD_PROVE)

.PHONY: build test test-contracts flow prove bench bench-corpora
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
#  Alt-Ergo is listed for three checks that CVC5 and Z3 stopped proving when
#  Max_Length grew to 2**24, even at level 4 with a minute each; Alt-Ergo
#  needs a fraction of a second for them.
prove:
	$(GNATPROVE) -P bwt.gpr -U --level=2 --timeout=5 --prover=cvc5,z3,altergo --counterexamples=off -j$(JOBS)

#  Real text for the SOURCE shape: the repository's own tracked sources and
#  documents, in a fixed order, so that it only changes with the commit.
#  Pass CORPUS=<file> to use another, for instance one past 4 MiB.
CORPUS ?= obj/bench/corpus.txt

#  Rebuilt on every run, so that it never lags behind the checkout.
.PHONY: obj/bench/corpus.txt
obj/bench/corpus.txt:
	mkdir -p obj/bench
	git -C ../.. ls-files -z '*.ads' '*.adb' '*.md' | sort -z \
	  | (cd ../.. && xargs -0 cat) > $@

#  A production build on purpose: contracts and run-time checks off, so the
#  timings measure the transforms and not their verification. The stack
#  limit is lifted because the encoders keep their tables on the stack, which
#  overflows the default 8 MiB from about 1 MiB of input.
bench: $(CORPUS)
	$(GPRBUILD) -P bench.gpr -XBWT_BUILD=bench -j$(JOBS)
	ulimit -s unlimited && bin/bench/bench_bwt $(CORPUS)

#  The public corpora that suffix-sorting and BWT libraries are benchmarked on
#  (Silesia, Canterbury, the Gauntlet, Pizza&Chili, bzip2's samples), cut to
#  CORPORA_SIZES bytes. They are downloaded on first use and never committed;
#  obj/ is ignored. At 4 MiB an encoding takes seconds, so this is opt-in and
#  takes several minutes. Pass CORPORA_SIZES=1048576 for a quicker run.
CORPORA ?= obj/corpora
CORPORA_SIZES ?= 1048576 4194304

bench-corpora:
	bench/fetch-corpora.sh $(CORPORA) $(CORPORA_SIZES)
	$(GPRBUILD) -P bench.gpr -XBWT_BUILD=bench -j$(JOBS)
	ulimit -s unlimited && bin/bench/bench_corpora \
	  $(foreach n,$(CORPORA_SIZES),$(CORPORA)/$(n)/*)
