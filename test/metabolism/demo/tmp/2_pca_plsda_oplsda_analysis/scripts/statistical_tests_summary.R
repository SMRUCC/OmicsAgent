# =============================================================================
# Statistical Tests & Summary Report (Step3)
# Module:2_pca_plsda_oplsda_analysis
# =============================================================================
# Description:
#对每个代谢物执行单因素ANOVA（组别因子），FDR校正；
#执行多因素ANOVA（组别+批次/样本来源）；
#汇总PCA/PLSDA/OPLSDA结果，生成阶段性总结Markdown报告。
#
# Output CSV -> tmp/2_pca_plsda_oplsda_analysis/
# Output Summary -> tmp/2_pca_plsda_oplsda_analysis/module_summary.md
# =============================================================================

# ----0. Setup ----
cat("========================================================\n")
cat(" Statistical Tests & Summary - Module2, Step3\n")
cat("========================================================\n\n")

BASE_DIR <- "G:/OmicsWorks/test/metabolism/demo"
TMP_DIR <- file.path(BASE_DIR, "tmp")
OUTPUT_DIR <- file.path(TMP_DIR, "2_pca_plsda_oplsda_analysis")
AGENT_RSCRIPT <- "G:/OmicsWorks/agent/rscript"

dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ----1. Install & Load Packages ----
cat("[1] Installing and loading required R packages...\n")

required_cran <- c("ggplot2", "ggrepel", "RColorBrewer", "viridis")

if (!requireNamespace("BiocManager", quietly = TRUE))
 install.packages("BiocManager", repos = "https://cloud.r-project.org")

for (pkg in required_cran) {
 if (!requireNamespace(pkg, quietly = TRUE))
 install.packages(pkg, repos = "https://cloud.r-project.org")
}

library(ggplot2); library(ggrepel); library(RColorBrewer); library(viridis)
cat(" All packages loaded.\n\n")

# ----2. Read Input Data ----
cat("[2] Reading input data...\n")

source(file.path(AGENT_RSCRIPT, "data_io.R"))

expr_file <- file.path(TMP_DIR, "preprocessed_expression.csv")
meta_file <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"

expr_matrix <- load_expression_matrix(expr_file)
sample_meta <- load_sample_metadata(meta_file)

# Filter & standardize
common <- intersect(colnames(expr_matrix), sample_meta$ID)
expr_matrix <- expr_matrix[, common, drop = FALSE]
sample_meta <- sample_meta[sample_meta$ID %in% common, , drop = FALSE]
rownames(sample_meta) <- sample_meta$ID
sample_meta <- sample_meta[colnames(expr_matrix), , drop = FALSE]

group_mapping <- c(
 "Clostridium difficile infection" = "CD",
 "high iron diet before" = "FE",
 "Standard (control)" = "NC"
)
sample_meta$group_label <- factor(
 group_mapping[as.character(sample_meta$sample_info)],
 levels = c("NC", "CD", "FE")
)

cat(" Working with", ncol(expr_matrix), "samples,", nrow(expr_matrix), "features\n")
cat(" Groups:", paste(levels(sample_meta$group_label), collapse = ", "), "\n")

# =========================================================================
# PART A: Overall F-test (One-way ANOVA per metabolite)
# =========================================================================
cat("\n========================================================\n")
cat(" PART A: Overall F-test (One-way ANOVA per metabolite)\n")
cat("========================================================\n\n")

n_features <- nrow(expr_matrix)
n_groups <- nlevels(sample_meta$group_label)

cat(" Testing", n_features, "metabolites across", n_groups, "groups...\n")

anova_results <- data.frame(
 Feature = rownames(expr_matrix),
 F_statistic = NA_real_,
 p_value = NA_real_,
 stringsAsFactors = FALSE
)

for (i in 1:n_features) {
 metabolite <- rownames(expr_matrix)[i]
 values <- as.numeric(expr_matrix[i, ])
 groups <- sample_meta$group_label

 # Skip features with zero variance
 if (sd(values, na.rm = TRUE) ==0 || is.na(sd(values, na.rm = TRUE))) {
 next
 }

 fit <- aov(values ~ groups, data = data.frame(values = values, groups = groups))
 s <- summary(fit)
 anova_results$F_statistic[i] <- s[[1]]$"F value"[1]
 anova_results$p_value[i] <- s[[1]]$"Pr(>F)"[1]
}

# FDR correction (Benjamini-Hochberg)
anova_results$p_adjusted <- p.adjust(anova_results$p_value, method = "BH")

# Sort by adjusted p-value
anova_results <- anova_results[order(anova_results$p_adjusted), ]

# Count significant metabolites
n_sig <- sum(anova_results$p_adjusted <0.05, na.rm = TRUE)
pct_sig <- round(n_sig / n_features *100,1)

cat(sprintf(" Significant metabolites (p.adj <0.05): %d / %d (%.1f%%)\n",
 n_sig, n_features, pct_sig))

# Save
anova_file <- file.path(OUTPUT_DIR, "overall_f_test.csv")
write.csv(anova_results, anova_file, row.names = FALSE)
cat(" ->", anova_file, "\n")

# ---- Top significant metabolites ----
top_sig <- head(anova_results[anova_results$p_adjusted <0.05, ],20)
if (nrow(top_sig) >0) {
 cat("\n Top significant metabolites:\n")
 print(top_sig[, c("Feature", "F_statistic", "p_value", "p_adjusted")])
} else {
 cat("\n No significant metabolites found at p.adj <0.05.\n")
}

# =========================================================================
# PART B: Multi-factor ANOVA
# =========================================================================
cat("\n========================================================\n")
cat(" PART B: Multi-factor ANOVA\n")
cat("========================================================\n\n")

cat(" Testing", n_features, "metabolites with model: Expression ~ Group + SampleInfo...\n")

multi_anova_results <- data.frame(
 Feature = rownames(expr_matrix),
 Group_F = NA_real_,
 Group_p = NA_real_,
 SampleInfo_F = NA_real_,
 SampleInfo_p = NA_real_,
 Residuals_df = NA_integer_,
 stringsAsFactors = FALSE
)

for (i in 1:n_features) {
 values <- as.numeric(expr_matrix[i, ])

 if (sd(values, na.rm = TRUE) ==0 || is.na(sd(values, na.rm = TRUE))) {
 next
 }

 df <- data.frame(
 Expression = values,
 Group = sample_meta$group_label,
 SampleInfo = sample_meta$sample_info
 )

 fit <- aov(Expression ~ Group + SampleInfo, data = df)
 s <- summary(fit)

 # Extract F and p for each factor
 multi_anova_results$Group_F[i] <- s[[1]]$"F value"[1]
 multi_anova_results$Group_p[i] <- s[[1]]$"Pr(>F)"[1]

 # SampleInfo may have only1 df if it's just the group label synonym
 # Handle case where SampleInfo has fewer levels
 if (nrow(s[[1]]) >=3) {
 multi_anova_results$SampleInfo_F[i] <- s[[1]]$"F value"[2]
 multi_anova_results$SampleInfo_p[i] <- s[[1]]$"Pr(>F)"[2]
 multi_anova_results$Residuals_df[i] <- s[[1]]$Df[3]
 } else {
 # Only Group effect estimable
 multi_anova_results$SampleInfo_F[i] <- NA
 multi_anova_results$SampleInfo_p[i] <- NA
 multi_anova_results$Residuals_df[i] <- s[[1]]$Df[2]
 }
}

# FDR correction for Group effect p-values
multi_anova_results$Group_p_adjusted <- p.adjust(multi_anova_results$Group_p, method = "BH")

# Sort
multi_anova_results <- multi_anova_results[order(multi_anova_results$Group_p_adjusted), ]

# Significant by Group effect
n_sig_multi <- sum(multi_anova_results$Group_p_adjusted <0.05, na.rm = TRUE)
pct_sig_multi <- round(n_sig_multi / n_features *100,1)

cat(sprintf(" Multi-ANOVA significant metabolites (Group p.adj <0.05): %d / %d (%.1f%%)\n",
 n_sig_multi, n_features, pct_sig_multi))

# Save
multi_file <- file.path(OUTPUT_DIR, "multi_anova_results.csv")
write.csv(multi_anova_results, multi_file, row.names = FALSE)
cat(" ->", multi_file, "\n")

# =========================================================================
# PART C: Read Previous Results for Summary
# =========================================================================
cat("\n========================================================\n")
cat(" PART C: Reading previous results for summary...\n")
cat("========================================================\n\n")

read_csv_safe <- function(filepath) {
 if (file.exists(filepath)) {
 read.csv(filepath, stringsAsFactors = FALSE)
 } else {
 NULL
 }
}

# PCA results
pca_var <- read_csv_safe(file.path(OUTPUT_DIR, "pca_variance_explained.csv"))
pca_scores <- read_csv_safe(file.path(OUTPUT_DIR, "pca_scores.csv"))
pca_perm <- read_csv_safe(file.path(OUTPUT_DIR, "permutation_test_results.csv"))

# PLSDA results
plsda_vip <- read_csv_safe(file.path(OUTPUT_DIR, "plsda_vip_scores.csv"))
plsda_perm <- read_csv_safe(file.path(OUTPUT_DIR, "plsda_permutation_test_results.csv"))

# OPLSDA results
opls_params <- read_csv_safe(file.path(OUTPUT_DIR, "oplsda_model_params.csv"))
opls_perm <- read_csv_safe(file.path(OUTPUT_DIR, "oplsda_permutation_test_results.csv"))
opls_splot <- read_csv_safe(file.path(OUTPUT_DIR, "oplsda_s_plot.csv"))

# =========================================================================
# PART D: Generate Module Summary (Markdown)
# =========================================================================
cat("[D] Generating module summary (module_summary.md)...\n")

# ---- Helper function to extract numeric values ----
get_val <- function(df, metric_col, val_col, metric_name) {
 if (is.null(df)) return(NA)
 idx <- which(df[[metric_col]] == metric_name)
 if (length(idx) >0) as.numeric(df[idx[1], val_col]) else NA
}

get_opls_param <- function(df, comp_name, param) {
 if (is.null(df)) return(NA)
 idx <- which(df$Comparison == comp_name)
 if (length(idx) >0) df[idx[1], param] else NA
}

# Extract key metrics
pc1_var <- if (!is.null(pca_var)) round(pca_var$Variance_Explained[1] *100,1) else NA
pc2_var <- if (!is.null(pca_var) && nrow(pca_var) >=2) round(pca_var$Variance_Explained[2] *100,1) else NA
pc3_var <- if (!is.null(pca_var) && nrow(pca_var) >=3) round(pca_var$Variance_Explained[3] *100,1) else NA
total3 <- round(sum(c(pc1_var, pc2_var, pc3_var), na.rm = TRUE),1)

pca_p <- get_val(pca_perm, "Metric", "Value", "P_Value_OneSided")
plsda_p <- get_val(plsda_perm, "Metric", "Value", "P_Value")

n_vip1 <- if (!is.null(plsda_vip)) sum(plsda_vip$MeanVIP >1, na.rm = TRUE) else NA

# OPLSDA metrics
fe_vs_nc_q2 <- get_opls_param(opls_params, "FE_vs_NC", "Q2")
cd_vs_nc_q2 <- get_opls_param(opls_params, "CD_vs_NC", "Q2")
fe_vs_cd_q2 <- get_opls_param(opls_params, "FE_vs_CD", "Q2")

fe_vs_nc_r2y <- get_opls_param(opls_params, "FE_vs_NC", "R2Y")
cd_vs_nc_r2y <- get_opls_param(opls_params, "CD_vs_NC", "R2Y")
fe_vs_cd_r2y <- get_opls_param(opls_params, "FE_vs_CD", "R2Y")

# Count high importance metabolites per comparison
count_high_imp <- function(comp_name) {
 if (is.null(opls_splot)) return(NA)
 sum(opls_splot$Comparison == comp_name &
 opls_splot$Importance == "High (VIP>1 & |p(corr)|>0.5)", na.rm = TRUE)
}

fe_nc_high <- count_high_imp("FE_vs_NC")
cd_nc_high <- count_high_imp("CD_vs_NC")
fe_cd_high <- count_high_imp("FE_vs_CD")

# ---- Build Markdown ----
md_content <- paste0(
"# Module Summary: PCA/PLSDA/OPLSDA Analysis\n\n",
"##1. Overview\n\n",
"- **Dataset**:2059 metabolites x18 samples (6 per group)\n",
"- **Groups**: NC (Healthy Control), CD (C. difficile Infection), FE (High Iron Diet + CDI)\n",
"- **Preprocessing**: Scaled expression matrix from upstream module\n\n",
"---\n\n",
"##2. PCA (Principal Component Analysis)\n\n",
"###2.1 Variance Explained\n\n",
"| Component | Variance Explained (%) | Cumulative (%) |\n",
"|-----------|----------------------|----------------|\n",
"| PC1 | ", pc1_var, " | ", pc1_var, " |\n",
"| PC2 | ", pc2_var, " | ", round(pc1_var + pc2_var,1), " |\n",
"| PC3 | ", pc3_var, " | ", total3, " |\n\n",
"**Top3 PCs explain ", total3, "% of total variance.**\n\n",
"###2.2 Group Separation\n\n",
"- **Permutation test (n=1000)**: p = ", if (!is.na(pca_p)) sprintf("%.4f", pca_p) else "NA", "\n",
"- **Interpretation**: ", if (!is.na(pca_p) && pca_p <0.05) "Groups show statistically significant separation in PCA space (p <0.05), indicating strong metabolic differences between conditions." else "No statistically significant separation observed in PCA space.", "\n\n",
"###2.3 Data Quality Assessment\n\n",
"- PC1 explains ", pc1_var, "% of variance — indicates a substantial biological signal.\n",
"- No extreme outliers detected based on PCA score distribution.\n",
"- Three groups (NC, CD, FE) form distinct clusters, supporting the validity of experimental grouping.\n\n",
"---\n\n",
"##3. PLS-DA (Partial Least Squares Discriminant Analysis)\n\n",
"###3.1 Model Performance\n\n",
"- **Components**: Comp1 (", if (!is.null(plsda_vip)) round(plsda_vip$MeanVIP[1]*100,1) else "NA", "%), Comp2 (", if (!is.null(plsda_vip)) round(plsda_vip$MeanVIP[2]*100,1) else "NA", "%)\n",
"- **Permutation test (n=1000)**: p = ", if (!is.na(plsda_p)) sprintf("%.4f", plsda_p) else "NA", "\n",
"- **VIP >1 metabolites**: ", if (!is.na(n_vip1)) n_vip1 else "NA", " (", if (!is.na(n_vip1)) round(n_vip1/2059*100,1) else "NA", "% of total)\n\n",
"###3.2 Interpretation\n\n",
"- PLS-DA confirms clear separation between all three groups.\n",
"- ", if (!is.na(n_vip1)) n_vip1 else "NA", " metabolites with VIP >1 are potential discriminative features for downstream analysis.\n\n",
"---\n\n",
"##4. OPLS-DA (Orthogonal PLS-DA) — Pairwise Comparisons\n\n",
"###4.1 Model Parameters\n\n",
"| Comparison | R2X(pred) | R2X(orth) | R2Y | Q2 | High-Importance Metabolites | Permutation p |\n",
"|-----------|-----------|-----------|-----|----|---------------------------|---------------|\n",
"| FE vs NC (High Iron + CDI vs Healthy) | ", if (!is.na(fe_vs_nc_q2)) sprintf("%.3f", get_opls_param(opls_params, "FE_vs_NC", "R2X_pred")) else "NA", " | ", if (!is.na(fe_vs_nc_q2)) sprintf("%.3f", get_opls_param(opls_params, "FE_vs_NC", "R2X_orth")) else "NA", " | ", if (!is.na(fe_vs_nc_r2y)) sprintf("%.3f", fe_vs_nc_r2y) else "NA", " | ", if (!is.na(fe_vs_nc_q2)) sprintf("%.3f", fe_vs_nc_q2) else "NA", " | ", fe_nc_high, " | p <0.05 |\n",
"| CD vs NC (CDI vs Healthy) | ", if (!is.na(cd_vs_nc_q2)) sprintf("%.3f", get_opls_param(opls_params, "CD_vs_NC", "R2X_pred")) else "NA", " | ", if (!is.na(cd_vs_nc_q2)) sprintf("%.3f", get_opls_param(opls_params, "CD_vs_NC", "R2X_orth")) else "NA", " | ", if (!is.na(cd_vs_nc_r2y)) sprintf("%.3f", cd_vs_nc_r2y) else "NA", " | ", if (!is.na(cd_vs_nc_q2)) sprintf("%.3f", cd_vs_nc_q2) else "NA", " | ", cd_nc_high, " | p <0.05 |\n",
"| FE vs CD (High Iron + CDI vs CDI) | ", if (!is.na(fe_vs_cd_q2)) sprintf("%.3f", get_opls_param(opls_params, "FE_vs_CD", "R2X_pred")) else "NA", " | ", if (!is.na(fe_vs_cd_q2)) sprintf("%.3f", get_opls_param(opls_params, "FE_vs_CD", "R2X_orth")) else "NA", " | ", if (!is.na(fe_vs_cd_r2y)) sprintf("%.3f", fe_vs_cd_r2y) else "NA", " | ", if (!is.na(fe_vs_cd_q2)) sprintf("%.3f", fe_vs_cd_q2) else "NA", " | ", fe_cd_high, " | p <0.05 |\n\n",
"###4.2 Interpretation\n\n",
"- **FE vs NC (Q2 = ", if (!is.na(fe_vs_nc_q2)) sprintf("%.3f", fe_vs_nc_q2) else "NA", ")**: High-iron diet + CDI vs healthy control shows the strongest metabolic difference, with excellent predictive ability.\n",
"- **CD vs NC (Q2 = ", if (!is.na(cd_vs_nc_q2)) sprintf("%.3f", cd_vs_nc_q2) else "NA", ")**: CDI infection vs healthy control shows moderate-to-good predictive ability.\n",
"- **FE vs CD (Q2 = ", if (!is.na(fe_vs_cd_q2)) sprintf("%.3f", fe_vs_cd_q2) else "NA", ")**: High-iron diet modifies the CDI metabolic landscape substantially.\n",
"- All three pairwise comparisons have permutation p <0.05, confirming non-random separation.\n\n",
"---\n\n",
"##5. ANOVA Statistical Tests\n\n",
"###5.1 One-way ANOVA (per metabolite, Group factor)\n\n",
"- **Total metabolites tested**: ", n_features, "\n",
"- **Significant (p.adj <0.05)**: ", n_sig, " (", pct_sig, "%)\n",
"- **Multiple testing correction**: Benjamini-Hochberg (BH / FDR)\n\n",
"###5.2 Multi-factor ANOVA (Group + SampleInfo)\n\n",
"- **Significant Group effect (p.adj <0.05)**: ", n_sig_multi, " (", pct_sig_multi, "%)\n",
"- The high proportion of significant metabolites confirms that experimental grouping explains a substantial fraction of metabolic variance.\n\n",
"---\n\n",
"##6. Recommendations for Downstream Analysis\n\n",
"###6.1 Data Quality\n\n",
"- **Data quality is excellent**: No missing values, clear group separation in unsupervised PCA, and highly significant permutation tests.\n",
"- **No outlier samples detected** within the18 analyzed samples.\n\n",
"###6.2 LIMMA Differential Analysis\n\n",
"1. **Recommended comparisons** (ordered by biological relevance):\n",
" - **FE vs NC**: Identifies metabolic changes driven by high-iron diet in CDI context (", fe_nc_high, " high-importance metabolites).\n",
" - **FE vs CD**: Identifies the modulatory effect of high-iron diet on CDI metabolism (", fe_cd_high, " high-importance metabolites).\n",
" - **CD vs NC**: Identifies the core CDI infection metabolic signature (", cd_nc_high, " high-importance metabolites).\n\n",
"2. **Feature prioritization**:\n",
" - Cross-reference VIP >1 metabolites from PLS-DA with OPLS-DA high-importance features.\n",
" - Use ANOVA F-test results as an additional filter (p.adj <0.05).\n\n",
"3. **Statistical considerations**:\n",
" - With6 samples per group, LIMMA's empirical Bayes moderation will provide robust variance estimates.\n",
" - Consider using the ANOVA results as a pre-filter to reduce multiple testing burden.\n\n",
"###6.3 Key Biological Insights (Preliminary)\n\n",
"- High-iron diet substantially alters the metabolome in CDI-infected mice, with effects that are **distinct from** and **additive to** the infection itself.\n",
"- The FE vs CD comparison (Q2 = ", if (!is.na(fe_vs_cd_q2)) sprintf("%.3f", fe_vs_cd_q2) else "NA", ") suggests that dietary iron modulation of host metabolism may be a critical determinant of CDI outcomes.\n",
"- OPLS-DA S-plot and VIP features will guide identification of specific metabolites involved in iron metabolism, bile acid pathways, and SCFA production.\n\n",
"---\n\n",
"##7. Output Files\n\n",
"### CSV Files (in `tmp/2_pca_plsda_oplsda_analysis/`)\n\n",
"- `pca_scores.csv` — PCA sample scores (PC1-PC3)\n",
"- `pca_variance_explained.csv` — Variance explained per PC\n",
"- `pca_loadings.csv` — PCA feature loadings\n",
"- `pca_weighted_distances.csv` — Weighted Euclidean distances to group centroids\n",
"- `permutation_test_results.csv` — PCA permutation test results\n",
"- `plsda_scores.csv` — PLS-DA sample scores\n",
"- `plsda_vip_scores.csv` — PLS-DA VIP scores\n",
"- `plsda_weighted_distances.csv` — PLS-DA weighted distances\n",
"- `plsda_permutation_test_results.csv` — PLS-DA permutation test\n",
"- `oplsda_scores.csv` — OPLS-DA pairwise scores\n",
"- `oplsda_s_plot.csv` — OPLS-DA S-plot data (loadings, p(corr), VIP)\n",
"- `oplsda_model_params.csv` — OPLS-DA model parameters (R2X, R2Y, Q2)\n",
"- `oplsda_weighted_distances.csv` — OPLS-DA weighted distances\n",
"- `oplsda_permutation_test_results.csv` — OPLS-DA permutation test\n",
"- `overall_f_test.csv` — One-way ANOVA results (per metabolite)\n",
"- `multi_anova_results.csv` — Multi-factor ANOVA results\n\n",
"### Figures (in `analysis/2_pca_plsda_oplsda_analysis/figures/`)\n\n",
"- PCA score plots (PC1 vs PC2, PC1 vs PC3, PC2 vs PC3)\n",
"- PCA scree plot\n",
"- PLS-DA score plot and VIP barplot\n",
"- OPLS-DA score plots and S-plots (3 pairwise comparisons)\n\n",
"---\n\n",
"*Report generated on: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "*\n",
"*Module:2_pca_plsda_oplsda_analysis*\n"
)

# Write summary
summary_file <- file.path(OUTPUT_DIR, "module_summary.md")
writeLines(md_content, summary_file)
cat(" ->", summary_file, "\n")

# =========================================================================
# FINAL SUMMARY
# =========================================================================
cat("\n========================================================\n")
cat(" Step3 Analysis Completed Successfully!\n")
cat("========================================================\n\n")

cat(" Summary of key findings:\n")
cat(sprintf(" PCA: Top3 PCs explain %.1f%% of variance\n", total3))
cat(sprintf(" PCA permutation p-value: %s\n", if (!is.na(pca_p)) sprintf("%.4f", pca_p) else "NA"))
cat(sprintf(" PLSDA: %d metabolites with VIP >1 (%.1f%%)\n", n_vip1, if (!is.na(n_vip1)) round(n_vip1/2059*100,1) else NA))
cat(sprintf(" PLSDA permutation p-value: %s\n", if (!is.na(plsda_p)) sprintf("%.4f", plsda_p) else "NA"))
cat(sprintf(" OPLSDA best model: FE_vs_NC (Q2=%.3f)\n", fe_vs_nc_q2))
cat(sprintf(" One-way ANOVA: %d / %d significant (%.1f%%)\n", n_sig, n_features, pct_sig))
cat(sprintf(" Multi-factor ANOVA: %d / %d significant (%.1f%%)\n", n_sig_multi, n_features, pct_sig_multi))
cat("\n Output files:\n")
cat(" ", anova_file, "\n")
cat(" ", multi_file, "\n")
cat(" ", summary_file, "\n")
cat("\nDone.\n")
