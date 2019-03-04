#!/bin/bash
# Based on Librispeech run.sh

mfccdir=mfcc
stage=1

. ./cmd.sh
. ./path.sh
. parse_options.sh

# you might not want to do this for interactive shells.
set -e


if [ $stage -le 1 ]; then
  local/data_prep.sh --cmd "$mfcc_cmd"
fi

if [ $stage -le 3 ]; then

  local/prepare_dict.sh data/local/dict_nosp data/train data/dev data/test

  utils/prepare_lang.sh data/local/dict_nosp \
   "<UNK>" data/local/lang_tmp_nosp data/lang_nosp

  #local/format_lms.sh --src-dir data/lang_nosp data/local/lm
fi


if [ $stage -le 6 ]; then
  for part in dev test train; do
    steps/make_mfcc.sh --cmd "$train_cmd" --nj 40 data/$part exp/make_mfcc/$part $mfccdir
    steps/compute_cmvn_stats.sh data/$part exp/make_mfcc/$part $mfccdir
  done
fi

if [ $stage -le 7 ]; then
  # Make some small data subsets for early system-build stages.
  utils/subset_data_dir.sh --shortest data/train 2000 data/train_2kshort
  utils/subset_data_dir.sh data/train 5000 data/train_5k
  utils/subset_data_dir.sh data/train 10000 data/train_10k
fi

if [ $stage -le 8 ]; then
  # train a monophone system
  steps/train_mono.sh --boost-silence 1.25 --nj 20 --cmd "$train_cmd" \
                      data/train_2kshort data/lang_nosp exp/mono

fi

if [ $stage -le 9 ]; then
  steps/align_si.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
                    data/train_5k data/lang_nosp exp/mono exp/mono_ali_5k

  # train a first delta + delta-delta triphone system on a subset of 5000 utterances
  steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" \
                        2000 10000 data/train_5k data/lang_nosp exp/mono_ali_5k exp/tri1
fi

if [ $stage -le 10 ]; then
  steps/align_si.sh --nj 10 --cmd "$train_cmd" \
                    data/train_10k data/lang_nosp exp/tri1 exp/tri1_ali_10k


  # train an LDA+MLLT system.
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
                          --splice-opts "--left-context=3 --right-context=3" 2500 15000 \
                          data/train_10k data/lang_nosp exp/tri1_ali_10k exp/tri2b

  #TODO: you should probably decode with some model as a sanity check
  ## decode using the LDA+MLLT model
  #(
  #  utils/mkgraph.sh data/lang_nosp_test_tgsmall \
  #                   exp/tri2b exp/tri2b/graph_nosp_tgsmall
  #  for test in test_clean test_other dev_clean dev_other; do
  #    steps/decode.sh --nj 20 --cmd "$decode_cmd" exp/tri2b/graph_nosp_tgsmall \
  #                    data/$test exp/tri2b/decode_nosp_tgsmall_$test
  #    steps/lmrescore.sh --cmd "$decode_cmd" data/lang_nosp_test_{tgsmall,tgmed} \
  #                       data/$test exp/tri2b/decode_nosp_{tgsmall,tgmed}_$test
  #    steps/lmrescore_const_arpa.sh \
  #      --cmd "$decode_cmd" data/lang_nosp_test_{tgsmall,tglarge} \
  #      data/$test exp/tri2b/decode_nosp_{tgsmall,tglarge}_$test
  #  done
  #)&
fi

if [ $stage -le 11 ]; then
  # Align a 10k utts subset using the tri2b model
  steps/align_si.sh  --nj 10 --cmd "$train_cmd" --use-graphs true \
                     data/train_10k data/lang_nosp exp/tri2b exp/tri2b_ali_10k

  # Train tri3b, which is LDA+MLLT+SAT on 10k utts
  steps/train_sat.sh --cmd "$train_cmd" 2500 15000 \
                     data/train_10k data/lang_nosp exp/tri2b_ali_10k exp/tri3b

fi

if [ $stage -le 12 ]; then
  # align the entire train_10k subset using the tri3b model
  steps/align_fmllr.sh --nj 20 --cmd "$train_cmd" \
    data/train_10k data/lang_nosp \
    exp/tri3b exp/tri3b_ali_10k

  # train another LDA+MLLT+SAT system on the entire 100 hour subset
  steps/train_sat.sh  --cmd "$train_cmd" 4200 40000 \
                      data/train_10k data/lang_nosp \
                      exp/tri3b_ali_10k exp/tri4b

fi

if [ $stage -le 18 ]; then
  steps/align_fmllr.sh --nj 40 --cmd "$train_cmd" \
                       data/train data/lang exp/tri4b exp/tri4b_ali_train

  # train a SAT model on all data.  Use the train_quick.sh script
  # as it is faster.
  steps/train_quick.sh --cmd "$train_cmd" \
                       7000 150000 data/train data/lang exp/tri4b_ali_train exp/tri5b
fi


if [ $stage -le 19 ]; then
  # this does some data-cleaning. The cleaned data should be useful when we add
  # the neural net and chain systems.  (although actually it was pretty clean already.)
  local/run_cleanup_segmentation.sh
fi
