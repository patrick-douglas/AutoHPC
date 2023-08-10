#!/bin/bash
w=$(tput sgr0) 
r=$(tput setaf 1)
g=$(tput setaf 2) 
y=$(tput setaf 3) 
USAGE="USAGE: $0 -u <username>"
if [ "$#" -lt "1" ] 
then 
    echo -e $USAGE;
exit 1    
else 
    var1=$2;
fi

while getopts u: option
do
case "${option}"
in
u) user_name=$OPTARG;;
esac
done

if [ "$user_name" = "" ]; then
"${g}Error, missing arguments:${y} -u | User name | <string>
${w}$USAGE"
exit 1
fi
threads=`nproc`
#biopython
# As root
pip install biopython
pip install biopython --upgrade
/usr/local/bin/python3.10 -m pip install --upgrade pip

#As user
su -c 'pip install biopython' $user_name
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


