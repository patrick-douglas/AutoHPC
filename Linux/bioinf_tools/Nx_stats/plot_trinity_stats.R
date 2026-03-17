#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(ggplot2)
})

# =====================================
# Command-line options
# =====================================
option_list <- list(
  make_option("--fasta", type = "character", help = "Trinity FASTA file"),
  make_option("--trinity_home", type = "character", default = Sys.getenv("TRINITY_HOME"),
              help = "Path to TRINITY_HOME [default: Sys.getenv('TRINITY_HOME')]"),
  make_option("--out_prefix", type = "character", default = NULL,
              help = "Output prefix [default: FASTA basename]"),
  make_option("--keep_stats", action = "store_true", default = TRUE,
              help = "Keep intermediate Trinity stats file [default: TRUE]")
)

opt <- parse_args(OptionParser(option_list = option_list))

# =====================================
# Basic checks
# =====================================
if (is.null(opt$fasta)) {
  stop("Please provide --fasta", call. = FALSE)
}

if (!file.exists(opt$fasta)) {
  stop(paste("FASTA file not found:", opt$fasta), call. = FALSE)
}

if (is.null(opt$trinity_home) || opt$trinity_home == "") {
  stop("TRINITY_HOME is not set. Provide --trinity_home or export TRINITY_HOME first.", call. = FALSE)
}

trinity_stats_script <- file.path(opt$trinity_home, "util", "TrinityStats.pl")

if (!file.exists(trinity_stats_script)) {
  stop(paste("Could not find TrinityStats.pl at:", trinity_stats_script), call. = FALSE)
}

# =====================================
# Output names
# =====================================
fasta_base <- basename(opt$fasta)
fasta_base <- sub("\\.(fa|fasta|fna)$", "", fasta_base, ignore.case = TRUE)

out_prefix <- if (is.null(opt$out_prefix)) fasta_base else opt$out_prefix

stats_file <- paste0(out_prefix, "_TrinityStats.txt")
plot_file  <- paste0(out_prefix, "_TrinityStats_plot.pdf")
tsv_file   <- paste0(out_prefix, "_TrinityStats_metrics.tsv")

# =====================================
# Run TrinityStats.pl
# =====================================
cat("Running TrinityStats.pl on:", opt$fasta, "\n")
stats_output <- system2(
  command = trinity_stats_script,
  args = shQuote(opt$fasta),
  stdout = TRUE,
  stderr = TRUE
)

if (length(stats_output) == 0) {
  stop("TrinityStats.pl returned no output.", call. = FALSE)
}

writeLines(stats_output, con = stats_file)
cat("Stats written to:", stats_file, "\n")

# =====================================
# Read stats
# =====================================
lines <- stats_output

extract_first_match <- function(pattern, lines) {
  hit <- grep(pattern, lines, value = TRUE)
  if (length(hit) == 0) return(NA_character_)
  hit[1]
}

extract_num_after_colon <- function(pattern, lines) {
  x <- extract_first_match(pattern, lines)
  if (is.na(x)) return(NA_real_)
  val <- sub(".*:\\s*", "", x)
  val <- gsub(",", "", val)
  as.numeric(val)
}

extract_num_after_tab <- function(pattern, lines) {
  x <- extract_first_match(pattern, lines)
  if (is.na(x)) return(NA_real_)
  val <- sub(".*\\t", "", x)
  val <- gsub(",", "", val)
  as.numeric(val)
}

# =====================================
# Global metrics
# =====================================
total_genes <- extract_num_after_tab("^Total trinity 'genes':", lines)
total_transcripts <- extract_num_after_tab("^Total trinity transcripts:", lines)
gc_percent <- as.numeric(sub("Percent GC:\\s*", "", grep("Percent GC:", lines, value = TRUE)))

# =====================================
# Locate sections
# =====================================
all_start <- grep("Stats based on ALL transcript contigs:", lines)
longest_start <- grep("Stats based on ONLY LONGEST ISOFORM per 'GENE':", lines)

if (length(all_start) == 0 || length(longest_start) == 0) {
  stop("Could not identify expected Trinity stats sections.", call. = FALSE)
}

all_block <- lines[all_start[1]:longest_start[1]]
longest_block <- lines[longest_start[1]:length(lines)]

# =====================================
# Parse metrics
# =====================================
get_section_metrics <- function(block, section_name) {
  data.frame(
    Section = section_name,
    Metric = c("N10", "N20", "N30", "N40", "N50", "Median length", "Average length"),
    Value = c(
      extract_num_after_colon("Contig N10:", block),
      extract_num_after_colon("Contig N20:", block),
      extract_num_after_colon("Contig N30:", block),
      extract_num_after_colon("Contig N40:", block),
      extract_num_after_colon("Contig N50:", block),
      extract_num_after_colon("Median contig length:", block),
      extract_num_after_colon("Average contig:", block)
    )
  )
}

df_all <- get_section_metrics(all_block, "All transcripts")
df_longest <- get_section_metrics(longest_block, "Longest isoform per gene")
plot_df <- rbind(df_all, df_longest)

plot_df$Metric <- factor(
  plot_df$Metric,
  levels = c("N10", "N20", "N30", "N40", "N50", "Median length", "Average length")
)

assembled_all <- extract_num_after_colon("Total assembled bases:", all_block)
assembled_longest <- extract_num_after_colon("Total assembled bases:", longest_block)

# =====================================
# Save parsed table
# =====================================
write.table(plot_df, file = tsv_file, sep = "\t", quote = FALSE, row.names = FALSE)
cat("Parsed metrics written to:", tsv_file, "\n")

# =====================================
# Build plot subtitle
# =====================================
subtitle_text <- paste0(
  "Genes: ", format(total_genes, big.mark = ","), 
  " | Transcripts: ", format(total_transcripts, big.mark = ","), 
  " | GC: ", gc_percent, "%\n",
  "Total assembled bases (all): ", format(assembled_all, big.mark = ","), 
  " | Longest isoform only: ", format(assembled_longest, big.mark = ",")
)

# =====================================
# Plot
# =====================================
p <- ggplot(plot_df, aes(x = Metric, y = Value, fill = Section)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.68) +
  geom_text(
    aes(label = round(Value, 1)),
    position = position_dodge(width = 0.75),
    vjust = -0.25,
    size = 3.5
  ) +
  scale_fill_manual(values = c("#4C78A8", "#F58518")) +
  labs(
    title = "Trinity assembly summary statistics",
    subtitle = subtitle_text,
    x = NULL,
    y = "Length / statistic value"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold"),
    plot.subtitle = element_text(size = 10),
    axis.text.x = element_text(angle = 30, hjust = 1),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    legend.title = element_blank(),
    legend.position = "top"
  ) +
  expand_limits(y = max(plot_df$Value, na.rm = TRUE) * 1.12)
theme(
  legend.margin = margin(0, 0, -10, 0)
)
ggsave(plot_file, p, width = 11, height = 6.5, device = cairo_pdf)
cat("Plot saved to:", plot_file, "\n")

# =====================================
# Optional cleanup
# =====================================
if (!opt$keep_stats && file.exists(stats_file)) {
  file.remove(stats_file)
  cat("Intermediate stats file removed:", stats_file, "\n")
}

cat("Done.\n")
