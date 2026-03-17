#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
  library(readr)
  library(dplyr)
  library(optparse)
  library(scales)
})

option_list <- list(
  make_option(
    c("--csv"),
    type = "character",
    help = "CSV com colunas: pct, ge80, ge90, ge100, total",
    metavar = "file"
  ),
  make_option(
    c("--prefix"),
    type = "character",
    default = "deep_enough_swissprot",
    help = "Prefixo dos arquivos de saída [default: %default]",
    metavar = "string"
  )
)

opt <- parse_args(OptionParser(option_list = option_list))

if (is.null(opt$csv)) {
  stop("ERRO: use --csv <deep_enough.csv>", call. = FALSE)
}

df <- read_csv(opt$csv, show_col_types = FALSE) %>%
  arrange(pct)

required_cols <- c("pct", "ge80", "ge90", "ge100", "total")
if (!all(required_cols %in% colnames(df))) {
  stop("ERRO: o CSV precisa ter as colunas: pct, ge80, ge90, ge100, total", call. = FALSE)
}

# gráfico principal usando >=80%
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

# gráfico opcional com >=80, >=90 e 100%
df_long <- df %>%
  select(pct, ge80, ge90, ge100) %>%
  tidyr::pivot_longer(
    cols = c(ge80, ge90, ge100),
    names_to = "metric",
    values_to = "count"
  ) %>%
  mutate(metric = recode(metric,
                         ge80 = ">=80%",
                         ge90 = ">=90%",
                         ge100 = "100%"))

p2 <- ggplot(df_long, aes(x = pct, y = count, group = metric)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.3) +
  scale_x_continuous(breaks = sort(unique(df_long$pct))) +
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
    axis.title = element_text(face = "bold")
  )

ggsave(paste0(opt$prefix, "_ge80.pdf"), p1, width = 7.2, height = 4.2)

ggsave(paste0(opt$prefix, "_multi.pdf"), p2, width = 7.2, height = 4.2)

message("Arquivos salvos:")
message("  ", opt$prefix, "_ge80.pdf")
message("  ", opt$prefix, "_multi.pdf")
