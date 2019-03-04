#!/bin/bash
set -eu

sessionsfile="$1"
outdir="$2"

while read session; do
  # Note: Kaldi path.sh usually sets LC_ALL=C
  env LC_ALL=fi_FI.utf8 local/build_datadir.py "$session" "$outdir"/$(basename "$session") \
    --text-preprocessor "perl -I local/parsing local/parsing/preprocess-fi-mod-utf8.pl"
done <"$sessionsfile"
