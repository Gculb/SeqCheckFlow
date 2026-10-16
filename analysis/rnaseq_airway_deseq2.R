suppressPackageStartupMessages({
  library(DESeq2)
  library(tximport)
  library(ggplot2)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  stop(
    "Usage: rnaseq_airway_deseq2.R <quant_manifest.tsv> <tx2gene.tsv>",
    call. = FALSE
  )
}

sample_data <- read.delim(args[[1]], stringsAsFactors = FALSE, check.names = FALSE)
tx2gene <- read.delim(
  args[[2]],
  header = FALSE,
  col.names = c("TXNAME", "GENEID"),
  stringsAsFactors = FALSE
)
if (!all(c("sample", "cell", "dex", "quant_file") %in% names(sample_data))) {
  stop("Quant manifest must include sample, cell, dex, and quant_file columns.", call. = FALSE)
}
if (!all(c("untrt", "trt") %in% unique(sample_data$dex))) {
  stop("The sample sheet must include untrt and trt treatment groups.", call. = FALSE)
}
quant_files <- sample_data$quant_file
if (anyDuplicated(sample_data$sample) || anyDuplicated(quant_files)) {
  stop("Sample names and quantification files must be unique.", call. = FALSE)
}
if (!all(file.exists(quant_files)) || !nrow(tx2gene)) {
  stop("Quantification files or transcript-to-gene mapping are missing.", call. = FALSE)
}

rownames(sample_data) <- sample_data$sample
sample_data$cell <- factor(sample_data$cell)
sample_data$dex <- relevel(factor(sample_data$dex), ref = "untrt")
files <- setNames(quant_files, sample_data$sample)
txi <- tximport(files, type = "salmon", tx2gene = tx2gene, ignoreTxVersion = TRUE)

dds <- DESeqDataSetFromTximport(txi, colData = sample_data, design = ~ cell + dex)
dds <- dds[rowSums(counts(dds)) >= 10, ]
dds <- DESeq(dds, quiet = TRUE)
result <- results(dds, contrast = c("dex", "trt", "untrt"))

result_table <- as.data.frame(result)
result_table$gene_id <- rownames(result_table)
result_table <- result_table[
  order(result_table$padj, result_table$pvalue, na.last = TRUE),
  c("gene_id", "baseMean", "log2FoldChange", "lfcSE", "stat", "pvalue", "padj")
]
write.csv(result_table, "deseq2_results.csv", row.names = FALSE, na = "")

normalized_counts <- counts(dds, normalized = TRUE)
normalized_counts_table <- data.frame(
  gene_id = rownames(normalized_counts),
  normalized_counts,
  check.names = FALSE,
  row.names = NULL
)
write.csv(normalized_counts_table, "normalized_counts.csv", row.names = FALSE)

gene_variance <- apply(normalized_counts, 1, var)
variance_table <- data.frame(
  gene_id = rownames(dds),
  baseMean = rowMeans(normalized_counts),
  normalized_count_variance = gene_variance,
  dispersion = dispersions(dds),
  log2FoldChange = result$log2FoldChange,
  lfcSE = result$lfcSE,
  check.names = FALSE
)
variance_table <- variance_table[order(
  variance_table$normalized_count_variance,
  decreasing = TRUE,
  na.last = TRUE
), ]
write.csv(variance_table, "gene_variance_diagnostics.csv", row.names = FALSE, na = "")

crispld2_id <- "ENSG00000103196"
crispld2_row <- match(crispld2_id, rownames(normalized_counts))
if (!is.na(crispld2_row)) {
  crispld2_counts <- normalized_counts[crispld2_row, ]
  donor_lines <- levels(sample_data$cell)
  donor_colors <- grDevices::hcl.colors(length(donor_lines), palette = "Dark 3")
  paired_counts <- unlist(lapply(donor_lines, function(donor) {
    sample_names <- sample_data$sample[
      sample_data$cell == donor & sample_data$dex %in% c("untrt", "trt")
    ]
    unname(crispld2_counts[sample_names])
  }))
  png("crispld2_paired_counts.png", width = 1200, height = 900, res = 150)
  plot(
    NA,
    xlim = c(0.8, 2.2),
    ylim = range(paired_counts, finite = TRUE) * c(0.75, 1.3),
    log = "y",
    xaxt = "n",
    xlab = "Treatment",
    ylab = "Normalized gene counts (log scale)",
    main = "CRISPLD2 expression within donor pairs"
  )
  axis(1, at = c(1, 2), labels = c("Untreated", "Dexamethasone"))
  for (i in seq_along(donor_lines)) {
    donor <- donor_lines[[i]]
    untrt_sample <- sample_data$sample[sample_data$cell == donor & sample_data$dex == "untrt"]
    trt_sample <- sample_data$sample[sample_data$cell == donor & sample_data$dex == "trt"]
    pair_values <- crispld2_counts[c(untrt_sample, trt_sample)]
    lines(c(1, 2), pair_values, col = donor_colors[[i]], lwd = 2)
    points(c(1, 2), pair_values, col = donor_colors[[i]], pch = 19, cex = 1.2)
  }
  legend("bottomright", legend = donor_lines, col = donor_colors, lty = 1, pch = 19, bty = "n", title = "Donor")
  mtext("Three donor pairs increase; N061011 decreases. Four pairs give limited precision.",
        side = 3, line = 0.25, cex = 0.8)
  dev.off()
}

significant <- result_table[!is.na(result_table$padj) & result_table$padj < 0.05, ]
upregulated <- sum(significant$log2FoldChange > 0)
downregulated <- sum(significant$log2FoldChange < 0)
conclusion <- if (nrow(significant) > 0) {
  sprintf(
    paste(
      "Conclusion: dexamethasone treatment is associated with differential",
      "gene expression in this airway smooth-muscle dataset after accounting",
      "for donor cell line (%d genes at adjusted p-value < 0.05). This",
      "dataset-specific reanalysis is exploratory and is not independent",
      "validation or evidence of a general treatment effect."
    ),
    nrow(significant)
  )
} else {
  paste(
    "Conclusion: no genes met the adjusted p-value < 0.05 threshold for the",
    "dexamethasone effect after accounting for donor cell line. With only four",
    "donors, this result does not establish that treatment has no biological",
    "effect; it is a dataset-specific, exploratory reanalysis."
  )
}
summary_lines <- c(
  "Dataset: raw paired-end RNA-seq for airway smooth muscle cells (GEO GSE52778)",
  "Comparison: dexamethasone-treated (trt) vs untreated (untrt)",
  "Raw FASTQ -> fastp -> Salmon selective-alignment quantification -> tximport -> DESeq2",
  "Model: ~ cell + dex; donor cell line is included to account for paired samples",
  sprintf("Samples: %d; donor cell lines: %d", nrow(sample_data), nlevels(sample_data$cell)),
  "Significance threshold: Benjamini-Hochberg adjusted p-value < 0.05",
  sprintf("Significant genes: %d (%d higher with dex, %d lower with dex)",
          nrow(significant), upregulated, downregulated),
  conclusion
)
writeLines(summary_lines, "analysis_summary.txt")

png("ma_plot.png", width = 1200, height = 900, res = 150)
plotMA(result, alpha = 0.05, ylim = c(-5, 5), main = "Dexamethasone vs untreated")
dev.off()

adjusted_p <- pmax(result_table$padj, .Machine$double.xmin, na.rm = FALSE)
volcano_y <- -log10(adjusted_p)
volcano_y[is.na(result_table$padj)] <- NA_real_
png("volcano_plot.png", width = 1200, height = 900, res = 150)
plot(
  result_table$log2FoldChange,
  volcano_y,
  pch = 16,
  cex = 0.45,
  col = ifelse(!is.na(result_table$padj) & result_table$padj < 0.05, "firebrick", "grey40"),
  xlab = "Log2 fold change (treated / untreated)",
  ylab = "-Log10 adjusted p-value",
  main = "Airway RNA-seq differential expression",
  ylim = c(0, max(volcano_y, -log10(0.05), na.rm = TRUE) * 1.05)
)
abline(h = -log10(0.05), lty = 2)
dev.off()

vsd <- varianceStabilizingTransformation(dds, blind = FALSE)
pca_data <- plotPCA(
  vsd,
  intgroup = c("dex", "cell"),
  returnData = TRUE
)
percent_var <- round(100 * attr(pca_data, "percentVar"))
pca <- ggplot(
  pca_data,
  aes(x = PC1, y = PC2, color = dex, shape = cell)
) +
  geom_point(size = 4) +
  xlab(sprintf("PC1: %d%% variance", percent_var[[1]])) +
  ylab(sprintf("PC2: %d%% variance", percent_var[[2]])) +
  labs(
    title = "Airway RNA-seq sample PCA",
    color = "Treatment",
    shape = "Donor cell line"
  ) +
  theme_bw()
ggsave("pca_plot.png", pca, width = 8, height = 6, dpi = 150)
writeLines(capture.output(sessionInfo()), "session_info.txt")
