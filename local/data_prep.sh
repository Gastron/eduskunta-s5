#!/bin/bash
set -eu

data_storage=/scratch/elec/puhe/c/eduskunta/Kielipankki/Eduskunta
test_data_storage="/scratch/elec/puhe/c/parliament-eval/"
data_dir="data"
base_set="base"
train_set="train"
dev_set="dev"
test_set="test"
logdir="$data_dir"/"$base_set"/log

cmd="run.pl"
nj=16
ndevsamples=1000

. utils/parse_options.sh || exit 1;
. ./path.sh

basedir="$data_dir"/"$base_set"
mkdir -p "$basedir"
mkdir -p $logdir

# Build Kaldi style data-dirs:
local/download_elan_parser.sh

# Find sessions:
rm -f "$basedir"/sessions.scp
for session in "$data_storage"/*/*; do
  echo "$session" >> "$basedir"/sessions.scp
done
sort --random-sort "$basedir"/sessions.scp -o "$basedir"/sessions.scp

# Split for parallel preprocessing:
mkdir -p "$basedir"/sessions
split_sessions=""
for n in $(seq $nj); do
  split_sessions="$split_sessions $logdir/sessions.$n.scp"
done
utils/split_scp.pl "$basedir"/sessions.scp $split_sessions

# Process in parallel
$cmd JOB=1:$nj "$logdir"/build_datadir.JOB.log \
  local/process_sessions.sh "$logdir"/sessions.JOB.scp "$basedir"/sessions

# Combine results:
for f in text utt2spk wav.scp segments; do
  cat "$basedir"/sessions/*/"$f" > "$basedir"/"$f"
done

echo "$LC_ALL"
utils/fix_data_dir.sh "$basedir"

# Filter too short and too long data
#1-30 seconds, max 500chars
filtdir="$basedir"_filt
local/remove_longshortdata.sh --minframes 100 --maxframes 3000 --maxchars 500 \
  "$basedir" "$filtdir"


# Test set is handled separetely:
local/build_test_datadir.sh "$test_data_storage" "$data_dir"/"$test_set"

# Split base data to train and dev (randomly): 
traindir="$data_dir"/"$train_set"
devdir="$data_dir"/"$dev_set"
mkdir -p "$traindir" 
mkdir -p "$devdir"

utils/subset_data_dir.sh "$filtdir" $ndevsamples "$devdir"
utils/subset_data_dir.sh \
  --utt-list <(utils/filter_scp.pl --exclude "$devdir"/utt2spk "$filtdir"/utt2spk) \
  "$filtdir" "$traindir" 
