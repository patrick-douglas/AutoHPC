#!/usr/bin/env bash
set -euo pipefail
HOME_UTIL="/usr/local/bin/util/"
SWISSPROT_FASTA="/blastdb/sprot/uniprot_sprot.fasta"
OUTCSV="deep_enough.csv"

echo "pct,ge80,ge90,ge100,total" > "$OUTCSV"

for pct in 10 20 30 40 50 60 70 80 90 100; do
  dir="${pct}"
  fasta="${dir}/reads_${pct}pct.trinity_out.Trinity.fasta"
  blast="${dir}/blast_${pct}pct_swissprot.outfmt6.txt"
  cov="${dir}/full_length_${pct}pct.tsv"

  if [[ ! -f "$fasta" ]]; then
    echo "AVISO: faltando $fasta, pulando"
    continue
  fi

  if [[ ! -f "$blast" ]]; then
    echo "AVISO: faltando $blast, pulando"
    continue
  fi

  $HOME_UTIL/analyze_blastPlus_topHit_coverage.pl \
    "$blast" \
    "$fasta" \
    "$SWISSPROT_FASTA" \
    > "$cov"

  ge80=$(awk '$1==80 {print $3}' "$cov")
  ge90=$(awk '$1==90 {print $3}' "$cov")
  ge100=$(awk '$1==100 {print $3}' "$cov")
  total=$(awk 'END{print $3}' "$cov")

  echo "${pct},${ge80},${ge90},${ge100},${total}" >> "$OUTCSV"
done

echo "Pronto: $OUTCSV"
