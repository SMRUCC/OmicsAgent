# =============================================================================
# PLSDA & OPLSDA Analysis Script
# Module:2_pca_plsda_oplsda_analysis - Step2: Supervised Dimensionality Reduction
# =============================================================================
# Description:
#使用 mixOmics包执行 PLSDA（ncomp=2），使用 ropls包执行 OPLSDA
#（1预测主成分 +1正交主成分），提取样本得分和 VIP值，
#计算加权欧氏距离和置换检验，绘制散点图并保存结果。
#
# Input files:
# - G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv
# - G:/OmicsWorks/test/metabolism/sampleinfo.csv
#
# Output files:
# - CSV: plsda_scores.csv, plsda_vip_scores.csv,
# oplsda_scores.csv, oplsda_s_plot.csv,
# plsda_weighted_distances.csv,
# oplsda_weighted_distances.csv,
# plsda_permutation_test_results.csv,
# oplsda_permutation_test_results.csv,
# oplsda_model_params.csv
# - Figures: PLSDA_score_plot.png/pdf,
# OPLSDA_score_plot.png/pdf,
# PLSDA_VIP_barplot.png/pdf,
# OPLSDA_S_plot.png/pdf
# =============================================================================

# ----0. Environment Setup ----
cat("========================================================\n")
cat(" PLSDA & OPLSDA Analysis - Module2, Step2\n")
cat("========================================================\n\n")

# Define absolute paths
BASE_DIR <- "G:/OmicsWorks/test/metabolism/demo"
TMP_DIR <- file.path(BASE_DIR, "tmp")
OUTPUT_DIR <- file.path(TMP_DIR, "2_pca_plsda_oplsda_analysis")
FIGURE_DIR <- file.path(BASE_DIR, "analysis", "2_pca_plsda_oplsda_analysis", "figures")
AGENT_RSCRIPT_DIR <- "G:/OmicsWorks/agent/rscript"

dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(FIGURE_DIR, showWarnings = FALSE, recursive = TRUE)

# ----1. Install & Load Packages ----
cat("[1] Checking and installing required packages...\n")

required_cran <- c("ggplot2", "ggrepel", "RColorBrewer", "viridis")
required_bioc <- c("mixOmics", "ropls")

if (!requireNamespace("BiocManager", quietly = TRUE))
 install.packages("BiocManager", repos = "https://cloud.r-project.org")

for (pkg in required_cran) {
 if (!requireNamespace(pkg, quietly = TRUE))
 install.packages(pkg, repos = "https://cloud.r-project.org")
}
for (pkg in required_bioc) {
 if (!requireNamespace(pkg, quietly = TRUE))
 BiocManager::install(pkg, ask = FALSE, update = FALSE)
}

library(ggplot2); library(ggrepel); library(RColorBrewer)
library(viridis); library(mixOmics); library(ropls)
cat(" All packages loaded.\n\n")

# ----2. Source Helpers ----
cat("[2] Loading helper scripts...\n")
source(file.path(AGENT_RSCRIPT_DIR, "data_io.R"))
source(file.path(AGENT_RSCRIPT_DIR, "multivariate.R"))
cat(" Helper scripts loaded.\n\n")

# ----3. Read Data ----
cat("[3] Reading input data...\n")

expr_file <- file.path(TMP_DIR, "preprocessed_expression.csv")
meta_file <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"

expr_matrix <- load_expression_matrix(expr_file)
sample_meta <- load_sample_metadata(meta_file)

cat(" Raw expression:", nrow(expr_matrix), "features x", ncol(expr_matrix), "samples\n")
cat(" Raw metadata:", nrow(sample_meta), "rows\n")

# ----4. Filter & Standardize ----
cat("[4] Filtering QC & standardizing groups...\n")

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

cat(" Working with", ncol(expr_matrix), "samples in",
 nlevels(sample_meta$group_label), "groups:\n")
print(table(sample_meta$group_label))

# =========================================================================
# PART A: PLSDA
# =========================================================================
cat("\n========================================================\n")
cat(" PART A: PLSDA with mixOmics\n")
cat("========================================================\n\n")

cat("[A1] Preparing data...\n")
X <- t(expr_matrix)
Y <- sample_meta[rownames(X), "group_label"]
cat(" X matrix:", nrow(X), "samples x", ncol(X), "features\n")
cat(" Y factor:", nlevels(Y), "levels\n")

# ----A2. Run PLSDA ----
cat("[A2] Running PLSDA (ncomp=2)...\n")
plsda_model <- mixOmics::plsda(X, Y, ncomp =2, scale = TRUE)

# Extract scores
plsda_scores <- as.data.frame(plsda_model$variates$X)
colnames(plsda_scores) <- c("Comp1", "Comp2")

# Extract VIP
plsda_vip <- as.data.frame(mixOmics::vip(plsda_model))
colnames(plsda_vip) <- c("Comp1", "Comp2")
plsda_vip$Feature <- rownames(plsda_vip)
plsda_vip$MeanVIP <- rowMeans(plsda_vip[, c("Comp1", "Comp2")])

cat(" VIP range: [", round(min(plsda_vip$MeanVIP),3), ",",
 round(max(plsda_vip$MeanVIP),3), "]\n")
cat(" Features with VIP >1:", sum(plsda_vip$MeanVIP >1), "\n")

# Add metadata
plsda_scores$SampleID <- rownames(plsda_scores)
plsda_scores$Group <- sample_meta[rownames(plsda_scores), "group_label"]
plsda_scores$SampleName <- sample_meta[rownames(plsda_scores), "sample_name"]
plsda_scores$SampleType <- sample_meta[rownames(plsda_scores), "sample_info"]

# ----A3. Save PLSDA Scores & VIP ----
cat("[A3] Saving PLSDA results...\n")
write.csv(plsda_scores, file.path(OUTPUT_DIR, "plsda_scores.csv"), row.names = FALSE)
plsda_vip_out <- plsda_vip[order(-plsda_vip$MeanVIP), ]
write.csv(plsda_vip_out, file.path(OUTPUT_DIR, "plsda_vip_scores.csv"), row.names = FALSE)
cat(" plsda_scores.csv and plsda_vip_scores.csv saved.\n")

# ----A4. PLSDA Weighted Distances ----
cat("[A4] Calculating PLSDA weighted distances...\n")
plsda_var <- plsda_model$prop_expl_var$X
cat(" Comp1 var:", round(plsda_var[1]*100,1),
 "%, Comp2 var:", round(plsda_var[2]*100,1), "%")
# Remove this line now unused
cat(" Comp1 var:", round(plsda_var[1]*100,1),
 "%, Comp2 var:", round(plsda_var[2]*100,1), "%\n")

w_plsda <- plsda_var / sum(plsda_var)
cat(" Weights:", round(w_plsda,4), "\n")

groups <- levels(sample_meta$group_label)

# Centroids
plsda_centroids <- matrix(NA, nrow = length(groups), ncol =2,
 dimnames = list(groups, c("Comp1", "Comp2")))
for (g in groups) {
 idx <- which(plsda_scores$Group == g)
 plsda_centroids[g, ] <- colMeans(plsda_scores[idx, c("Comp1", "Comp2")])
}
cat(" PLSDA centroids:\n"); print(round(plsda_centroids,4))

# Within-group distances
plsda_within <- data.frame(SampleID = plsda_scores$SampleID,
 SampleName = plsda_scores$SampleName,
 Group = plsda_scores$Group,
 stringsAsFactors = FALSE)
for (i in 1:nrow(plsda_scores)) {
 g <- as.character(plsda_scores$Group[i])
 vec <- as.numeric(plsda_scores[i, c("Comp1", "Comp2")])
 plsda_within$Distance[i] <- sqrt(sum(w_plsda * (vec - plsda_centroids[g, ])^2))
}
write.csv(plsda_within, file.path(OUTPUT_DIR, "plsda_weighted_distances.csv"), row.names = FALSE)

# Between-group distances (for permutation)
between_helper <- function(scores, centroids, weights, groups) {
 all_between <- c()
 for (i in 1:nrow(scores)) {
 g <- as.character(scores$Group[i])
 others <- setdiff(groups, g)
 vec <- as.numeric(scores[i, c("Comp1", "Comp2")])
 for (og in others) {
 all_between <- c(all_between, sqrt(sum(weights * (vec - centroids[og, ])^2)))
 }
 }
 mean(all_between)
}

# ----A5. PLSDA Permutation Test ----
cat("[A5] PLSDA permutation test (n=1000)...\n")
obs_within_plsda <- mean(plsda_within$Distance)
obs_between_plsda <- between_helper(plsda_scores, plsda_centroids, w_plsda, groups)
obs_ratio_plsda <- obs_within_plsda / obs_between_plsda
cat(sprintf(" Observed within/between ratio: %.4f\n", obs_ratio_plsda))

set.seed(42)
n_perm <-1000
perm_ratios_plsda <- numeric(n_perm)

for (p in 1:n_perm) {
 perm_labels <- sample(sample_meta$group_label)
 perm_cent <- matrix(NA, nrow = length(groups), ncol =2,
 dimnames = list(groups, c("Comp1", "Comp2")))
 for (g in groups) {
 idx2 <- which(perm_labels == g)
 perm_cent[g, ] <- colMeans(plsda_scores[idx2, c("Comp1", "Comp2")])
 }
 perm_within <- numeric(nrow(plsda_scores))
 for (i in 1:nrow(plsda_scores)) {
 g <- as.character(perm_labels[i])
 vec <- as.numeric(plsda_scores[i, c("Comp1", "Comp2")])
 perm_within[i] <- sqrt(sum(w_plsda * (vec - perm_cent[g, ])^2))
 }
 perm_between <- c()
 for (i in 1:nrow(plsda_scores)) {
 g <- as.character(perm_labels[i])
 others <- setdiff(groups, g)
 vec <- as.numeric(plsda_scores[i, c("Comp1", "Comp2")])
 for (og in others) {
 perm_between <- c(perm_between, sqrt(sum(w_plsda * (vec - perm_cent[og, ])^2)))
 }
 }
 perm_ratios_plsda[p] <- mean(perm_within) / mean(perm_between)
}

p_val_plsda <- sum(perm_ratios_plsda <= obs_ratio_plsda) / n_perm
cat(sprintf(" PLSDA permutation p-value: %.4f\n", p_val_plsda))

plsda_perm_df <- data.frame(
 Metric = c("Observed_Ratio", "Mean_Permuted_Ratio",
 "Perm_2.5%", "Perm_97.5%", "P_Value"),
 Value = c(obs_ratio_plsda, mean(perm_ratios_plsda),
 quantile(perm_ratios_plsda,0.025),
 quantile(perm_ratios_plsda,0.975), p_val_plsda)
)
write.csv(plsda_perm_df, file.path(OUTPUT_DIR, "plsda_permutation_test_results.csv"), row.names = FALSE)

# ----A6. PLSDA Score Plot ----
cat("[A6] Generating PLSDA score plot...\n")
group_colors <- c("NC" = "#4DBBD5", "CD" = "#E64B35", "FE" = "#00A087")
orig_types <- levels(sample_meta$sample_info)
shape_vals <- c(16,17,15,18,8,3,4)
names(shape_vals) <- orig_types[1:min(length(orig_types), length(shape_vals))]

p_plsda <- ggplot(plsda_scores, aes(x = Comp1, y = Comp2,
 color = Group, shape = SampleType)) +
 geom_point(size =3.5, alpha =0.85) +
 stat_ellipse(level =0.95, type = "t", linewidth =0.8,
 aes(fill = Group), alpha =0.1, geom = "polygon") +
 geom_text_repel(aes(label = SampleName), size =3.0,
 max.overlaps =20, box.padding =0.5, show.legend = FALSE) +
 scale_color_manual(values = group_colors,
 labels = c("NC" = "NC (Healthy Control)",
 "CD" = "CD (C. diff Infection)",
 "FE" = "FE (High Iron + CDI)")) +
 scale_fill_manual(values = group_colors, guide = "none") +
 scale_shape_manual(values = shape_vals) +
 labs(title = "PLS-DA Score Plot",
 x = paste0("Component1 (", round(plsda_var[1]*100,1), "%)"),
 y = paste0("Component2 (", round(plsda_var[2]*100,1), "%)"),
 color = "Group", shape = "Condition") +
 theme_bw(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 legend.position = "right",
 panel.grid.minor = element_blank())

ggsave(file.path(FIGURE_DIR, "PLSDA_score_plot.png"), p_plsda, width =9, height =7, dpi =300)
ggsave(file.path(FIGURE_DIR, "PLSDA_score_plot.pdf"), p_plsda, width =9, height =7)
cat(" PLSDA score plot saved.\n")

# ----A7. PLSDA VIP Barplot ----
cat("[A7] Generating PLSDA VIP barplot (top20)...\n")
vip_top <- head(plsda_vip_out[order(-plsda_vip_out$MeanVIP), ],20)
vip_top$Feature <- factor(vip_top$Feature, levels = vip_top$Feature[order(vip_top$MeanVIP)])

p_vip <- ggplot(vip_top, aes(x = Feature, y = MeanVIP, fill = MeanVIP)) +
 geom_bar(stat = "identity") +
 coord_flip() +
 geom_hline(yintercept =1, color = "red", linetype = "dashed", linewidth =0.8) +
 scale_fill_gradient(low = "lightblue", high = "darkred") +
 labs(title = "Top20 VIP Scores (PLS-DA)",
 x = "Metabolite", y = "VIP Score") +
 theme_bw(base_size =11) +
 theme(plot.title = element_text(hjust =0.5, size =13, face = "bold"),
 legend.position = "none")

ggsave(file.path(FIGURE_DIR, "PLSDA_VIP_barplot.png"), p_vip, width =8, height =7, dpi =300)
ggsave(file.path(FIGURE_DIR, "PLSDA_VIP_barplot.pdf"), p_vip, width =8, height =7)
cat(" PLSDA VIP barplot saved.\n")

# =========================================================================
# PART B: OPLSDA (pairwise binary comparisons)
# Note: ropls OPLS-DA only supports binary classification.
# We run3 pairwise comparisons: FE_vs_NC, CD_vs_NC, FE_vs_CD
# =========================================================================
cat("\n========================================================\n")
cat(" PART B: OPLSDA - Pairwise Comparisons\n")
cat("========================================================\n\n")

pairwise_list <- list(
 c("FE", "NC"),
 c("CD", "NC"),
 c("FE", "CD")
)
pairwise_names <- c("FE_vs_NC", "CD_vs_NC", "FE_vs_CD")

all_opls_scores <- list()
all_splot_data <- list()
all_opls_params <- list()

for (pw_idx in seq_along(pairwise_list)) {
 pw <- pairwise_list[[pw_idx]]
 pw_name <- pairwise_names[pw_idx]
 cat(sprintf("\n[B%d] Running OPLSDA: %s\n", pw_idx, pw_name))
  
 # Subset data for this pair
 keep_samples <- rownames(X)[sample_meta[rownames(X), "group_label"] %in% pw]
 X_pair <- X[keep_samples, , drop = FALSE]
 Y_pair <- factor(as.character(sample_meta[keep_samples, "group_label"]))
  
 cat(" Samples:", nrow(X_pair), " Features:", ncol(X_pair), "\n")
 cat(" Groups:", paste(levels(Y_pair), collapse=" vs "), "\n")
  
 # Run OPLSDA
 set.seed(42)
 opls_pair <- ropls::opls(X_pair, Y_pair, predI =1, orthoI =1,
 fig.pdfC = "none", info.txtC = "none",
 permI =0)
  
 # Extract parameters
 mdl_df <- opls_pair@modelDF
 r2x_pred <- ifelse(nrow(mdl_df) >=1, mdl_df[1, "R2X"], NA)
 r2x_orth <- ifelse(nrow(mdl_df) >=2, mdl_df[2, "R2X"], NA)
 r2y <- ifelse(nrow(mdl_df) >=1, mdl_df[1, "R2Y"], NA)
 q2 <- ifelse(nrow(mdl_df) >=1, mdl_df[1, "Q2"], NA)
 cat(sprintf(" R2X(pred)=%.3f, R2X(orth)=%.3f, R2Y=%.3f, Q2=%.3f\n",
 r2x_pred, r2x_orth, r2y, q2))
  
 all_opls_params[[pw_name]] <- data.frame(
 Comparison = pw_name,
 R2X_pred = r2x_pred, R2X_orth = r2x_orth,
 R2Y = r2y, Q2 = q2,
 stringsAsFactors = FALSE
 )
  
 # Scores
 scores_pair <- as.data.frame(ropls::getScoreMN(opls_pair))
 ncol_sp <- ncol(scores_pair)
 colnames(scores_pair) <- paste0("Comp",1:ncol_sp)
 if (ncol_sp ==1) scores_pair$Comp2 <- rep(0, nrow(scores_pair))
 scores_pair$SampleID <- rownames(scores_pair)
 scores_pair$Group <- sample_meta[rownames(scores_pair), "group_label"]
 scores_pair$SampleName <- sample_meta[rownames(scores_pair), "sample_name"]
 scores_pair$SampleType <- sample_meta[rownames(scores_pair), "sample_info"]
 scores_pair$Comparison <- pw_name
 all_opls_scores[[pw_name]] <- scores_pair
  
 # VIP
 vip_pair <- ropls::getVipVn(opls_pair)
  
 # S-plot data
 load_pair <- ropls::getLoadingMN(opls_pair)
 # Compute p(corr) manually: correlation between each feature and predictive score
 pred_scores <- opls_pair@scoreMN[,1, drop=FALSE]
 pcorr_pair <- apply(X_pair,2, function(x) cor(x, pred_scores[,1]))
  
 splot_pair <- data.frame(
 Feature = rownames(load_pair),
 Loading = as.numeric(load_pair[,1]),
 pcorr = as.numeric(pcorr_pair),
 Comparison = pw_name,
 stringsAsFactors = FALSE
 )
 splot_pair$VIP <- vip_pair[splot_pair$Feature]
 splot_pair$abs_loading <- abs(splot_pair$Loading)
 splot_pair$abs_pcorr <- abs(splot_pair$pcorr)
 splot_pair$Importance <- ifelse(
 splot_pair$VIP >1 & splot_pair$abs_pcorr >0.5,
 "High (VIP>1 & |p(corr)|>0.5)",
 ifelse(splot_pair$VIP >1, "Medium (VIP>1)", "Low")
 )
 all_splot_data[[pw_name]] <- splot_pair
 cat(sprintf(" Important metabolites (VIP>1 & |p(corr)|>0.5): %d\n",
 sum(splot_pair$Importance == "High (VIP>1 & |p(corr)|>0.5)")))
}

# Combine and save
opls_params_all <- do.call(rbind, all_opls_params)
write.csv(opls_params_all, file.path(OUTPUT_DIR, "oplsda_model_params.csv"), row.names = FALSE)
cat("\n oplda_model_params.csv saved.\n")

opls_scores_all <- do.call(rbind, all_opls_scores)
write.csv(opls_scores_all, file.path(OUTPUT_DIR, "oplsda_scores.csv"), row.names = FALSE)
cat(" oplda_scores.csv saved.\n")

splot_all <- do.call(rbind, all_splot_data)
write.csv(splot_all, file.path(OUTPUT_DIR, "oplsda_s_plot.csv"), row.names = FALSE)
cat(" oplda_s_plot.csv saved.\n")

# ----B3. OPLSDA Score Plot (combining all pairwise for visualization) ----
cat("[B3] Generating OPLSDA score plots...\n")
for (pw_name in pairwise_names) {
 sc <- all_opls_scores[[pw_name]]
 sc_df <- all_splot_data[[pw_name]]
  
 # Color for the two groups in this comparison
 comp_colors <- group_colors[names(group_colors) %in% unique(as.character(sc$Group))]
  
 p_opls <- ggplot(sc, aes(x = Comp1, y = Comp2,
 color = Group, shape = SampleType)) +
 geom_point(size =4, alpha =0.9) +
 stat_ellipse(level =0.95, type = "t", linewidth =0.8) +
 geom_text_repel(aes(label = SampleName), size =3.0,
 max.overlaps =20, box.padding =0.5, show.legend = FALSE) +
 scale_color_manual(values = comp_colors) +
 scale_shape_manual(values = shape_vals) +
 labs(title = paste0("OPLS-DA Score Plot (", pw_name, ")"),
 x = "Predictive Component (p1)",
 y = "Orthogonal Component (o1)",
 color = "Group", shape = "Condition",
 subtitle = paste0("R2Y=", round(all_opls_params[[pw_name]]$R2Y,3),
 ", Q2=", round(all_opls_params[[pw_name]]$Q2,3))) +
 theme_bw(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, size =13, face = "bold"),
 legend.position = "right", panel.grid.minor = element_blank())
  
 ggsave(file.path(FIGURE_DIR, paste0("OPLSDA_score_plot_", pw_name, ".png")),
 p_opls, width =8, height =6, dpi =300)
 ggsave(file.path(FIGURE_DIR, paste0("OPLSDA_score_plot_", pw_name, ".pdf")),
 p_opls, width =8, height =6)
 cat(" OPLSDA score plot saved for", pw_name, "\n")
}

# ----B4. OPLSDA S-plots ----
cat("[B4] OPLSDA S-plot for each pairwise comparison...\n")
for (pw_name in pairwise_names) {
 sp <- all_splot_data[[pw_name]]
 sp$label <- ifelse(sp$Importance == "High (VIP>1 & |p(corr)|>0.5)", sp$Feature, "")
  
 p_splot <- ggplot(sp, aes(x = Loading, y = pcorr, color = Importance)) +
 geom_point(size =1.8, alpha =0.7) +
 geom_text_repel(aes(label = label), size =2.8, max.overlaps =12,
 box.padding =0.4, show.legend = FALSE) +
 geom_hline(yintercept =0, linetype = "dashed", color = "grey50", linewidth =0.5) +
 geom_vline(xintercept =0, linetype = "dashed", color = "grey50", linewidth =0.5) +
 scale_color_manual(values = c("High (VIP>1 & |p(corr)|>0.5)" = "#E64B35",
 "Medium (VIP>1)" = "#00A087", "Low" = "grey70")) +
 labs(title = paste0("OPLS-DA S-Plot (", pw_name, ")"),
 x = "Loading (p[1])", y = "Correlation (p(corr)[1])",
 color = "Importance") +
 theme_bw(base_size =11) +
 theme(plot.title = element_text(hjust =0.5, size =12, face = "bold"),
 legend.position = "right")
  
 ggsave(file.path(FIGURE_DIR, paste0("OPLSDA_S_plot_", pw_name, ".png")),
 p_splot, width =9, height =7, dpi =300)
 ggsave(file.path(FIGURE_DIR, paste0("OPLSDA_S_plot_", pw_name, ".pdf")),
 p_splot, width =9, height =7)
 cat(" OPLSDA S-plot saved for", pw_name, "\n")
}

# ----B5. OPLSDA Weighted Distances ----
cat("[B5] Calculating OPLSDA weighted distances...\n")
w_opls <- c(0.6,0.4)

# Reconstruct full opls scores for distance calculation
# Use FE_vs_NC comparison as base for all samples (most comprehensive)
opls_base <- all_opls_scores[["FE_vs_NC"]]
opls_base_all <- opls_base[match(sample_meta$ID, opls_base$SampleID), ]

# But we have scores only for FE and NC samples, not CD
# Let's compute distances per pairwise comparison
opls_dist_list <- list()
for (pw_name in pairwise_names) {
 sc <- all_opls_scores[[pw_name]]
 grps <- unique(as.character(sc$Group))
  
 cent <- matrix(NA, nrow = length(grps), ncol =2,
 dimnames = list(grps, c("Comp1", "Comp2")))
 for (g in grps) {
 idx <- which(sc$Group == g)
 cent[g, ] <- colMeans(sc[idx, c("Comp1", "Comp2")])
 }
  
 dist_df <- data.frame(SampleID = sc$SampleID, Group = sc$Group,
 Comparison = pw_name, stringsAsFactors = FALSE)
 for (i in 1:nrow(sc)) {
 g <- as.character(sc$Group[i])
 vec <- as.numeric(sc[i, c("Comp1", "Comp2")])
 dist_df$Distance[i] <- sqrt(sum(w_opls * (vec - cent[g, ])^2))
 }
 opls_dist_list[[pw_name]] <- dist_df
}
opls_dist_all <- do.call(rbind, opls_dist_list)
write.csv(opls_dist_all, file.path(OUTPUT_DIR, "oplsda_weighted_distances.csv"), row.names = FALSE)
cat(" oplda_weighted_distances.csv saved.\n")

# ----B6. OPLSDA Permutation Test (per comparison) ----
cat("[B6] OPLSDA permutation test (n=1000 per pair)...\n")
set.seed(42)
n_perm <-1000
opls_perm_list <- list()

for (pw_name in pairwise_names) {
 sc <- all_opls_scores[[pw_name]]
 grps <- unique(as.character(sc$Group))
  
 # Observe centroids
 cent <- matrix(NA, nrow = length(grps), ncol =2,
 dimnames = list(grps, c("Comp1", "Comp2")))
 for (g in grps) {
 idx <- which(sc$Group == g)
 cent[g, ] <- colMeans(sc[idx, c("Comp1", "Comp2")])
 }
  
 # Observed within distance
 obs_within <- mean(sapply(1:nrow(sc), function(i) {
 g <- as.character(sc$Group[i])
 sqrt(sum(w_opls * (as.numeric(sc[i, c("Comp1", "Comp2")]) - cent[g, ])^2))
 }))
  
 # Observed between distance
 obs_between <- mean(unlist(lapply(1:nrow(sc), function(i) {
 g <- as.character(sc$Group[i])
 og <- setdiff(grps, g)
 sapply(og, function(og2) {
 sqrt(sum(w_opls * (as.numeric(sc[i, c("Comp1", "Comp2")]) - cent[og2, ])^2))
 })
 })))
 obs_ratio <- obs_within / obs_between
  
 # Permutation
 perm_ratios <- numeric(n_perm)
 for (p in 1:n_perm) {
 perm_lab <- sample(sc$Group)
 perm_cent <- matrix(NA, nrow = length(grps), ncol =2,
 dimnames = list(grps, c("Comp1", "Comp2")))
 for (g in grps) {
 idx2 <- which(perm_lab == g)
 perm_cent[g, ] <- colMeans(sc[idx2, c("Comp1", "Comp2")])
 }
 pw_perm <- sapply(1:nrow(sc), function(i) {
 g <- as.character(perm_lab[i])
 sqrt(sum(w_opls * (as.numeric(sc[i, c("Comp1", "Comp2")]) - perm_cent[g, ])^2))
 })
 pb_perm <- unlist(lapply(1:nrow(sc), function(i) {
 g <- as.character(perm_lab[i])
 sapply(setdiff(grps, g), function(og2) {
 sqrt(sum(w_opls * (as.numeric(sc[i, c("Comp1", "Comp2")]) - perm_cent[og2, ])^2))
 })
 }))
 perm_ratios[p] <- mean(pw_perm) / mean(pb_perm)
 }
  
 p_val <- sum(perm_ratios <= obs_ratio) / n_perm
 cat(sprintf(" %s: ratio=%.4f, p=%.4f\n", pw_name, obs_ratio, p_val))
  
 opls_perm_list[[pw_name]] <- data.frame(
 Comparison = pw_name,
 Observed_Ratio = obs_ratio,
 Mean_Permuted_Ratio = mean(perm_ratios),
 Perm_2.5 = quantile(perm_ratios,0.025),
 Perm_97.5 = quantile(perm_ratios,0.975),
 P_Value = p_val,
 stringsAsFactors = FALSE
 )
}

opls_perm_all <- do.call(rbind, opls_perm_list)
write.csv(opls_perm_all, file.path(OUTPUT_DIR, "oplsda_permutation_test_results.csv"), row.names = FALSE)
cat(" oplda_permutation_test_results.csv saved.\n")

# ----B7. Summary of best pairwise comparison ----
cat("[B7] OPLSDA comparison summary...\n")
best_q2 <- which.max(opls_params_all$Q2)
cat(sprintf(" Best OPLSDA model: %s (Q2=%.3f)\n",
 opls_params_all$Comparison[best_q2], opls_params_all$Q2[best_q2]))
# =========================================================================
# SUMMARY OUTPUT
# =========================================================================
cat("\n========================================================\n")
cat(" PLSDA & OPLSDA Analysis Completed!\n")
cat("========================================================\n\n")

cat(" Key results:\n")
cat(sprintf(" PLSDA: VIP>1 metabolites: %d\n", sum(plsda_vip_out$MeanVIP >1)))
cat(sprintf(" PLSDA permutation p-value: %.4f\n", p_val_plsda))
cat(sprintf(" PLSDA permutation p-value: %.4f\n", p_val_plsda))
best_opls <- opls_params_all[which.max(opls_params_all$Q2), ]
cat(sprintf(" OPLSDA best model: %s (R2X_pred=%.3f, R2Y=%.3f, Q2=%.3f)\n",
 best_opls$Comparison, best_opls$R2X_pred, best_opls$R2Y, best_opls$Q2))
cat(sprintf(" PLSDA: VIP>1 metabolites: %d\n", sum(plsda_vip_out$MeanVIP >1)))
for (pw_nm in pairwise_names) {
 sp_cnt <- sum(all_splot_data[[pw_nm]]$Importance == "High (VIP>1 & |p(corr)|>0.5)")
 cat(sprintf(" OPLSDA(%s): High-importance metabolites: %d\n", pw_nm, sp_cnt))
}
cat("\n")

if (p_val_plsda <0.05) cat(" => PLSDA group separation significant (p<0.05)\n")
else cat(" => PLSDA group separation NOT significant (p>=0.05)\n")

for (pw_nm in pairwise_names) {
 pv <- opls_perm_all$P_Value[opls_perm_all$Comparison == pw_nm]
 q2v <- opls_params_all$Q2[opls_params_all$Comparison == pw_nm]
 if (pv <0.05) {
 cat(sprintf(" => OPLSDA(%s) separation significant (p=%.4f, Q2=%.3f)\n", pw_nm, pv, q2v))
 } else {
 cat(sprintf(" => OPLSDA(%s) separation NOT significant (p=%.4f, Q2=%.3f)\n", pw_nm, pv, q2v))
 }
 if (q2v >=0.4) cat(sprintf(" => OPLSDA(%s) good predictive ability\n", pw_nm))
 else if (q2v >=0) cat(sprintf(" => OPLSDA(%s) moderate predictive ability\n", pw_nm))
 else cat(sprintf(" => OPLSDA(%s) may be overfitted\n", pw_nm))
}
cat("\nOutput files:\n")
cat(" CSV in:", OUTPUT_DIR, "\n")
cat(" - plsda_scores.csv, plsda_vip_scores.csv\n")
cat(" - plsda_weighted_distances.csv, plsda_permutation_test_results.csv\n")
cat(" - oplsda_scores.csv, oplsda_s_plot.csv, oplsda_model_params.csv\n")
cat(" - oplsda_weighted_distances.csv, oplsda_permutation_test_results.csv\n")
cat(" Figures in:", FIGURE_DIR, "\n")
cat(" - PLSDA_score_plot.png/pdf, PLSDA_VIP_barplot.png/pdf\n")
cat(" - OPLSDA_score_plot.png/pdf, OPLSDA_S_plot.png/pdf\n")
cat("\nDone.\n")
