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

#  Proving still uses whatever PATH offers, except in libs/git_changes, which
#  resolves GNATprove 16 for itself. Reconciling that asks for a second
#  resolver of the same shape as tools/gnatformat; the version it would pin
#  sits here already, so neither tool's number has to be hunted for twice.
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
