#!/bin/bash
set -euo pipefail

# ===== Colors =====
w=$(tput sgr0)
r=$(tput setaf 1)
g=$(tput setaf 2)
y=$(tput setaf 3)

USAGE="USAGE: $0 -u <username>"

# ===== Parse args =====
user_name=""

while getopts ":u:" option; do
  case "${option}" in
    u) user_name="$OPTARG" ;;
    *) echo -e "${r}Invalid option${w}\n$USAGE"; exit 1 ;;
  esac
done

if [ -z "$user_name" ]; then
  echo -e "${r}Error:${y} missing -u <username>${w}\n$USAGE"
  exit 1
fi

threads=$(nproc)

# ======================================================
# Python deps
# ======================================================
echo "${y}*******************"
echo "Python packages"
echo "*******************${w}"

su - "$user_name" -c "pip install --upgrade pip"
su - "$user_name" -c "pip install --upgrade biopython pandas"

# ======================================================
# BBTools / BBMap
# ======================================================
echo "${y}*******************"
echo "BBMap"
echo "*******************${w}"

bbtools_url="https://phoenixnap.dl.sourceforge.net/project/bbmap/BBMap_39.68.tar.gz"
bbtools_tar="BBMap_39.68.tar.gz"
bbtools_path="/home/$user_name/bbmap"

su - "$user_name" -c "
cd ~ &&
rm -f $bbtools_tar &&
wget $bbtools_url &&
tar -zxf $bbtools_tar &&
rm -f $bbtools_tar
"

rm -rf /usr/local/bin/bbmap
mv -f "$bbtools_path" /usr/local/bin/
ln -fs /usr/local/bin/bbmap/bbmap.sh /usr/local/bin/bbmap.sh

# ======================================================
# Miniprot
# ======================================================
echo "${y}*******************"
echo "Miniprot"
echo "*******************${w}"

miniprot_url="https://github.com/lh3/miniprot/releases/download/v0.18/miniprot-0.18_x64-linux.tar.bz2"
miniprot_bz2="miniprot-0.18_x64-linux.tar.bz2"
miniprot_tar="miniprot-0.18_x64-linux.tar"

su - "$user_name" -c "
cd ~ &&
rm -f $miniprot_bz2 $miniprot_tar &&
wget $miniprot_url &&
bunzip2 $miniprot_bz2 &&
tar -xf $miniprot_tar &&
rm -f $miniprot_tar
"

rm -rf /usr/local/bin/miniprot*
mv /home/$user_name/miniprot-* /usr/local/bin/
ln -fs /usr/local/bin/miniprot*/miniprot /usr/local/bin/miniprot

# ======================================================
# BLAST
# ======================================================
echo "${y}*******************"
echo "BLAST"
echo "*******************${w}"

#apt-fast install -y ncbi-blast+

# ======================================================
# Augustus
# ======================================================
echo "${y}*******************"
echo "Augustus"
echo "*******************${w}"

apt-fast install -y augustus augustus-data augustus-doc

# ======================================================
# MetaEuk
# ======================================================
echo "${y}*******************"
echo "MetaEuk"
echo "*******************${w}"

metaeuk_url="https://mmseqs.com/metaeuk/metaeuk-linux-avx2.tar.gz"
metaeuk_tar="metaeuk-linux-avx2.tar.gz"

su - "$user_name" -c "
cd ~ &&
rm -f $metaeuk_tar &&
wget $metaeuk_url &&
tar -xzf $metaeuk_tar &&
rm -f $metaeuk_tar
"

rm -rf /usr/local/bin/metaeuk-linux-avx2
mv /home/$user_name/metaeuk /usr/local/bin/metaeuk-linux-avx2
ln -fs /usr/local/bin/metaeuk-linux-avx2/bin/metaeuk /usr/local/bin/metaeuk

# ======================================================
# Prodigal
# ======================================================
echo "${y}*******************"
echo "Prodigal"
echo "*******************${w}"

prodigal_url="https://github.com/hyattpd/Prodigal/archive/refs/tags/v2.6.3.tar.gz"
prodigal_tar="v2.6.3.tar.gz"

su - "$user_name" -c "
cd ~ &&
rm -f $prodigal_tar &&
wget $prodigal_url &&
tar -xzf $prodigal_tar &&
rm -f $prodigal_tar
"

cd /home/$user_name/Prodigal-* && make install
rm -rf /home/$user_name/Prodigal-*

# ======================================================
# HMMER
# ======================================================
echo "${y}*******************"
echo "HMMER"
echo "*******************${w}"

hmmer_url="http://eddylab.org/software/hmmer/hmmer.tar.gz"
hmmer_tar="hmmer.tar.gz"

su - "$user_name" -c "
cd ~ &&
rm -f $hmmer_tar &&
wget $hmmer_url &&
tar -xzf $hmmer_tar
"

cd /home/$user_name/hmmer-* && ./configure && make -j "$threads" && make install
rm -rf /home/$user_name/hmmer-* 

# ======================================================
# SEPP
# ======================================================
echo "${y}*******************"
echo "SEPP"
echo "*******************${w}"

sepp_url="https://github.com/smirarab/sepp/archive/refs/tags/v4.5.5.tar.gz"
sepp_tar="v4.5.5.tar.gz"

su - "$user_name" -c "
cd ~ &&
rm -f $sepp_tar &&
wget $sepp_url &&
tar -xzf $sepp_tar
"

cd /home/$user_name/sepp-* && python setup.py config && python setup.py install
rm -rf /home/$user_name/sepp-* 

# ======================================================
echo
echo "${g}Installation finished successfully.${w}"
