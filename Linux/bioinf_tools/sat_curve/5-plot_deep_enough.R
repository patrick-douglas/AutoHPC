#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(optparse)
  library(scales)
})

option_list <- list(
  make_option(
    c("--csv"),
    type = "character",
    help = "CSV with saturation summary metrics",
    metavar = "file"
  ),
  make_option(
    c("--prefix"),
    type = "character",
    default = "deep_enough_swissprot",
    help = "Output file prefix [default: %default]",
    metavar = "string"
  )
)

opt <- parse_args(OptionParser(option_list = option_list))

if (is.null(opt$csv)) {
  stop("ERROR: use --csv <deep_enough.csv>", call. = FALSE)
}

df <- read_csv(opt$csv, show_col_types = FALSE) %>%
  arrange(pct)

required_cols <- c(
  "pct", "ge80", "ge90", "ge100", "total",
  "blast_total_hits",
  "unique_transcripts",
  "unique_swissprot_hits",
  "highconf_unique_swissprot"
)

if (!all(required_cols %in% colnames(df))) {
  missing_cols <- setdiff(required_cols, colnames(df))
  stop(
    paste0(
      "ERROR: CSV is missing required columns: ",
      paste(missing_cols, collapse = ", ")
    ),
    call. = FALSE
  )
}

# -----------------------------
# Plot 1: >=80% full-length
# -----------------------------
p1 <- ggplot(df, aes(x = pct, y = ge80)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.5) +
  scale_x_continuous(breaks = df$pct) +
  scale_y_continuous(labels = label_number(big.mark = ",")) +
  labs(
    title = "Sequencing depth saturation analysis",
    subtitle = "Metric: transcripts with top Swiss-Prot hit coverage >=80%",
    x = "Fraction of reads used in assembly (%)",
    y = "Number of transcripts (>=80% coverage)"
  ) +
  theme_classic(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    axis.title = element_text(face = "bold")
  )

# -----------------------------
# Plot 2: full-length multi
# -----------------------------
df_full_long <- df %>%
  select(pct, ge80, ge90, ge100) %>%
  pivot_longer(
    cols = c(ge80, ge90, ge100),
    names_to = "metric",
    values_to = "count"
  ) %>%
  mutate(metric = recode(
    metric,
    ge80 = ">=80%",
    ge90 = ">=90%",
    ge100 = "100%"
  ))

p2 <- ggplot(df_full_long, aes(x = pct, y = count, group = metric, linetype = metric)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.3) +
  scale_x_continuous(breaks = sort(unique(df_full_long$pct))) +
  scale_y_continuous(labels = label_number(big.mark = ",")) +
  labs(
    title = "Full-length transcript recovery across read depth",
    x = "Fraction of reads used in assembly (%)",
    y = "Number of transcripts",
    linetype = NULL
  ) +
  theme_classic(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    axis.title = element_text(face = "bold"),
    legend.position = "right"
  )

# -----------------------------
# Plot 3: unique Swiss-Prot hits
# -----------------------------
p3 <- ggplot(df, aes(x = pct, y = unique_swissprot_hits)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.5) +
  scale_x_continuous(breaks = df$pct) +
  scale_y_continuous(labels = label_number(big.mark = ",")) +
  labs(
    title = "Functional saturation based on Swiss-Prot",
    subtitle = "Metric: unique Swiss-Prot proteins detected",
    x = "Fraction of reads used in assembly (%)",
    y = "Unique Swiss-Prot hits"
  ) +
  theme_classic(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    axis.title = element_text(face = "bold")
  )

# -----------------------------
# Plot 4: relative functional saturation
# -----------------------------
df <- df %>%
  mutate(relative_unique_swissprot = unique_swissprot_hits / max(unique_swissprot_hits, na.rm = TRUE))

p4 <- ggplot(df, aes(x = pct, y = relative_unique_swissprot)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.5) +
  scale_x_continuous(breaks = df$pct) +
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(0, 1)) +
  labs(
    title = "Relative functional saturation",
    subtitle = "Unique Swiss-Prot hits normalized to the maximum observed value",
    x = "Fraction of reads used in assembly (%)",
    y = "Fraction of maximum unique Swiss-Prot hits"
  ) +
  theme_classic(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    axis.title = element_text(face = "bold")
  )

ggsave(paste0(opt$prefix, "_ge80.pdf"), p1, width = 7.2, height = 4.2)
ggsave(paste0(opt$prefix, "_full_length_multi.pdf"), p2, width = 7.2, height = 4.2)
ggsave(paste0(opt$prefix, "_unique_swissprot.pdf"), p3, width = 7.2, height = 4.2)
ggsave(paste0(opt$prefix, "_functional_relative.pdf"), p4, width = 7.2, height = 4.2)

message("Files saved:")
message("  ", opt$prefix, "_ge80.pdf")
message("  ", opt$prefix, "_full_length_multi.pdf")
message("  ", opt$prefix, "_unique_swissprot.pdf")
message("  ", opt$prefix, "_functional_relative.pdf")

readme_file <- paste0(opt$prefix, "_README.txt")

readme_text <- paste(
"Sequencing Depth Saturation Analysis",
"====================================",
"",
"This analysis evaluates how sequencing depth affects transcriptome assembly completeness and functional annotation recovery using Trinity and DIAMOND (Swiss-Prot).",
"",
"Generated files:",
"",
paste0("1. ", opt$prefix, "_ge80.pdf"),
"   - Metric: Number of transcripts with >=80% coverage of the best Swiss-Prot hit.",
"   - Interpretation:",
"     Reflects recovery of near full-length transcripts.",
"     Plateau indicates sufficient sequencing depth for transcript reconstruction.",
"",
paste0("2. ", opt$prefix, "_full_length_multi.pdf"),
"   - Metrics: >=80%, >=90%, and 100% coverage thresholds.",
"   - Interpretation:",
"     Shows stringency of transcript completeness.",
"     Higher thresholds (100%) indicate truly full-length transcripts.",
"",
paste0("3. ", opt$prefix, "_unique_swissprot.pdf"),
"   - Metric: Number of unique Swiss-Prot proteins detected.",
"   - Interpretation:",
"     Represents functional diversity captured by sequencing.",
"     This is the most biologically relevant saturation metric.",
"     Plateau suggests most functional diversity has been recovered.",
"",
paste0("4. ", opt$prefix, "_functional_relative.pdf"),
"   - Metric: Unique Swiss-Prot hits normalized to the maximum observed.",
"   - Interpretation:",
"     Indicates fraction of total detectable functional diversity.",
"     Useful to determine how much sequencing is 'enough'.",
"",
"General interpretation guidelines:",
"",
"- Rapid increase followed by plateau:",
"  Sequencing depth is approaching saturation.",
"",
"- Continuous increase without plateau:",
"  Additional sequencing may reveal more transcripts/proteins.",
"",
"- Early plateau (e.g., <50% reads):",
"  Dataset likely already well covered.",
"",
"Important notes:",
"",
"- Trinity assemblies may contain redundant or fragmented transcripts.",
"- Swiss-Prot represents a curated subset of proteins; unannotated sequences are not included.",
"- Functional saturation does not necessarily equal transcriptome completeness.",
"",
"Recommended primary metric:",
"  unique_swissprot_hits (functional diversity)",
"",
"Recommended supporting metric:",
"  ge80 (transcript completeness)",
"",
"End of report.",
sep = "\n"
)

writeLines(readme_text, readme_file)

message("  ", readme_file)
