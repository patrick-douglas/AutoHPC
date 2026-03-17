#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(ggplot2)
  library(parallel)
})

# =========================================================
# Options
# =========================================================
option_list <- list(
  make_option("--fasta", type = "character", help = "Path to Trinity fasta"),
  make_option("--samples", type = "character", help = "Path to samples.txt"),
  make_option("--threads", type = "integer", default = parallel::detectCores(),
              help = "Number of threads [default: all available]"),
  make_option("--trinity_home", type = "character", default = Sys.getenv("TRINITY_HOME"),
              help = "Path to TRINITY_HOME [default: Sys.getenv('TRINITY_HOME')]"),
  make_option("--seqType", type = "character", default = "fq",
              help = "Sequence type: fq or fa [default: %default]"),
  make_option("--out_prefix", type = "character", default = NULL,
              help = "Prefix for output files [default: fasta basename]")
)

opt <- parse_args(OptionParser(option_list = option_list))

# =========================================================
# Checks
# =========================================================
if (is.null(opt$fasta)) stop("Please provide --fasta", call. = FALSE)
if (is.null(opt$samples)) stop("Please provide --samples", call. = FALSE)

if (!file.exists(opt$fasta)) stop(paste("FASTA not found:", opt$fasta), call. = FALSE)
if (!file.exists(opt$samples)) stop(paste("samples.txt not found:", opt$samples), call. = FALSE)

if (is.null(opt$trinity_home) || opt$trinity_home == "") {
  stop("TRINITY_HOME is not set. Provide --trinity_home or export TRINITY_HOME first.", call. = FALSE)
}

if (!opt$seqType %in% c("fq", "fa")) {
  stop("--seqType must be either 'fq' or 'fa'", call. = FALSE)
}

# Resolve absolute paths BEFORE any setwd()
fasta_abs   <- normalizePath(opt$fasta, winslash = "/", mustWork = TRUE)
samples_abs <- normalizePath(opt$samples, winslash = "/", mustWork = TRUE)
trinity_home_abs <- normalizePath(opt$trinity_home, winslash = "/", mustWork = TRUE)

align_script  <- file.path(trinity_home_abs, "util", "align_and_estimate_abundance.pl")
matrix_script <- file.path(trinity_home_abs, "util", "abundance_estimates_to_matrix.pl")
exn50_script  <- file.path(trinity_home_abs, "util", "misc", "contig_ExN50_statistic.pl")

for (f in c(align_script, matrix_script, exn50_script)) {
  if (!file.exists(f)) stop(paste("Required Trinity script not found:", f), call. = FALSE)
}

# =========================================================
# Output names
# =========================================================
fasta_base <- basename(fasta_abs)
fasta_base <- sub("\\.(fa|fasta|fna)$", "", fasta_base, ignore.case = TRUE)
out_prefix <- if (is.null(opt$out_prefix)) fasta_base else opt$out_prefix

exp_samples_dir  <- file.path(getwd(), "exp_samples")
exp_matrix_dir   <- file.path(getwd(), "exp_matrix")

quant_files_txt  <- file.path(exp_samples_dir, "quant_files.txt")
checklist_file   <- paste0(out_prefix, "_quant_checklist.tsv")
matrix_expected_candidates <- c(
  file.path(exp_matrix_dir, "transcripts.isoform.TMM.EXPR.matrix"),
  file.path(exp_matrix_dir, "transcripts.TMM.EXPR.matrix")
)
exn50_stats_file <- paste0(out_prefix, "_ExN50.transcript.stats")
exn50_plot_file  <- paste0(out_prefix, "_ExN50_plot.pdf")
exp_matrix_dir <- file.path(getwd(), "exp_matrix")

# =========================================================
# Helpers
# =========================================================
msg <- function(...) cat(..., "\n")

safe_system <- function(cmd, args, stdout = "", stderr = "") {
  msg("Running:", paste(c(shQuote(cmd), shQuote(args)), collapse = " "))
  ret <- system2(command = cmd, args = args, stdout = stdout, stderr = stderr)
  if (!identical(ret, 0L)) {
    stop(paste("Command failed with exit status", ret, ":", cmd), call. = FALSE)
  }
}

infer_sample_id_from_quant <- function(path) {
  parent <- basename(dirname(path))
  grandparent <- basename(dirname(dirname(path)))
  c(parent, grandparent)
}

check_existing_quants <- function(exp_samples_dir, sample_ids) {
  quant_files <- list.files(
    path = exp_samples_dir,
    pattern = "^quant\\.sf$",
    recursive = TRUE,
    full.names = TRUE
  )

  if (length(quant_files) == 0) {
    return(list(
      exists = FALSE,
      complete = FALSE,
      quant_files = character(0),
      sample_check_df = NULL,
      quant_check_df = NULL
    ))
  }

  quant_files <- normalizePath(quant_files, winslash = "/", mustWork = FALSE)
  quant_files <- sort(unique(quant_files))

  quant_candidates <- lapply(quant_files, infer_sample_id_from_quant)

  matched_sample <- vapply(seq_along(quant_candidates), function(i) {
    candidates <- quant_candidates[[i]]
    hit <- intersect(candidates, sample_ids)
    if (length(hit) > 0) hit[1] else NA_character_
  }, character(1))

  quant_check_df <- data.frame(
    quant_file = quant_files,
    parent_dir = vapply(quant_files, function(x) basename(dirname(x)), character(1)),
    grandparent_dir = vapply(quant_files, function(x) basename(dirname(dirname(x))), character(1)),
    matched_sample = matched_sample,
    matched = !is.na(matched_sample),
    stringsAsFactors = FALSE
  )

  sample_check_df <- data.frame(
    sample_id = sample_ids,
    quantified = sample_ids %in% na.omit(matched_sample),
    stringsAsFactors = FALSE
  )

  sample_match_counts <- table(na.omit(matched_sample))
  sample_check_df$quant_file_count <- as.integer(sample_match_counts[sample_check_df$sample_id])
  sample_check_df$quant_file_count[is.na(sample_check_df$quant_file_count)] <- 0L

  complete <- all(sample_check_df$quantified)

  list(
    exists = TRUE,
    complete = complete,
    quant_files = quant_files,
    sample_check_df = sample_check_df,
    quant_check_df = quant_check_df
  )
}

# =========================================================
# Prepare directories
# =========================================================
if (!dir.exists(exp_samples_dir)) {
  dir.create(exp_samples_dir, recursive = TRUE)
}

# =========================================================
# Read samples.txt
# Assumes sample ID is in column 2
# =========================================================
msg("Reading samples file:", samples_abs)

samples_df <- tryCatch(
  read.delim(samples_abs, header = FALSE, sep = "\t", stringsAsFactors = FALSE, quote = ""),
  error = function(e) {
    stop("Could not read samples file as tab-delimited text.", call. = FALSE)
  }
)

if (ncol(samples_df) < 3) {
  stop("samples.txt seems malformed. Expected at least 3 columns.", call. = FALSE)
}

sample_ids <- trimws(samples_df[[2]])
sample_ids <- sample_ids[nzchar(sample_ids)]

if (length(sample_ids) == 0) {
  stop("No sample IDs found in column 2 of samples.txt", call. = FALSE)
}

msg("Found", length(sample_ids), "sample IDs in samples.txt")

# =========================================================
# Step 1 - Quantification
# =========================================================
msg("Step 1/4: Checking existing quantifications in", exp_samples_dir)

existing <- check_existing_quants(exp_samples_dir, sample_ids)

if (existing$exists && existing$complete) {
  msg("Existing quant.sf files already cover all samples in samples.txt")
  msg("Skipping abundance estimation step")
} else {
  msg("Step 1/4: Running align_and_estimate_abundance.pl")

  original_wd <- getwd()
  setwd(exp_samples_dir)
  on.exit(setwd(original_wd), add = TRUE)

  align_args <- c(
    "--transcripts", fasta_abs,
    "--samples_file", samples_abs,
    "--seqType", opt$seqType,
    "--est_method", "salmon",
    "--thread_count", as.character(opt$threads),
    "--trinity_mode",
    "--prep_reference"
  )

  safe_system(align_script, align_args)

  setwd(original_wd)
}

# =========================================================
# Step 2 - Find quant.sf and build checklist
# =========================================================
msg("Step 2/4: Finding quant.sf files inside", exp_samples_dir)

existing <- check_existing_quants(exp_samples_dir, sample_ids)

quant_files <- existing$quant_files
sample_check_df <- existing$sample_check_df
quant_check_df <- existing$quant_check_df

if (length(quant_files) == 0) {
  stop("No quant.sf files were found inside exp_samples.", call. = FALSE)
}

writeLines(quant_files, quant_files_txt)
msg("Saved quant.sf file list to:", quant_files_txt)
msg("Found", length(quant_files), "quant.sf files")

write.table(
  sample_check_df,
  file = checklist_file,
  sep = "\t",
  quote = FALSE,
  row.names = FALSE
)
msg("Saved sample quantification checklist to:", checklist_file)

n_expected <- length(sample_ids)
n_matched  <- sum(sample_check_df$quantified)
n_missing  <- sum(!sample_check_df$quantified)

msg("Checklist summary:")
msg("  Samples in samples.txt:", n_expected)
msg("  Samples with matching quant.sf:", n_matched)
msg("  Samples missing quant.sf:", n_missing)

if (n_missing > 0) {
  missing_samples <- sample_check_df$sample_id[!sample_check_df$quantified]
  msg("Missing samples:")
  for (s in missing_samples) msg("  -", s)
  stop("Not all samples listed in samples.txt were matched to quant.sf files. Aborting before matrix generation.", call. = FALSE)
}

unmatched_quant <- quant_check_df$quant_file[!quant_check_df$matched]
if (length(unmatched_quant) > 0) {
  msg("Warning: some quant.sf files did not match any sample ID in samples.txt:")
  for (q in unmatched_quant) msg("  -", q)
}
if (!dir.exists(exp_matrix_dir)) {
  dir.create(exp_matrix_dir, recursive = TRUE)
}
# =========================================================
# Step 3 - Create abundance matrix
# =========================================================
msg("Step 3/4: Running abundance_estimates_to_matrix.pl")

if (!dir.exists(exp_matrix_dir)) {
  dir.create(exp_matrix_dir, recursive = TRUE)
}

original_wd <- getwd()
setwd(exp_matrix_dir)

safe_quant_file <- normalizePath(quant_files_txt, winslash = "/", mustWork = TRUE)

matrix_args <- c(
  "--est_method", "salmon",
  "--gene_trans_map", "none",
  "--out_prefix", "transcripts",
  "--name_sample_by_basedir",
#  "--basedir_index", "-1",
  "--quant_files", safe_quant_file
)

safe_system(matrix_script, matrix_args)

setwd(original_wd)

matrix_expected <- matrix_expected_candidates[file.exists(matrix_expected_candidates)][1]

if (is.na(matrix_expected)) {
  stop("No matrix file generated inside exp_matrix/", call. = FALSE)
}

msg("Matrix generated:", matrix_expected)
# =========================================================
# Step 4 - ExN50
# =========================================================
msg("Step 4/4: Running contig_ExN50_statistic.pl")

exn50_args <- c(
  matrix_expected,
  fasta_abs,
  "transcript"
)

exn50_lines <- system2(exn50_script, args = exn50_args, stdout = TRUE, stderr = TRUE)

if (length(exn50_lines) == 0) {
  stop("ExN50 script returned no output.", call. = FALSE)
}

writeLines(exn50_lines, exn50_stats_file)
msg("Saved ExN50 stats to:", exn50_stats_file)

# =========================================================
# Parse ExN50 output
# =========================================================
exn50_lines <- exn50_lines[nzchar(trimws(exn50_lines))]
exn50_lines <- exn50_lines[!grepl("^\\s*#", exn50_lines)]

df <- tryCatch(
  read.table(text = exn50_lines, header = FALSE, stringsAsFactors = FALSE),
  error = function(e) NULL
)

if (is.null(df) || ncol(df) < 2) {
  stop("Could not parse ExN50 output into two columns.", call. = FALSE)
}

df <- df[, 1:2]
colnames(df) <- c("Ex", "N50")

df$Ex  <- suppressWarnings(as.numeric(df$Ex))
df$N50 <- suppressWarnings(as.numeric(df$N50))
df <- df[!is.na(df$Ex) & !is.na(df$N50), ]

if (nrow(df) == 0) {
  stop("Parsed ExN50 table is empty after numeric conversion.", call. = FALSE)
}

# =========================================================
# Plot
# =========================================================
p <- ggplot(df, aes(x = Ex, y = N50)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  labs(
    title = "ExN50 profile",
    subtitle = out_prefix,
    x = "Expression percentile (Ex)",
    y = "N50"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid.major.x = element_blank()
  )

ggsave(exn50_plot_file, p, width = 9, height = 5.5, device = cairo_pdf)
msg("Saved plot to:", exn50_plot_file)

msg("Done.")
