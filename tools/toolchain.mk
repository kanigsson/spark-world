#  Repo-wide toolchain pins. Every project's Makefile includes this file, and
#  the resolver scripts beside it read the same version strings, so a version
#  moves in exactly one place.
#
#  The formatter is pinned because an unpinned one rewrites the repository
#  wholesale the first time a developer's PATH offers a different release.
#  A version is matched as a prefix against the tool's own --version output.
#
#  Beware the numbering: the formatter shipped alongside FSF GNAT 16 calls
#  itself 26.0. The number tracks the release year, not the compiler version,
#  so a pin of "16." would match nothing.
GNATFORMAT_VERSION ?= 26.

#  The prover is pinned for the projects that prove clean against it, so that
#  "this project proves" stays a claim about the repository rather than about
#  whichever build a developer's PATH happens to offer. Unlike the formatter
#  version, this one is matched against the "FSF <version>" that GNATprove
#  prints, so a development build does not satisfy it.
GNATPROVE_VERSION ?= 16.

#  This file's own directory, so a project's Makefile needs no path of its own
#  beyond the include.
SPARK_WORLD_TOOLS := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))

#  The resolver, not a binary: it finds a matching formatter at run time and
#  applies the switches this repository has settled on. Setting GNATFORMAT in
#  local.mk replaces it outright and gives up the version check; setting
#  GNATFORMAT_BIN instead names a candidate that still gets checked.
GNATFORMAT ?= $(SPARK_WORLD_TOOLS)/gnatformat

#  Formats this project's sources -- every project in the repository formats
#  the same way, through the same traversal.
SPARK_WORLD_FORMAT := $(SPARK_WORLD_TOOLS)/format-repo

#  The prover resolver, not a binary, and deliberately not the default for
#  GNATPROVE: a project opts in by setting GNATPROVE ?= $(SPARK_WORLD_PROVE),
#  and only the projects that prove clean against the pin have done so. A
#  project with outstanding checks keeps whatever PATH offers, because pinning
#  it would promise a result it does not currently deliver. Pinning one is a
#  one-line edit to its Makefile, made when its last check closes.
SPARK_WORLD_PROVE := $(SPARK_WORLD_TOOLS)/gnatprove
