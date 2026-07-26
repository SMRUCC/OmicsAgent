# =============================================================================
# PCA Analysis Script
# Module:2_pca_plsda_oplsda_analysis - Step1: PCA
# =============================================================================
# Description:
#读取预处理后的表达矩阵和样本信息表，执行PCA分析，
#计算样本得分、加权欧氏距离、置换检验，并生成散点图。
#
# Input files:
# - G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv
# - G:/OmicsWorks/test/metabolism/sampleinfo.csv
#
# Output files:
# - CSV: pca_scores.csv, pca_variance_explained.csv,
# pca_weighted_distances.csv, permutation_test_results.csv
# - Figures: PCA_score_plot_PC1_vs_PC2.png/pdf,
# PCA_score_plot_PC1_vs_PC3.png/pdf
# =============================================================================

# ----0. Environment Setup ----
cat("=====================================================\n")
cat(" PCA Analysis - Module2\n")
cat("=====================================================\n\n")

# Define absolute paths
BASE_DIR <- "G:/OmicsWorks/test/metabolism/demo"
TMP_DIR <- file.path(BASE_DIR, "tmp")
SCRIPT_DIR <- file.path(TMP_DIR, "2_pca_plsda_oplsda_analysis", "scripts")
OUTPUT_DIR <- file.path(TMP_DIR, "2_pca_plsda_oplsda_analysis")
FIGURE_DIR <- file.path(BASE_DIR, "analysis", "2_pca_plsda_oplsda_analysis", "figures")
AGENT_RSCRIPT_DIR <- "G:/OmicsWorks/agent/rscript"

# Create output directories if they don't exist
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(FIGURE_DIR, showWarnings = FALSE, recursive = TRUE)

# ----1. Install and Load Required Packages ----
cat("[1] Checking and installing required packages...\n")

required_cran <- c("ggplot2", "ggrepel", "RColorBrewer", "viridis")
required_bioc <- c("mixOmics", "ropls")

# Ensure BiocManager is available
if (!requireNamespace("BiocManager", quietly = TRUE)) {
 install.packages("BiocManager", repos = "https://cloud.r-project.org")
}

# Install CRAN packages
for (pkg in required_cran) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 cat(" Installing CRAN package:", pkg, "...\n")
 install.packages(pkg, repos = "https://cloud.r-project.org")
 }
}

# Install Bioconductor packages
for (pkg in required_bioc) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 cat(" Installing Bioconductor package:", pkg, "...\n")
 BiocManager::install(pkg, ask = FALSE, update = FALSE)
 }
}

# Load packages
library(ggplot2)
library(ggrepel)
library(RColorBrewer)
library(viridis)
library(mixOmics)
library(ropls)

cat(" All packages loaded successfully.\n\n")

# ----2. Source Helper Scripts ----
cat("[2] Loading helper scripts...\n")
source(file.path(AGENT_RSCRIPT_DIR, "data_io.R"))
source(file.path(AGENT_RSCRIPT_DIR, "multivariate.R"))
source(file.path(AGENT_RSCRIPT_DIR, "visualization.R"))
cat(" Helper scripts loaded.\n\n")

# ----3. Read Input Data ----
cat("[3] Reading input data...\n")

expr_file <- file.path(TMP_DIR, "preprocessed_expression.csv")
meta_file <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"

cat(" Expression matrix:", expr_file, "\n")
cat(" Sample metadata:", meta_file, "\n")

# Read expression matrix
expr_matrix <- load_expression_matrix(expr_file)
cat(" Expression matrix dimensions:", nrow(expr_matrix), "features x",
 ncol(expr_matrix), "samples\n")

# Read sample metadata
sample_meta <- load_sample_metadata(meta_file)
cat(" Sample metadata rows:", nrow(sample_meta), "\n")
cat(" Groups in metadata:\n")
print(table(sample_meta$sample_info))

# ----4. Filter QC Samples and Match Metadata ----
cat("\n[4] Filtering QC samples and matching metadata...\n")

# QC samples are in sample_meta but NOT in expression matrix columns
# Keep only samples that exist in BOTH expression matrix and metadata
common_samples <- intersect(colnames(expr_matrix), sample_meta$ID)
cat(" Common samples between expression matrix and metadata:", 
 length(common_samples), "\n")

# Filter expression matrix to only common samples
expr_matrix <- expr_matrix[, common_samples, drop = FALSE]

# Filter metadata to only common samples
sample_meta <- sample_meta[sample_meta$ID %in% common_samples, , drop = FALSE]
rownames(sample_meta) <- sample_meta$ID

# Reorder metadata to match expression matrix column order
sample_meta <- sample_meta[colnames(expr_matrix), , drop = FALSE]

cat(" After filtering:\n")
cat(" Expression matrix:", nrow(expr_matrix), "features x",
 ncol(expr_matrix), "samples\n")
cat(" Metadata rows:", nrow(sample_meta), "\n")

# ----5. Standardize Group Labels ----
cat("\n[5] Standardizing group labels...\n")

# Map original group labels to standardized short names
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

# ----6. Transpose Expression Matrix (samples x features) ----
cat("\n[6] Transposing expression matrix for PCA...\n")

# PCA is performed on samples (rows) x features (columns)
expr_t <- t(expr_matrix)
cat(" Transposed matrix dimensions:", nrow(expr_t), "samples x",
 ncol(expr_t), "features\n")

# ----7. Perform PCA ----
cat("\n[7] Performing PCA with prcomp(scale=TRUE)...\n")

pca_result <- prcomp(expr_t, scale. = TRUE, center = TRUE)

# Extract variance explained
variance_explained <- summary(pca_result)$importance[2, ] # Proportion of variance
cumulative_variance <- summary(pca_result)$importance[3, ] # Cumulative proportion

cat(" Variance explained:\n")
for (i in 1:min(5, length(variance_explained))) {
 cat(sprintf(" PC%d: %.2f%% (cumulative: %.2f%%)\n", 
 i, variance_explained[i] *100, cumulative_variance[i] *100))
}

# Extract scores for PC1, PC2, PC3
pca_scores <- as.data.frame(pca_result$x[,1:3])
colnames(pca_scores) <- c("PC1", "PC2", "PC3")
pca_scores$SampleID <- rownames(pca_scores)

# Add group information
pca_scores$Group <- sample_meta[rownames(pca_scores), "group_label"]
pca_scores$SampleName <- sample_meta[rownames(pca_scores), "sample_name"]

cat(" PCA scores computed for", nrow(pca_scores), "samples.\n")

# ----8. Save PCA Scores and Variance ----
cat("\n[8] Saving PCA scores and variance explained...\n")

# Save scores
scores_output <- file.path(OUTPUT_DIR, "pca_scores.csv")
write.csv(pca_scores, scores_output, row.names = FALSE)
cat(" Scores saved to:", scores_output, "\n")

# Save variance explained
var_df <- data.frame(
 PC = paste0("PC",1:length(variance_explained)),
 Variance_Explained = variance_explained,
 Cumulative_Variance = cumulative_variance,
 Std_Dev = pca_result$sdev
)
var_output <- file.path(OUTPUT_DIR, "pca_variance_explained.csv")
write.csv(var_df, var_output, row.names = FALSE)
cat(" Variance explained saved to:", var_output, "\n")

# Save loadings (top features per PC)
loadings_df <- as.data.frame(pca_result$rotation[,1:3])
loadings_output <- file.path(OUTPUT_DIR, "pca_loadings.csv")
loadings_df$Feature <- rownames(loadings_df)
write.csv(loadings_df[, c("Feature", "PC1", "PC2", "PC3")], 
 loadings_output, row.names = FALSE)
cat(" Loadings saved to:", loadings_output, "\n")

# ----9. Calculate Weighted Euclidean Distances ----
cat("\n[9] Calculating weighted Euclidean distances to group centroids...\n")

# Use top3 PCs for weighted distance
n_pcs_used <-3
weights <- variance_explained[1:n_pcs_used] / sum(variance_explained[1:n_pcs_used])
cat(" PC weights (based on variance explained):\n")
for (i in 1:n_pcs_used) {
 cat(sprintf(" PC%d: %.4f\n", i, weights[i]))
}

# Calculate group centroids (mean scores per group)
groups <- levels(sample_meta$group_label)
centroids <- matrix(NA, nrow = length(groups), ncol = n_pcs_used)
rownames(centroids) <- groups
colnames(centroids) <- paste0("PC",1:n_pcs_used)

for (g in groups) {
 idx <- which(pca_scores$Group == g)
 centroids[g, ] <- colMeans(pca_scores[idx, paste0("PC",1:n_pcs_used)])
}

cat(" Group centroids (first3 PCs):\n")
print(round(centroids,4))

# Calculate weighted Euclidean distance for each sample to its group centroid
weighted_distances <- data.frame(
 SampleID = pca_scores$SampleID,
 SampleName = pca_scores$SampleName,
 Group = pca_scores$Group,
 stringsAsFactors = FALSE
)

for (i in 1:nrow(pca_scores)) {
 sample_group <- as.character(pca_scores$Group[i])
 centroid <- centroids[sample_group, ]
 score_vector <- as.numeric(pca_scores[i, paste0("PC",1:n_pcs_used)])
  
 # Weighted Euclidean distance
 diff_sq <- (score_vector - centroid)^2
 weighted_distances$Distance_To_Centroid[i] <- sqrt(sum(weights * diff_sq))
}

cat(" Distance statistics:\n")
cat(sprintf(" Min: %.4f\n", min(weighted_distances$Distance_To_Centroid)))
cat(sprintf(" Max: %.4f\n", max(weighted_distances$Distance_To_Centroid)))
cat(sprintf(" Mean: %.4f\n", mean(weighted_distances$Distance_To_Centroid)))

# Save weighted distances
dist_output <- file.path(OUTPUT_DIR, "pca_weighted_distances.csv")
write.csv(weighted_distances, dist_output, row.names = FALSE)
cat(" Weighted distances saved to:", dist_output, "\n")

# ----10. Permutation Test ----
cat("\n[10] Performing permutation test (n=1000)...\n")

# Calculate observed mean within-group distance
mean_within_observed <- mean(weighted_distances$Distance_To_Centroid)

# Calculate observed mean between-group distances
# For each sample, calculate distance to centroids of OTHER groups
between_distances <- c()
for (i in 1:nrow(pca_scores)) {
 sample_group <- as.character(pca_scores$Group[i])
 other_groups <- setdiff(groups, sample_group)
 score_vector <- as.numeric(pca_scores[i, paste0("PC",1:n_pcs_used)])
  
 for (g in other_groups) {
 centroid <- centroids[g, ]
 diff_sq <- (score_vector - centroid)^2
 between_distances <- c(between_distances, sqrt(sum(weights * diff_sq)))
 }
}
mean_between_observed <- mean(between_distances)
observed_ratio <- mean_within_observed / mean_between_observed

cat(sprintf(" Observed mean within-group distance: %.4f\n", mean_within_observed))
cat(sprintf(" Observed mean between-group distance: %.4f\n", mean_between_observed))
cat(sprintf(" Observed within/between ratio: %.4f\n", observed_ratio))

# Permutation test
set.seed(42)
n_perm <-1000
perm_ratios <- numeric(n_perm)

for (p in 1:n_perm) {
 # Permute group labels
 perm_labels <- sample(sample_meta$group_label)
  
 # Calculate permuted centroids
 perm_centroids <- matrix(NA, nrow = length(groups), ncol = n_pcs_used)
 rownames(perm_centroids) <- groups
 colnames(perm_centroids) <- paste0("PC",1:n_pcs_used)
  
 for (g in groups) {
 idx <- which(perm_labels == g)
 perm_centroids[g, ] <- colMeans(pca_scores[idx, paste0("PC",1:n_pcs_used)])
 }
  
 # Calculate permuted within-group distances
 perm_within_dists <- numeric(nrow(pca_scores))
 for (i in 1:nrow(pca_scores)) {
 sample_group <- as.character(perm_labels[i])
 centroid <- perm_centroids[sample_group, ]
 score_vector <- as.numeric(pca_scores[i, paste0("PC",1:n_pcs_used)])
 diff_sq <- (score_vector - centroid)^2
 perm_within_dists[i] <- sqrt(sum(weights * diff_sq))
 }
  
 # Calculate permuted between-group distances
 perm_between_dists <- c()
 for (i in 1:nrow(pca_scores)) {
 sample_group <- as.character(perm_labels[i])
 other_groups <- setdiff(groups, sample_group)
 score_vector <- as.numeric(pca_scores[i, paste0("PC",1:n_pcs_used)])
    
 for (g in other_groups) {
 centroid <- perm_centroids[g, ]
 diff_sq <- (score_vector - centroid)^2
 perm_between_dists <- c(perm_between_dists, sqrt(sum(weights * diff_sq)))
 }
 }
  
 perm_ratios[p] <- mean(perm_within_dists) / mean(perm_between_dists)
}

# Calculate p-value (one-tailed: observed ratio < permuted ratios?)
p_value_within_less <- sum(perm_ratios <= observed_ratio) / n_perm
# Also calculate p-value for observed ratio being different from expected
p_value_two_sided <-2 * min(p_value_within_less,1 - p_value_within_less)

cat(sprintf(" Permutation test results (n=%d):\n", n_perm))
cat(sprintf(" Observed within/between ratio: %.4f\n", observed_ratio))
cat(sprintf(" Mean permuted ratio: %.4f\n", mean(perm_ratios)))
cat(sprintf(" Permuted ratio95%% CI: [%.4f, %.4f]\n", 
 quantile(perm_ratios,0.025), quantile(perm_ratios,0.975)))
cat(sprintf(" P-value (one-sided, within < between): %.4f\n", p_value_within_less))

# Save permutation results
perm_results <- data.frame(
 Metric = c("Observed_Ratio", "Mean_Permuted_Ratio", 
 "Perm_2.5%", "Perm_97.5%",
 "P_Value_OneSided", "P_Value_TwoSided"),
 Value = c(observed_ratio, mean(perm_ratios),
 quantile(perm_ratios,0.025), quantile(perm_ratios,0.975),
 p_value_within_less, p_value_two_sided)
)
perm_output <- file.path(OUTPUT_DIR, "permutation_test_results.csv")
write.csv(perm_results, perm_output, row.names = FALSE)
cat(" Permutation results saved to:", perm_output, "\n")

# ----11. Generate PCA Scatter Plots ----
cat("\n[11] Generating PCA scatter plots...\n")

# Color palette for groups
group_colors <- c("NC" = "#4DBBD5", # Blue
 "CD" = "#E64B35", # Red
 "FE" = "#00A087") # Green

# Shape palette for sample types (using sample_info for shapes)
sample_types <- levels(sample_meta$sample_info)
n_types <- length(sample_types)
shape_values <- c(16,17,15,18,8,3,4) # Various point shapes
names(shape_values) <- sample_types[1:min(n_types, length(shape_values))]

# Add shape mapping to scores
pca_scores$SampleType <- sample_meta[rownames(pca_scores), "sample_info"]

# ----11a. PC1 vs PC2 ----
cat(" Plotting PCA PC1 vs PC2...\n")

var_pc1 <- variance_explained[1] *100
var_pc2 <- variance_explained[2] *100

p_pc12 <- ggplot(pca_scores, aes(x = PC1, y = PC2, 
 color = Group, 
 shape = SampleType)) +
 geom_point(size =3.5, alpha =0.85) +
 stat_ellipse(level =0.95, type = "t", linewidth =0.8, 
 aes(fill = Group), alpha =0.1, geom = "polygon") +
 geom_text_repel(aes(label = SampleName), size =3.0, 
 max.overlaps =20, box.padding =0.5,
 show.legend = FALSE) +
 scale_color_manual(values = group_colors, 
 labels = c("NC" = "NC (Healthy Control)",
 "CD" = "CD (C. diff Infection)",
 "FE" = "FE (High Iron + CDI)")) +
 scale_fill_manual(values = group_colors, guide = "none") +
 scale_shape_manual(values = shape_values) +
 labs(title = "PCA Score Plot (PC1 vs PC2)",
 subtitle = paste0("Total variance explained: ", 
 round(var_pc1 + var_pc2,1), "%"),
 x = paste0("PC1 (", round(var_pc1,1), "%)"),
 y = paste0("PC2 (", round(var_pc2,1), "%)"),
 color = "Group", shape = "Condition") +
 theme_bw(base_size =12) +
 theme(
 plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 plot.subtitle = element_text(hjust =0.5, size =10, color = "grey40"),
 legend.position = "right",
 legend.title = element_text(size =10, face = "bold"),
 legend.text = element_text(size =9),
 panel.grid.minor = element_blank()
 )

# Save PC1 vs PC2
ggsave(filename = file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC2.png"),
 plot = p_pc12, width =9, height =7, dpi =300)
ggsave(filename = file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC2.pdf"),
 plot = p_pc12, width =9, height =7)
cat(" Saved PCA PC1 vs PC2 plot.\n")

# ----11b. PC1 vs PC3 ----
cat(" Plotting PCA PC1 vs PC3...\n")

var_pc3 <- variance_explained[3] *100

p_pc13 <- ggplot(pca_scores, aes(x = PC1, y = PC3, 
 color = Group, 
 shape = SampleType)) +
 geom_point(size =3.5, alpha =0.85) +
 stat_ellipse(level =0.95, type = "t", linewidth =0.8, 
 aes(fill = Group), alpha =0.1, geom = "polygon") +
 geom_text_repel(aes(label = SampleName), size =3.0, 
 max.overlaps =20, box.padding =0.5,
 show.legend = FALSE) +
 scale_color_manual(values = group_colors,
 labels = c("NC" = "NC (Healthy Control)",
 "CD" = "CD (C. diff Infection)",
 "FE" = "FE (High Iron + CDI)")) +
 scale_fill_manual(values = group_colors, guide = "none") +
 scale_shape_manual(values = shape_values) +
 labs(title = "PCA Score Plot (PC1 vs PC3)",
 subtitle = paste0("Total variance explained: ", 
 round(var_pc1 + var_pc3,1), "%"),
 x = paste0("PC1 (", round(var_pc1,1), "%)"),
 y = paste0("PC3 (", round(var_pc3,1), "%)"),
 color = "Group", shape = "Condition") +
 theme_bw(base_size =12) +
 theme(
 plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 plot.subtitle = element_text(hjust =0.5, size =10, color = "grey40"),
 legend.position = "right",
 legend.title = element_text(size =10, face = "bold"),
 legend.text = element_text(size =9),
 panel.grid.minor = element_blank()
 )

# Save PC1 vs PC3
ggsave(filename = file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC3.png"),
 plot = p_pc13, width =9, height =7, dpi =300)
ggsave(filename = file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC3.pdf"),
 plot = p_pc13, width =9, height =7)
cat(" Saved PCA PC1 vs PC3 plot.\n")

# ----11c. PC2 vs PC3 (bonus) ----
cat(" Plotting PCA PC2 vs PC3...\n")

p_pc23 <- ggplot(pca_scores, aes(x = PC2, y = PC3, 
 color = Group, 
 shape = SampleType)) +
 geom_point(size =3.5, alpha =0.85) +
 stat_ellipse(level =0.95, type = "t", linewidth =0.8, 
 aes(fill = Group), alpha =0.1, geom = "polygon") +
 geom_text_repel(aes(label = SampleName), size =3.0, 
 max.overlaps =20, box.padding =0.5,
 show.legend = FALSE) +
 scale_color_manual(values = group_colors,
 labels = c("NC" = "NC (Healthy Control)",
 "CD" = "CD (C. diff Infection)",
 "FE" = "FE (High Iron + CDI)")) +
 scale_fill_manual(values = group_colors, guide = "none") +
 scale_shape_manual(values = shape_values) +
 labs(title = "PCA Score Plot (PC2 vs PC3)",
 subtitle = paste0("Total variance explained: ", 
 round(var_pc2 + var_pc3,1), "%"),
 x = paste0("PC2 (", round(var_pc2,1), "%)"),
 y = paste0("PC3 (", round(var_pc3,1), "%)"),
 color = "Group", shape = "Condition") +
 theme_bw(base_size =12) +
 theme(
 plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 plot.subtitle = element_text(hjust =0.5, size =10, color = "grey40"),
 legend.position = "right",
 legend.title = element_text(size =10, face = "bold"),
 legend.text = element_text(size =9),
 panel.grid.minor = element_blank()
 )

# Save PC2 vs PC3
ggsave(filename = file.path(FIGURE_DIR, "PCA_score_plot_PC2_vs_PC3.png"),
 plot = p_pc23, width =9, height =7, dpi =300)
ggsave(filename = file.path(FIGURE_DIR, "PCA_score_plot_PC2_vs_PC3.pdf"),
 plot = p_pc23, width =9, height =7)
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

ggsave(filename = file.path(FIGURE_DIR, "PCA_scree_plot.png"),
 plot = p_scree, width =8, height =5, dpi =300)
ggsave(filename = file.path(FIGURE_DIR, "PCA_scree_plot.pdf"),
 plot = p_scree, width =8, height =5)
cat(" Scree plot saved.\n")

# ----13. Generate Summary Statistics ----
cat("\n[13] Generating PCA summary statistics...\n")

# Calculate mean distances per group
group_dist_summary <- aggregate(Distance_To_Centroid ~ Group, 
 data = weighted_distances, 
 FUN = function(x) c(Mean = mean(x), SD = sd(x), 
 Min = min(x), Max = max(x)))
cat(" Group distance summary:\n")
print(group_dist_summary)

# Calculate pairwise separation (distance between centroids)
pairwise_dist <- dist(centroids)
cat(" Pairwise centroid distances (Euclidean, weighted space):\n")
print(round(as.matrix(pairwise_dist),4))

# ----14. Script Completion ----
cat("\n=====================================================\n")
cat(" PCA Analysis Completed Successfully!\n")
cat("=====================================================\n")
cat("\nOutput files:\n")
cat(" CSV files:\n")
cat(" ", scores_output, "\n")
cat(" ", var_output, "\n")
cat(" ", loadings_output, "\n")
cat(" ", dist_output, "\n")
cat(" ", perm_output, "\n")
cat(" Figures:\n")
cat(" ", file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC2.png"), "\n")
cat(" ", file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC2.pdf"), "\n")
cat(" ", file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC3.png"), "\n")
cat(" ", file.path(FIGURE_DIR, "PCA_score_plot_PC1_vs_PC3.pdf"), "\n")
cat(" ", file.path(FIGURE_DIR, "PCA_score_plot_PC2_vs_PC3.png"), "\n")
cat(" ", file.path(FIGURE_DIR, "PCA_score_plot_PC2_vs_PC3.pdf"), "\n")
cat(" ", file.path(FIGURE_DIR, "PCA_scree_plot.png"), "\n")
cat(" ", file.path(FIGURE_DIR, "PCA_scree_plot.pdf"), "\n")
cat("\nKey findings:\n")
cat(sprintf(" PC1 explains %.1f%% of variance\n", var_pc1))
cat(sprintf(" PC2 explains %.1f%% of variance\n", var_pc2))
cat(sprintf(" PC3 explains %.1f%% of variance\n", var_pc3))
cat(sprintf(" Top3 PCs explain %.1f%% of total variance\n", 
 sum(variance_explained[1:3]) *100))
cat(sprintf(" Permutation test p-value: %.4f\n", p_value_within_less))
if (p_value_within_less <0.05) {
 cat(" => Group separation is statistically significant (p <0.05)\n")
} else {
 cat(" => Group separation is NOT statistically significant (p >=0.05)\n")
}
cat("\nDone.\n")
