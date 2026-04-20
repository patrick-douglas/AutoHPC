#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG (ajuste aqui) ======
HPC_FASTA_GR="/home/me/HpcGridRunner/BioIfx/hpc_FASTA_GridRunner.pl"
GRIDCONF="/home/me/HpcGridRunner/hpc_conf/SLURM.blast.conf"

# DB do DIAMOND (prefix do .dmnd, sem extensão)  <<-- se você usa fasta, ok também, mas normalmente é .dmnd
DIAMOND_DB="/blastdb/sprot/uniprot_sprot.fasta"

EVALUE="1e-3"
MAX_TARGETS="1"
OUTFMT="6"
SENS="--more-sensitive"

SEQS_PER_BIN="1000"
PCTS=(10)

FORCE=1
# ==================================

# Checagens básicas
[[ -x "$HPC_FASTA_GR" ]] || { echo "ERRO: não achei executável $HPC_FASTA_GR"; exit 1; }
[[ -f "$GRIDCONF" ]]     || { echo "ERRO: não achei $GRIDCONF"; exit 1; }

for pct in "${PCTS[@]}"; do
  dir="${pct}"
  trinity_fa="reads_${pct}pct.trinity_out.Trinity.fasta"
  out_prefix="blast_${pct}pct_swissprot"
  out_file="${out_prefix}.outfmt6"

  echo
  echo "=============================="
  echo ">> DIAMOND ${pct}% (pasta: ${dir})"
  echo "=============================="

  [[ -d "$dir" ]] || { echo "AVISO: pasta '$dir' não existe, pulando"; continue; }

  pushd "$dir" >/dev/null

  if [[ ! -f "$trinity_fa" ]]; then
    echo "AVISO: não achei $dir/$trinity_fa, pulando"
    popd >/dev/null
    continue
  fi

  if [[ -f "$out_file" && "$FORCE" -eq 0 ]]; then
    echo "AVISO: output '$dir/$out_file' já existe. (FORCE=0) Pulando."
    popd >/dev/null
    continue
  fi

  if [[ -f "$out_file" && "$FORCE" -eq 1 ]]; then
    echo "FORCE=1: removendo output antigo $dir/$out_file"
    rm -f "$out_file" "${out_file}.txt" 2>/dev/null || true
    rm -rf "$out_file" farmit* *.cmds *.cache_success 2>/dev/null || true
  fi

  # Template: usa __QUERY_FILE__ e mantém $(getconf ...) literal para ser avaliado no node
  cmd_template="$(cat <<'EOF'
diamond blastx -d __DIAMOND_DB__ -q __QUERY_FILE__ --evalue __EVALUE__ --max-target-seqs __MAX_TARGETS__ --outfmt __OUTFMT__ --threads $(getconf _NPROCESSORS_ONLN) __SENS__
EOF
)"

  # Substitui placeholders "nossos" (mais seguro do que misturar aspas)
  cmd_template="${cmd_template/__DIAMOND_DB__/${DIAMOND_DB}}"
  cmd_template="${cmd_template/__EVALUE__/${EVALUE}}"
  cmd_template="${cmd_template/__MAX_TARGETS__/${MAX_TARGETS}}"
  cmd_template="${cmd_template/__OUTFMT__/${OUTFMT}}"
  cmd_template="${cmd_template/__SENS__/${SENS}}"

  # Submete via GridRunner
  "$HPC_FASTA_GR" \
    --cmd_template "$cmd_template" \
    --query_fasta "$trinity_fa" \
    --grid_conf "$GRIDCONF" \
    --parafly \
    -N "$SEQS_PER_BIN" \
    -O "$out_file"
  # Unificar os arquivos .OUT (recursivo + ordenado)
  echo ">> Unindo fragmentos .OUT dentro de: $out_file"

  sleep 2

  outs=()
  mapfile -t outs < <(
    find "$PWD/$out_file" -type f -name "*.OUT" -size +0c | sort -V
  )

  if [ "${#outs[@]}" -gt 0 ]; then
    cat "${outs[@]}" > "${out_file}.txt"
    echo ">> OK: ${out_file}.txt (${#outs[@]} arquivos)"
  else
    echo "!! AVISO: não encontrei nenhum *.OUT em $PWD/$out_file"
  fi


  popd >/dev/null
done

echo
echo "✅ Done. DIAMOND blastx submetido para os percentuais definidos."

