#!/bin/bash
w=$(tput sgr0) 
r=$(tput setaf 1)
g=$(tput setaf 2) 
y=$(tput setaf 3)
while getopts a:b:x:y:d:g:i:q: option
do
case "${option}"
in
a) up_subsetA=$OPTARG;;
b) up_subsetB=$OPTARG;;
x) up_subsetAfactor_labeling=$OPTARG;;
y) up_subsetBfactor_labeling=$OPTARG;;
d) edgR_DE_results=$OPTARG;;
g) gene_trans_map=$OPTARG;;
i) trinity_fasta=$OPTARG;;
q) salmon_quant_sf=$OPTARG;;

esac
done
if [ "$up_subsetA" = "" ]; then
echo "${g}Error, missing arguments:${y} -a | blast2go table for subset A NOTE: remove genes with no GOs | <string>"
echo "Example: -a control_up_subset.b2g.table.txt"
exit 1
fi
if [ "$up_subsetB" = "" ]; then
echo "${g}Error, missing arguments:${y} -b | blast2go table for subset B NOTE: remove genes with no GOs | <string>"
echo "Example: -b infected_up_subset.b2g.table.txt"
exit 1
fi
if [ "$up_subsetAfactor_labeling" = "" ]; then
echo "${g}Error, missing arguments:${y} -x | experimental condition | <string>"
echo "Example: -x control"
exit 1
fi
if [ "$up_subsetBfactor_labeling" = "" ]; then
echo "${g}Error, missing arguments:${y} -y | experimental condition | <string>"
echo "Example: -y infected"
exit 1
fi
if [ "$edgR_DE_results" = "" ]; then
echo "${g}Error, missing arguments:${y} -d | Difeerential Expression edgR results file | <string>"
echo "Example: -d salmon.gene.counts.matrix.control_vs_infected.edgeR.DE_results"
exit 1
fi
if [ "$gene_trans_map" = "" ]; then
echo "${g}Error, missing arguments:${y} -g | Trinity Gene to transcripts map file | <string>"
echo "Example: -g Trinity.fasta.gene_trans_map"
exit 1
fi
if [ "$trinity_fasta" = "" ]; then
echo "${g}Error, missing arguments:${y} -i | Trinity FASTA file User name | <string>"
echo "Example: -i Trinity.fasta"
exit 1
fi
if [ "$salmon_quant_sf" = "" ]; then
echo "${g}Error, missing arguments:${y} -q | quant_sf file generated by salmon | <string>"
echo "Example: -q quant.sf"
exit 1
fi
#Inicio
echo "${g}================="
echo "${w}Auto GoSeq script${g}"
echo "=================${w}"
echo ''
echo "Declared options:" 
echo "-a${g} $up_subsetA${w}"
echo "-b${g} $up_subsetB${w}"
echo "-x${g} $up_subsetAfactor_labeling${w}"
echo "-y${g} $up_subsetBfactor_labeling${w}"
echo "-d${g} $edgR_DE_results${w}"
echo "-g${g} $gene_trans_map${w}"
echo "-i${g} $trinity_fasta${w}"
echo "-q${g} $salmon_quant_sf${w}"
echo "${g}=================${w}"
echo ""
rm -rf .Corset-tools
echo "Generating ${g}factor_labeling.txt...${w}"
#Processa o subset A
cat $up_subsetA | grep TRINITY |awk -F "\t" '{print $3"\t"}' | sed "s/$/$up_subsetAfactor_labeling/" > .factorA
#Processa o subset B
cat $up_subsetB | grep TRINITY |awk -F "\t" '{print $3"\t"}' | sed "s/$/$up_subsetBfactor_labeling/" > .factorB
#Combina A + B
cat .factorA .factorB | awk -F "\t" '{print $2,$1}'> factor_labeling.txt
sed -i 's/ /\t/g' factor_labeling.txt
rm -rf .factorA .factorB

echo "Generating ${g}background.txt...${w}"
#Gerar arquivo background
# Aqui eu usarei o coreto tools para pegar apenas as insoformas mais longas em PB
#Criar o TARGETCLUST fake
#edgR_DE_results=salmon.gene.counts.matrix.female_vs_male.edgeR.DE_results
cat $edgR_DE_results | grep TRINITY | awk '{print $1}' > .target.cluster.txt

#Criar o CLUSTMAP
cat $gene_trans_map | awk '{print $2,"\t"$1}' > .cluster.map.txt

#Trinity fasta original

#Baixar e Rodar o fetchClusterSeqs.py
git clone --quiet https://github.com/patrick-douglas/Corset-tools.git > /dev/null
mv Corset-tools .Corset-tools

python3 .Corset-tools/fetchClusterSeqs.py -i $trinity_fasta -t .target.cluster.txt -c .cluster.map.txt -l -o .target_genes.fa

#Criar a lista de ID a partir do fasta criado pelo fetchClusterSeqs.py
cat .target_genes.fa | grep TRINITY | awk -F ">" '{print $2}' > background.txt

#limpar arquivos temporarios
rm -rf .Corset-tools .cluster.map.txt .target.cluster.txt .target_genes.fa *.log

#Create GO_assignments.txt file
cat $up_subsetA $up_subsetB | grep -v "Tags" > .up_subsetAB_no_heads.txt

subset_original=".up_subsetAB_no_heads.txt"
subset=${subset_original::-4}

# Get GO names
#Criar um arquivo com as colunas gene_ID e GO_ID
cat .up_subsetAB_no_heads.txt | awk -F "\t" '{print $3,"\t"$11}' > $subset

#remove P: C: F:
sed -i -e "s/P://g" $subset
sed -i -e "s/C://g" $subset
sed -i -e "s/F://g" $subset
cat $subset > .test

#Replace ; por \n;
sed -i -e "s/; /\n;/g" $subset
sed -i -e "s/ \t/\n;/g" $subset

# Dividir o arquivo resultante por gene
mkdir -p genes && cd genes
csplit -s -z ../$subset /TRINITY/ '{*}'

# Adicionar o sufixo .txt em todos os arquivos
for i in *; do mv "$i" "${i%.*}.txt"; done

# Criar um nova coluna com o GENE_ID ao lado de cada GO_ID

for f in *.txt ; do 
    GENE_ID=`head -n 1 $f`
    sed "s/;/$GENE_ID\t/" $f | tail -n +2 > $f.GO_seq

  done
rm -rf *.txt 

# Combinar todos os arquivos GO_seq resultantes
cat *.GO_seq > ../$subset.GO_names
cd .. 
rm -rf genes
rm $subset

# Get GO ids
mkdir genes
#Criar um arquivo com as colunas gene_ID e GO_ID
cat .up_subsetAB_no_heads.txt | awk -F "\t" '{print $3,"\t"$10}' > $subset

#remove P: C: F:
sed -i -e "s/P://g" $subset
sed -i -e "s/C://g" $subset
sed -i -e "s/F://g" $subset
sed -i -e "s/;_GO/\; GO/g" $subset

sed -i -e "s/P://g" $subset

#Replace ; por \n;
sed -i -e "s/; /\n;/g" $subset
sed -i -e "s/ \t/\n;/g" $subset

# Dividir o arquivo resultante por gene
mkdir -p genes && cd genes
csplit -s -z ../$subset /TRINITY/ '{*}' 2> /dev/null

# Adicionar o sufixo .txt em todos os arquivos
for i in *; do mv "$i" "${i%.*}.txt"; done

# Criar um nova coluna com o GENE_ID ao lado de cada GO_ID

for f in *.txt ; do
    GENE_ID=`head -n 1 $f`
    sed "s/;/$GENE_ID\t/" $f | tail -n +2 > $f.GO_seq

  done
rm -rf *.txt $subset

# Combinar todos os arquivos GO_seq resultantes
cat *.GO_seq > ../$subset.GO_ids
cd .. 
rm -rf genes
rm $subset
rm .test

#Criar o arquivi final 
paste $subset.GO_ids $subset.GO_names | awk -F "\t" '{print $1,"\t"$2"-"$4"\t",$2}' > $subset.GO_ids_names
mv $subset.GO_ids_names $up_subsetAfactor_labeling-$up_subsetBfactor_labeling.GO_ids_names
rm $subset.GO_ids $subset.GO_names
rm -rf .up_subsetAB_no_heads.txt

#criar o arquivo lenghts 
echo "Generating${g} $up_subsetAfactor_labeling-$up_subsetBfactor_labelinggene_lengths...${w}"
subset=$up_subsetAfactor_labeling-$up_subsetBfactor_labeling

#Criar a lista de transcritos:
#cat $up_subsetAfactor_labeling-$up_subsetBfactor_labeling.GO_ids_names | awk '{print $1}' > .list
cat background.txt > .list

#Extratir os comprimentos dos genes
cat $salmon_quant_sf | grep -f .list | awk -F "\t" '{print $1"\t",$2}' > $subset.gene_lengths
rm .list
#adicionar os headings no arquivo 
sed -i '1 i\gene_id\tlength' $subset.gene_lengths


#Create GO_assignments.txt file final
echo "Generating ${g}GO_assignments.txt...${w}"
cat $up_subsetA | grep -v "Tags" | awk  '$10!=""' > .up_subsetAB_no_heads.txt
cat $up_subsetB | grep -v "Tags" | awk  '$10!=""' >> .up_subsetAB_no_heads.txt

subset_original=".up_subsetAB_no_heads.txt"
subset=${subset_original::-4}

# Get GO ids
#Criar um arquivo com as colunas gene_ID e GO_ID
cat .up_subsetAB_no_heads.txt | awk -F "\t" '{print $3,"\t"$10}' > $subset

#remove P: C: F:
sed -i -e "s/P://g" $subset
sed -i -e "s/C://g" $subset
sed -i -e "s/F://g" $subset


#remover info das isoformas
sed -i -e "s/; GO/\;_GO/g" $subset
#cat $subset | awk -F "_i" '{print $1,$2}' > .teste
#cat .teste | awk '{print $1,"\t"$3}' > $subset
#rm .teste
sed -i -e "s/;_GO/\; GO/g" $subset

sed -i -e "s/P://g" $subset


#Replace ; por \n;
sed -i -e "s/; /,/g" $subset
mv $subset $up_subsetAfactor_labeling-$up_subsetBfactor_labeling.GO_assignments

rm -rf genes .up_subsetAB_no_heads.txt  __runGOseq.R
rm -rf  GOseq_results && mkdir GOseq_results
echo "${w}Running GOSeq...${w}"
cd GOseq_results 
${TRINITY_HOME}/Analysis/DifferentialExpression/run_GOseq.pl --factor_labeling ../factor_labeling.txt --GO_assignments ../$up_subsetAfactor_labeling-$up_subsetBfactor_labeling.GO_assignments --lengths ../female-male.gene_lengths --background ../background.txt  > /dev/null 2>&1
echo "${w}All Done!${w}"
echo "${w}You can find results in: ${g}GOseq_results${w}"
echo ":D"