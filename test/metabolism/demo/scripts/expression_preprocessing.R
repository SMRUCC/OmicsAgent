###############################################################################
# Expression Matrix Preprocessing Script
# 
# This script preprocesses the untargeted metabolomics LC-MS expression matrix
# (2059 metabolites x18 samples) by:
#1. Loading and parsing raw expression data
#2. Handling missing values (filtering + imputation)
#3. Normalizing to relative abundance (sample-sum normalization)
#4. Performing median scaling per molecule
#5. Generating quality control visualizations
#
# Research: High-iron diet effects on Clostridioides difficile infection (CDI)
# Dataset: Untargeted metabolomics LC-MS data
# Author: Bioinformatics R Script
###############################################################################

# ============================================================================
#0. Setup Environment and Paths
# ============================================================================

cat("========================================\n")
cat(" EXPRESSION MATRIX PREPROCESSING\n")
cat("========================================\n\n")

# ---- Working directories ----
workspace_root <- "G:/OmicsWorks/test/metabolism/demo"
tmp_dir <- file.path(workspace_root, "tmp", "1_expression_matrix_preprocessing")
fig_dir <- file.path(workspace_root, "analysis", "1_expression_matrix_preprocessing", "figures")
scripts_dir <- file.path(workspace_root, "scripts")
rscript_tools <- "G:/OmicsWorks/agent/rscript"

# Create output directories if they don't exist
dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

cat("[INFO] Output directory (CSV):", tmp_dir, "\n")
cat("[INFO] Output directory (figures):", fig_dir, "\n\n")

# ---- Load helper scripts from rscript tools ----
source(file.path(rscript_tools, "data_io.R"))
source(file.path(rscript_tools, "missing_value.R"))
source(file.path(rscript_tools, "normalization.R"))
source(file.path(rscript_tools, "visualization.R"))
source(file.path(rscript_tools, "qcqa.R"))

# ---- Load/install required R packages ----
required_packages <- c("ggplot2", "pheatmap", "RColorBrewer", "reshape2", "ggrepel")
for (pkg in required_packages) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 install.packages(pkg, repos = "https://cran.r-project.org")
 }
 library(pkg, character.only = TRUE)
}

cat("[INFO] All required packages loaded.\n\n")

# ============================================================================
#1. Load Expression Matrix and Sample Metadata
# ============================================================================

cat("------------------------------------------------\n")
cat("1. LOADING DATA\n")
cat("------------------------------------------------\n\n")

# ---- File paths ----
expression_file <- "G:/OmicsWorks/test/metabolism/expression.csv"
sampleinfo_file <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"
metabolite_anno_file <- "G:/OmicsWorks/test/metabolism/metabolites.csv"

# ---- Load expression matrix ----
cat("[STEP1.1] Loading expression matrix from:", expression_file, "\n")

# Read raw CSV - first column has empty header (the molecule IDs)
raw_expr <- read.csv(expression_file, stringsAsFactors = FALSE, check.names = FALSE)
cat(" Raw dimensions:", nrow(raw_expr), "rows x", ncol(raw_expr), "cols\n")
cat(" Column names:", paste(head(colnames(raw_expr)), collapse = ", "), "...\n")

# The first column (empty name "") contains molecule identifiers
molecule_ids <- as.character(raw_expr[,1])
cat(" First few molecule IDs:", paste(head(molecule_ids), collapse = ", "), "\n")

# Extract sample columns (columns2 through19 = all18 samples)
sample_cols <- colnames(raw_expr)[-1]
cat(" Sample columns (", length(sample_cols), " total):\n")
cat(" ", paste(sample_cols, collapse = ", "), "\n")

# Build numeric expression matrix
expr_matrix <- as.matrix(raw_expr[, -1])
rownames(expr_matrix) <- molecule_ids
colnames(expr_matrix) <- sample_cols
storage.mode(expr_matrix) <- "numeric"

cat(" Expression matrix dimensions:", dim(expr_matrix)[1], "metabolites x",
 dim(expr_matrix)[2], "samples\n")
cat(" Expression value range: [", round(min(expr_matrix, na.rm = TRUE),4), ",",
 round(max(expr_matrix, na.rm = TRUE),4), "]\n")

# ---- Load sample metadata ----
cat("\n[STEP1.2] Loading sample metadata from:", sampleinfo_file, "\n")
sample_meta <- load_sample_metadata(sampleinfo_file)
cat(" Metadata dimensions:", nrow(sample_meta), "samples x", ncol(sample_meta), "cols\n")
cat(" Sample info groups:\n")
print(table(sample_meta$sample_info))

# ---- Load metabolite annotation ----
cat("\n[STEP1.3] Loading metabolite annotation from:", metabolite_anno_file, "\n")
metabolite_anno <- read.csv(metabolite_anno_file, stringsAsFactors = FALSE, check.names = FALSE)
cat(" Annotation dimensions:", nrow(metabolite_anno), "metabolites x",
 ncol(metabolite_anno), "cols\n")
cat(" Annotation columns:", paste(colnames(metabolite_anno), collapse = ", "), "\n")

# ============================================================================
#2. Filter Samples: Remove QC Samples Not Present in Expression Matrix
# ============================================================================

cat("\n------------------------------------------------\n")
cat("2. SAMPLE FILTERING\n")
cat("------------------------------------------------\n\n")

cat("[STEP2.1] Identifying QC samples in metadata...\n")
qc_samples_meta <- sample_meta$ID[sample_meta$sample_info == "QC"]
cat(" QC samples in metadata:", paste(qc_samples_meta, collapse = ", "), "\n")

cat("[STEP2.2] Checking which QC samples exist in expression matrix...\n")
qc_in_expr <- intersect(qc_samples_meta, colnames(expr_matrix))
cat(" QC samples found in expression matrix:", length(qc_in_expr), "\n")
if (length(qc_in_expr) >0) {
 cat(" Present:", paste(qc_in_expr, collapse = ", "), "\n")
} else {
 cat(" None found (all QC samples absent from expression matrix).\n")
}

# Filter metadata to only keep samples present in expression matrix
samples_in_expr <- intersect(sample_meta$ID, colnames(expr_matrix))
cat("\n[STEP2.3] Filtering metadata to match expression matrix samples...\n")
cat(" Samples in both metadata and expression matrix:", length(samples_in_expr), "\n")
sample_meta_filtered <- sample_meta[sample_meta$ID %in% samples_in_expr, , drop = FALSE]

# Reorder metadata to match expression matrix column order
sample_meta_filtered <- sample_meta_filtered[match(colnames(expr_matrix),
 sample_meta_filtered$ID), ]
cat(" Final sample metadata dimensions:", nrow(sample_meta_filtered), "x",
 ncol(sample_meta_filtered), "\n")
cat(" Group distribution after filtering:\n")
print(table(sample_meta_filtered$sample_info))

# ============================================================================
#3. Missing Value Analysis and Handling
# ============================================================================

cat("\n------------------------------------------------\n")
cat("3. MISSING VALUE ANALYSIS\n")
cat("------------------------------------------------\n\n")

# ----3a. Missing value statistics ----
cat("[STEP3.1] Computing missing value statistics...\n")
na_stats <- get_missing_stats(expr_matrix)
cat(na_stats$summary, "\n")

# Per-sample missing ratio
sample_na_ratio <- colMeans(is.na(expr_matrix))
cat("\n Missing ratio per sample:\n")
for (s in names(sample_na_ratio)) {
 cat(sprintf(" %-20s: %5.2f%%\n", s, sample_na_ratio[s] *100))
}

# Per-group missing ratio
cat("\n Missing ratio per group:\n")
for (grp in levels(sample_meta_filtered$sample_info)) {
 grp_samples <- sample_meta_filtered$ID[sample_meta_filtered$sample_info == grp]
 grp_na <- mean(is.na(expr_matrix[, grp_samples, drop = FALSE]))
 cat(sprintf(" %-35s: %5.2f%%\n", grp, grp_na *100))
}

# ----3b. Visualize missing value pattern ----
cat("\n[STEP3.2] Generating missing value visualization...\n")

# Bar plot of missing ratio per sample
na_df <- data.frame(
 Sample = factor(names(sample_na_ratio), levels = names(sample_na_ratio)),
 MissingRatio = sample_na_ratio *100,
 Group = sample_meta_filtered$sample_info[match(names(sample_na_ratio),
 sample_meta_filtered$ID)]
)

p_na <- ggplot(na_df, aes(x = Sample, y = MissingRatio, fill = Group)) +
 geom_bar(stat = "identity") +
 geom_text(aes(label = sprintf("%.1f%%", MissingRatio)),
 vjust = -0.3, size =2.8) +
 scale_fill_brewer(palette = "Set2") +
 labs(title = "Missing Value Ratio per Sample",
 x = "Sample", y = "Missing Ratio (%)") +
 theme_bw() +
 theme(axis.text.x = element_text(angle =45, hjust =1, size =8),
 plot.title = element_text(hjust =0.5, face = "bold"))

ggsave(file.path(fig_dir, "Missing_ratio_per_sample.pdf"),
 p_na, width =10, height =6)
ggsave(file.path(fig_dir, "Missing_ratio_per_sample.png"),
 p_na, width =10, height =6, dpi =300)
cat(" Missing ratio plot saved to figures folder.\n")

# ----3c. Filter features by missing value threshold ----
cat("\n[STEP3.3] Filtering features with excessive missing values...\n")
cat(" Using group-based filtering with50% threshold...\n")

expr_filtered <- filter_missing_values(expr_matrix, sample_meta_filtered,
 threshold =0.5, method = "group")
cat(" After filtering:", nrow(expr_filtered), "features retained\n")
cat(" Removed:", nrow(expr_matrix) - nrow(expr_filtered), "features\n")

# ----3d. Impute remaining missing values ----
cat("\n[STEP3.4] Imputing remaining missing values (half-minimum strategy)...\n")
remaining_na <- sum(is.na(expr_filtered))
cat(" Remaining NA values:", remaining_na, "\n")

if (remaining_na >0) {
 expr_imputed <- impute_half_min(expr_filtered)
 cat(" Imputation complete. NA values remaining:", sum(is.na(expr_imputed)), "\n")
} else {
 cat(" No missing values to impute.\n")
 expr_imputed <- expr_filtered
}

# ============================================================================
#4. Log-Transformation Assessment
# ============================================================================

cat("\n------------------------------------------------\n")
cat("4. LOG-TRANSFORMATION ASSESSMENT\n")
cat("------------------------------------------------\n\n")

max_val <- max(expr_imputed, na.rm = TRUE)
min_pos_val <- min(expr_imputed[expr_imputed >0], na.rm = TRUE)
mean_val <- mean(expr_imputed, na.rm = TRUE)
median_val <- median(as.vector(expr_imputed), na.rm = TRUE)

cat(sprintf(" Expression value summary:\n"))
cat(sprintf(" Maximum value : %.4f\n", max_val))
cat(sprintf(" Minimum positive : %.4f\n", min_pos_val))
cat(sprintf(" Mean value : %.4f\n", mean_val))
cat(sprintf(" Median value : %.4f\n", median_val))

# Decision: data is on LC-MS raw intensity scale (max ~283).
# Typical log-transform threshold is when max >>1000 or data is heavily skewed.
# Here the dynamic range is moderate, so we skip log transformation.
cat("\n [DECISION] Log-transformation SKIPPED.\n")
cat(" Reason: The raw max value (", round(max_val,2), ") is moderate\n")
cat(" and the data is already on a linear semi-quantitative scale.\n")
cat(" Log-transform would compress biologically meaningful differences.\n")

# Generate distribution plot to confirm
expr_values <- as.vector(expr_imputed)
expr_values <- expr_values[expr_values >0 & is.finite(expr_values)]

p_dist <- ggplot(data.frame(value = expr_values), aes(x = value)) +
 geom_histogram(bins =60, fill = "steelblue", color = "black", alpha =0.7) +
 labs(title = "Distribution of Expression Values (Raw Scale)",
 subtitle = "Moderate dynamic range, log-transform not needed",
 x = "Expression Value", y = "Frequency") +
 theme_bw() +
 theme(plot.title = element_text(hjust =0.5, face = "bold"),
 plot.subtitle = element_text(hjust =0.5))

ggsave(file.path(fig_dir, "Expression_distribution_raw.pdf"),
 p_dist, width =8, height =5)
ggsave(file.path(fig_dir, "Expression_distribution_raw.png"),
 p_dist, width =8, height =5, dpi =300)
cat(" Distribution plot saved.\n")

# ============================================================================
#5. Sample-Sum Normalization (Relative Abundance)
# ============================================================================

cat("\n------------------------------------------------\n")
cat("5. SAMPLE-SUM NORMALIZATION (RELATIVE ABUNDANCE)\n")
cat("------------------------------------------------\n\n")

cat("[STEP5.1] Computing sample sums before normalization...\n")
sample_sums_before <- colSums(expr_imputed, na.rm = TRUE)
cat(" Sample sums range: [", round(min(sample_sums_before),2), ", ",
 round(max(sample_sums_before),2), "]\n")

cat("\n[STEP5.2] Performing sample-sum normalization (scale factor =1)...\n")
cat(" Using scale_factor =1 to keep values as relative proportions (0-1).\n")
expr_norm <- normalize_sample_sum(expr_imputed, scale_factor =1, pseudo_count =0)

# Verify normalization
sample_sums_after <- colSums(expr_norm, na.rm = TRUE)
cat("\n Verification - sample sums after normalization:\n")
cat(" All ~1.0:", all(abs(sample_sums_after -1.0) <1e-6), "\n")
cat(" Range: [", round(min(sample_sums_after),6), ",",
 round(max(sample_sums_after),6), "]\n")

# Compare before/after boxplot
expr_before_df <- melt(as.data.frame(expr_imputed))
colnames(expr_before_df) <- c("Sample", "Value")
expr_before_df$Stage <- "Before Normalization"

expr_after_df <- melt(as.data.frame(expr_norm))
colnames(expr_after_df) <- c("Sample", "Value")
expr_after_df$Stage <- "After Normalization"

compare_df <- rbind(
 cbind(expr_before_df, Group = rep(sample_meta_filtered$sample_info[
 match(expr_before_df$Sample, sample_meta_filtered$ID)], each =1)),
 cbind(expr_after_df, Group = rep(sample_meta_filtered$sample_info[
 match(expr_after_df$Sample, sample_meta_filtered$ID)], each =1))
)
compare_df$Stage <- factor(compare_df$Stage, levels = c("Before Normalization",
 "After Normalization"))

# Set zero values to NA for plotting
compare_df$Value[compare_df$Value ==0] <- NA

p_norm <- ggplot(na.omit(compare_df), aes(x = Sample, y = Value, fill = Group)) +
 geom_boxplot(outlier.size =0.5) +
 facet_wrap(~ Stage, scales = "free_y", nrow =2) +
 scale_fill_brewer(palette = "Set2") +
 labs(title = "Expression Distribution: Before vs After Normalization",
 x = "Sample", y = "Expression Value") +
 theme_bw() +
 theme(axis.text.x = element_text(angle =45, hjust =1, size =7),
 plot.title = element_text(hjust =0.5, face = "bold"),
 strip.text = element_text(face = "bold"))

ggsave(file.path(fig_dir, "Normalization_comparison.pdf"),
 p_norm, width =14, height =10)
ggsave(file.path(fig_dir, "Normalization_comparison.png"),
 p_norm, width =14, height =10, dpi =300)
cat(" Normalization comparison plot saved.\n")

# ============================================================================
#6. Median Scaling per Molecule (Feature)
# ============================================================================

cat("\n------------------------------------------------\n")
cat("6. FEATURE-MEDIAN SCALING\n")
cat("------------------------------------------------\n\n")

cat("[STEP6.1] Performing median scaling per molecule...\n")
cat(" For each metabolite, divide all values by the median across all samples.\n")
expr_scaled <- scale_feature_median(expr_norm, log_transform = FALSE)

cat("\n[STEP6.2] Checking scaled data properties...\n")
cat(" Scaled value range: [", round(min(expr_scaled, na.rm = TRUE),4), ",",
 round(max(expr_scaled, na.rm = TRUE),4), "]\n")
cat(" Median of all values:", round(median(as.vector(expr_scaled), na.rm = TRUE),4), "\n")

# Check that each feature's median is ~1
feature_medians_check <- apply(expr_scaled,1, median, na.rm = TRUE)
cat(" Feature medians range: [", round(min(feature_medians_check),4), ",",
 round(max(feature_medians_check),4), "]\n")
cat(" All feature medians ~1:",
 all(abs(feature_medians_check -1.0) <1e-6), "\n")

# ============================================================================
#7. Save Processed Data
# ============================================================================

cat("\n------------------------------------------------\n")
cat("7. SAVING PROCESSED DATA\n")
cat("------------------------------------------------\n\n")

# ----7a. Save all intermediate matrices ----

#1. Filtered + Imputed (raw scale)
cat("[STEP7.1] Saving filtered+imputed expression matrix...\n")
save_result_table(expr_imputed,
 file.path(tmp_dir, "01_expression_filtered_imputed.csv"))

#2. Normalized (relative abundance)
cat("[STEP7.2] Saving normalized expression matrix (relative abundance)...\n")
save_result_table(expr_norm,
 file.path(tmp_dir, "02_expression_normalized_relative_abundance.csv"))

#3. Median-scaled (final preprocessed data)
cat("[STEP7.3] Saving median-scaled expression matrix (final preprocessed)...\n")
save_result_table(expr_scaled,
 file.path(tmp_dir, "03_expression_median_scaled_final.csv"))

#4. Save preprocessing summary
cat("[STEP7.4] Saving preprocessing summary...\n")

summary_lines <- c(
 "=== EXPRESSION MATRIX PREPROCESSING SUMMARY ===",
 paste("Script run time:", Sys.time()),
 "",
 "--- Input Data ---",
 paste("Expression matrix:", expression_file),
 paste("Sample metadata:", sampleinfo_file),
 paste("Metabolite annotation:", metabolite_anno_file),
 paste("Original dimensions:", nrow(expr_matrix), "metabolites x",
 ncol(expr_matrix), "samples"),
 paste("Original groups:",
 paste(names(table(sample_meta_filtered$sample_info)), collapse = ", ")),
 "",
 "--- QC Sample Handling ---",
 paste("QC samples in metadata:",
 paste(qc_samples_meta, collapse = ", ")),
 paste("QC samples in expression matrix:",
 ifelse(length(qc_in_expr) >0, paste(qc_in_expr, collapse = ", "), "NONE")),
 paste("QC samples were excluded (not present in expression matrix)."),
 "",
 "--- Missing Value Handling ---",
 paste("Original missing ratio:", round(na_stats$overall_ratio *100,2), "%"),
 paste("Missing value filter: group-based, threshold =50%"),
 paste("Features before filter:", nrow(expr_matrix)),
 paste("Features after filter:", nrow(expr_filtered)),
 paste("Features removed:", nrow(expr_matrix) - nrow(expr_filtered)),
 paste("Imputation method: half-minimum positive value"),
 paste("NA values after imputation:", sum(is.na(expr_imputed))),
 "",
 "--- Log Transformation ---",
 paste("Max raw value:", round(max_val,4)),
 paste("Decision: SKIPPED (data already on linear semi-quantitative scale)"),
 "",
 "--- Normalization ---",
 paste("Method: Sample-sum (relative abundance)"),
 paste("Scale factor:1 (proportions)"),
 "",
 "--- Scaling ---",
 paste("Method: Feature-median scaling"),
 paste("Scaled value range: [", round(min(expr_scaled, na.rm = TRUE),4), ",",
 round(max(expr_scaled, na.rm = TRUE),4), "]"),
 "",
 "--- Output Files ---",
 paste("Filtered + Imputed:",
 file.path(tmp_dir, "01_expression_filtered_imputed.csv")),
 paste("Relative Abundance:",
 file.path(tmp_dir, "02_expression_normalized_relative_abundance.csv")),
 paste("Median Scaled (Final):",
 file.path(tmp_dir, "03_expression_median_scaled_final.csv")),
 "",
 "--- Figure Files ---",
 paste("Missing ratio plot:", file.path(fig_dir, "Missing_ratio_per_sample.pdf")),
 paste("Expression distribution:", file.path(fig_dir, "Expression_distribution_raw.pdf")),
 paste("Normalization comparison:", file.path(fig_dir, "Normalization_comparison.pdf")),
 "",
 "--- Final Preprocessed Data Summary ---",
 paste("Final dimensions:", nrow(expr_scaled), "metabolites x",
 ncol(expr_scaled), "samples"),
 paste("Sample groups in final data:"),
 paste(" Standard (control):",
 sum(sample_meta_filtered$sample_info == "Standard (control)"), "samples"),
 paste(" Clostridium difficile infection:",
 sum(sample_meta_filtered$sample_info == "Clostridium difficile infection"),
 "samples"),
 paste(" high iron diet before:",
 sum(sample_meta_filtered$sample_info == "high iron diet before"), "samples"),
 "",
 "--- Research Context ---",
 "This preprocessed data will be used for downstream differential analysis",
 "to identify metabolites mediating the protective effect of high-iron diet",
 "against CDI, particularly L-proline, TUDCA, bile acids, and SCFAs."
)

writeLines(summary_lines, file.path(tmp_dir, "preprocessing_summary.txt"))
cat(" Summary saved to:", file.path(tmp_dir, "preprocessing_summary.txt"), "\n")

# ============================================================================
#8. Generate Final QC Visualizations (Preprocessed Data)
# ============================================================================

cat("\n------------------------------------------------\n")
cat("8. FINAL QC VISUALIZATION\n")
cat("------------------------------------------------\n\n")

cat("[STEP8.1] Generating heatmap of median-scaled data (top50 most variable features)...\n")

# Select top50 most variable features
feature_vars <- apply(expr_scaled,1, var, na.rm = TRUE)
top_n <- min(50, length(feature_vars))
top50_features <- names(sort(feature_vars, decreasing = TRUE))[1:top_n]
expr_top50 <- expr_scaled[top50_features, ]

# Order samples by group
group_order <- order(sample_meta_filtered$sample_info)
expr_top50_ordered <- expr_top50[, group_order, drop = FALSE]
meta_ordered <- sample_meta_filtered[group_order, ]

# Column annotation
col_anno <- data.frame(
 Group = meta_ordered$sample_info,
 row.names = meta_ordered$ID
)
n_groups <- nlevels(meta_ordered$sample_info)
anno_colors <- list(
 Group = setNames(
 brewer.pal(max(n_groups,3), "Set2")[1:n_groups],
 levels(meta_ordered$sample_info)
 )
)

# Heatmap annotation labels
group_labels <- levels(meta_ordered$sample_info)
group_colors <- setNames(
 brewer.pal(max(length(group_labels),3), "Set2")[1:length(group_labels)],
 group_labels
)

cat(" Group colors for heatmap:\n")
for (g in names(group_colors)) {
 cat(sprintf(" %-35s: %s\n", g, group_colors[g]))
}

# Generate heatmap
pdf(file.path(fig_dir, "Heatmap_top50_median_scaled.pdf"), width =10, height =8)
pheatmap(expr_top50_ordered,
 cluster_rows = TRUE,
 cluster_cols = FALSE,
 annotation_col = col_anno,
 annotation_colors = anno_colors,
 show_rownames = TRUE,
 show_colnames = TRUE,
 color = colorRampPalette(c("#4DBBD5", "white", "#E64B35"))(100),
 fontsize_row =6,
 fontsize_col =8,
 border_color = NA,
 main = paste0("Top ", top_n, " Most Variable Metabolites\n(Median-Scaled Relative Abundance)"),
 scale = "none")
dev.off()
cat(" Heatmap PDF saved.\n")

png(file.path(fig_dir, "Heatmap_top50_median_scaled.png"),
 width =10, height =8, units = "in", res =300)
pheatmap(expr_top50_ordered,
 cluster_rows = TRUE,
 cluster_cols = FALSE,
 annotation_col = col_anno,
 annotation_colors = anno_colors,
 show_rownames = TRUE,
 show_colnames = TRUE,
 color = colorRampPalette(c("#4DBBD5", "white", "#E64B35"))(100),
 fontsize_row =6,
 fontsize_col =8,
 border_color = NA,
 main = paste0("Top ", top_n, " Most Variable Metabolites\n(Median-Scaled Relative Abundance)"),
 scale = "none")
dev.off()
cat(" Heatmap PNG saved.\n")

# ---- PCA Plot ----
cat("\n[STEP8.2] Generating PCA plot of preprocessed data...\n")

# Transpose: samples as rows, features as columns
expr_t <- t(expr_scaled)
pca_result <- prcomp(expr_t, center = TRUE, scale. = FALSE, rank. =5)
pca_var <- summary(pca_result)$importance[2,1:3] *100

pca_df <- data.frame(
 PC1 = pca_result$x[,1],
 PC2 = pca_result$x[,2],
 Sample = rownames(pca_result$x),
 Group = sample_meta_filtered$sample_info[match(rownames(pca_result$x),
 sample_meta_filtered$ID)]
)

p_pca <- ggplot(pca_df, aes(x = PC1, y = PC2, color = Group, label = Sample)) +
 geom_point(size =3, alpha =0.8) +
 geom_text_repel(size =3, show.legend = FALSE, max.overlaps =15) +
 scale_color_brewer(palette = "Set2") +
 labs(title = "PCA of Preprocessed Expression Data",
 subtitle = "Median-scaled relative abundance",
 x = sprintf("PC1 (%.1f%%)", pca_var[1]),
 y = sprintf("PC2 (%.1f%%)", pca_var[2])) +
 theme_bw() +
 theme(plot.title = element_text(hjust =0.5, face = "bold"),
 plot.subtitle = element_text(hjust =0.5))

ggsave(file.path(fig_dir, "PCA_preprocessed_data.pdf"),
 p_pca, width =8, height =6)
ggsave(file.path(fig_dir, "PCA_preprocessed_data.png"),
 p_pca, width =8, height =6, dpi =300)
cat(" PCA plot saved.\n")

# ============================================================================
#9. Check for Key Metabolites from Research Background
# ============================================================================

cat("\n------------------------------------------------\n")
cat("9. KEY METABOLITE CHECK\n")
cat("------------------------------------------------\n\n")

# Define key metabolites from research context
key_metabolites_list <- c(
 "L-Proline", "Proline", "L-proline",
 "TUDCA", "Tauroursodeoxycholic acid",
 "Taurocholate", "Glycocholate", "Cholate",
 "Chenodeoxycholate", "Lithocholate", "Deoxycholate",
 "Butyrate", "Acetate", "Propionate", "Lactate",
 "SCFA", "Short-chain fatty acid",
 "Iron", "Fe2+", "Fe3+",
 "Calprotectin", "S100A8", "S100A9",
 "Lipocalin-2", "LCN2"
)

# Search in metabolite annotation names
if ("name" %in% colnames(metabolite_anno)) {
 cat("[STEP9.1] Searching for key metabolites in annotation file...\n")
 anno_names <- tolower(metabolite_anno$name)
 found_list <- list()
  
 for (km in key_metabolites_list) {
 km_lower <- tolower(km)
 match_idx <- grep(km_lower, anno_names, ignore.case = TRUE)
 if (length(match_idx) >0) {
 found_df <- metabolite_anno[match_idx, c("name", "id", "formula", "kegg")]
 found_df$SearchTerm <- km
 found_list[[km]] <- found_df
 cat(sprintf(" '%s' found in %d metabolite(s):\n", km, length(match_idx)))
 n_show <- min(length(match_idx),3)
 for (j in seq_len(n_show)) {
 cat(sprintf(" - %s (ID: %s)\n",
 metabolite_anno$name[match_idx[j]],
 metabolite_anno$id[match_idx[j]]))
 }
 if (length(match_idx) >3) {
 cat(sprintf(" ... and %d more\n", length(match_idx) -3))
 }
 }
 }
  
 if (length(found_list) >0) {
 found_all <- do.call(rbind, found_list)
 write.csv(found_all,
 file.path(tmp_dir, "key_metabolites_search_results.csv"),
 row.names = FALSE)
 cat("\n Search results saved to:",
 file.path(tmp_dir, "key_metabolites_search_results.csv"), "\n")
 } else {
 cat("\n No key metabolites found by name search.\n")
 cat(" (They may be annotated under different names / IUPAC names)\n")
 }
}

# Also check if any key metabolite IDs are in the expression matrix
cat("\n[STEP9.2] Checking metabolite annotation coverage...\n")
expr_ids <- rownames(expr_scaled)
anno_ids <- metabolite_anno$id
matched_ids <- intersect(expr_ids, anno_ids)
cat(" Metabolites with annotation:", length(matched_ids), "/", nrow(expr_scaled), "\n")
cat(" Annotation rate:", sprintf("%.1f%%",100 * length(matched_ids) / nrow(expr_scaled)), "\n")

# ============================================================================
#10. Complete
# ============================================================================

cat("\n========================================\n")
cat(" PREPROCESSING COMPLETE\n")
cat("========================================\n\n")
cat("Output files:\n")
cat(" CSV:\n")
cat(" ", file.path(tmp_dir, "01_expression_filtered_imputed.csv"), "\n")
cat(" ", file.path(tmp_dir, "02_expression_normalized_relative_abundance.csv"), "\n")
cat(" ", file.path(tmp_dir, "03_expression_median_scaled_final.csv"), "\n")
cat(" ", file.path(tmp_dir, "preprocessing_summary.txt"), "\n")
cat(" Figures:\n")
cat(" ", file.path(fig_dir, "Missing_ratio_per_sample.pdf/png"), "\n")
cat(" ", file.path(fig_dir, "Expression_distribution_raw.pdf/png"), "\n")
cat(" ", file.path(fig_dir, "Normalization_comparison.pdf/png"), "\n")
cat(" ", file.path(fig_dir, "Heatmap_top50_median_scaled.pdf/png"), "\n")
cat(" ", file.path(fig_dir, "PCA_preprocessed_data.pdf/png"), "\n")
cat("\nReady for downstream differential analysis.\n")
cat("Final dataset:", nrow(expr_scaled), "metabolites x",
 ncol(expr_scaled), "samples\n")
cat("Groups:", paste(levels(sample_meta_filtered$sample_info), collapse = ", "), "\n")
cat("\n========================================\n")
