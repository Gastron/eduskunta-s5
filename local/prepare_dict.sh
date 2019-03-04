#!/bin/bash
set -eu

. ./path.sh
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <dict-dir> <data-dir1> [<data-dir2>...]"
  exit 1
fi
dictdir="$1"; shift
mkdir -p "$dictdir"

# Make paths to the text files in each data dir:
datadirs=($@)
texts=( "${datadirs[@]/%//text}" )

# Lexicon:
cat <<EOF >"$dictdir"/lexicon_special
!sil sil
<unk> spn
EOF
# Operations line by line inside the subshell (brackets):
# 1 Handle encoding correctly.
# 2 Put every word on a separate line
# 3 Sort and filter to unique words
# 4 Turn into lexicon lines, like: 
#   word w o r d 
(
export LC_ALL=en_GB.utf8
cat $texts | cut -d" " -f2- | tr " " "\n" | \
  sort -u |\
  local/to_lexicon.py > "$dictdir"/lexicon_words
)
cat "$dictdir"/lexicon_special "$dictdir"/lexicon_words |\
  sort > "$dictdir"/lexicon.txt

# Build phone lists from the lexicon parts:
cat "$dictdir"/lexicon_words | cut -d" " -f2- | tr " " "\n" |\
  sort -u > "$dictdir"/nonsilence_phones.txt
cat "$dictdir"/lexicon_special | cut -d" " -f2- | tr " " "\n" |\
  sort -u > "$dictdir"/silence_phones.txt
echo "sil" > "$dictdir"/optional_silence.txt #have this match !sil in lexicon

# MISC:
touch "$dictdir"/extra_questions.txt #Not used, but should be present

utils/validate_dict_dir.pl "$dictdir"
