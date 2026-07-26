# =============================================================================
# PLSDA & OPLSDA Analysis Script (Step2)
# Module:2_pca_plsda_oplsda_analysis
# =============================================================================
# Description:
#使用 mixOmics执行 PLSDA（有监督降维），使用 ropls执行 OPLSDA
# （成对比较）。提取得分、VIP、S-plot、模型参数，计算加权欧氏距离
#和置换检验，生成图形。
#
# Output CSV -> tmp/2_pca_plsda_oplsda_analysis/
# Output Figures -> analysis/2_pca_plsda_oplsda_analysis/figures/
# =============================================================================

# ----0. Setup ----
cat("========================================================\n")
cat(" PLSDA & OPLSDA Analysis - Module2, Step2\n")
cat("========================================================\n\n")

BASE_DIR <- "G:/OmicsWorks/test/metabolism/demo"
TMP_DIR <- file.path(BASE_DIR, "tmp")
OUTPUT_DIR <- file.path(TMP_DIR, "2_pca_plsda_oplsda_analysis")
FIGURE_DIR <- file.path(BASE_DIR, "analysis", "2_pca_plsda_oplsda_analysis", "figures")
AGENT_RSCRIPT <- "G:/OmicsWorks/agent/rscript"

dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(FIGURE_DIR, showWarnings = FALSE, recursive = TRUE)

# ----1. Install & Load Packages ----
cat("[1] Installing and loading required R packages...\n")

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
source(file.path(AGENT_RSCRIPT, "data_io.R"))
source(file.path(AGENT_RSCRIPT, "multivariate.R"))
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
cat("[4] Filtering QC samples & standardizing groups...\n")

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
cat("[A2] Running PLSDA (ncomp=2, scale=TRUE)...\n")
plsda_model <- mixOmics::plsda(X, Y, ncomp =2, scale = TRUE)

# Extract scores
plsda_scores <- as.data.frame(plsda_model$variates$X)
colnames(plsda_scores) <- c("Comp1", "Comp2")

# Extract VIP
plsda_vip <- as.data.frame(mixOmics::vip(plsda_model))
colnames(plsda_vip) <- c("Comp1", "Comp2")
plsda_vip$Feature <- rownames(plsda_vip)
plsda_vip$MeanVIP <- rowMeans(plsda_vip[, c("Comp1", "Comp2")], na.rm = TRUE)

cat(" VIP range: [", round(min(plsda_vip$MeanVIP, na.rm = TRUE),3), ",",
 round(max(plsda_vip$MeanVIP, na.rm = TRUE),3), "]\n")
cat(" Features with VIP >1:", sum(plsda_vip$MeanVIP >1, na.rm = TRUE), "\n")

# Add metadata to scores
plsda_scores$SampleID <- rownames(plsda_scores)
plsda_scores$Group <- sample_meta[rownames(plsda_scores), "group_label"]
plsda_scores$SampleName <- sample_meta[rownames(plsda_scores), "sample_name"]
plsda_scores$SampleType <- sample_meta[rownames(plsda_scores), "sample_info"]

# ----A3. Save PLSDA Scores & VIP ----
cat("[A3] Saving PLSDA results...\n")
write.csv(plsda_scores, file.path(OUTPUT_DIR, "plsda_scores.csv"), row.names = FALSE)
plsda_vip_out <- plsda_vip[order(-plsda_vip$MeanVIP), ]
write.csv(plsda_vip_out, file.path(OUTPUT_DIR, "plsda_vip_scores.csv"), row.names = FALSE)
cat(" -> plsda_scores.csv & plsda_vip_scores.csv saved.\n")

# ----A4. PLSDA Weighted Distances ----
cat("[A4] Calculating PLSDA weighted distances...\n")

# Variance explained per component (X variates)
plsda_var <- plsda_model$prop_expl_var$X
cat(sprintf(" Comp1 var: %.2f%%, Comp2 var: %.2f%%\n",
 plsda_var[1] *100, plsda_var[2] *100))

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
cat(" PLSDA centroids:\n")
print(round(plsda_centroids,4))

# Within-group distances
plsda_within <- data.frame(
 SampleID = plsda_scores$SampleID,
 SampleName = plsda_scores$SampleName,
 Group = plsda_scores$Group,
 stringsAsFactors = FALSE
)
for (i in 1:nrow(plsda_scores)) {
 g <- as.character(plsda_scores$Group[i])
 vec <- as.numeric(plsda_scores[i, c("Comp1", "Comp2")])
 plsda_within$Distance[i] <- sqrt(sum(w_plsda * (vec - plsda_centroids[g, ])^2))
}

write.csv(plsda_within, file.path(OUTPUT_DIR, "plsda_weighted_distances.csv"), row.names = FALSE)
cat(" -> plsda_weighted_distances.csv saved.\n")

# ----A5. PLSDA Permutation Test ----
cat("[A5] PLSDA permutation test (n=1000)...\n")

# Observed statistics
mean_within_plsda <- mean(plsda_within$Distance)

# Between distances
between_plsda <- c()
for (i in 1:nrow(plsda_scores)) {
 g <- as.character(plsda_scores$Group[i])
 vec <- as.numeric(plsda_scores[i, c("Comp1", "Comp2")])
 for (og in setdiff(groups, g)) {
 between_plsda <- c(between_plsda,
 sqrt(sum(w_plsda * (vec - plsda_centroids[og, ])^2)))
 }
}
mean_between_plsda <- mean(between_plsda)
obs_ratio_plsda <- mean_within_plsda / mean_between_plsda

cat(sprintf(" Observed within/between ratio: %.4f\n", obs_ratio_plsda))

# Permutation
set.seed(42)
n_perm <-1000
perm_ratios_plsda <- numeric(n_perm)

for (p in 1:n_perm) {
 perm_labels <- sample(sample_meta$group_label)

 # Permuted centroids
 perm_cent <- matrix(NA, nrow = length(groups), ncol =2,
 dimnames = list(groups, c("Comp1", "Comp2")))
 for (g in groups) {
 idx2 <- which(perm_labels == g)
 perm_cent[g, ] <- colMeans(plsda_scores[idx2, c("Comp1", "Comp2")])
 }

 # Permuted within
 pw <- numeric(nrow(plsda_scores))
 for (i in 1:nrow(plsda_scores)) {
 g <- as.character(perm_labels[i])
 vec <- as.numeric(plsda_scores[i, c("Comp1", "Comp2")])
 pw[i] <- sqrt(sum(w_plsda * (vec - perm_cent[g, ])^2))
 }

 # Permuted between
 pb <- c()
 for (i in 1:nrow(plsda_scores)) {
 g <- as.character(perm_labels[i])
 vec <- as.numeric(plsda_scores[i, c("Comp1", "Comp2")])
 for (og in setdiff(groups, g)) {
 pb <- c(pb, sqrt(sum(w_plsda * (vec - perm_cent[og, ])^2)))
 }
 }
 perm_ratios_plsda[p] <- mean(pw) / mean(pb)
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
write.csv(plsda_perm_df, file.path(OUTPUT_DIR, "plsda_permutation_test_results.csv"),
 row.names = FALSE)
cat(" -> plsda_permutation_test_results.csv saved.\n")

# ----A6. PLSDA Score Plot ----
cat("[A6] Generating PLSDA score plot...\n")

group_colors <- c("NC" = "#4DBBD5", "CD" = "#E64B35", "FE" = "#00A087")
orig_types <- levels(sample_meta$sample_info)
shape_vals <- c(16,17,15,18,8,3,4)
names(shape_vals) <- orig_types[1:min(length(orig_types), length(shape_vals))]

legend_labels <- c(
 "NC" = "NC (Healthy Control)",
 "CD" = "CD (C. diff Infection)",
 "FE" = "FE (High Iron + CDI)"
)

p_plsda <- ggplot(plsda_scores, aes(x = Comp1, y = Comp2,
 color = Group, shape = SampleType)) +
 geom_point(size =3.5, alpha =0.85) +
 stat_ellipse(level =0.95, type = "t", linewidth =0.8,
 aes(fill = Group), alpha =0.1, geom = "polygon") +
 geom_text_repel(aes(label = SampleName), size =3.0,
 max.overlaps =20, box.padding =0.5,
 show.legend = FALSE) +
 scale_color_manual(values = group_colors, labels = legend_labels) +
 scale_fill_manual(values = group_colors, guide = "none") +
 scale_shape_manual(values = shape_vals) +
 labs(title = "PLS-DA Score Plot",
 x = paste0("Component1 (", round(plsda_var[1] *100,1), "%)"),
 y = paste0("Component2 (", round(plsda_var[2] *100,1), "%)"),
 color = "Group", shape = "Condition") +
 theme_bw(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 legend.position = "right",
 panel.grid.minor = element_blank())

ggsave(file.path(FIGURE_DIR, "PLSDA_score_plot.png"), p_plsda,
 width =9, height =7, dpi =300)
ggsave(file.path(FIGURE_DIR, "PLSDA_score_plot.pdf"), p_plsda,
 width =9, height =7)
cat(" -> PLSDA score plot saved.\n")

# ----A7. PLSDA VIP Barplot (Top20) ----
cat("[A7] Generating PLSDA VIP barplot (top20)...\n")

vip_top <- head(plsda_vip_out[order(-plsda_vip_out$MeanVIP), ],20)
vip_top$Feature <- factor(vip_top$Feature,
 levels = vip_top$Feature[order(vip_top$MeanVIP)])

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

ggsave(file.path(FIGURE_DIR, "PLSDA_VIP_barplot.png"), p_vip,
 width =8, height =7, dpi =300)
ggsave(file.path(FIGURE_DIR, "PLSDA_VIP_barplot.pdf"), p_vip,
 width =8, height =7)
cat(" -> PLSDA VIP barplot saved.\n")

# =========================================================================
# PART B: OPLSDA (Pairwise Binary Comparisons)
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

# Weights for OPLSDA distance (predictive comp gets0.6, orthogonal gets0.4)
w_opls <- c(0.6,0.4)

all_opls_scores <- list()
all_splot_data <- list()
all_opls_params <- list()
all_opls_perm <- list()
all_opls_dist <- list()

for (pw_idx in seq_along(pairwise_list)) {
 pw <- pairwise_list[[pw_idx]]
 pw_name <- pairwise_names[pw_idx]
 cat(sprintf("\n[B%d] Running OPLSDA: %s\n", pw_idx, pw_name))

 # Subset data for this pair
 keep_samples <- rownames(X)[sample_meta[rownames(X), "group_label"] %in% pw]
 X_pair <- X[keep_samples, , drop = FALSE]
 Y_pair <- factor(as.character(sample_meta[keep_samples, "group_label"]))

 cat(" Samples:", nrow(X_pair), " Features:", ncol(X_pair), "\n")
 cat(" Groups:", paste(levels(Y_pair), collapse = " vs "), "\n")

 # Run OPLSDA with1 predictive +1 orthogonal component
 set.seed(42)
 opls_pair <- ropls::opls(X_pair, Y_pair, predI =1, orthoI =1,
 fig.pdfC = "none", info.txtC = "none",
 permI =0)

 # ----B1a. Extract Model Parameters ----
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

 # ----B1b. Extract Scores ----
 scores_pair <- as.data.frame(ropls::getScoreMN(opls_pair))
 ncol_sp <- ncol(scores_pair)
 colnames(scores_pair) <- paste0("Comp",1:ncol_sp)
 # If only1 column (predictive), add zero column for orthogonal
 if (ncol_sp ==1) scores_pair$Comp2 <- rep(0, nrow(scores_pair))
 if (ncol_sp >=2) colnames(scores_pair)[2] <- "Comp2"

 scores_pair$SampleID <- rownames(scores_pair)
 scores_pair$Group <- sample_meta[rownames(scores_pair), "group_label"]
 scores_pair$SampleName <- sample_meta[rownames(scores_pair), "sample_name"]
 scores_pair$SampleType <- sample_meta[rownames(scores_pair), "sample_info"]
 scores_pair$Comparison <- pw_name
 all_opls_scores[[pw_name]] <- scores_pair

 # ----B1c. Compute S-plot data ----
 load_pair <- ropls::getLoadingMN(opls_pair)
 pred_scores <- as.matrix(opls_pair@scoreMN[,1, drop = FALSE])
 pcorr_pair <- apply(X_pair,2, function(x) cor(x, pred_scores[,1]))

 # VIP from OPLS
 vip_pair <- ropls::getVipVn(opls_pair)
 names(vip_pair) <- names(pcorr_pair)

 splot_pair <- data.frame(
 Feature = names(pcorr_pair),
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

 high_count <- sum(splot_pair$Importance == "High (VIP>1 & |p(corr)|>0.5)")
 cat(sprintf(" High-importance metabolites: %d\n", high_count))

 # ----B2. OPLSDA Weighted Distances ----
 grps <- unique(as.character(scores_pair$Group))

 # Centroids
 cent <- matrix(NA, nrow = length(grps), ncol =2,
 dimnames = list(grps, c("Comp1", "Comp2")))
 for (g in grps) {
 idx <- which(scores_pair$Group == g)
 cent[g, ] <- colMeans(scores_pair[idx, c("Comp1", "Comp2")])
 }

 dist_df <- data.frame(
 SampleID = scores_pair$SampleID,
 SampleName = scores_pair$SampleName,
 Group = scores_pair$Group,
 Comparison = pw_name,
 stringsAsFactors = FALSE
 )
 for (i in 1:nrow(scores_pair)) {
 g <- as.character(scores_pair$Group[i])
 vec <- as.numeric(scores_pair[i, c("Comp1", "Comp2")])
 dist_df$Distance[i] <- sqrt(sum(w_opls * (vec - cent[g, ])^2))
 }
 all_opls_dist[[pw_name]] <- dist_df

 # ----B3. OPLSDA Permutation Test ----
 # Observed within
 obs_within_op <- mean(dist_df$Distance)

 # Observed between
 obs_between_op <- c()
 for (i in 1:nrow(scores_pair)) {
 g <- as.character(scores_pair$Group[i])
 vec <- as.numeric(scores_pair[i, c("Comp1", "Comp2")])
 for (og in setdiff(grps, g)) {
 obs_between_op <- c(obs_between_op,
 sqrt(sum(w_opls * (vec - cent[og, ])^2)))
 }
 }
 obs_ratio_op <- obs_within_op / mean(obs_between_op)

 # Permutation
 perm_ratios_op <- numeric(n_perm)
 for (p in 1:n_perm) {
 perm_lab <- sample(scores_pair$Group)
 perm_cent <- matrix(NA, nrow = length(grps), ncol =2,
 dimnames = list(grps, c("Comp1", "Comp2")))
 for (g in grps) {
 idx2 <- which(perm_lab == g)
 perm_cent[g, ] <- colMeans(scores_pair[idx2, c("Comp1", "Comp2")])
 }

 pw_p <- numeric(nrow(scores_pair))
 for (i in 1:nrow(scores_pair)) {
 g <- as.character(perm_lab[i])
 vec <- as.numeric(scores_pair[i, c("Comp1", "Comp2")])
 pw_p[i] <- sqrt(sum(w_opls * (vec - perm_cent[g, ])^2))
 }

 pb_p <- c()
 for (i in 1:nrow(scores_pair)) {
 g <- as.character(perm_lab[i])
 vec <- as.numeric(scores_pair[i, c("Comp1", "Comp2")])
 for (og in setdiff(grps, g)) {
 pb_p <- c(pb_p, sqrt(sum(w_opls * (vec - perm_cent[og, ])^2)))
 }
 }
 perm_ratios_op[p] <- mean(pw_p) / mean(pb_p)
 }

 p_val_op <- sum(perm_ratios_op <= obs_ratio_op) / n_perm
 cat(sprintf(" %s: ratio=%.4f, p=%.4f\n", pw_name, obs_ratio_op, p_val_op))

 all_opls_perm[[pw_name]] <- data.frame(
 Comparison = pw_name,
 Observed_Ratio = obs_ratio_op,
 Mean_Permuted_Ratio = mean(perm_ratios_op),
 Perm_2.5 = quantile(perm_ratios_op,0.025),
 Perm_97.5 = quantile(perm_ratios_op,0.975),
 P_Value = p_val_op,
 stringsAsFactors = FALSE
 )
}

# ----B4. Save OPLSDA Results ----
cat("\n[B4] Saving OPLSDA results to CSV...\n")

# Model params
opls_params_all <- do.call(rbind, all_opls_params)
write.csv(opls_params_all, file.path(OUTPUT_DIR, "oplsda_model_params.csv"),
 row.names = FALSE)
cat(" -> oplsda_model_params.csv saved.\n")

# Scores
opls_scores_all <- do.call(rbind, all_opls_scores)
write.csv(opls_scores_all, file.path(OUTPUT_DIR, "oplsda_scores.csv"),
 row.names = FALSE)
cat(" -> oplsda_scores.csv saved.\n")

# S-plot
splot_all <- do.call(rbind, all_splot_data)
write.csv(splot_all, file.path(OUTPUT_DIR, "oplsda_s_plot.csv"),
 row.names = FALSE)
cat(" -> oplsda_s_plot.csv saved.\n")

# Weighted distances
opls_dist_all <- do.call(rbind, all_opls_dist)
write.csv(opls_dist_all, file.path(OUTPUT_DIR, "oplsda_weighted_distances.csv"),
 row.names = FALSE)
cat(" -> oplsda_weighted_distances.csv saved.\n")

# Permutation results
opls_perm_all <- do.call(rbind, all_opls_perm)
write.csv(opls_perm_all, file.path(OUTPUT_DIR, "oplsda_permutation_test_results.csv"),
 row.names = FALSE)
cat(" -> oplsda_permutation_test_results.csv saved.\n")

# ----B5. OPLSDA Score Plots ----
cat("[B5] Generating OPLSDA score plots...\n")

for (pw_name in pairwise_names) {
 sc <- all_opls_scores[[pw_name]]
 comp_colors <- group_colors[names(group_colors) %in% unique(as.character(sc$Group))]

 param <- all_opls_params[[pw_name]]
 subtitle_text <- paste0("R2Y=", round(param$R2Y,3),
 ", Q2=", round(param$Q2,3))

 p_opls <- ggplot(sc, aes(x = Comp1, y = Comp2,
 color = Group, shape = SampleType)) +
 geom_point(size =4, alpha =0.9) +
 stat_ellipse(level =0.95, type = "t", linewidth =0.8,
 aes(fill = Group), alpha =0.1, geom = "polygon") +
 geom_text_repel(aes(label = SampleName), size =3.0,
 max.overlaps =20, box.padding =0.5,
 show.legend = FALSE) +
 scale_color_manual(values = comp_colors) +
 scale_fill_manual(values = comp_colors, guide = "none") +
 scale_shape_manual(values = shape_vals) +
 labs(title = paste0("OPLS-DA Score Plot (", pw_name, ")"),
 x = "Predictive Component (p1)",
 y = "Orthogonal Component (o1)",
 color = "Group", shape = "Condition",
 subtitle = subtitle_text) +
 theme_bw(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, size =13, face = "bold"),
 plot.subtitle = element_text(hjust =0.5, size =10, color = "grey40"),
 legend.position = "right",
 panel.grid.minor = element_blank())

 ggsave(file.path(FIGURE_DIR, paste0("OPLSDA_score_plot_", pw_name, ".png")),
 p_opls, width =8, height =6, dpi =300)
 ggsave(file.path(FIGURE_DIR, paste0("OPLSDA_score_plot_", pw_name, ".pdf")),
 p_opls, width =8, height =6)
 cat(" -> OPLSDA score plot saved for", pw_name, "\n")
}

# ----B6. OPLSDA S-plots ----
cat("[B6] Generating OPLSDA S-plots...\n")

for (pw_name in pairwise_names) {
 sp <- all_splot_data[[pw_name]]
 sp$label <- ifelse(sp$Importance == "High (VIP>1 & |p(corr)|>0.5)",
 sp$Feature, "")

 p_splot <- ggplot(sp, aes(x = Loading, y = pcorr, color = Importance)) +
 geom_point(size =1.8, alpha =0.7) +
 geom_text_repel(aes(label = label), size =2.8, max.overlaps =12,
 box.padding =0.4, show.legend = FALSE) +
 geom_hline(yintercept =0, linetype = "dashed", color = "grey50",
 linewidth =0.5) +
 geom_vline(xintercept =0, linetype = "dashed", color = "grey50",
 linewidth =0.5) +
 scale_color_manual(
 values = c("High (VIP>1 & |p(corr)|>0.5)" = "#E64B35",
 "Medium (VIP>1)" = "#00A087",
 "Low" = "grey70")
 ) +
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
 cat(" -> OPLSDA S-plot saved for", pw_name, "\n")
}

# =========================================================================
# SUMMARY
# =========================================================================
cat("\n========================================================\n")
cat(" PLSDA & OPLSDA Analysis Completed!\n")
cat("========================================================\n\n")

cat(" Key results:\n")
cat(sprintf(" PLSDA - VIP>1 metabolites: %d\n",
 sum(plsda_vip_out$MeanVIP >1, na.rm = TRUE)))
cat(sprintf(" PLSDA - permutation p-value: %.4f\n", p_val_plsda))

if (p_val_plsda <0.05) {
 cat(" => PLSDA group separation significant (p <0.05)\n")
} else {
 cat(" => PLSDA group separation NOT significant (p >=0.05)\n")
}

best_opls <- opls_params_all[which.max(opls_params_all$Q2), ]
cat(sprintf(" OPLSDA - Best model: %s (R2Y=%.3f, Q2=%.3f)\n",
 best_opls$Comparison, best_opls$R2Y, best_opls$Q2))

for (pw_nm in pairwise_names) {
 sp_cnt <- sum(all_splot_data[[pw_nm]]$Importance ==
 "High (VIP>1 & |p(corr)|>0.5)")
 pv <- all_opls_perm[[pw_nm]]$P_Value
 q2v <- all_opls_params[[pw_nm]]$Q2

 cat(sprintf(" OPLSDA(%s): High-importance=%d, p=%.4f, Q2=%.3f\n",
 pw_nm, sp_cnt, pv, q2v))

 if (pv <0.05) {
 cat(sprintf(" => %s separation significant\n", pw_nm))
 } else {
 cat(sprintf(" => %s separation NOT significant\n", pw_nm))
 }

 if (!is.na(q2v)) {
 if (q2v >=0.4) cat(sprintf(" => %s good predictive ability (Q2>=0.4)\n", pw_nm))
 else if (q2v >=0) cat(sprintf(" => %s moderate predictive ability (0<=Q2<0.4)\n", pw_nm))
 else cat(sprintf(" => %s may be overfitted (Q2<0)\n", pw_nm))
 }
}

cat("\nOutput CSV files:\n")
cat(" ", file.path(OUTPUT_DIR, "plsda_scores.csv"), "\n")
cat(" ", file.path(OUTPUT_DIR, "plsda_vip_scores.csv"), "\n")
cat(" ", file.path(OUTPUT_DIR, "plsda_weighted_distances.csv"), "\n")
cat(" ", file.path(OUTPUT_DIR, "plsda_permutation_test_results.csv"), "\n")
cat(" ", file.path(OUTPUT_DIR, "oplsda_scores.csv"), "\n")
cat(" ", file.path(OUTPUT_DIR, "oplsda_s_plot.csv"), "\n")
cat(" ", file.path(OUTPUT_DIR, "oplsda_model_params.csv"), "\n")
cat(" ", file.path(OUTPUT_DIR, "oplsda_weighted_distances.csv"), "\n")
cat(" ", file.path(OUTPUT_DIR, "oplsda_permutation_test_results.csv"), "\n")

cat("Output Figures:\n")
cat(" ", file.path(FIGURE_DIR, "PLSDA_score_plot.png/pdf"), "\n")
cat(" ", file.path(FIGURE_DIR, "PLSDA_VIP_barplot.png/pdf"), "\n")
cat(" ", file.path(FIGURE_DIR, "OPLSDA_score_plot_*.png/pdf"), "\n")
cat(" ", file.path(FIGURE_DIR, "OPLSDA_S_plot_*.png/pdf"), "\n")

cat("\nDone.\n")
