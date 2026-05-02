#!/bin/bash

# =======================
# USER-DEFINED PARAMETERS
# =======================
trimmomatic_bin=/home/me/Trimmomatic-0.39/trimmomatic-0.39.jar
PHRED="-phred33"
MINLEN=26 #Drop the read if it is below a specified length.
CROP=250 #Cut the read to a specified length.
LEADING=5 #Cut bases off the start of a read, if below a threshold quality
TRAILING=5 #Cut bases off the end of a read, if below a threshold quality.
HEADCROP=15 #Cut the specified number of bases from the start of the read.
AVGQUAL=5 #Specifies the minimum Phred quality score of a read to be kept.
SLIDINGWINDOW=4:5 #Scan the read with a 4-base wide sliding window, cutting when the average quality per base drops below 5 (SLIDINGWINDOW:4:5)
THREADS=$(nproc)

# =======================
# ARGUMENT PARSING
# =======================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fastq)
      FASTQ="$2"
      shift 2
      ;;
    --output_dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# =======================
# VALIDATION
# =======================
if [[ -z "$FASTQ" ]]; then
  echo "Error: please provide --fastq <file.fastq>"
  exit 1
fi

if [[ ! -f "$FASTQ" ]]; then
  echo "Error: FASTQ file not found"
  exit 1
fi

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR=$(dirname "$FASTQ")
fi

mkdir -p "$OUTPUT_DIR"

# =======================
# FILE NAMES
# =======================
filename=$(basename "$FASTQ")
base="${filename%%.*}"
temp_fastq="$OUTPUT_DIR/${base}.temp.fastq"
out_fastq="$OUTPUT_DIR/${base}.trimmed.fastq"
log_file="$OUTPUT_DIR/${base}.trimmomatic.log"

# =======================
# LOG HEADER
# =======================
{
  echo "=============================================="
  echo "Trimmomatic run log"
  echo "Sample: $base"
  echo "Date: $(date)"
  echo "Input FASTQ: $FASTQ"
  echo "Output FASTQ: $out_fastq"
  echo "Parameters:"
  echo "  PHRED=$PHRED"
  echo "  MINLEN=$MINLEN"
  echo "  CROP=$CROP"
  echo "  LEADING=$LEADING"
  echo "  TRAILING=$TRAILING"
  echo "  HEADCROP=$HEADCROP"
  echo "  THREADS=$THREADS"
  echo "  AVGQUAL=$AVGQUAL"
  echo "  SLIDINGWINDOW=$SLIDINGWINDOW "
  echo "=============================================="
} > "$log_file"

# =======================
# RUN TRIMMOMATIC
# =======================
echo "Processing: $FASTQ"
echo "Logging to: $log_file"
#Stage 1 cleaning
java -jar "$trimmomatic_bin" SE "$PHRED" "$FASTQ" "$temp_fastq" \
 CROP:$CROP \
 LEADING:$LEADING \
 TRAILING:$TRAILING \
 HEADCROP:$HEADCROP \
 AVGQUAL:$AVGQUAL \
 SLIDINGWINDOW:$SLIDINGWINDOW -threads "$THREADS" \
 >> "$log_file" 2>&1

#Stage 2 Removing seqs smaller than 25bp
java -jar "$trimmomatic_bin" SE "$PHRED" "$temp_fastq" "$out_fastq" MINLEN:$MINLEN -threads "$THREADS" 
rm "$temp_fastq"

# =======================
# SUMMARY
# =======================
echo "" >> "$log_file"
cat $log_file

echo "FastQC completed" >> "$log_file"
echo "✔ Finished processing $base"
