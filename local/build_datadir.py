#!/usr/bin/env python3
import pathlib
#The pympi-ling Elan parser; not the MPI interface.
# available: https://github.com/dopefishh/pympi
import pympi

def find_file_pairs(root):
  rootpath = pathlib.Path(root)
  eafs = rootpath.glob('**/*.eaf')
  wavs = list(rootpath.glob('**/*.wav'))
  pairs = []
  def match_and_del(eaf):
    i, wav = next((i, wav) for i, wav in enumerate(wavs) if wav.stem == eaf.stem)
    del wavs[i]
    return wav
  for eaf in eafs:
    try:
      wav = match_and_del(eaf)
    except StopIteration:
      continue
    pairs.append((eaf, wav))
  return pairs

def parse_spk(tier_id):
  return "".join(char for char in tier_id.lower() if char.isalpha())

__existing_uttids__ = set() #Tracking for duplicates
def create_uttid(speaker, recordid, start):
  #start and end in floating point seconds
  candidate = speaker + "-" + recordid + "-{0:08d}".format(int(start*1000.)) + "-1"
  while candidate in __existing_uttids__:
    #modify the last character till a unique uttid is found
    base, sentence_index = candidate.rsplit("-", maxsplit=1)
    candidate = base + "-" + str(int(sentence_index)+1)
  __existing_uttids__.add(candidate)
  return candidate

def create_recordid(wavpath):
  return wavpath.stem

class Slottsy:
  #This is for convenience, kind of like a more flexible namedtuple
  __slots__ = () #No dict, but instead define __slots__ in subclass to just have those attrs
  def __init__(self, *args, **kwargs):
    for i, val in enumerate(args):
      setattr(self, self.__slots__[i], arg)
    for key, val in kwargs.items():
      setattr(self, key, val)

class Line(Slottsy):
  #Represents a line in a Kaldi style data dir file
  def __str__(self):
    return " ".join(str(getattr(self, attr)) for attr in self.__slots__)

class Utt2SpkLine(Line): __slots__ = "uttid", "speaker" 
class SegmentsLine(Line): 
  __slots__ = "uttid", "recordid", "start", "end"
class TextLine(Line): 
  __slots__ = "uttid", "text"
  def __str__(self):
    return self.uttid + " " +  " ".join(self.text)

def make_text_preprocessor_from_external(command):
  import subprocess, io
  proc = subprocess.Popen(command, shell=True, 
      stdin=subprocess.PIPE, stdout=subprocess.PIPE)
  istream = io.TextIOWrapper(proc.stdin, 
      encoding="utf-8", line_buffering=True)
  ostream = io.TextIOWrapper(proc.stdout, 
      encoding="utf-8", line_buffering=True)
  def preprocess(text):
    istream.write(text+"\n")
    return ostream.readline()[:-1]#Cut the newline out
  return preprocess

def unity_text_preprocessor(raw):
  return raw

def process_sentence_end(text):
  if text[-1] in ".!?":
    return True, text[:-1]
  else:
    return False, text

def time_equal(x,y): 
  #"close enough" equality check for floating point time values
  return x-y < 0.01

def parse_eaf(eafpath, recordid,
    text_preprocessor=unity_text_preprocessor):
  #Parse Kaldi-style info from an eaf. 
  #Each eaf corresponds to one audio file.
  #First get a linear, word-by-word record:
  eaf = pympi.Elan.Eaf(eafpath.as_posix())
  parsed = {}
  all_alignments = []
  for tier_id in eaf.tiers:
    raw_alignment = eaf.get_annotation_data_for_tier(tier_id)
    tagged_alignment = [(float(start)/1000, float(end)/1000, word, tier_id) 
        for start, end, word in raw_alignment]
    all_alignments.extend(tagged_alignment)
  all_alignments.sort(key = lambda ta: ta[0])
  #Then parse this into the kaldi contents
  #These are the Kaldi data dir contents that will be extracted:
  utt2spk = []
  segments = []
  text = []
  for start, end, word, tier_id in all_alignments:
    speaker = parse_spk(tier_id)
    parsed_word = text_preprocessor(word) #This could be an external program call
    #Manage some problem cases:
    if not parsed_word:  
      continue
    if time_equal(start, end):
      end = end+0.1
    sentence_end, parsed_word = process_sentence_end(parsed_word)
    start_new = ( not utt2spk #first utterance found
        or start_new or speaker != utt2spk[-1].speaker )
    if start_new:
      start_new = False
      uttid = create_uttid(speaker, recordid, start)
      utt2spk.append(Utt2SpkLine(uttid = uttid, speaker = speaker))
      segments.append(SegmentsLine(uttid = uttid, recordid = recordid, start = start, end = end))
      text.append(TextLine(uttid = uttid, text = []))
    segments[-1].end = end
    text[-1].text.append(parsed_word)
    start_new = sentence_end 
  return {"utt2spk":utt2spk, "segments":segments, "text":text}

class WavScpLine(Line): __slots__ = "recordid", "wavpath"
def process_pairs(pairs, **eaf_parse_args):
  wavscp = []
  utt2spk = []
  segments = []
  text = []
  for eafpath, wavpath in pairs:
    recordid = create_recordid(wavpath)
    wavscp.append(WavScpLine(recordid = recordid, wavpath = wavpath))
    parsed = parse_eaf(eafpath, recordid, **eaf_parse_args)
    utt2spk.extend(parsed["utt2spk"])
    segments.extend(parsed["segments"])
    text.extend(parsed["text"])
  return {"wav.scp":wavscp, "utt2spk":utt2spk, "segments":segments, "text":text}

def write_datadir(dirpath, parsed_contents):
  if not all(parsed_contents.values()): #Some scp empty
    print("Refusing to create empty/incomplete directory at", dirpath)
    return
  try: #py3.4 doesn't have mkdir(..., exist_ok=True) flag
    dirpath.mkdir(parents=True)
  except FileExistsError:
    pass
  for filename, content_lines in parsed_contents.items():
    filepath = dirpath / filename
    with filepath.open("w") as fo:
      for line in content_lines:
        print(line, file=fo)

if __name__ == "__main__":
  import argparse
  parser = argparse.ArgumentParser("Builds a Kaldi-style datadir from a directory structure containing EAFs and corresponding wavs.")
  parser.add_argument("source", help = "The source directory structure", 
      type=pathlib.Path)
  parser.add_argument("target", help = "Where to put the resulting datadir", 
      type=pathlib.Path)
  parser.add_argument("--text-preprocessor", nargs=1, help = "An external preprocessor program that reads stdin and outputs to stdout the preprocessed text. It should preserve .!? as these are used to split sentences.", default=None)
  args = parser.parse_args()
  pairs = find_file_pairs(args.source)
  if args.text_preprocessor:
    preprocessor = make_text_preprocessor_from_external(args.text_preprocessor)
    parsed_contents = process_pairs(pairs, text_preprocessor=preprocessor)
  else:
    parsed_contents = process_pairs(pairs)
  write_datadir(args.target, parsed_contents)

