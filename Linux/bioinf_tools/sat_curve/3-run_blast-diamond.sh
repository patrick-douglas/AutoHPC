#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat << 'EOF'
Usage:
  run_diamond_by_pct.sh [options]

Description:
  Runs DIAMOND blastx against Swiss-Prot for Trinity assemblies generated
  from percentage-based FASTQ subsets.

Options:
  --db PATH              DIAMOND database prefix or FASTA path
  --gridconf PATH        GridRunner SLURM config
  --hpc-fasta-gr PATH    Path to hpc_FASTA_GridRunner.pl
  --seqs-per-bin N       Number of sequences per FASTA bin [default: 1000]
  --evalue VALUE         DIAMOND e-value cutoff [default: 1e-3]
  --max-targets N        Max target sequences [default: 1]
  --sensitivity STR      DIAMOND sensitivity option [default: --more-sensitive]
  --pcts "10 20 30"      Percentages to process manually
  --no-auto              Disable auto-detection of numeric folders
  --force                Remove previous outputs before running
  --help                 Show this help message

Default behavior:
  Auto-detects numeric folders such as:
    10/, 20/, 30/, ... 100/

Expected files inside each folder:
  reads_10pct.trinity_out.Trinity.fasta
  reads_20pct.trinity_out.Trinity.fasta
  ...

Output:
  blast_10pct_swissprot.outfmt6/
  blast_10pct_swissprot.outfmt6.txt

Example:
  ./run_diamond_by_pct.sh --force
  ./run_diamond_by_pct.sh --pcts "10 20 30" --seqs-per-bin 500
EOF
}

# ===== Defaults =====
HPC_FASTA_GR="/home/me/HpcGridRunner/BioIfx/hpc_FASTA_GridRunner.pl"
GRIDCONF="/home/me/HpcGridRunner/hpc_conf/SLURM.blast.conf"
DIAMOND_DB="/blastdb/sprot/uniprot_sprot.fasta"

EVALUE="1e-3"
MAX_TARGETS="1"
OUTFMT="6"
SENS="--more-sensitive"
SEQS_PER_BIN="20"

AUTO_DETECT=1
FORCE=0
PCTS=(10)

# ===== Argument parser =====
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)
      DIAMOND_DB="$2"; shift 2 ;;
    --gridconf)
      GRIDCONF="$2"; shift 2 ;;
    --hpc-fasta-gr)
      HPC_FASTA_GR="$2"; shift 2 ;;
    --seqs-per-bin)
      SEQS_PER_BIN="$2"; shift 2 ;;
    --evalue)
      EVALUE="$2"; shift 2 ;;
    --max-targets)
      MAX_TARGETS="$2"; shift 2 ;;
    --sensitivity)
      SENS="$2"; shift 2 ;;
    --pcts)
      read -r -a PCTS <<< "$2"
      AUTO_DETECT=0
      shift 2 ;;
    --no-auto)
      AUTO_DETECT=0; shift ;;
    --force)
      FORCE=1; shift ;;
    --help|-h)
      show_help; exit 0 ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      echo "Use --help for usage." >&2
      exit 1 ;;
  esac
done

# ===== Checks =====
[[ -x "$HPC_FASTA_GR" ]] || { echo "ERROR: executable not found: $HPC_FASTA_GR" >&2; exit 1; }
[[ -f "$GRIDCONF" ]]     || { echo "ERROR: config file not found: $GRIDCONF" >&2; exit 1; }
command -v diamond >/dev/null 2>&1 || { echo "ERROR: diamond not found in PATH" >&2; exit 1; }

if [[ ! "$SEQS_PER_BIN" =~ ^[0-9]+$ || "$SEQS_PER_BIN" -le 0 ]]; then
  echo "ERROR: --seqs-per-bin must be a positive integer." >&2
  exit 1
fi

# ===== Auto-detect percentage folders =====
if [[ "$AUTO_DETECT" -eq 1 ]]; then
  mapfile -t PCTS < <(
    find . -maxdepth 1 -type d -regex './[0-9]+' \
      | sed 's|./||' \
      | sort -n
  )
fi

if [[ "${#PCTS[@]}" -eq 0 ]]; then
  echo "ERROR: no percentage folders found or provided." >&2
  exit 1
fi

echo "=============================="
echo "DIAMOND saturation pipeline"
echo "=============================="
echo "Database      : $DIAMOND_DB"
echo "Grid conf     : $GRIDCONF"
echo "Seqs per bin  : $SEQS_PER_BIN"
echo "E-value       : $EVALUE"
echo "Max targets   : $MAX_TARGETS"
echo "Sensitivity   : $SENS"
echo "Force         : $FORCE"
echo "Percentages   : ${PCTS[*]}"
echo

for pct in "${PCTS[@]}"; do
  dir="${pct}"
  trinity_fa="reads_${pct}pct.trinity_out.Trinity.fasta"
  out_file="blast_${pct}pct_swissprot.outfmt6"

  echo
  echo "=============================="
  echo ">> DIAMOND ${pct}% (folder: ${dir})"
  echo "=============================="

  [[ -d "$dir" ]] || { echo "WARNING: folder '$dir' does not exist, skipping"; continue; }

  pushd "$dir" >/dev/null

  if [[ ! -f "$trinity_fa" ]]; then
    echo "WARNING: file not found: $dir/$trinity_fa, skipping"
    popd >/dev/null
    continue
  fi

  if [[ -e "$out_file" && "$FORCE" -eq 0 ]]; then
    echo "WARNING: output '$dir/$out_file' already exists. Use --force to overwrite. Skipping."
    popd >/dev/null
    continue
  fi

  if [[ -e "$out_file" && "$FORCE" -eq 1 ]]; then
    echo ">> FORCE enabled: removing previous outputs"
    rm -rf "$out_file" "${out_file}.txt" farmit* *.cmds *.cache_success 2>/dev/null || true
  fi

  cmd_template="$(cat <<'EOF'
diamond blastx -d __DIAMOND_DB__ -q __QUERY_FILE__ --evalue __EVALUE__ --max-target-seqs __MAX_TARGETS__ --outfmt 6 --threads $(getconf _NPROCESSORS_ONLN) __SENS__
EOF
)"

  cmd_template="${cmd_template/__DIAMOND_DB__/${DIAMOND_DB}}"
  cmd_template="${cmd_template/__EVALUE__/${EVALUE}}"
  cmd_template="${cmd_template/__MAX_TARGETS__/${MAX_TARGETS}}"
  cmd_template="${cmd_template/__SENS__/${SENS}}"

  "$HPC_FASTA_GR" \
    --cmd_template "$cmd_template" \
    --query_fasta "$trinity_fa" \
    --grid_conf "$GRIDCONF" \
    --parafly \
    -N "$SEQS_PER_BIN" \
    -O "$out_file"

  echo ">> Merging .OUT fragments inside: $out_file"

  outs=()
  mapfile -t outs < <(
    find "$PWD/$out_file" -type f -name "*.OUT" -size +0c | sort -V
  )

  if [[ "${#outs[@]}" -gt 0 ]]; then
    cat "${outs[@]}" > "${out_file}.txt"
    echo ">> OK: ${out_file}.txt (${#outs[@]} files)"
  else
    echo "!! WARNING: no non-empty *.OUT files found in $PWD/$out_file"
  fi

  # Optional quick audit of ERR files
  err_count=$(find "$PWD/$out_file" -type f -name "*.ERR" -size +0c | wc -l)
  if [[ "$err_count" -gt 0 ]]; then
    echo "!! WARNING: $err_count non-empty .ERR files found in $out_file"
  fi

  popd >/dev/null
done

echo
echo "SUCCESS: DIAMOND blastx completed for selected percentages."
