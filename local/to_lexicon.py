#!/usr/bin/env python3
import sys
for line in sys.stdin:
  word = line.strip()
  if not word:
    continue
  print(word, " ".join(word))
