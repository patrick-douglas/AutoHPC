#!/usr/bin/env bash
set -euo pipefail

HOME_UTIL="/usr/local/bin/util"
SWISSPROT_FASTA="/blastdb/sprot/uniprot_sprot.fasta"
OUTCSV="deep_enough.csv"

EVALUE_CUTOFF="1e-5"
BITSCORE_CUTOFF="50"

PCTS=(10 20 30 40 50 60 70 80 90 100)

ANALYZE_SCRIPT="${HOME_UTIL}/analyze_blastPlus_topHit_coverage.pl"

[[ -x "$ANALYZE_SCRIPT" ]] || { echo "ERROR: script not found/executable: $ANALYZE_SCRIPT" >&2; exit 1; }
[[ -f "$SWISSPROT_FASTA" ]] || { echo "ERROR: Swiss-Prot FASTA not found: $SWISSPROT_FASTA" >&2; exit 1; }

echo "pct,ge80,ge90,ge100,total,blast_total_hits,unique_transcripts,unique_swissprot_hits,highconf_unique_swissprot" > "$OUTCSV"

for pct in "${PCTS[@]}"; do
  dir="${pct}"
  fasta="${dir}/reads_${pct}pct.trinity_out.Trinity.fasta"
  blast="${dir}/blast_${pct}pct_swissprot.outfmt6.txt"
  cov="${dir}/full_length_${pct}pct.tsv"

  echo
  echo "=============================="
  echo ">> Processing ${pct}%"
  echo "=============================="

  if [[ ! -f "$fasta" ]]; then
    echo "WARNING: missing $fasta, skipping" >&2
    continue
  fi

  if [[ ! -f "$blast" ]]; then
    echo "WARNING: missing $blast, skipping" >&2
    continue
  fi

  "$ANALYZE_SCRIPT" \
    "$blast" \
    "$fasta" \
    "$SWISSPROT_FASTA" \
    > "$cov"

  ge80=$(awk '$1==80 {print $3}' "$cov")
  ge90=$(awk '$1==90 {print $3}' "$cov")
  ge100=$(awk '$1==100 {print $3}' "$cov")
  total=$(awk 'END{print $3}' "$cov")

  blast_total_hits=$(awk 'NF > 0 {n++} END {print n+0}' "$blast")

  unique_transcripts=$(awk 'NF >= 1 {print $1}' "$blast" | sort -u | wc -l)
  unique_swissprot_hits=$(awk 'NF >= 2 {print $2}' "$blast" | sort -u | wc -l)

  highconf_unique_swissprot=$(
    awk -v e="$EVALUE_CUTOFF" -v b="$BITSCORE_CUTOFF" \
      'NF >= 12 && $11 <= e && $12 >= b {print $2}' "$blast" \
      | sort -u \
      | wc -l
  )

  echo "${pct},${ge80},${ge90},${ge100},${total},${blast_total_hits},${unique_transcripts},${unique_swissprot_hits},${highconf_unique_swissprot}" >> "$OUTCSV"

  echo ">> ge80: $ge80 | ge90: $ge90 | unique Swiss-Prot hits: $unique_swissprot_hits"
done

echo
echo "SUCCESS: summary written to $OUTCSV"
