# =============================================================================
# PCA Analysis Script (Step1)
# Module:2_pca_plsda_oplsda_analysis
# =============================================================================
# Description:
#读取预处理后的表达矩阵和样本信息表，执行PCA分析，
#计算样本得分、加权欧氏距离、置换检验，并生成散点图。
#所有CSV输出到 tmp/2_pca_plsda_oplsda_analysis/
#所有图形输出到 analysis/2_pca_plsda_oplsda_analysis/figures/
# =============================================================================

# ----0. Setup ----
cat("=====================================================\n")
cat(" PCA Analysis - Module2, Step1\n")
cat("=====================================================\n\n")

BASE_DIR <- "G:/OmicsWorks/test/metabolism/demo"
TMP_DIR <- file.path(BASE_DIR, "tmp")
SCRIPT_DIR <- file.path(TMP_DIR, "2_pca_plsda_oplsda_analysis", "scripts")
OUTPUT_DIR <- file.path(TMP_DIR, "2_pca_plsda_oplsda_analysis")
FIGURE_DIR <- file.path(BASE_DIR, "analysis", "2_pca_plsda_oplsda_analysis", "figures")
AGENT_RSCRIPT <- "G:/OmicsWorks/agent/rscript"

dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(FIGURE_DIR, showWarnings = FALSE, recursive = TRUE)

# ----1. Install & Load Packages ----
cat("[1] Installing and loading required R packages...\n")

required_cran <- c("ggplot2", "ggrepel", "RColorBrewer", "viridis")
required_bioc <- c("mixOmics", "ropls")

if (!requireNamespace("BiocManager", quietly = TRUE)) {
 install.packages("BiocManager", repos = "https://cloud.r-project.org")
}

for (pkg in required_cran) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 cat(" Installing CRAN package:", pkg, "...\n")
 install.packages(pkg, repos = "https://cloud.r-project.org")
 }
}

for (pkg in required_bioc) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 cat(" Installing Bioconductor package:", pkg, "...\n")
 BiocManager::install(pkg, ask = FALSE, update = FALSE)
 }
}

library(ggplot2)
library(ggrepel)
library(RColorBrewer)
library(viridis)
library(mixOmics)
library(ropls)
cat(" All packages loaded successfully.\n\n")

# ----2. Source helper scripts ----
cat("[2] Loading helper scripts from", AGENT_RSCRIPT, "...\n")
source(file.path(AGENT_RSCRIPT, "data_io.R"))
source(file.path(AGENT_RSCRIPT, "multivariate.R"))
source(file.path(AGENT_RSCRIPT, "visualization.R"))
cat(" Helper scripts loaded.\n\n")

# ----3. Read Input Data ----
cat("[3] Reading input data...\n")
expr_file <- file.path(TMP_DIR, "preprocessed_expression.csv")
meta_file <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"

cat(" Expression matrix:", expr_file, "\n")
cat(" Sample metadata:", meta_file, "\n")

expr_matrix <- load_expression_matrix(expr_file)
cat(" Expression matrix dimensions:", nrow(expr_matrix), "features x",
 ncol(expr_matrix), "samples\n")

sample_meta <- load_sample_metadata(meta_file)
cat(" Sample metadata rows:", nrow(sample_meta), "\n")
cat(" Groups in metadata:\n")
print(table(sample_meta$sample_info))

# ----4. Filter QC Samples & Match ----
cat("\n[4] Filtering QC samples and matching metadata...\n")

# Keep samples that exist in BOTH expression matrix AND metadata
common_samples <- intersect(colnames(expr_matrix), sample_meta$ID)
cat(" Common samples:", length(common_samples), "\n")

expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
sample_meta <- sample_meta[sample_meta$ID %in% common_samples, , drop = FALSE]
rownames(sample_meta) <- sample_meta$ID
sample_meta <- sample_meta[colnames(expr_matrix), , drop = FALSE]

cat(" After filtering:\n")
cat(" Expression matrix:", nrow(expr_matrix), "features x",
 ncol(expr_matrix), "samples\n")
cat(" Metadata rows:", nrow(sample_meta), "\n")

# ----5. Standardize Group Labels ----
cat("\n[5] Standardizing group labels...\n")

group_mapping <- c(
 "Clostridium difficile infection" = "CD",
 "high iron diet before" = "FE",
 "Standard (control)" = "NC"
)

sample_meta$group_label <- factor(
 group_mapping[as.character(sample_meta$sample_info)],
 levels = c("NC", "CD", "FE")
)

cat(" Group mapping:\n")
print(table(sample_meta$group_label))

# ----6. Transpose Expression Matrix ----
cat("\n[6] Transposing expression matrix (samples x features)...\n")
expr_t <- t(expr_matrix)
cat(" Transposed matrix:", nrow(expr_t), "samples x", ncol(expr_t), "features\n")

# ----7. Perform PCA ----
cat("\n[7] Performing PCA with prcomp(scale=TRUE, center=TRUE)...\n")

pca_result <- prcomp(expr_t, scale. = TRUE, center = TRUE)

# Variance explained
variance_explained <- summary(pca_result)$importance[2, ]
cumulative_variance <- summary(pca_result)$importance[3, ]

cat(" Variance explained (top5 PCs):\n")
for (i in 1:min(5, length(variance_explained))) {
 cat(sprintf(" PC%d: %.2f%% (cumulative: %.2f%%)\n",
 i, variance_explained[i] *100, cumulative_variance[i] *100))
}

# Extract PC1-PC3 scores
pca_scores <- as.data.frame(pca_result$x[,1:3])
colnames(pca_scores) <- c("PC1", "PC2", "PC3")
pca_scores$SampleID <- rownames(pca_scores)
pca_scores$Group <- sample_meta[rownames(pca_scores), "group_label"]
pca_scores$SampleName <- sample_meta[rownames(pca_scores), "sample_name"]
pca_scores$SampleType <- sample_meta[rownames(pca_scores), "sample_info"]

cat(" PCA scores computed for", nrow(pca_scores), "samples.\n")

# ----8. Save PCA Scores & Variance ----
cat("\n[8] Saving PCA results to CSV...\n")

# Scores
scores_file <- file.path(OUTPUT_DIR, "pca_scores.csv")
write.csv(pca_scores, scores_file, row.names = FALSE)
cat(" ->", scores_file, "\n")

# Variance explained
var_df <- data.frame(
 PC = paste0("PC",1:length(variance_explained)),
 Variance_Explained = variance_explained,
 Cumulative_Variance = cumulative_variance,
 Std_Dev = pca_result$sdev
)
var_file <- file.path(OUTPUT_DIR, "pca_variance_explained.csv")
write.csv(var_df, var_file, row.names = FALSE)
cat(" ->", var_file, "\n")

# Loadings (top3 PCs)
loadings_df <- as.data.frame(pca_result$rotation[,1:3])
loadings_df$Feature <- rownames(loadings_df)
loadings_file <- file.path(OUTPUT_DIR, "pca_loadings.csv")
write.csv(loadings_df[, c("Feature", "PC1", "PC2", "PC3")],
 loadings_file, row.names = FALSE)
cat(" ->", loadings_file, "\n")

# ----9. Weighted Euclidean Distances ----
cat("\n[9] Calculating weighted Euclidean distances to group centroids...\n")

n_pcs <-3
weights <- variance_explained[1:n_pcs] / sum(variance_explained[1:n_pcs])
cat(" PC weights (based on variance explained):\n")
for (i in 1:n_pcs) {
 cat(sprintf(" PC%d: %.4f\n", i, weights[i]))
}

groups <- levels(sample_meta$group_label)
centroids <- matrix(NA, nrow = length(groups), ncol = n_pcs,
 dimnames = list(groups, c("PC1", "PC2", "PC3")))
for (g in groups) {
 idx <- which(pca_scores$Group == g)
 centroids[g, ] <- colMeans(pca_scores[idx, c("PC1", "PC2", "PC3")])
}

cat(" Group centroids:\n")
print(round(centroids,4))

# Calculate weighted distances
weighted_dist <- data.frame(
 SampleID = pca_scores$SampleID,
 SampleName = pca_scores$SampleName,
 Group = pca_scores$Group,
 stringsAsFactors = FALSE,
 Distance_To_Centroid = NA_real_
)

for (i in 1:nrow(pca_scores)) {
 sg <- as.character(pca_scores$Group[i])
 cent <- centroids[sg, ]
 vec <- as.numeric(pca_scores[i, c("PC1", "PC2", "PC3")])
 weighted_dist$Distance_To_Centroid[i] <- sqrt(sum(weights * (vec - cent)^2))
}

cat(" Within-group distance stats:\n")
cat(sprintf(" Min: %.4f\n", min(weighted_dist$Distance_To_Centroid)))
cat(sprintf(" Max: %.4f\n", max(weighted_dist$Distance_To_Centroid)))
cat(sprintf(" Mean: %.4f\n", mean(weighted_dist$Distance_To_Centroid)))

dist_file <- file.path(OUTPUT_DIR, "pca_weighted_distances.csv")
write.csv(weighted_dist, dist_file, row.names = FALSE)
cat(" ->", dist_file, "\n")

# ----10. Permutation Test ----
cat("\n[10] Performing permutation test (n=1000)...\n")

# Observed within-group distance mean
mean_within_obs <- mean(weighted_dist$Distance_To_Centroid)

# Observed between-group distances
between_dists <- c()
for (i in 1:nrow(pca_scores)) {
 sg <- as.character(pca_scores$Group[i])
 other_g <- setdiff(groups, sg)
 vec <- as.numeric(pca_scores[i, c("PC1", "PC2", "PC3")])
 for (og in other_g) {
 between_dists <- c(between_dists, sqrt(sum(weights * (vec - centroids[og, ])^2)))
 }
}
mean_between_obs <- mean(between_dists)
obs_ratio <- mean_within_obs / mean_between_obs

cat(sprintf(" Observed mean within-group distance: %.4f\n", mean_within_obs))
cat(sprintf(" Observed mean between-group distance: %.4f\n", mean_between_obs))
cat(sprintf(" Observed within/between ratio: %.4f\n", obs_ratio))

# Permutation
set.seed(42)
n_perm <-1000
perm_ratios <- numeric(n_perm)

for (p in 1:n_perm) {
 perm_labels <- sample(sample_meta$group_label)

 # Permuted centroids
 perm_cent <- matrix(NA, nrow = length(groups), ncol = n_pcs,
 dimnames = list(groups, c("PC1", "PC2", "PC3")))
 for (g in groups) {
 idx <- which(perm_labels == g)
 perm_cent[g, ] <- colMeans(pca_scores[idx, c("PC1", "PC2", "PC3")])
 }

 # Permuted within
 perm_within <- numeric(nrow(pca_scores))
 for (i in 1:nrow(pca_scores)) {
 g <- as.character(perm_labels[i])
 vec <- as.numeric(pca_scores[i, c("PC1", "PC2", "PC3")])
 perm_within[i] <- sqrt(sum(weights * (vec - perm_cent[g, ])^2))
 }

 # Permuted between
 perm_between <- c()
 for (i in 1:nrow(pca_scores)) {
 g <- as.character(perm_labels[i])
 vec <- as.numeric(pca_scores[i, c("PC1", "PC2", "PC3")])
 for (og in setdiff(groups, g)) {
 perm_between <- c(perm_between, sqrt(sum(weights * (vec - perm_cent[og, ])^2)))
 }
 }
 perm_ratios[p] <- mean(perm_within) / mean(perm_between)
}

p_value <- sum(perm_ratios <= obs_ratio) / n_perm

cat(sprintf(" Permutation test results (n=%d):\n", n_perm))
cat(sprintf(" Mean permuted ratio: %.4f\n", mean(perm_ratios)))
cat(sprintf(" Permuted ratio95%% CI: [%.4f, %.4f]\n",
 quantile(perm_ratios,0.025), quantile(perm_ratios,0.975)))
cat(sprintf(" P-value (one-sided): %.4f\n", p_value))
if (p_value <0.05) {
 cat(" => Group separation is statistically significant (p <0.05)\n")
} else {
 cat(" => Group separation is NOT statistically significant (p >=0.05)\n")
}

perm_results <- data.frame(
 Metric = c("Observed_Ratio", "Mean_Permuted_Ratio",
 "Perm_2.5%", "Perm_97.5%", "P_Value_OneSided"),
 Value = c(obs_ratio, mean(perm_ratios),
 quantile(perm_ratios,0.025), quantile(perm_ratios,0.975), p_value)
)
perm_file <- file.path(OUTPUT_DIR, "permutation_test_results.csv")
write.csv(perm_results, perm_file, row.names = FALSE)
cat(" ->", perm_file, "\n")

# ----11. PCA Scatter Plots ----
cat("\n[11] Generating PCA scatter plots...\n")

# Color palette (fixed)
group_colors <- c("NC" = "#4DBBD5", "CD" = "#E64B35", "FE" = "#00A087")

# Shape mapping for sample types
orig_types <- levels(sample_meta$sample_info)
shape_vals <- c(16,17,15,18,8,3,4)
names(shape_vals) <- orig_types[1:min(length(orig_types), length(shape_vals))]

# Legend labels
legend_labels <- c(
 "NC" = "NC (Healthy Control)",
 "CD" = "CD (C. diff Infection)",
 "FE" = "FE (High Iron + CDI)"
)

# Helper function to build a PCA scatter plot
make_pca_plot <- function(data, xcol, ycol, xlab, ylab, title, subtitle) {
 p <- ggplot(data, aes_string(x = xcol, y = ycol,
 color = "Group", shape = "SampleType")) +
 geom_point(size =3.5, alpha =0.85) +
 stat_ellipse(level =0.95, type = "t", linewidth =0.8,
 aes_string(fill = "Group"), alpha =0.1, geom = "polygon") +
 geom_text_repel(aes(label = SampleName), size =3.0,
 max.overlaps =20, box.padding =0.5,
 show.legend = FALSE) +
 scale_color_manual(values = group_colors, labels = legend_labels) +
 scale_fill_manual(values = group_colors, guide = "none") +
 scale_shape_manual(values = shape_vals) +
 labs(title = title, subtitle = subtitle,
 x = xlab, y = ylab, color = "Group", shape = "Condition") +
 theme_bw(base_size =12) +
 theme(
 plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 plot.subtitle = element_text(hjust =0.5, size =10, color = "grey40"),
 legend.position = "right",
 legend.title = element_text(size =10, face = "bold"),
 legend.text = element_text(size =9),
 panel.grid.minor = element_blank()
 )
 return(p)
}

var_pc1 <- variance_explained[1] *100
var_pc2 <- variance_explained[2] *100
var_pc3 <- variance_explained[3] *100

# ----11a. PC1 vs PC2 ----
cat(" Plotting PC1 vs PC2...\n")
p_pc12 <- make_pca_plot(
 pca_scores, "PC1", "PC2",
 paste0("PC1 (", round(var_pc1,1), "%)"),
 paste0("PC2 (", round(var_pc2,1), "%)"),
 "PCA Score Plot (PC1 vs PC2)",
 paste0("Total variance: ", round(var_pc1 + var_pc2,1), "%")
)
ggsave(file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC2.png"),
 p_pc12, width =9, height =7, dpi =300)
ggsave(file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC2.pdf"),
 p_pc12, width =9, height =7)
cat(" Saved PCA PC1 vs PC2 plot.\n")

# ----11b. PC1 vs PC3 ----
cat(" Plotting PC1 vs PC3...\n")
p_pc13 <- make_pca_plot(
 pca_scores, "PC1", "PC3",
 paste0("PC1 (", round(var_pc1,1), "%)"),
 paste0("PC3 (", round(var_pc3,1), "%)"),
 "PCA Score Plot (PC1 vs PC3)",
 paste0("Total variance: ", round(var_pc1 + var_pc3,1), "%")
)
ggsave(file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC3.png"),
 p_pc13, width =9, height =7, dpi =300)
ggsave(file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC3.pdf"),
 p_pc13, width =9, height =7)
cat(" Saved PCA PC1 vs PC3 plot.\n")

# ----11c. PC2 vs PC3 ----
cat(" Plotting PC2 vs PC3...\n")
p_pc23 <- make_pca_plot(
 pca_scores, "PC2", "PC3",
 paste0("PC2 (", round(var_pc2,1), "%)"),
 paste0("PC3 (", round(var_pc3,1), "%)"),
 "PCA Score Plot (PC2 vs PC3)",
 paste0("Total variance: ", round(var_pc2 + var_pc3,1), "%")
)
ggsave(file.path(FIGURE_DIR, "PCA_score_plot_PC2_vs_PC3.png"),
 p_pc23, width =9, height =7, dpi =300)
ggsave(file.path(FIGURE_DIR, "PCA_score_plot_PC2_vs_PC3.pdf"),
 p_pc23, width =9, height =7)
cat(" Saved PCA PC2 vs PC3 plot.\n")

# ----12. Scree Plot ----
cat("\n[12] Generating scree plot...\n")

scree_data <- data.frame(
 PC = factor(paste0("PC",1:10), levels = paste0("PC",1:10)),
 Variance = variance_explained[1:10] *100
)

p_scree <- ggplot(scree_data, aes(x = PC, y = Variance, group =1)) +
 geom_bar(stat = "identity", fill = "steelblue", alpha =0.8, width =0.7) +
 geom_line(color = "darkred", linewidth =0.8) +
 geom_point(color = "darkred", size =2) +
 labs(title = "Scree Plot",
 x = "Principal Component",
 y = "Variance Explained (%)") +
 theme_bw(base_size =12) +
 theme(
 plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 panel.grid.minor = element_blank()
 )

ggsave(file.path(FIGURE_DIR, "PCA_scree_plot.png"),
 p_scree, width =8, height =5, dpi =300)
ggsave(file.path(FIGURE_DIR, "PCA_scree_plot.pdf"),
 p_scree, width =8, height =5)
cat(" Scree plot saved.\n")

# ----13. Summary Statistics ----
cat("\n[13] PCA Summary statistics:\n")

# Per-group distance summary
cat(" Group distance summary:\n")
for (g in groups) {
 sub <- weighted_dist$Distance_To_Centroid[weighted_dist$Group == g]
 cat(sprintf(" %s: mean=%.4f, sd=%.4f, min=%.4f, max=%.4f\n",
 g, mean(sub), sd(sub), min(sub), max(sub)))
}

# Pairwise centroid distances
cat(" Pairwise centroid distances:\n")
pair_dist <- as.matrix(dist(centroids))
print(round(pair_dist,4))

cat("\n=====================================================\n")
cat(" PCA Analysis Completed Successfully!\n")
cat("=====================================================\n\n")

cat("Output CSV files:\n")
cat(" ", scores_file, "\n")
cat(" ", var_file, "\n")
cat(" ", loadings_file, "\n")
cat(" ", dist_file, "\n")
cat(" ", perm_file, "\n")

cat("Output Figures:\n")
cat(" ", file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC2.png/pdf"), "\n")
cat(" ", file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC3.png/pdf"), "\n")
cat(" ", file.path(FIGURE_DIR, "PCA_score_plot_PC2_vs_PC3.png/pdf"), "\n")
cat(" ", file.path(FIGURE_DIR, "PCA_scree_plot.png/pdf"), "\n")

cat("\nKey findings:\n")
cat(sprintf(" PC1: %.1f%%, PC2: %.1f%%, PC3: %.1f%%\n", var_pc1, var_pc2, var_pc3))
cat(sprintf(" Top3 PCs explain %.1f%% of total variance\n",
 sum(variance_explained[1:3]) *100))
cat(sprintf(" Permutation p-value: %.4f\n", p_value))
if (p_value <0.05) {
 cat(" => Groups show statistically significant separation in PCA space.\n")
} else {
 cat(" => Groups do NOT show statistically significant separation in PCA space.\n")
}
cat("\nDone.\n")
