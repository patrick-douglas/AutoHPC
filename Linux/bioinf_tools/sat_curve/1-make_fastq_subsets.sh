#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat << 'EOF'
Usage:
  Single-end:
    make_fastq_subsets.sh --fastq FILE --pct_int N [options]

  Paired-end:
    make_fastq_subsets.sh --fastq1 FILE_R1 --fastq2 FILE_R2 --pct_int N [options]

Description:
  Generates FASTQ subsets at different percentages using seqtk.
  A directory is created for each percentage, containing the corresponding subset.

Modes:
  Single-end:
    --fastq FILE

  Paired-end:
    --fastq1 FILE_R1
    --fastq2 FILE_R2

Required arguments:
  --pct_int N        Percentage interval between subsets
                     Examples:
                       10  -> 10,20,30,...,100
                       20  -> 20,40,60,80,100

Optional arguments:
  --seed N           Random seed for reproducibility [default: 100]
  --outdir DIR       Output base directory [default: current directory]
  --help             Show this help message and exit

Examples:
  Single-end:
    ./make_fastq_subsets.sh --fastq all_reads.fq --pct_int 10
    ./make_fastq_subsets.sh --fastq all_reads.fq.gz --pct_int 20 --outdir sat_curve

  Paired-end:
    ./make_fastq_subsets.sh --fastq1 reads_R1.fq --fastq2 reads_R2.fq --pct_int 10
    ./make_fastq_subsets.sh --fastq1 reads_R1.fq.gz --fastq2 reads_R2.fq.gz --pct_int 20 --seed 42

Expected output:
  Single-end:
    10/reads_10pct.fq
    20/reads_20pct.fq
    ...
    100/reads_100pct.fq

  Paired-end:
    10/reads_10pct_R1.fq
    10/reads_10pct_R2.fq
    ...
    100/reads_100pct_R1.fq
    100/reads_100pct_R2.fq

Requirements:
  - seqtk installed and available in PATH

Notes:
  For paired-end data, the same seed is used for R1 and R2 to preserve pairing.
EOF
}

FASTQ=""
FASTQ1=""
FASTQ2=""
PCT_INT=""
SEED="100"
OUTDIR="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fastq)
      FASTQ="${2:-}"
      shift 2
      ;;
    --fastq1)
      FASTQ1="${2:-}"
      shift 2
      ;;
    --fastq2)
      FASTQ2="${2:-}"
      shift 2
      ;;
    --pct_int)
      PCT_INT="${2:-}"
      shift 2
      ;;
    --seed)
      SEED="${2:-}"
      shift 2
      ;;
    --outdir)
      OUTDIR="${2:-}"
      shift 2
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo "Use --help to see the available options." >&2
      exit 1
      ;;
  esac
done

MODE=""

if [[ -n "$FASTQ" ]]; then
  if [[ -n "$FASTQ1" || -n "$FASTQ2" ]]; then
    echo "ERROR: use either --fastq (single-end) or --fastq1/--fastq2 (paired-end), not both." >&2
    exit 1
  fi
  MODE="single"
else
  if [[ -n "$FASTQ1" || -n "$FASTQ2" ]]; then
    if [[ -z "$FASTQ1" || -z "$FASTQ2" ]]; then
      echo "ERROR: for paired-end mode, both --fastq1 and --fastq2 must be provided." >&2
      exit 1
    fi
    MODE="paired"
  fi
fi

if [[ -z "$MODE" ]]; then
  echo "ERROR: provide --fastq for single-end mode or --fastq1/--fastq2 for paired-end mode." >&2
  echo "Use --help to see the usage information." >&2
  exit 1
fi

if [[ -z "$PCT_INT" ]]; then
  echo "ERROR: --pct_int is required." >&2
  exit 1
fi

if ! command -v seqtk >/dev/null 2>&1; then
  echo "ERROR: seqtk was not found in PATH." >&2
  exit 1
fi

if [[ ! "$PCT_INT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --pct_int must be a positive integer." >&2
  exit 1
fi

if [[ "$PCT_INT" -le 0 || "$PCT_INT" -gt 100 ]]; then
  echo "ERROR: --pct_int must be between 1 and 100." >&2
  exit 1
fi

if [[ ! "$SEED" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --seed must be a positive integer." >&2
  exit 1
fi

if [[ "$MODE" == "single" ]]; then
  [[ -f "$FASTQ" ]] || { echo "ERROR: input file not found: $FASTQ" >&2; exit 1; }
else
  [[ -f "$FASTQ1" ]] || { echo "ERROR: input file not found: $FASTQ1" >&2; exit 1; }
  [[ -f "$FASTQ2" ]] || { echo "ERROR: input file not found: $FASTQ2" >&2; exit 1; }
fi

mkdir -p "$OUTDIR"

get_ext() {
  local f="$1"
  if [[ "$f" =~ \.gz$ ]]; then
    echo "fq.gz"
  else
    echo "fq"
  fi
}

run_seqtk_single() {
  local in="$1"
  local frac="$2"
  local out="$3"

  if [[ "$in" =~ \.gz$ ]]; then
    seqtk sample -s"$SEED" <(gzip -dc "$in") "$frac" | gzip -c > "$out"
  else
    seqtk sample -s"$SEED" "$in" "$frac" > "$out"
  fi
}

echo "Mode            : $MODE"
echo "Percentage step : $PCT_INT"
echo "Seed            : $SEED"
echo "Output dir      : $OUTDIR"

if [[ "$MODE" == "single" ]]; then
  echo "Input FASTQ     : $FASTQ"
else
  echo "Input FASTQ R1  : $FASTQ1"
  echo "Input FASTQ R2  : $FASTQ2"
fi
echo

for (( pct=PCT_INT; pct<=100; pct+=PCT_INT )); do
  pct_dir="${OUTDIR}/${pct}"
  mkdir -p "$pct_dir"

  frac=$(awk -v p="$pct" 'BEGIN { printf "%.10f", p/100 }')

  if [[ "$MODE" == "single" ]]; then
    ext=$(get_ext "$FASTQ")
    out_fastq="${pct_dir}/reads_${pct}pct.${ext}"

    echo ">> Generating ${pct}% subset: $out_fastq"

    if [[ "$pct" -eq 100 ]]; then
      cp -f "$FASTQ" "$out_fastq"
    else
      run_seqtk_single "$FASTQ" "$frac" "$out_fastq"
    fi

  else
    ext1=$(get_ext "$FASTQ1")
    ext2=$(get_ext "$FASTQ2")

    out_r1="${pct_dir}/reads_${pct}pct_R1.${ext1}"
    out_r2="${pct_dir}/reads_${pct}pct_R2.${ext2}"

    echo ">> Generating ${pct}% subset:"
    echo "   R1: $out_r1"
    echo "   R2: $out_r2"

    if [[ "$pct" -eq 100 ]]; then
      cp -f "$FASTQ1" "$out_r1"
      cp -f "$FASTQ2" "$out_r2"
    else
      run_seqtk_single "$FASTQ1" "$frac" "$out_r1"
      run_seqtk_single "$FASTQ2" "$frac" "$out_r2"
    fi
  fi
done

echo
echo "SUCCESS: all FASTQ subsets were generated successfully."
