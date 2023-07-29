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
#As root
pip install biopython
pip install biopython --upgrade
/usr/bin/python3 -m pip install --upgrade pip
#As me
su -c 'pip install biopython' $user_name
su -c 'pip install biopython --upgrade' $user_name
su -c '/usr/bin/python3 -m pip install --upgrade pip' $user_name

#pandas
sudo apt-fast install -y python3-pandas

#bbtools
echo "${y}*******************"
echo 'BBMap'
echo "*******************${w}"
bbtools_url=https://gox.dl.sourceforge.net/project/bbmap/BBMap_39.01.tar.gz
bbtools_tar=BBMap_39.01.tar.gz
bbtools_path=/home/$user_name/bbmap/
su -c "cd ~/ && wget $bbtools_url" $user_name
su -c "cd ~/ && tar -zxf $bbtools_tar" $user_name
cd /home/rm -rf $bbtools_tar
bbmap_ver=`$bbtools_path/bbmap.sh --version`
#blast
#add check blast install
#Augustus
#add check blast install
#metaeuk
echo "${y}*******************"
echo 'metaeuk'
echo "*******************${w}"
metaeuk_url=https://mmseqs.com/metaeuk/metaeuk-linux-avx2.tar.gz
metaeuk_tar=metaeuk-linux-avx2.tar.gz
metaeuk_path=/home/$user_name/metaeuk/
su -c "cd ~/ && wget $metaeuk_url" $user_name
su -c "cd ~/ && tar -zxf $metaeuk_tar" $user_name
rm -rf $metaeuk_tar
metaeuk_ver=`$metaeuk_path/bin/metaeuk | grep  Version`
export PATH=$(pwd)/metaeuk/bin/:$PATH

#Prodigal
echo "${y}*******************"
echo 'Prodigal'
echo "*******************${w}"
prodigal_url=https://github.com/hyattpd/Prodigal/releases/download/v2.6.3/prodigal.linux
prodigal_exe=prodigal.linux
prodigal_path=/home/$user_name/prodigal/
su -c "$prodigal_path" $user_name
su -c "cd ~/ && wget $prodigal_url" $user_name
su -c "cd ~/ && tar -zxf $prodigal_exe" $user_name
prodigal_ver=`$prodigal_path/prodigal.linux -v`

#hmmer
echo "${y}*******************"
echo 'hmmer'
echo "*******************${w}"
hmmer_url=http://eddylab.org/software/hmmer/hmmer.tar.gz
hmmer_tar=hmmer.tar.gz
hmmer_path=/home/$user_name/hmmer-3.3.2/
su -c "cd ~/ && wget $hmmer_url" $user_name
su -c "cd ~/ && tar -zxf $hmmer_tar" $user_name
su -c "cd $hmmer_path && ./configure" $user_name
su -c "cd $hmmer_path && ./make -j $threads" $user_name
cd $hmmer_path && make install
rm -rf $hmmer_tar
hmmer_ver=`hmmscan -h | grep HMMER`

#sepp
echo "${y}*******************"
echo 'sepp'
echo "*******************${w}"
sepp_url=https://github.com/smirarab/sepp/archive/refs/tags/4.5.1.tar.gz
sepp_tar=4.5.1.tar.gz
sepp_path=/home/$user_name/sepp/

su -c "cd ~/ && wget $sepp_url" $user_name
su -c "cd ~/ && tar -zxf $sepp_tar" $user_name
su -c "cd ~/ && mv sepp-4.5.1 sepp" $user_name
/home/$user_name/sepp/python3 setup.py config
/home/$user_name/sepp/python3 setup.py install










