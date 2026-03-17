#!/usr/bin/env Rscript

# ==============================
# Load libraries
# ==============================
suppressPackageStartupMessages({
  library(ggplot2)
  library(optparse)
})

# ==============================
# Command line options
# ==============================
option_list <- list(
  make_option("--align_file", type = "character", help = "Bowtie2 align_stats.txt file")
)

opt <- parse_args(OptionParser(option_list = option_list))

if (is.null(opt$align_file)) {
  stop("Please provide --align_file")
}

# ==============================
# Read file
# ==============================
lines <- readLines(opt$align_file)

# ==============================
# Extract percentages
# ==============================
unaligned <- as.numeric(sub(".*\\((.*)%\\).*", "\\1",
                            grep("aligned 0 times", lines, value = TRUE)))

aligned_once <- as.numeric(sub(".*\\((.*)%\\).*", "\\1",
                               grep("aligned exactly 1 time", lines, value = TRUE)))

aligned_multi <- as.numeric(sub(".*\\((.*)%\\).*", "\\1",
                                grep("aligned >1 times", lines, value = TRUE)))

overall <- as.numeric(sub("(.*)% overall alignment rate", "\\1",
                          grep("overall alignment rate", lines, value = TRUE)))

# ==============================
# Create dataframe
# ==============================
df <- data.frame(
  Category = factor(
    c("Unaligned", "Aligned once", "Aligned >1 times"),
    levels = c("Unaligned", "Aligned once", "Aligned >1 times")
  ),
  Percent = c(unaligned, aligned_once, aligned_multi)
)

# ==============================
# Plot
# ==============================
p <- ggplot(df, aes(x = "", y = Percent, fill = Category)) +
  geom_bar(stat = "identity", width = 0.6) +
  coord_flip() +
  theme_minimal(base_size = 15) +
  labs(
    title = "Read representation against Trinity assembly",
    subtitle = paste("Overall alignment rate:", overall, "%"),
    x = "",
    y = "Percentage of reads"
  ) +
  theme(
    axis.text.y = element_blank(),
    axis.ticks.y = element_blank(),
    panel.grid.major.y = element_blank()
  )

# ==============================
# Save output
# ==============================
out_file <- sub("\\.txt$", "_plot.png", opt$align_file)

ggsave(out_file, p, width = 8, height = 4, dpi = 300)

cat("Plot saved as:", out_file, "\n")
