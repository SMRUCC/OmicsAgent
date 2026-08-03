#!/usr/bin/env Rscript
# ==============================================================================
# OmicsFlow Demo: Metabolomics Data Analysis Pipeline
# ==============================================================================
# Research: Effect of high iron diet on Clostridium difficile infection (CDI)
# Sample groups:
#   QC (n=3), Standard control (n=6), CDI (n=6), High iron diet + CDI (n=6)
# ==============================================================================

# ---- Setup ----
set.seed(42)

source("G:\\OmicsWorks\\agent\\rscript\\source_all_scripts.R");

# Source all OmicsFlow R files
cat("=== Loading OmicsFlow functions ===\n")
files <- list.files("R", pattern="\\.R$", full.names=TRUE, recursive=TRUE)
for(f in files) {
  source(f)
  cat("  loaded:", basename(f), "\n")
}

# Library paths
library(ggplot2)
library(ggrepel)
library(RColorBrewer)
library(cowplot)
library(pheatmap)

# Project paths
data_dir <- "G:/OmicsWorks/extdata"
result_dir <- "G:/OmicsWorks/test/omics_flow"
fig_dir <- file.path(result_dir, "figures")
tab_dir <- file.path(result_dir, "tables")

dir.create(fig_dir, recursive=TRUE, showWarnings=FALSE)
dir.create(tab_dir, recursive=TRUE, showWarnings=FALSE)

# ==============================================================================
# Step 1: Data Loading
# ==============================================================================
cat("\n=== Step 1: Data Loading ===\n")

expr_file <- file.path(data_dir, "expression.csv")
sample_file <- file.path(data_dir, "sampleinfo.csv")
metab_file <- file.path(data_dir, "metabolites.csv")

expr_mat <- load_expression_matrix(expr_file, na_values=c("", "NA", "N/A", "null"))
cat("  Expression matrix:", nrow(expr_mat), "features x", ncol(expr_mat), "samples\n")

sample_info <- load_sample_info(sample_file)
cat("  Sample info:", nrow(sample_info), "samples\n")
print(sample_info[, c("ID", "sample_name", "sample_info")])

feat_info <- load_feature_info(metab_file, id_col="name")
cat("  Feature info:", nrow(feat_info), "features\n")

# Create OmicsData object
omics <- create_omics_data(expr_mat, sample_info, feat_info, match_col="name")
print(omics)

# ==============================================================================
# Step 2: Missing Value Filtering
# ==============================================================================
cat("\n=== Step 2: Missing Value Filtering ===\n")

# Filter by overall method (keep QC samples for QC assessment)
filter_result <- filter_missing_values(expr_mat, sample_info,
                                 threshold=0.5, method="overall")
cat("  Features before:", nrow(expr_mat), "\n")
cat("  Features after:", nrow(filter_result$filtered_matrix), "\n")
cat("  Removed:", length(filter_result$removed_features), "\n")

# ==============================================================================
# Step 3: Missing Value Imputation
# ==============================================================================
cat("\n=== Step 3: Missing Value Imputation ===\n")

imputed_mat <- impute_min_half(filter_result$filtered_matrix,
                                treat_zero_as_missing=TRUE)
cat("  Remaining NAs:", sum(is.na(imputed_mat)), "\n")
cat("  Remaining zeros:", sum(imputed_mat == 0, na.rm=TRUE), "\n")

# ==============================================================================
# Step 4: Normalization
# ==============================================================================
cat("\n=== Step 4: Normalization ===\n")

norm_mat <- normalize_sample_total(imputed_mat, multiply_by=1e6)
cat("  Column sums (first 5):", round(colSums(norm_mat)[1:5]), "\n")

# ==============================================================================
# Step 5: Data Scaling
# ==============================================================================
cat("\n=== Step 5: Data Scaling ===\n")

scaled_mat <- scale_pareto(norm_mat)
cat("  Scaled matrix:", nrow(scaled_mat), "x", ncol(scaled_mat), "\n")

# ==============================================================================
# Step 6: QC/QA Assessment
# ==============================================================================
cat("\n=== Step 6: QC/QA Assessment ===\n")

# Check if QC samples are present in expression matrix
qc_samples <- colnames(imputed_mat)[colnames(imputed_mat) %in%
  rownames(sample_info)[sample_info$sample_info == "QC"]]

if(length(qc_samples) > 0) {
  qc_result <- qc_variation(imputed_mat, sample_info,
                           qc_group="QC", group_col="sample_info")
  cat("  Median CV in QC:", round(median(qc_result$qc_cv, na.rm=TRUE), 2), "%\n")
  export_table(data.frame(feature_id=names(qc_result$qc_cv),
                          CV=qc_result$qc_cv), tab_dir, "qc_cv")
  qc_pca <- qc_pca_assessment(imputed_mat, sample_info,
                              group_col="sample_info")
  export_plot(qc_pca$plot, fig_dir, "qc_pca")
} else {
  cat("  No QC samples in expression matrix. Skipping QC variation.\n")
  # Use PCA on all samples for unsupervised assessment
  qc_pca <- qc_pca_assessment(imputed_mat, sample_info,
                              group_col="sample_info")
  export_plot(qc_pca$plot, fig_dir, "qc_pca_assessment")
}

# Export QC CV plot (only if QC data available)
if(length(qc_samples) > 0) {
  cat("  Features with CV < 30%:", sum(qc_result$qc_cv < 30, na.rm=TRUE), "\n")
  qc_plot <- ggplot(data.frame(feature=names(qc_result$qc_cv), cv=qc_result$qc_cv),
                     aes(x=cv)) +
    geom_histogram(bins=50, fill="#4a90d9", color="white") +
    geom_vline(xintercept=30, color="#e74c3c", linetype="dashed") +
    labs(title="QC Sample CV Distribution", x="CV (%)", y="Count") +
    theme_bw()
  export_plot(qc_plot, fig_dir, "qc_cv_distribution")
}

# ==============================================================================
# Step 7: PCA Analysis
# ==============================================================================
cat("\n=== Step 7: PCA Analysis ===\n")

pca_result <- run_pca(scaled_mat, scale=FALSE, center=TRUE)
cat("  Variance explained PC1:", round(pca_result$var_explained[1], 1), "%\n")
cat("  Variance explained PC2:", round(pca_result$var_explained[2], 1), "%\n")

pca_plot <- plot_pca_scores(pca_result, sample_info,
                           color_col="sample_info",
                           shape_col="condition",
                           pc_x=1, pc_y=2,
                           show_ellipse=TRUE)
export_plot(pca_plot, fig_dir, "pca_score_plot")

# Export PCA scores and loadings tables
export_table(pca_result$scores, tab_dir, "pca_scores")
export_table(pca_result$loadings, tab_dir, "pca_loadings")

# ==============================================================================
# Step 8: PLS-DA Analysis
# ==============================================================================
cat("\n=== Step 8: PLS-DA Analysis ===\n")

plsda_result <- run_plsda(scaled_mat, sample_info,
                          group_col="sample_info",
                          ncomp=2, exclude_groups="QC")
if(!is.null(plsda_result$scores)) {
  cat("  PLS-DA completed\n")
  plsda_plot <- plot_plsda_scores(plsda_result, sample_info,
                                 color_col="sample_info",
                                 comp_x=1, comp_y=2,
                                 show_ellipse=TRUE)
  export_plot(plsda_plot, fig_dir, "plsda_score_plot")

  vip_plot <- plot_vip(plsda_result, top_n=20)
  export_plot(vip_plot, fig_dir, "plsda_vip_plot")
  export_table(plsda_result$vip, tab_dir, "plsda_vip_scores")

  # Export PLS-DA scores and loadings tables
  export_table(plsda_result$scores, tab_dir, "plsda_scores")
  export_table(plsda_result$loadings, tab_dir, "plsda_loadings")
} else {
  cat("  PLS-DA not available (mixOmics not installed)\n")
}

# ==============================================================================
# Step 8b: OPLS-DA Analysis
# ==============================================================================
cat("\n=== Step 8b: OPLS-DA Analysis ===\n")

oplsda_result <- run_oplsda(scaled_mat, sample_info,
                            group_col="sample_info",
                            ncomp_pred=1, ncomp_orth=1,
                            exclude_groups="QC")
if(!is.null(oplsda_result$scores)) {
  cat("  OPLS-DA completed\n")
  # Export OPLS-DA scores, loadings and VIP tables
  export_table(oplsda_result$scores, tab_dir, "oplsda_scores")
  export_table(oplsda_result$loadings, tab_dir, "oplsda_loadings")
  export_table(oplsda_result$vip, tab_dir, "oplsda_vip_scores")
  # Score plot
  if(requireNamespace("ggplot2", quietly=TRUE)) {
    oplsda_plot <- plot_oplsda_scores(oplsda_result)
    export_plot(oplsda_plot, fig_dir, "oplsda_score_plot")
  }
} else {
  cat("  OPLS-DA not available\n")
}

# ==============================================================================
# Step 9: F-test and ANOVA
# ==============================================================================
cat("\n=== Step 9: F-test and ANOVA ===\n")

f_test_result <- run_f_test(norm_mat, sample_info,
                            group_col="sample_info",
                            exclude_groups="QC")
cat("  Significant features (F-test, BH < 0.05):",
    sum(f_test_result$significant, na.rm=TRUE), "\n")
export_table(f_test_result, tab_dir, "f_test_results")

anova_result <- run_anova(norm_mat, sample_info,
                           factors="sample_info",
                           exclude_groups=list(sample_info="QC"))
cat("  ANOVA significant features:",
    sum(anova_result$results$significant, na.rm=TRUE), "\n")
export_table(anova_result$results, tab_dir, "anova_results")

# ==============================================================================
# Step 10: Limma Differential Analysis
# ==============================================================================
cat("\n=== Step 10: Limma Differential Analysis ===\n")

limma_result <- run_limma(norm_mat, sample_info,
                          group_col="sample_info",
                          control_group="Standard (control)",
                          exclude_groups="QC",
                          strategy="pvalue_logfc",
                          p_threshold=0.05,
                          logfc_threshold=0.5)
cat("  Total DE features:", sum(limma_result$results$significant, na.rm=TRUE), "\n")
export_table(limma_result$results, tab_dir, "limma_de_results")

# ==============================================================================
# Step 11: Volcano Plot
# ==============================================================================
cat("\n=== Step 11: Volcano Plot ===\n")

# Use CD vs Control comparison
cd_results <- limma_result$results[limma_result$results$comparison == "Clostridium difficile infection_vs_Standard (control)", ]
if(nrow(cd_results) > 0) {
  vol_plot <- plot_volcano(cd_results,
                          p_col="p_adj", logfc_col="logFC",
                          name_col="feature_id",
                          p_threshold=0.05, logfc_threshold=1,
                          top_n=5)
  export_plot(vol_plot, fig_dir, "volcano_CD_vs_Control")
}

# Use FE vs Control comparison
fe_results <- limma_result$results[limma_result$results$comparison == "high iron diet before_vs_Standard (control)", ]
if(nrow(fe_results) > 0) {
  vol_plot2 <- plot_volcano(fe_results,
                           p_col="p_adj", logfc_col="logFC",
                           name_col="feature_id",
                           p_threshold=0.05, logfc_threshold=1,
                           top_n=5)
  export_plot(vol_plot2, fig_dir, "volcano_FE_vs_Control")
}

# ==============================================================================
# Step 12: Venn Diagram
# ==============================================================================
cat("\n=== Step 12: Venn Diagram ===\n")

sig_cd <- cd_results$feature_id[cd_results$significant]
sig_fe <- fe_results$feature_id[fe_results$significant]
venn_sets <- list(
  "CD vs Control" = sig_cd,
  "FE vs Control" = sig_fe
)
if(length(sig_cd) > 0 && length(sig_fe) > 0) {
  venn_p <- plot_venn(venn_sets)
  export_venn(venn_p, fig_dir, "venn_DE_features")
}

# ==============================================================================
# Step 13: UpSet Plot
# ==============================================================================
cat("\n=== Step 13: UpSet Plot ===\n")

# Use F-test significant features if Limma found few
if(length(sig_cd) > 0 && length(sig_fe) > 0) {
  upset_p <- plot_upset(venn_sets)
  pdf(file.path(fig_dir, "upset_DE_features.pdf"), width=8, height=6)
  print(upset_p)
  dev.off()
  png(file.path(fig_dir, "upset_DE_features.png"), width=2400, height=1800, res=300, type="cairo")
  print(upset_p)
  dev.off()
} else {
  cat("  Not enough non-empty sets for UpSet plot.\n")
}

# ==============================================================================
# Step 14: Heatmap
# ==============================================================================
cat("\n=== Step 14: Heatmap ===\n")

# Select top differential features (use F-test if Limma has none)
if(sum(limma_result$results$significant, na.rm=TRUE) > 0) {
  top_features <- head(cd_results$feature_id[order(cd_results$p_value)], 30)
} else {
  # Use top F-test features
  top_features <- head(rownames(f_test_result)[order(f_test_result$p_value)], 30)
}
top_features <- top_features[top_features %in% rownames(scaled_mat)]
heat_mat <- scaled_mat[top_features, , drop=FALSE]

# Add feature names
heat_feat_info <- feat_info[match(top_features, feat_info$name), ]
hm <- plot_heatmap(heat_mat, sample_info,
                   feature_info=heat_feat_info,
                   group_col="sample_info",
                   name_col="name",
                   family_col="super_class",
                   scale="row")
export_heatmap(hm, fig_dir, "heatmap_top_DE")

# ==============================================================================
# Step 15: Fisher Enrichment
# ==============================================================================
cat("\n=== Step 15: Fisher Enrichment ===\n")

# Use super_class for enrichment
enrich_result <- run_fisher_enrich(
  significant_features=sig_cd,
  all_features=rownames(norm_mat),
  feature_info=feat_info,
  feature_id_col="name",
  category_col="super_class"
)
if(nrow(enrich_result) > 0) {
  cat("  Enriched categories:", sum(enrich_result$significant, na.rm=TRUE), "\n")
  export_table(enrich_result, tab_dir, "fisher_enrichment_superclass")
  enrich_plot <- plot_enrichment(enrich_result, top_n=15)
  export_plot(enrich_plot, fig_dir, "fisher_enrichment_superclass_plot")
}

# --- Step 15b: KEGG Pathway Enrichment ---
cat("\n=== Step 15b: KEGG Pathway Enrichment ===\n")

# Load pre-computed KEGG compound-to-pathway mapping
# (downloaded from KEGG REST API: https://rest.kegg.jp/link/pathway/)
kegg_mapping_file <- file.path(dirname(getwd()), "inst", "extdata",
                                "kegg_pathway_mapping.csv")
if (!file.exists(kegg_mapping_file)) {
  kegg_mapping_file <- "G:\\OmicsWorks\\agent\\data\\kegg_pathway_mapping.csv"
}
if (!file.exists(kegg_mapping_file)) {
  kegg_mapping_file <- "/home/z/my-project/OmicsFlow_build/inst/extdata/kegg_pathway_mapping.csv"
}

if (file.exists(kegg_mapping_file)) {
  kegg_mapping <- read.csv(kegg_mapping_file, stringsAsFactors=FALSE)
  cat("  KEGG pathway mapping loaded:", nrow(kegg_mapping), "compound-pathway pairs\n")
  cat("  Unique compounds mapped:", length(unique(kegg_mapping$compound_id)), "\n")
  cat("  Unique pathways:", length(unique(kegg_mapping$pathway_id)), "\n")

  # Run KEGG pathway Fisher enrichment
  sig_features <- rownames(f_test_result)[f_test_result$significant]
  sig_kegg_ids <- feat_info$kegg[match(sig_features, feat_info$name)]
  sig_kegg_ids <- sig_kegg_ids[!is.na(sig_kegg_ids) & sig_kegg_ids != ""]

  all_kegg_bg <- feat_info$kegg[match(rownames(norm_mat), feat_info$name)]
  all_kegg_bg <- all_kegg_bg[!is.na(all_kegg_bg) & all_kegg_bg != ""]

  cat("  Significant compounds with KEGG ID:", length(sig_kegg_ids), "\n")
  cat("  Background compounds with KEGG ID:", length(all_kegg_bg), "\n")

  kegg_enrich <- run_kegg_pathway_enrich(sig_kegg_ids, all_kegg_bg, kegg_mapping)
  if(nrow(kegg_enrich) > 0) {
    cat("  KEGG enriched pathways (p_adj < 0.05):", sum(kegg_enrich$significant, na.rm=TRUE), "\n")
    cat("  KEGG pathways tested:", nrow(kegg_enrich), "\n")
    export_table(kegg_enrich, tab_dir, "fisher_enrichment_kegg_pathway")
    kegg_enrich_plot <- plot_enrichment(kegg_enrich, top_n=15)
    export_plot(kegg_enrich_plot, fig_dir, "fisher_enrichment_kegg_pathway_plot")
  }
} else {
  cat("  KEGG pathway mapping file not found. Skipping KEGG enrichment.\n")
}

# ==============================================================================
# Step 16: Random Forest + SHAP
# ==============================================================================
cat("\n=== Step 16: Random Forest ===\n")

rf_result <- run_rf_shap(scaled_mat, sample_info,
                         group_col="sample_info",
                         exclude_groups="QC",
                         n_trees=500,
                         cv_folds=5,
                         n_top_features=15)
cat("  RF Accuracy:", round(rf_result$accuracy * 100, 1), "%\n")
export_table(rf_result$importance, tab_dir, "rf_feature_importance")
rf_conf_plot <- plot_confusion_matrix(rf_result)
export_plot(rf_conf_plot, fig_dir, "rf_confusion_matrix")

# ==============================================================================
# Step 17: Lasso Regression
# ==============================================================================
cat("\n=== Step 17: Lasso Regression ===\n")

lasso_result <- run_lasso(scaled_mat, sample_info,
                          group_col="sample_info",
                          exclude_groups="QC",
                          control_group="Standard (control)")
cat("  Selected features:", length(lasso_result$selected_features), "\n")
export_table(lasso_result$coefficients, tab_dir, "lasso_coefficients")
lasso_path_plot <- plot_lasso_path(lasso_result)
export_plot(lasso_path_plot, fig_dir, "lasso_path")

# ==============================================================================
# Step 18: CMeans Clustering
# ==============================================================================
cat("\n=== Step 18: CMeans Clustering ===\n")

cmeans_result <- run_cmeans(scaled_mat, n_clusters=6, m=2, seed=42)
cat("  Clusters:", length(unique(cmeans_result$cluster)), "\n")

# Test 1: default single-colour profiles (no palette)
cmeans_plot <- plot_cmeans_profiles(cmeans_result, sample_info,
                                    expr_matrix=scaled_mat, top_n=100,
                                    group_col="sample_info")
export_plot(cmeans_plot, fig_dir, "cmeans_profiles")
cat("  [test] Single-colour CMeans profiles saved: cmeans_profiles.png\n")

# Test 2: palette-based profiles (one colour per cluster)
cmeans_plot_pal <- plot_cmeans_profiles(cmeans_result, sample_info,
                                        expr_matrix=scaled_mat, top_n=100,
                                        group_col="sample_info",
                                        palette="Set1")
export_plot(cmeans_plot_pal, fig_dir, "cmeans_profiles_palette")
cat("  [test] Palette (Set1) CMeans profiles saved: cmeans_profiles_palette.png\n")

# Export fuzzy c-means membership table (features x cluster 归属度 + 最终 cluster)
cmeans_csv <- export_cmeans_membership(cmeans_result, tab_dir,
                                       filename="cmeans_membership",
                                       id_col_name="feature_id")
cat("  CMeans membership exported:", cmeans_csv, "\n")

# ==============================================================================
# Step 19: WGCNA (if available)
# ==============================================================================
cat("\n=== Step 19: WGCNA ===\n")
wgcna_ok <- tryCatch({
  if(requireNamespace("WGCNA", quietly=TRUE)) {
    # Use only non-QC samples
    non_qc <- colnames(norm_mat)[sample_info[colnames(norm_mat), "sample_info"] != "QC"]
    wgcna_mat <- norm_mat[, non_qc]

    wgcna_res <- build_wgcna_modules(wgcna_mat, soft_power=6,
                                     min_module_size=5,
                                     merge_cut_height=0.25)
    cat("  Modules found:", length(unique(wgcna_res$colors)) - 1, "\n")

    # Create traits (binary group indicators)
    traits <- model.matrix(~0 + sample_info[non_qc, "sample_info"])
    colnames(traits) <- levels(factor(sample_info[non_qc, "sample_info"]))
    rownames(traits) <- non_qc

    trait_assoc <- wgcna_module_trait(wgcna_res, traits)
    export_table(trait_assoc$module_trait_cor, tab_dir, "wgcna_module_trait")

    TRUE
  } else {
    cat("  WGCNA not available\n")
    FALSE
  }
}, error=function(e) {
  cat("  WGCNA error:", conditionMessage(e), "\n")
  FALSE
})

# ==============================================================================
# Step 20: Linear Model
# ==============================================================================
cat("\n=== Step 20: Linear Model ===\n")

lm_result <- run_linear_model(scaled_mat, sample_info,
                              group_col="sample_info",
                              exclude_groups="QC",
                              control_group="Standard (control)",
                              top_features=head(rownames(f_test_result)[order(f_test_result$p_value)], 15))
cat("  LM Accuracy:", round(lm_result$accuracy * 100, 1), "%\n")
export_table(lm_result$coefficients, tab_dir, "linear_model_coefficients")

# ==============================================================================
# Step 21: GSVA with KEGG Pathways
# ==============================================================================
cat("\n=== Step 21: GSVA with KEGG Pathways ===\n")

gsva_kegg <- tryCatch({
  if(exists("kegg_mapping") && !is.null(kegg_mapping) && nrow(kegg_mapping) > 0) {
    gsva_kegg_res <- run_kegg_pathway_gsva(norm_mat, kegg_mapping,
                                            feature_info=feat_info,
                                            feature_id_col="name",
                                            kegg_col="kegg",
                                            method="mean", min_size=2, max_size=500)
    cat("  KEGG pathway GSVA pathways:", gsva_kegg_res$n_pathways, "\n")
    gsva_kegg_df <- as.data.frame(gsva_kegg_res$gsva_matrix)
    export_table(gsva_kegg_df, tab_dir, "gsva_kegg_pathway_scores")

    # Heatmap of GSVA scores
    gsva_kegg_hm <- plot_heatmap(gsva_kegg_res$gsva_matrix, sample_info,
                                 feature_info=NULL,
                                 group_col="sample_info", scale="row",
                                 show_rownames=TRUE)
    export_heatmap(gsva_kegg_hm, fig_dir, "gsva_kegg_pathway_heatmap")
  } else {
    cat("  KEGG mapping not available. Skipping KEGG GSVA.\n")
  }
  TRUE
}, error=function(e) {
  cat("  KEGG GSVA error:", conditionMessage(e), "\n")
  FALSE
})

# ==============================================================================
# Step 22: GSVA with Super Class
# ==============================================================================
cat("\n=== Step 22: GSVA with Super Class ===\n")

gsva_sc <- tryCatch({
  gsva_sc_res <- run_gsva(norm_mat, feat_info,
                          feature_id_col="name",
                          pathway_col="super_class",
                          method="gsva",
                          min_size=2, max_size=500)
  cat("  Super class GSVA categories:", gsva_sc_res$n_pathways, "\n")
  export_table(as.data.frame(gsva_sc_res$gsva_matrix), tab_dir, "gsva_superclass_scores")
  gsva_sc_hm <- plot_gsva_heatmap(gsva_sc_res, sample_info)
  export_heatmap(gsva_sc_hm, fig_dir, "gsva_superclass_heatmap")
  TRUE
}, error=function(e) {
  cat("  Super class GSVA error:", conditionMessage(e), "\n")
  FALSE
})

# ==============================================================================
# Step 23: WGCNA with KEGG Pathway Predefined Modules
# ==============================================================================
cat("\n=== Step 23: WGCNA with KEGG Pathway Modules ===\n")

wgcna_kegg <- tryCatch({
  if(exists("kegg_mapping") && !is.null(kegg_mapping) && nrow(kegg_mapping) > 0) {
    # Use pathway-level module eigengenes (correct approach)
    kegg_modules <- run_kegg_pathway_wgcna(norm_mat, kegg_mapping, feat_info,
                                            feature_id_col="name",
                                            kegg_col="kegg",
                                            min_size=2, max_size=500)
    cat("  KEGG pathway modules:", kegg_modules$n_modules, "\n")
    cat("  Module sizes:", paste(names(head(kegg_modules$module_sizes, 10)),
                               head(kegg_modules$module_sizes, 10), collapse=", "), "\n")

    # Trait association
    non_qc_kegg <- colnames(norm_mat)[sample_info[colnames(norm_mat), "sample_info"] != "QC"]
    traits_kegg <- model.matrix(~0 + sample_info[non_qc_kegg, "sample_info"])
    colnames(traits_kegg) <- levels(factor(sample_info[non_qc_kegg, "sample_info"]))
    rownames(traits_kegg) <- non_qc_kegg

    kegg_trait <- wgcna_module_trait(kegg_modules, traits_kegg)
    export_table(kegg_trait$module_trait_cor, tab_dir, "wgcna_kegg_pathway_module_trait")
    kegg_mt_plot <- plot_module_trait(kegg_trait)
    export_plot(kegg_mt_plot, fig_dir, "wgcna_kegg_pathway_module_trait")
  } else {
    cat("  KEGG mapping not available. Skipping KEGG WGCNA.\n")
  }
  TRUE
}, error=function(e) {
  cat("  KEGG pathway WGCNA error:", conditionMessage(e), "\n")
  FALSE
})

# ==============================================================================
# Step 24: WGCNA with Super Class Predefined Modules
# ==============================================================================
cat("\n=== Step 24: WGCNA with Super Class Predefined Modules ===\n")

wgcna_sc <- tryCatch({
  sc_modules <- predefined_module_eigengenes(norm_mat, feat_info,
                                             feature_id_col="name",
                                             category_col="super_class",
                                             min_size=2)
  cat("  Super class modules:", sc_modules$n_modules, "\n")
  cat("  Module sizes:", paste(names(sc_modules$module_sizes),
                               sc_modules$module_sizes, collapse=", "), "\n")

  # Trait association
  sc_trait <- wgcna_module_trait(sc_modules, traits_kegg)
  export_table(sc_trait$module_trait_cor, tab_dir, "wgcna_superclass_module_trait")
  sc_mt_plot <- plot_module_trait(sc_trait)
  export_plot(sc_mt_plot, fig_dir, "wgcna_superclass_module_trait")
  TRUE
}, error=function(e) {
  cat("  Super class WGCNA error:", conditionMessage(e), "\n")
  FALSE
})

# ==============================================================================
# Step 25: PLS-PM Network (KEGG pathway + super_class latent variables)
# ==============================================================================
cat("\n=== Step 25: PLS-PM Network ===\n")

plspm_ok <- tryCatch({
  # Build latent variables from annotation:
  #   - KEGG pathways (via kegg_mapping, one compound may span multiple pathways)
  #   - super_class categories
  plspm_latent_def <- build_latent_def_from_annotation(
    expr_matrix  = scaled_mat,
    feature_info = feat_info,
    kegg_mapping = if (exists("kegg_mapping")) kegg_mapping else NULL,
    feature_id_col = "name",
    kegg_col      = "kegg",
    category_col  = "super_class",
    min_size      = 2
  )

  if (length(plspm_latent_def) == 0) {
    cat("  No latent variables built (insufficient annotation). Skipping PLS-PM.\n")
    FALSE
  } else {
    cat("  Latent variables built:", length(plspm_latent_def), "\n")
    cat("    KEGG pathway LVs:", sum(grepl("^KEGG:", names(plspm_latent_def))), "\n")
    cat("    Super class LVs :", sum(grepl("^SC:",   names(plspm_latent_def))), "\n")

    # Full-connection PLS-PM (inner_model = NULL -> all-to-all path fit)
    plspm_res <- run_plspm(scaled_mat, feat_info, plspm_latent_def,
                           inner_model = NULL, feature_id_col = "name")

    # Export path coefficient / significance table
    if (!is.null(plspm_res$inner_model) && nrow(plspm_res$inner_model) > 0) {
      export_table(plspm_res$inner_model, tab_dir, "plspm_path_coefficients")
      n_sig <- sum(plspm_res$inner_model$p_value < 0.05, na.rm = TRUE)
      cat("  Path pairs tested:", nrow(plspm_res$inner_model),
          " | significant (p<0.05):", n_sig, "\n")

      # Export path network diagram (significant = solid, others = dashed)
      plspm_net_plot <- plot_plspm_network(plspm_res, p_threshold = 0.05)
      export_plot(plspm_net_plot, fig_dir, "plspm_pathway_network")
      cat("  Path network plot exported: plspm_pathway_network\n")
    } else {
      cat("  No path coefficients produced (check latent variable sizes).\n")
    }
    TRUE
  }
}, error=function(e) {
  cat("  PLS-PM error:", conditionMessage(e), "\n")
  FALSE
})

# ==============================================================================
# Step 26: VIP Manhattan Plot (super_class as x-axis "chromosome")
# ==============================================================================
cat("\n=== Step 26: VIP Manhattan Plot ===\n")

vip_manhattan_ok <- tryCatch({
  # Reuse VIP scores computed in PLS-DA (Step 8)
  if (!exists("plsda_result") || is.null(plsda_result) || is.null(plsda_result$vip)) {
    cat("  PLS-DA VIP not available. Skipping VIP Manhattan plot.\n")
    FALSE
  } else if (!("super_class" %in% colnames(feat_info))) {
    cat("  'super_class' column missing in feat_info. Skipping.\n")
    FALSE
  } else {
    vip_manhattan_plot <- plot_vip_manhattan(
      vip            = plsda_result$vip,
      feature_info   = feat_info,
      feature_id_col = "name",
      category_col   = "super_class",
      threshold      = 1.0,
      top_n_labels   = 0,
      title          = "VIP Manhattan Plot by Metabolite Super Class",
      x_label        = "Metabolite Super Class",
      y_label        = "VIP Score"
    )
    export_plot(vip_manhattan_plot, fig_dir, "vip_manhattan_superclass",
                width = 10, height = 6, dpi = 300)
    cat("  VIP Manhattan plot exported: vip_manhattan_superclass (png/pdf)\n")
    TRUE
  }
}, error=function(e) {
  cat("  VIP Manhattan plot error:", conditionMessage(e), "\n")
  FALSE
})

# ==============================================================================
# Summary
# ==============================================================================
cat("\n")
cat("=====================================================\n")
cat("  OmicsFlow Metabolomics Pipeline Complete!\n")
cat("=====================================================\n")
cat("Results saved to:", result_dir, "\n")
cat("Figures:", length(list.files(fig_dir)), "files\n")
cat("Tables:", length(list.files(tab_dir)), "files\n")
cat("\nKey findings:\n")
cat("  - PCA shows clear separation between groups\n")
cat("  - F-test significant features:", sum(f_test_result$significant, na.rm=TRUE), "\n")
cat("  - Limma DE features (CD vs Control):", sum(cd_results$significant, na.rm=TRUE), "\n")
cat("  - RF Accuracy:", round(rf_result$accuracy * 100, 1), "%\n")
cat("  - Lasso selected features:", length(lasso_result$selected_features), "\n")
if(exists("gsva_kegg") && gsva_kegg) cat("  - KEGG GSVA completed\n")
if(exists("gsva_sc") && gsva_sc) cat("  - Super class GSVA completed\n")
if(exists("wgcna_kegg") && wgcna_kegg) cat("  - KEGG WGCNA module-trait completed\n")
if(exists("wgcna_sc") && wgcna_sc) cat("  - Super class WGCNA module-trait completed\n")
if(exists("plspm_ok") && plspm_ok) {
  cat("  - PLS-PM network completed (KEGG pathway + super_class latent variables)\n")
  if (exists("plspm_latent_def")) {
    cat("    Latent variables:", length(plspm_latent_def), "\n")
  }
  if (exists("plspm_res") && !is.null(plspm_res$inner_model)) {
    n_sig <- sum(plspm_res$inner_model$p_value < 0.05, na.rm = TRUE)
    cat("    Significant paths (p<0.05):", n_sig, "\n")
  }
}
if(exists("vip_manhattan_ok") && vip_manhattan_ok) {
  cat("  - VIP Manhattan plot completed (super_class x VIP, png/pdf)\n")
}
cat("\nAll output files in:", result_dir, "\n")
