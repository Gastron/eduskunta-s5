#!/bin/bash
#Downloads the Python Elan (and textgrid) parser, this can also be installed with pip install pympi-ling
cd local
rm -rf pympi
git clone https://github.com/dopefishh/pympi ./pympi-git
mv pympi-git/pympi pympi
rm -rf pympi-git
