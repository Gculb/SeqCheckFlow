suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) {
  stop("Usage: rnaseq_sample_qc.R <samplesheet.tsv>", call. = FALSE)
}

samples <- read.delim(args[[1]], stringsAsFactors = FALSE, check.names = FALSE)
if (!all(c("sample", "run", "cell", "dex") %in% names(samples))) {
  stop("Sample sheet must include sample, run, cell, and dex columns.", call. = FALSE)
}

rows <- lapply(seq_len(nrow(samples)), function(i) {
  sample <- samples$sample[[i]]
  fastp_candidates <- c(
    paste0(sample, ".fastp.json"),
    file.path("qc", paste0(sample, ".fastp.json")),
    file.path("../qc", paste0(sample, ".fastp.json"))
  )
  existing_fastp <- fastp_candidates[file.exists(fastp_candidates)]
  fastp_file <- if (length(existing_fastp)) existing_fastp[[1]] else NA_character_
  salmon_meta_candidates <- c(
    file.path(paste0(sample, "_salmon"), "aux_info", "meta_info.json"),
    file.path(sample, "aux_info", "meta_info.json"),
    file.path("salmon", sample, "aux_info", "meta_info.json"),
    file.path("../quant", sample, "aux_info", "meta_info.json")
  )
  existing_meta <- salmon_meta_candidates[file.exists(salmon_meta_candidates)]
  salmon_meta <- if (length(existing_meta)) existing_meta[[1]] else NA_character_
  if (is.na(fastp_file) || is.na(salmon_meta)) {
    stop(sprintf("Missing fastp or Salmon metadata for sample %s.", sample), call. = FALSE)
  }
  fastp <- jsonlite::fromJSON(fastp_file)
  salmon <- jsonlite::fromJSON(salmon_meta)
  data.frame(
    sample = sample,
    run = samples$run[[i]],
    cell = samples$cell[[i]],
    dex = samples$dex[[i]],
    q20_before_pct = 100 * fastp$summary$before_filtering$q20_rate,
    q20_after_pct = 100 * fastp$summary$after_filtering$q20_rate,
    q30_before_pct = 100 * fastp$summary$before_filtering$q30_rate,
    q30_after_pct = 100 * fastp$summary$after_filtering$q30_rate,
    reads_passed_fastp = fastp$filtering_result$passed_filter_reads,
    salmon_processed = salmon$num_processed,
    salmon_mapped = salmon$num_mapped,
    salmon_mapping_pct = salmon$percent_mapped,
    check.names = FALSE
  )
})

summary <- do.call(rbind, rows)
numeric_columns <- vapply(summary, is.numeric, logical(1))
summary[numeric_columns] <- lapply(summary[numeric_columns], round, digits = 2)
write.table(summary, "sample_qc_summary.tsv", sep = "\t", row.names = FALSE, quote = FALSE)

plot_colors <- ifelse(summary$dex == "trt", "#a65d28", "#176b87")
sample_positions <- rev(seq_len(nrow(summary)))
png("sample_qc_plot.png", width = 1800, height = 1000, res = 150)
par(mfrow = c(1, 2), mar = c(5, 8, 4, 1), oma = c(2, 0, 0, 0))
plot(
  summary$q30_after_pct,
  sample_positions,
  xlim = c(90, 100),
  ylim = c(0.5, nrow(summary) + 0.5),
  yaxt = "n",
  pch = 19,
  col = plot_colors,
  xlab = "Bases at Q30 or higher (%)",
  ylab = "",
  main = "Read quality after fastp"
)
axis(2, at = sample_positions, labels = summary$sample, las = 1, cex.axis = 0.8)
plot(
  summary$salmon_mapping_pct,
  sample_positions,
  xlim = c(90, 100),
  ylim = c(0.5, nrow(summary) + 0.5),
  yaxt = "n",
  pch = 19,
  col = plot_colors,
  xlab = "Reads mapped (%)",
  ylab = "",
  main = "Salmon mapping rate"
)
axis(2, at = sample_positions, labels = summary$sample, las = 1, cex.axis = 0.8)
mtext("Untreated", side = 1, outer = TRUE, line = 0.5, at = 0.35, col = "#176b87")
mtext("Dexamethasone treated", side = 1, outer = TRUE, line = 0.5, at = 0.72, col = "#a65d28")
dev.off()
