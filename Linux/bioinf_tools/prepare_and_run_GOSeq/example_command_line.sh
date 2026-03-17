#!/bin/bash
prepare_and_run_GOSeq.sh -a ../Female/A-female_up_subset_merged.b2g.table.txt -b ../Male/B-male_up_subset_merged.b2g.table.txt -x female -y male -d original_data/salmon.gene.counts.matrix.female_vs_male.edgeR.DE_results -g original_data/tambaqui.macho-femea_Grazyelly.fasta.gene_trans_map -i original_data/tambaqui.macho-femea_Grazyelly.fasta -q original_data/quant.sf
