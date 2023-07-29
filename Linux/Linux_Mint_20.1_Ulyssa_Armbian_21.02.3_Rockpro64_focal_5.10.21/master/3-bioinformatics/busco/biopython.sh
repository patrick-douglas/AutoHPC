#!/bin/bash
#biopython
pip install biopython
pip install biopython --upgrade
/usr/local/bin/python3.10 -m pip install --upgrade pip

#pandas
sudo apt-fast install -y python3-pandas

#bbtools
wget https://gox.dl.sourceforge.net/project/bbmap/BBMap_39.01.tar.gz
tar -zxf BBMap_39.01.tar.gz && rm -rf BBMap_39.01.tar.gz
#blast

#Augustus

#metaeuk
wget https://mmseqs.com/metaeuk/metaeuk-linux-avx2.tar.gz; tar xzvf metaeuk-linux-avx2.tar.gz; export PATH=$(pwd)/metaeuk/bin/:$PATH

#Prodigal
wget https://github.com/hyattpd/Prodigal/releases/download/v2.6.3/prodigal.linux

#hmmer


