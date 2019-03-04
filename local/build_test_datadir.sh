#!/bin/bash
set -eu

storage="$1"
outdir="$2"


. ./path.sh

rm -rf "$outdir"
mkdir -p "$outdir"

for session in "$storage"/session_*; do
  session_name=$(basename "$session")
  for trn in "$session"/*.trn; do
    base=$(basename $trn .trn)
    wav="$session"/"$base".wav
    uttid="$base"
    spk="$base"
    echo "$uttid $wav" >> "$outdir"/wav.scp
    echo "$uttid $spk" >> "$outdir"/utt2spk
    cat <(echo -n "$uttid ") "$trn" >> "$outdir"/text
    echo "$uttid $session_name" >> "$outdir"/utt2session
  done
done

utils/fix_data_dir.sh "$outdir"
