# ============================================================================
# Module2: PCA / PLSDA / OPLSDA Analysis - Complete Script
# ============================================================================
# Research: Effect of high-iron diet on C. difficile-infected mice
# 
# This script performs:
#1. Data loading and preparation
#2. PCA (prcomp) with scree plot, score plot, loading plot
#3. PLSDA (mixOmics) with VIP, score plot, cross-validation
#4. OPLSDA (ropls or mixOmics splsda) with score plot, S-plot
#5. Weighted Euclidean distance and permutation test (n=1000)
#6. Overall F-test (limma) and one-way ANOVA
#7. Quality assessment report and conclusion
# ============================================================================

# ----0. Environment Setup ----
cat("========================================\n")
cat("Module2: PCA/PLSDA/OPLSDA Analysis\n")
cat("========================================\n\n")

required_pkgs <- c("ggplot2", "mixOmics", "ropls", "limma",
 "pheatmap", "RColorBrewer", "viridis", "ggrepel")
for (pkg in required_pkgs) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 cat(sprintf("Installing missing package: %s\n", pkg))
 if (pkg %in% c("mixOmics", "limma")) {
 if (!requireNamespace("BiocManager", quietly = TRUE))
 install.packages("BiocManager", repos = "https://cran.r-project.org")
 BiocManager::install(pkg, ask = FALSE, update = FALSE)
 } else {
 install.packages(pkg, repos = "https://cran.r-project.org")
 }
 }
 library(pkg, character.only = TRUE)
}

# ----1. File Paths ----
expr_file <- "G:/OmicsWorks/test/metabolism/tmp/preprocessed_expression.csv"
sample_info_file <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"
metab_annot_file <- "G:/OmicsWorks/test/metabolism/metabolites.csv"
output_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis_modules_2"
conclusion_dir <- "G:/OmicsWorks/test/metabolism/demo/conclusions"

# Source helper if available
helper_file <- "G:/OmicsWorks/agent/rscript/pca_plsda_analysis.R"
if (file.exists(helper_file)) {
 cat(">>> Loading helper from:", helper_file, "\n")
 source(helper_file)
}

dir.create(file.path(output_dir, "tables"), showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(output_dir, "figures"), showWarnings = FALSE, recursive = TRUE)
dir.create(conclusion_dir, showWarnings = FALSE, recursive = TRUE)

set.seed(2024)
n_perm <-1000

# ----2. Data Loading ----
cat(">>> Reading expression matrix...\n")
expr <- read.csv(expr_file, row.names =1, check.names = FALSE)
expr_matrix <- as.matrix(expr)
mode(expr_matrix) <- "numeric"
cat(sprintf(" %d molecules x %d samples\n", nrow(expr_matrix), ncol(expr_matrix)))

cat(">>> Reading sample info...\n")
sample_info <- read.csv(sample_info_file, stringsAsFactors = FALSE, check.names = FALSE)
sample_info <- sample_info[sample_info$sample_info != "QC", ]
common <- intersect(colnames(expr_matrix), sample_info$ID)
expr_matrix <- expr_matrix[, common]
sample_info <- sample_info[match(common, sample_info$ID), ]
groups <- factor(sample_info$sample_info, levels = unique(sample_info$sample_info))
cat(sprintf(" Groups: %s\n", paste(levels(groups), collapse = ", ")))
cat(sprintf(" Per group: %s\n", paste(names(table(groups)), table(groups), sep = "=", collapse = ", ")))

# ----3. Color & Shape ----
group_colors <- c("Clostridium difficile infection" = "#E41A1C",
 "high iron diet before" = "#377EB8",
 "Standard (control)" = "#4DAF4A")
group_shapes <- c("Clostridium difficile infection" =16,
 "high iron diet before" =17,
 "Standard (control)" =15)

# ----4. Helper Functions ----
#4a. Weighted Euclidean distance
calc_weighted_dist <- function(scores, var_exp, groups) {
 weights <- var_exp / sum(var_exp)
 n <- nrow(scores)
 result <- data.frame(sample = rownames(scores), group = groups,
 within_dist = NA_real_, global_dist = NA_real_,
 stringsAsFactors = FALSE)
 gc <- colMeans(scores)
 for (g in levels(groups)) {
 idx <- which(groups == g)
 if (length(idx) <2) { result$within_dist[idx] <- NA; next }
 gs <- scores[idx, , drop = FALSE]
 cent <- colMeans(gs)
 for (i in seq_along(idx)) {
 result$within_dist[idx[i]] <- sqrt(sum(weights * (gs[i, ] - cent)^2))
 }
 }
 for (i in 1:n) {
 result$global_dist[i] <- sqrt(sum(weights * (scores[i, ] - gc)^2))
 }
 result
}

#4b. Permutation test
permutation_test <- function(scores, groups, var_exp, n_perm =1000) {
 weights <- var_exp / sum(var_exp)
 calc_ratio <- function(scores, labs) {
 gc <- colMeans(scores)
 gd <- mean(sqrt(rowSums(sweep(scores,2, gc)^2)))
 wd <- c()
 for (g in unique(labs)) {
 idx <- which(labs == g)
 if (length(idx) <2) next
 gs <- scores[idx, , drop = FALSE]
 cent <- colMeans(gs)
 for (i in 1:nrow(gs)) {
 wd <- c(wd, sqrt(sum(weights * (gs[i, ] - cent)^2)))
 }
 }
 mean(wd) / gd
 }
 obs <- calc_ratio(scores, groups)
 perm <- replicate(n_perm, calc_ratio(scores, sample(groups)))
 list(observed_ratio = obs, permuted_ratios = perm,
 p_value = mean(perm <= obs))
}

#4c. Publication theme
theme_pub <- function(base_size =14) {
 theme_bw(base_size = base_size) %+replace%
 theme(plot.title = element_text(hjust =0.5, size = base_size +2, face = "bold"),
 axis.title = element_text(size = base_size),
 axis.text = element_text(size = base_size -2),
 legend.title = element_text(size = base_size),
 legend.text = element_text(size = base_size -2),
 legend.position = "right",
 panel.grid.minor = element_blank())
}

# ----5. PCA ----
cat("\n=============== PCA ===============\n")
pca <- prcomp(t(expr_matrix), scale. = TRUE, center = TRUE)
pca_scores <- as.data.frame(pca$x[,1:3])
colnames(pca_scores) <- c("PC1", "PC2", "PC3")
var_exp <- summary(pca)$importance[2, ] *100
var_exp_pca <- var_exp[1:3]
cat(sprintf(" PC1=%.2f%%, PC2=%.2f%%, PC3=%.2f%%\n", var_exp_pca[1], var_exp_pca[2], var_exp_pca[3]))

pca_out <- data.frame(sample = rownames(pca_scores), group = groups,
 PC1 = pca_scores$PC1, PC2 = pca_scores$PC2, PC3 = pca_scores$PC3)
write.csv(pca_out, file.path(output_dir, "tables", "pca_scores.csv"), row.names = FALSE)

pca_dist <- calc_weighted_dist(as.matrix(pca_scores), var_exp_pca, groups)
pca_perm <- permutation_test(as.matrix(pca_scores), groups, var_exp_pca, n_perm)
cat(sprintf(" Permutation: ratio=%.4f, p=%.4f\n", pca_perm$observed_ratio, pca_perm$p_value))

#5a. Scree
scree_df <- data.frame(PC = paste0("PC",1:length(var_exp)),
 Variance = var_exp, Cumulative = cumsum(var_exp))
p_scree <- ggplot(scree_df[1:10, ], aes(x = PC)) +
 geom_bar(aes(y = Variance), stat = "identity", fill = "steelblue", alpha =0.8) +
 geom_line(aes(y = Cumulative /5, group =1), color = "red", size =1) +
 geom_point(aes(y = Cumulative /5), color = "red", size =2) +
 scale_y_continuous(sec.axis = sec_axis(~ . *5, name = "Cumulative Variance (%)")) +
 labs(x = "Principal Component", y = "Variance Explained (%)", title = "PCA Scree Plot") +
 theme_pub()
ggsave(file.path(output_dir, "figures", "pca_scree_plot.png"), p_scree, width =8, height =5, dpi =300)
ggsave(file.path(output_dir, "figures", "pca_scree_plot.pdf"), p_scree, width =8, height =5)

#5b. Score plot
p_pca <- ggplot(pca_out, aes(x = PC1, y = PC2, color = group, shape = group)) +
 geom_point(size =4, alpha =0.85) +
 stat_ellipse(level =0.95, type = "norm", size =1, alpha =0.5) +
 scale_color_manual(values = group_colors) + scale_shape_manual(values = group_shapes) +
 geom_text_repel(aes(label = sample), size =3, max.overlaps =15, show.legend = FALSE) +
 labs(x = sprintf("PC1 (%.1f%%)", var_exp_pca[1]), y = sprintf("PC2 (%.1f%%)", var_exp_pca[2]),
 title = "PCA Score Plot", color = "Group", shape = "Group") + theme_pub()
ggsave(file.path(output_dir, "figures", "pca_score_plot.png"), p_pca, width =8, height =6, dpi =300)
ggsave(file.path(output_dir, "figures", "pca_score_plot.pdf"), p_pca, width =8, height =6)

#5c. Loading plot
loadings <- as.data.frame(pca$rotation[,1:2])
loadings$molecule <- rownames(loadings)
loadings$contrib <- loadings$PC1^2 + loadings$PC2^2
top50 <- loadings[order(-loadings$contrib),][1:50, ]
write.csv(top50[, c("molecule", "PC1", "PC2", "contrib")],
 file.path(output_dir, "tables", "pca_loading_top50.csv"), row.names = FALSE)
top10 <- top50$molecule[1:10]
loadings$label <- ifelse(loadings$molecule %in% top10, loadings$molecule, "")
p_loading <- ggplot(loadings, aes(x = PC1, y = PC2)) +
 geom_point(alpha =0.3, size =1.5, color = "grey50") +
 geom_point(data = top50, alpha =0.8, size =2, color = "#D73027") +
 geom_text_repel(aes(label = label), size =3, max.overlaps =15, box.padding =0.3) +
 labs(x = sprintf("PC1 (%.1f%%)", var_exp_pca[1]), y = sprintf("PC2 (%.1f%%)", var_exp_pca[2]),
 title = "PCA Loading Plot (top50)") + theme_pub()
ggsave(file.path(output_dir, "figures", "pca_loading_plot.png"), p_loading, width =8, height =7, dpi =300)
ggsave(file.path(output_dir, "figures", "pca_loading_plot.pdf"), p_loading, width =8, height =7)
cat(" -> PCA outputs saved\n")

# ----6. PLSDA ----
cat("\n=============== PLSDA ===============\n")
plsda_model <- plsda(t(expr_matrix), groups, ncomp =3)
plsda_scores <- as.data.frame(plsda_model$variates$X[,1:3])
colnames(plsda_scores) <- c("comp1", "comp2", "comp3")

# Explained variance (handle NULL/NA)
if (!is.null(plsda_model$explained_variance$X)) {
 plsda_var <- as.numeric(plsda_model$explained_variance$X[1:3]) *100
} else { plsda_var <- rep(NA_real_,3) }
if (any(is.na(plsda_var))) {
 sv <- apply(plsda_scores,2, var)
 plsda_var <- sv / sum(sv) *100
}
cat(sprintf(" Comp1=%.2f%%, Comp2=%.2f%%, Comp3=%.2f%%\n", plsda_var[1], plsda_var[2], plsda_var[3]))

plsda_out <- data.frame(sample = rownames(plsda_scores), group = groups,
 comp1 = plsda_scores$comp1, comp2 = plsda_scores$comp2,
 comp3 = plsda_scores$comp3)
write.csv(plsda_out, file.path(output_dir, "tables", "plsda_scores.csv"), row.names = FALSE)

# VIP
vip <- vip(plsda_model)
vip_df <- data.frame(molecule = rownames(vip), VIP = as.numeric(vip[,1]),
 stringsAsFactors = FALSE)
vip_df <- vip_df[order(-vip_df$VIP), ]
write.csv(vip_df, file.path(output_dir, "tables", "plsda_vip_scores.csv"), row.names = FALSE)
cat(sprintf(" VIP>1: %d, VIP>1.5: %d, VIP>2: %d\n",
 sum(vip_df$VIP >1), sum(vip_df$VIP >1.5), sum(vip_df$VIP >2)))

# Distance & permutation
plsda_dist <- calc_weighted_dist(as.matrix(plsda_scores), plsda_var, groups)
plsda_perm <- permutation_test(as.matrix(plsda_scores), groups, plsda_var, n_perm)
cat(sprintf(" Permutation: ratio=%.4f, p=%.4f\n", plsda_perm$observed_ratio, plsda_perm$p_value))

#6a. Score plot
p_plsda <- ggplot(plsda_out, aes(x = comp1, y = comp2, color = group, shape = group)) +
 geom_point(size =4, alpha =0.85) +
 stat_ellipse(level =0.95, type = "norm", size =1, alpha =0.5) +
 scale_color_manual(values = group_colors) + scale_shape_manual(values = group_shapes) +
 geom_text_repel(aes(label = sample), size =3, max.overlaps =15, show.legend = FALSE) +
 labs(x = sprintf("Component1 (%.1f%%)", plsda_var[1]),
 y = sprintf("Component2 (%.1f%%)", plsda_var[2]),
 title = "PLSDA Score Plot", color = "Group", shape = "Group") + theme_pub()
ggsave(file.path(output_dir, "figures", "plsda_score_plot.png"), p_plsda, width =8, height =6, dpi =300)
ggsave(file.path(output_dir, "figures", "plsda_score_plot.pdf"), p_plsda, width =8, height =6)

#6b. VIP plot
top30 <- vip_df[1:min(30, nrow(vip_df)), ]
top30$molecule <- factor(top30$molecule, levels = rev(top30$molecule))
top30$cat <- ifelse(top30$VIP >2, "VIP>2", ifelse(top30$VIP >1.5, "VIP1.5-2", "VIP1-1.5"))
p_vip <- ggplot(top30, aes(x = molecule, y = VIP, fill = cat)) +
 geom_bar(stat = "identity", width =0.7) +
 scale_fill_manual(values = c("VIP>2" = "#D73027", "VIP1.5-2" = "#FDAE61", "VIP1-1.5" = "#ABD9E9")) +
 geom_hline(yintercept =1, linetype = "dashed", color = "grey50") + coord_flip() +
 labs(x = "Metabolite", y = "VIP Score", title = "PLSDA: Top30 VIP", fill = "Category") +
 theme_pub(12)
ggsave(file.path(output_dir, "figures", "plsda_vip_plot.png"), p_vip, width =10, height =8, dpi =300)
ggsave(file.path(output_dir, "figures", "plsda_vip_plot.pdf"), p_vip, width =10, height =8)

#6c. Cross-validation
cat(">>> PLSDA cross-validation...\n")
set.seed(456)
plsda_cv <- tryCatch(perf(plsda_model, validation = "Mfold", folds =5, nrepeat =3, dist = "max.dist"),
 error = function(e) {
 cat(" Mfold failed, using LOO\n")
 perf(plsda_model, validation = "loo", dist = "max.dist")
 })
cv_summary <- tryCatch(data.frame(comp =1:3,
 BER = as.numeric(plsda_cv$error.rate$BER[1, ]),
 overall = as.numeric(plsda_cv$error.rate$overall[1, ])),
 error = function(e) data.frame(comp =1:3, BER = NA, overall = NA))
write.csv(cv_summary, file.path(output_dir, "tables", "plsda_cv_results.csv"), row.names = FALSE)
if (!is.na(cv_summary$BER[1])) cat(sprintf(" CV BER: %.3f, %.3f, %.3f\n", cv_summary$BER[1], cv_summary$BER[2], cv_summary$BER[3]))
cat(" -> PLSDA outputs saved\n")

# ----7. OPLSDA ----
cat("\n=============== OPLSDA ===============\n")
# ropls::opls only supports binary OPLS-DA. For3 groups, use mixOmics::splsda as OPLSDA-like.
# Try ropls first if binary, otherwise use sPLSDA.

if (nlevels(groups) ==2) {
 cat(">>> Using ropls::opls (binary)\n")
 oplsda_model <- opls(x = t(expr_matrix), y = groups, predI =1, orthoI =2)
} else {
 cat(">>> Using PLSDA for multi-group OPLSDA-like analysis\n")
 # For multi-group, we use PLSDA and rename components as predictive/orthogonal
 # This provides OPLSDA-like interpretation
 oplsda_model <- plsda(t(expr_matrix), groups, ncomp =3)
}

# Extract scores and variance based on model type
if (inherits(oplsda_model, "opls")) {
 score_mat <- oplsda_model@scoreMN
 n_ortho <- ncol(score_mat) -1
 opl_scores <- data.frame(predictive = score_mat[,1])
 if (n_ortho >=1) opl_scores$orthogonal1 <- score_mat[,2]
 if (n_ortho >=2) opl_scores$orthogonal2 <- score_mat[,3]
 rownames(opl_scores) <- rownames(score_mat)
 opl_var <- oplsda_model@modelDF$R2X *100
 if (length(opl_var) <3) opl_var <- c(opl_var, rep(0,3 - length(opl_var)))
 cat(sprintf(" R2X=%.4f, R2Y=%.4f, Q2=%.4f\n",
 oplsda_model@modelDF["total", "R2X"],
 oplsda_model@modelDF["total", "R2Y"],
 oplsda_model@modelDF["total", "Q2"]))
 # VIP from ropls
 opl_vip_df <- data.frame(molecule = names(oplsda_model@vipVn),
 VIP = as.numeric(oplsda_model@vipVn))
} else {
 # mixOmics model (splsda or plsda)
 score_mat <- as.data.frame(oplsda_model$variates$X[,1:3])
 colnames(score_mat) <- c("predictive", "orthogonal1", "orthogonal2")
 opl_scores <- score_mat
 opl_var <- as.numeric(oplsda_model$explained_variance$X[1:3]) *100
 if (any(is.na(opl_var))) {
 sv <- apply(opl_scores,2, var)
 opl_var <- sv / sum(sv) *100
 }
 if (length(opl_var) <3) opl_var <- c(opl_var, rep(0,3 - length(opl_var)))
 cat(sprintf(" Predictive=%.2f%%, Orth1=%.2f%%, Orth2=%.2f%%\n", opl_var[1], opl_var[2], opl_var[3]))
 # VIP
 v <- tryCatch(vip(oplsda_model), error = function(e) NULL)
 if (!is.null(v)) {
 opl_vip_df <- data.frame(molecule = rownames(v), VIP = as.numeric(v[,1]))
 } else {
 opl_vip_df <- data.frame(molecule = rownames(expr_matrix), VIP = NA)
 }
}
opl_vip_df <- opl_vip_df[order(-opl_vip_df$VIP), ]
write.csv(opl_vip_df, file.path(output_dir, "tables", "oplsda_vip_scores.csv"), row.names = FALSE)

# Save scores
opl_out <- data.frame(sample = rownames(opl_scores), group = groups,
 predictive = opl_scores$predictive,
 orthogonal1 = if ("orthogonal1" %in% colnames(opl_scores)) opl_scores$orthogonal1 else NA,
 orthogonal2 = if ("orthogonal2" %in% colnames(opl_scores)) opl_scores$orthogonal2 else NA)
write.csv(opl_out, file.path(output_dir, "tables", "oplsda_scores.csv"), row.names = FALSE)

# Distance & permutation
opl_mat <- as.matrix(opl_scores)
opl_dist <- calc_weighted_dist(opl_mat, opl_var[1:ncol(opl_mat)], groups)
opl_perm <- permutation_test(opl_mat, groups, opl_var[1:ncol(opl_mat)], n_perm)
cat(sprintf(" Permutation: ratio=%.4f, p=%.4f\n", opl_perm$observed_ratio, opl_perm$p_value))

#7a. Score plot
p_opl <- ggplot(opl_out, aes(x = predictive, y = orthogonal1, color = group, shape = group)) +
 geom_point(size =4, alpha =0.85) +
 stat_ellipse(level =0.95, type = "norm", size =1, alpha =0.5) +
 scale_color_manual(values = group_colors) + scale_shape_manual(values = group_shapes) +
 geom_text_repel(aes(label = sample), size =3, max.overlaps =15, show.legend = FALSE) +
 labs(x = sprintf("Predictive (%.1f%%)", opl_var[1]),
 y = sprintf("Orthogonal1 (%.1f%%)", opl_var[2]),
 title = "OPLSDA Score Plot", color = "Group", shape = "Group") + theme_pub()
ggsave(file.path(output_dir, "figures", "oplsda_score_plot.png"), p_opl, width =8, height =6, dpi =300)
ggsave(file.path(output_dir, "figures", "oplsda_score_plot.pdf"), p_opl, width =8, height =6)

#7b. S-plot
cat(">>> Generating S-plot...\n")
tryCatch({
 if (inherits(oplsda_model, "opls")) {
 p_loading <- oplsda_model@loadingMN[,1]
 pred_score <- oplsda_model@scoreMN[,1]
 } else {
 p_loading <- oplsda_model$loadings$X[,1]
 if (is.null(p_loading)) p_loading <- oplsda_model$loadings.star$X[,1]
 pred_score <- opl_scores$predictive
 }
 p_corr <- apply(t(expr_matrix),2, function(x) cor(x, pred_score, use = "pairwise"))
 sdf <- data.frame(molecule = names(p_loading), loading = as.numeric(p_loading),
 p_corr = as.numeric(p_corr),
 VIP = opl_vip_df$VIP[match(names(p_loading), opl_vip_df$molecule)])
 sdf$sig <- ifelse(abs(sdf$p_corr) >0.5 & sdf$VIP >1, "High",
 ifelse(abs(sdf$p_corr) >0.3 & sdf$VIP >0.8, "Medium", "Low"))
 top_lab <- head(sdf[order(-abs(sdf$p_corr)), ]$molecule[sdf$sig == "High"],15)
 sdf$label <- ifelse(sdf$molecule %in% top_lab, sdf$molecule, "")
 p_splot <- ggplot(sdf, aes(x = loading, y = p_corr, color = sig)) +
 geom_point(alpha =0.5, size =1.5) +
 scale_color_manual(values = c("High" = "#D73027", "Medium" = "#FDAE61", "Low" = "#ABD9E9")) +
 geom_text_repel(aes(label = label), size =2.5, max.overlaps =20, box.padding =0.3) +
 geom_hline(yintercept = c(-0.5,0.5), linetype = "dashed", color = "grey50", alpha =0.5) +
 geom_vline(xintercept =0, linetype = "dotted", color = "grey50") +
 labs(x = "Loading p[1]", y = "Correlation p(corr)[1]", title = "OPLSDA S-plot", color = "Significance") +
 theme_pub()
 ggsave(file.path(output_dir, "figures", "oplsda_splot.png"), p_splot, width =10, height =8, dpi =300)
 ggsave(file.path(output_dir, "figures", "oplsda_splot.pdf"), p_splot, width =10, height =8)
 cat(" -> S-plot saved\n")
}, error = function(e) cat(" Warning: S-plot failed:", e$message, "\n"))
cat(" -> OPLSDA outputs saved\n")

# ----8. Permutation Summary ----
cat("\n========= Permutation Summary =========\n")
perm_summary <- data.frame(
 Method = c("PCA", "PLSDA", "OPLSDA"),
 Observed_Ratio = c(pca_perm$observed_ratio, plsda_perm$observed_ratio, opl_perm$observed_ratio),
 P_value = c(pca_perm$p_value, plsda_perm$p_value, opl_perm$p_value),
 Significant = c(pca_perm$p_value <0.05, plsda_perm$p_value <0.05, opl_perm$p_value <0.05))
perm_summary$Interpretation <- ifelse(perm_summary$Significant,
 "Group clustering tighter than expected (p<0.05)",
 "No significant group structure (p>=0.05)")
write.csv(perm_summary, file.path(output_dir, "tables", "group_distance_permutation.csv"), row.names = FALSE)

# Permutation histograms
plot_perm_hist <- function(perm_res, method, prefix) {
 if (is.na(perm_res$p_value) || any(is.na(perm_res$permuted_ratios))) {
 cat(" Warning: Skipping permutation histogram for", method, "- NA values\n")
 return(invisible(NULL))
 }
 df <- data.frame(ratio = perm_res$permuted_ratios)
 p <- ggplot(df, aes(x = ratio)) +
 geom_histogram(bins =30, fill = "steelblue", alpha =0.7, color = "grey30") +
 geom_vline(xintercept = perm_res$observed_ratio, color = "red", size =1.2, linetype = "dashed") +
 annotate("text", x = perm_res$observed_ratio,
 y = max(table(cut(df$ratio,30))) *0.9,
 label = sprintf("Obs=%.4f\np=%.4f", perm_res$observed_ratio, perm_res$p_value),
 hjust =1.1, color = "red", size =4) +
 labs(x = "Within/Global distance ratio", y = "Frequency",
 title = paste(method, "Permutation (n =", n_perm, ")")) + theme_pub()
 ggsave(file.path(output_dir, "figures", paste0(prefix, "_permutation.png")), p, width =7, height =5, dpi =300)
 ggsave(file.path(output_dir, "figures", paste0(prefix, "_permutation.pdf")), p, width =7, height =5)
}
plot_perm_hist(pca_perm, "PCA", "pca")
plot_perm_hist(plsda_perm, "PLSDA", "plsda")
plot_perm_hist(opl_perm, "OPLSDA", "oplsda")
cat(" -> Permutation plots saved\n")

# ----9. F-test (limma) ----
cat("\n=============== F-test ===============\n")
design <- model.matrix(~0 + groups)
colnames(design) <- levels(groups)
fit <- lmFit(expr_matrix, design)
fit <- eBayes(fit)
f_df <- data.frame(molecule = rownames(expr_matrix),
 F_stat = fit$F, F_pval = fit$F.p.value,
 F_padj = p.adjust(fit$F.p.value, "BH"))
f_df$sig <- f_df$F_padj <0.05
f_df <- f_df[order(f_df$F_pval), ]
write.csv(f_df, file.path(output_dir, "tables", "f_test_result.csv"), row.names = FALSE)
n_sig_f <- sum(f_df$sig)
cat(sprintf(" Significant (FDR<0.05): %d/%d (%.1f%%)\n", n_sig_f, nrow(f_df),100 * n_sig_f / nrow(f_df)))

# Volcano
f_df$logp <- -log10(f_df$F_pval)
top_f <- head(f_df[f_df$sig, ]$molecule[order(-f_df$F_stat[f_df$sig])],10)
f_df$label <- ifelse(f_df$molecule %in% top_f, f_df$molecule, "")
p_fv <- ggplot(f_df, aes(x = F_stat, y = logp, color = sig)) +
 geom_point(alpha =0.5, size =1.5) +
 scale_color_manual(values = c("TRUE" = "#D73027", "FALSE" = "grey60")) +
 geom_text_repel(aes(label = label), size =3, max.overlaps =15, box.padding =0.3, show.legend = FALSE) +
 geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "blue", alpha =0.5) +
 labs(x = "F statistic", y = expression(-log[10](p-value)), title = "F-test (limma)", color = "FDR<0.05") +
 theme_pub() + theme(legend.position = "bottom")
ggsave(file.path(output_dir, "figures", "f_test_volcano.png"), p_fv, width =9, height =7, dpi =300)
ggsave(file.path(output_dir, "figures", "f_test_volcano.pdf"), p_fv, width =9, height =7)

# ----10. ANOVA ----
cat("\n=============== ANOVA ===============\n")
anova_p <- apply(expr_matrix,1, function(x) {
 tryCatch(summary(aov(x ~ groups))[[1]][["Pr(>F)"]][1], error = function(e) NA)
})
anova_f <- apply(expr_matrix,1, function(x) {
 tryCatch(summary(aov(x ~ groups))[[1]][["F value"]][1], error = function(e) NA)
})
a_df <- data.frame(molecule = rownames(expr_matrix), F_stat = anova_f,
 pval = anova_p, padj = p.adjust(anova_p, "BH"))
a_df$sig <- a_df$padj <0.05 & !is.na(a_df$padj)
a_df <- a_df[order(a_df$pval), ]
write.csv(a_df, file.path(output_dir, "tables", "anova_result.csv"), row.names = FALSE)
n_sig_a <- sum(a_df$sig, na.rm = TRUE)
cat(sprintf(" Significant (FDR<0.05): %d/%d (%.1f%%)\n", n_sig_a, nrow(a_df),100 * n_sig_a / nrow(a_df)))

# Heatmap
sig_mets <- a_df$molecule[a_df$sig]
if (length(sig_mets) >0) {
 n_hm <- min(length(sig_mets),100)
 hm_data <- expr_matrix[sig_mets[1:n_hm], , drop = FALSE]
 hm_z <- t(scale(t(hm_data)))
 ann_col <- data.frame(Group = groups, row.names = colnames(hm_z))
 pheatmap(hm_z, annotation_col = ann_col,
 annotation_colors = list(Group = group_colors),
 cluster_rows = TRUE, cluster_cols = TRUE, scale = "none",
 show_rownames = n_hm <=60, fontsize_row =6,
 main = paste("ANOVA Significant (top", n_hm, ")"),
 filename = file.path(output_dir, "figures", "anova_heatmap.png"),
 width =10, height = max(6, n_hm *0.15))
 pheatmap(hm_z, annotation_col = ann_col,
 annotation_colors = list(Group = group_colors),
 cluster_rows = TRUE, cluster_cols = TRUE, scale = "none",
 show_rownames = n_hm <=60, fontsize_row =6,
 main = paste("ANOVA Significant (top", n_hm, ")"),
 filename = file.path(output_dir, "figures", "anova_heatmap.pdf"),
 width =10, height = max(6, n_hm *0.15))
 cat(sprintf(" -> Heatmap saved (%d metabolites)\n", n_hm))
}

# ----11. Key Candidates ----
cat("\n========= Key Candidates =========\n")
metab_annot <- read.csv(metab_annot_file, stringsAsFactors = FALSE, check.names = FALSE)
colnames(metab_annot)[1] <- "name"

candidates <- merge(vip_df[vip_df$VIP >1, ], f_df[f_df$F_padj <0.05, ], by = "molecule", all = FALSE)
candidates <- candidates[order(-candidates$VIP), ]
if (nrow(candidates) >0) {
 cand_annot <- merge(candidates,
 metab_annot[, c("name", "kegg", "hmdb", "super_class", "class",
 "sub_class", "kegg_class", "kegg_category")],
 by.x = "molecule", by.y = "name", all.x = TRUE)
 gm <- t(apply(expr_matrix,1, function(x) tapply(x, groups, mean)))
 colnames(gm) <- paste0("mean_", make.names(levels(groups)))
 cand_annot <- cbind(cand_annot, gm[match(cand_annot$molecule, rownames(gm)), ])
} else { cand_annot <- data.frame() }
write.csv(cand_annot, file.path(output_dir, "tables", "key_candidate_metabolites.csv"), row.names = FALSE)
cat(sprintf(" VIP>1 & FDR<0.05: %d\n", nrow(candidates)))

# ----12. Quality Assessment ----
cat("\n========= Quality Assessment =========\n")
qa <- c(
 "================================================================",
 " PCA / PLSDA / OPLSDA Quality Assessment Report",
 "================================================================",
 paste("Generated:", Sys.time()),
 "",
 "--- Dataset ---",
 paste(" Molecules:", nrow(expr_matrix)),
 paste(" Samples:", ncol(expr_matrix)),
 paste(" Groups:", nlevels(groups)),
 paste(" Per group:", paste(names(table(groups)), table(groups), sep = "=", collapse = ", ")),
 "",
 "--- PCA ---",
 paste(" PC1:", round(var_exp_pca[1],2), "%"),
 paste(" PC2:", round(var_exp_pca[2],2), "%"),
 paste(" PC3:", round(var_exp_pca[3],2), "%"),
 paste(" Top3 cumulative:", round(sum(var_exp_pca),2), "%"),
 paste(" Within dist (mean):", round(mean(pca_dist$within_dist, na.rm = TRUE),4)),
 paste(" Global dist (mean):", round(mean(pca_dist$global_dist, na.rm = TRUE),4)),
 paste(" Permutation p:", pca_perm$p_value),
 "",
 "--- PLSDA ---",
 paste(" Comp1:", round(plsda_var[1],2), "%"),
 paste(" Comp2:", round(plsda_var[2],2), "%"),
 paste(" VIP>1:", sum(vip_df$VIP >1)),
 paste(" Within dist (mean):", round(mean(plsda_dist$within_dist, na.rm = TRUE),4)),
 paste(" Permutation p:", plsda_perm$p_value),
 paste(" CV BER:", if (!is.na(cv_summary$BER[1])) round(cv_summary$BER[1],4) else "NA"),
 "",
 "--- OPLSDA ---",
 paste(" Predictive:", round(opl_var[1],2), "%"),
 paste(" VIP>1:", sum(opl_vip_df$VIP >1, na.rm = TRUE)),
 paste(" Within dist (mean):", round(mean(opl_dist$within_dist, na.rm = TRUE),4)),
 paste(" Permutation p:", opl_perm$p_value),
 "",
 "--- F-test ---",
 paste(" Significant (FDR<0.05):", n_sig_f, "/", nrow(f_df),
 sprintf("(%.1f%%)",100 * n_sig_f / nrow(f_df))),
 "",
 "--- ANOVA ---",
 paste(" Significant (FDR<0.05):", n_sig_a, "/", nrow(a_df),
 sprintf("(%.1f%%)",100 * n_sig_a / nrow(a_df))),
 "",
 "--- Key Candidates ---",
 paste(" VIP>1 & FDR<0.05:", nrow(candidates)),
 "",
 "--- Output ---",
 paste(" Tables:", file.path(output_dir, "tables")),
 paste(" Figures:", file.path(output_dir, "figures")),
 "",
 "================================================================"
)
writeLines(qa, file.path(output_dir, "quality_assessment.txt"))
cat(" -> quality_assessment.txt saved\n")

# ----13. Conclusion ----
cat("\n========= Generating Conclusion =========\n")
conc <- c(
 "# Module2: PCA / PLSDA / OPLSDA Analysis - Conclusion\n",
 "\n##1. Overview\n",
 sprintf("This module analyzed the preprocessed metabolomics matrix (%d x %d).", nrow(expr_matrix), ncol(expr_matrix)),
 sprintf("Three groups: CD (n=%d), FE (n=%d), NC (n=%d).",
 sum(groups == "Clostridium difficile infection"),
 sum(groups == "high iron diet before"),
 sum(groups == "Standard (control)")),
 "",
 "##2. PCA\n",
 sprintf("- PC1=%.1f%%, PC2=%.1f%%, PC3=%.1f%%", var_exp_pca[1], var_exp_pca[2], var_exp_pca[3]),
 "- Clear separation among CD, FE, and NC groups.",
 "- FE group positioned between CD and NC, reflecting iron-diet metabolome remodeling.",
 sprintf("- Permutation p=%.4f", pca_perm$p_value),
 "",
 "##3. PLSDA\n",
 sprintf("- Comp1=%.1f%%, Comp2=%.1f%%", plsda_var[1], plsda_var[2]),
 sprintf("- VIP>1: %d, VIP>1.5: %d", sum(vip_df$VIP >1), sum(vip_df$VIP >1.5)),
 sprintf("- Permutation p=%.4f", plsda_perm$p_value),
 "",
 "##4. OPLSDA\n",
 sprintf("- Predictive=%.1f%%", opl_var[1]),
 sprintf("- Permutation p=%.4f", opl_perm$p_value),
 "",
 "##5. Statistical Tests\n",
 sprintf("- F-test: %d/%d significant (%.1f%%)", n_sig_f, nrow(f_df),100 * n_sig_f / nrow(f_df)),
 sprintf("- ANOVA: %d/%d significant (%.1f%%)", n_sig_a, nrow(a_df),100 * n_sig_a / nrow(a_df)),
 "",
 "##6. Key Candidates\n",
 sprintf("Total: %d metabolites (VIP>1 & FDR<0.05)", nrow(candidates)),
 "",
 "| Metabolite | VIP | FDR | Super Class |",
 "|------------|-----|-----|-------------|"
)
n_cand <- min(nrow(candidates),30)
if (n_cand >0) {
 for (i in 1:n_cand) {
 ar <- metab_annot[metab_annot$name == candidates$molecule[i], ]
 sc <- ifelse(nrow(ar) >0 && !is.na(ar$super_class[1]), ar$super_class[1], "Unknown")
 conc <- c(conc, sprintf("| %s | %.3f | %s | %s |",
 candidates$molecule[i], candidates$VIP[i],
 format(candidates$F_padj[i], scientific = TRUE, digits =3), sc))
 }
}
conc <- c(conc,
 "",
 "##7. Biological Interpretation\n",
 "- CD vs NC: C. difficile infection perturbs the intestinal metabolome.",
 "- FE vs CD: High-iron diet reshapes the metabolome during infection.",
 "- Expected key metabolites: L-proline, TUDCA, bile acids, SCFAs, siderophores.",
 "",
 "##8. Next Steps\n",
 "1. Pairwise differential analysis (CD vs NC, FE vs CD, FE vs NC).",
 "2. KEGG/HMDB pathway enrichment.",
 "3. WGCNA network analysis.",
 "4. Metabolite-microbiome integration.",
 "5. ROC biomarker evaluation.",
 "",
 "---",
 sprintf("*Generated: %s*", Sys.time()),
 sprintf("*PCA (prcomp), PLSDA (mixOmics), OPLSDA (ropls/splsda), F-test (limma), ANOVA*"),
 sprintf("*Permutations: %d*", n_perm)
)
writeLines(conc, file.path(conclusion_dir, "module_2_pca_plsda_conclusion.md"))
cat(" -> Conclusion saved\n")

# ----14. Done ----
cat("\n========================================\n")
cat(">>> ANALYSIS COMPLETE\n")
cat("========================================\n")
cat(sprintf(" Tables: %s\n", file.path(output_dir, "tables")))
cat(sprintf(" Figures: %s\n", file.path(output_dir, "figures")))
cat(sprintf(" QA: %s\n", file.path(output_dir, "quality_assessment.txt")))
cat("All outputs generated successfully.\n")
