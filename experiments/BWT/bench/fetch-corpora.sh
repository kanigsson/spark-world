#!/bin/sh
#  Downloads the public corpora that suffix-sorting and BWT libraries are
#  benchmarked on (libsais, libdivsufsort, the Bannai et al. BBWT), and cuts
#  each file into prefixes of the given sizes. The corpora are large and not
#  ours to redistribute, so they are fetched, never committed.
#
#  Usage: bench/fetch-corpora.sh [DIR [SIZE...]]
#    DIR   defaults to obj/corpora, which git ignores
#    SIZE  in bytes; defaults to 1 MiB and 4 MiB
#
#  DIR/dl caches the downloads, DIR/full holds whole files (the large
#  collections only up to the largest SIZE), and DIR/<SIZE>/ the prefixes. A
#  file shorter than a size is left out of it rather than padded, since
#  padding would repeat it and change how hard it is.
set -eu

DIR=${1:-obj/corpora}
[ $# -gt 0 ] && shift
SIZES=${*:-1048576 4194304}
LARGEST=$(printf '%s\n' $SIZES | sort -n | tail -n 1)

mkdir -p "$DIR/dl" "$DIR/full"
cd "$DIR"

get() {
  [ -s "dl/$1" ] && return 0
  curl -fL --retry 3 -o "dl/$1.part" "$2"
  mv "dl/$1.part" "dl/$1"
}

#  Silesia: mixed real data (text, executables, databases, images).
get silesia.zip https://sun.aei.polsl.pl/~sdeor/corpus/silesia.zip
#  Large Canterbury: E.coli, the King James bible, the CIA world fact book.
get large.zip https://corpus.canterbury.ac.nz/resources/large.zip
#  Gauntlet: inputs built to defeat suffix sorters (Fibonacci strings, long
#  repeats). That is where prefix doubling needs the most rounds.
[ -d dl/gauntlet_corpus ] ||
  git clone -q --depth 1 https://github.com/michaelmaniscalco/gauntlet_corpus.git dl/gauntlet_corpus
#  Pizza&Chili: DNA and proteins, and three real repetitive collections.
get dna.gz https://pizzachili.dcc.uchile.cl/texts/dna/dna.50MB.gz
get proteins.gz https://pizzachili.dcc.uchile.cl/texts/protein/proteins.50MB.gz
for f in cere einstein.en.txt kernel; do
  get $f.gz https://pizzachili.dcc.uchile.cl/repcorpus/real/$f.gz
done
#  bzip2's own quick-test references.
for i in 1 2 3; do
  get sample$i.ref https://gitlab.com/bzip2/bzip2/-/raw/master/tests/input/quick/sample$i.ref
done

(cd full && unzip -qo ../dl/silesia.zip && unzip -qo ../dl/large.zip E.coli bible.txt world192.txt)
for f in dl/gauntlet_corpus/*; do
  [ "${f##*/}" = README.md ] || cp "$f" full/
done
cp dl/sample?.ref full/
#  The .gz files hold 50 MB to 400 MB; only a prefix is ever used.
for f in dna proteins cere einstein.en.txt kernel; do
  if [ ! -s "full/$f" ] || [ "$(wc -c < "full/$f")" -lt "$LARGEST" ]; then
    gzip -dc "dl/$f.gz" 2> /dev/null | head -c "$LARGEST" > "full/$f" || true
  fi
done

for n in $SIZES; do
  mkdir -p "$n"
  for f in full/*; do
    if [ "$(wc -c < "$f")" -ge "$n" ]; then
      head -c "$n" "$f" > "$n/${f##*/}"
    fi
  done
  echo "$DIR/$n: $(ls "$n" | wc -l) files"
done
