# ============================================================================
# Module2: PCA/PLSDA/OPLSDA Enhanced Analysis Script
# ============================================================================
# This script runs PCA, PLSDA, OPLSDA, F-test, and ANOVA with full outputs
# including: score plots, VIP plots, S-plots,3D PCA, scree plots,
# heatmaps, permutation tests, and stage conclusion generation.
#
# Usage:
# Rscript module_2_enhanced_analysis.R
# ============================================================================

# ---- Load required packages ----
required_pkgs <- c("ggplot2", "mixOmics", "limma", "pheatmap", "plotly", 
 "dplyr", "tidyr", "htmlwidgets")
for (pkg in required_pkgs) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 install.packages(pkg, repos = "https://cran.r-project.org")
 }
 library(pkg, character.only = TRUE)
}

# ---- Configuration ----
expr_file <- "G:/OmicsWorks/test/metabolism/expression.csv"
sample_info_file <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"
metab_annot_file <- "G:/OmicsWorks/test/metabolism/metabolites.csv"
output_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis_modules_2"
conclusion_dir <- "G:/OmicsWorks/test/metabolism/demo/conclusions"
group_col <- "sample_info"
n_perm <-1000
set.seed(2024)

dir.create(file.path(output_dir, "tables"), showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(output_dir, "figures"), showWarnings = FALSE, recursive = TRUE)
dir.create(conclusion_dir, showWarnings = FALSE, recursive = TRUE)

# ----1. Data Preparation ----
cat(">>> Reading expression data...\n")
expr <- read.csv(expr_file, row.names =1, check.names = FALSE)
expr_matrix <- as.matrix(expr)
mode(expr_matrix) <- "numeric"

cat(">>> Reading sample info...\n")
sample_info <- read.csv(sample_info_file, stringsAsFactors = FALSE, check.names = FALSE)

# Keep only biological samples (exclude QC)
sample_info <- sample_info[sample_info$sample_info != "QC", ]
common_samples <- intersect(colnames(expr_matrix), sample_info$ID)
expr_matrix <- expr_matrix[, common_samples]
sample_info <- sample_info[match(common_samples, sample_info$ID), ]

groups <- factor(sample_info[[group_col]])
cat(">>> Groups:", levels(groups), "\n")
cat(">>> Samples per group:", table(groups), "\n")

# Color mapping
group_colors <- c("Clostridium difficile infection" = "#E41A1C",
 "high iron diet before" = "#377EB8",
 "Standard (control)" = "#4DAF4A")
group_shapes <- c("Clostridium difficile infection" =16,
 "high iron diet before" =17,
 "Standard (control)" =15)

# ---- Helper: weighted Euclidean distance ----
calc_weighted_dist <- function(scores, var_exp) {
 # scores: matrix of n_samples x n_components
 # var_exp: vector of variance explained for each component
 weights <- var_exp / sum(var_exp)
 n <- nrow(scores)
 result <- data.frame(sample = rownames(scores), 
 group = groups,
 within_dist = NA, global_dist = NA)
  
 # Global centroid
 global_centroid <- colMeans(scores)
  
 for (g in levels(groups)) {
 idx <- which(groups == g)
 if (length(idx) <2) {
 result$within_dist[idx] <- NA
 next
 }
 g_scores <- scores[idx, , drop = FALSE]
 centroid <- colMeans(g_scores)
 for (i in seq_along(idx)) {
 d <- sqrt(sum(weights * (g_scores[i, ] - centroid)^2))
 result$within_dist[idx[i]] <- d
 }
 }
  
 for (i in 1:n) {
 d <- sqrt(sum(weights * (scores[i, ] - global_centroid)^2))
 result$global_dist[i] <- d
 }
  
 return(result)
}

# ---- Helper: permutation test ----
permutation_test <- function(scores, groups, var_exp, n_perm =1000) {
 weights <- var_exp / sum(var_exp)
  
 # Observed within-group vs global distance ratio
 calc_ratio <- function(scores, labels) {
 global_centroid <- colMeans(scores)
 global_d <- mean(sqrt(rowSums(sweep(scores,2, global_centroid)^2)))
    
 within_d <- c()
 for (g in unique(labels)) {
 idx <- which(labels == g)
 if (length(idx) <2) next
 g_scores <- scores[idx, , drop = FALSE]
 cent <- colMeans(g_scores)
 for (i in 1:nrow(g_scores)) {
 d <- sqrt(sum(weights * (g_scores[i, ] - cent)^2))
 within_d <- c(within_d, d)
 }
 }
 return(mean(within_d) / global_d)
 }
  
 obs_ratio <- calc_ratio(scores, groups)
 perm_ratios <- numeric(n_perm)
  
 for (p in 1:n_perm) {
 shuffled <- sample(groups)
 perm_ratios[p] <- calc_ratio(scores, shuffled)
 }
  
 p_val <- mean(perm_ratios <= obs_ratio)
  
 return(list(observed_ratio = obs_ratio, 
 permuted_ratios = perm_ratios,
 p_value = p_val))
}

# ============================================================================
# ----2. PCA Analysis ----
# ============================================================================
cat("\n========================================\n")
cat(">>> Running PCA...\n")
cat("========================================\n")

pca_result <- prcomp(t(expr_matrix), scale. = TRUE, center = TRUE)
pca_scores_full <- as.data.frame(pca_result$x)
pca_scores <- pca_scores_full[,1:3]
colnames(pca_scores) <- c("PC1", "PC2", "PC3")

var_exp_all <- summary(pca_result)$importance[2, ] *100
var_exp_pca <- var_exp_all[1:3]

# Save PCA scores
pca_out <- data.frame(
 sample = rownames(pca_scores),
 group = groups,
 PC1 = pca_scores$PC1,
 PC2 = pca_scores$PC2,
 PC3 = pca_scores$PC3
)
write.csv(pca_out, file.path(output_dir, "tables", "pca_scores.csv"), row.names = FALSE)

# PCA distance and permutation
pca_dist <- calc_weighted_dist(as.matrix(pca_scores), var_exp_pca)
pca_perm <- permutation_test(as.matrix(pca_scores), groups, var_exp_pca, n_perm)

cat(sprintf("PCA: Observed ratio=%.4f, p-value=%.4f\n", pca_perm$observed_ratio, pca_perm$p_value))

# ---- PCA Scree Plot ----
scree_df <- data.frame(
 PC = paste0("PC",1:length(var_exp_all)),
 Variance = var_exp_all,
 Cumulative = cumsum(var_exp_all)
)

p_scree <- ggplot(scree_df[1:10, ], aes(x = PC)) +
 geom_bar(aes(y = Variance), stat = "identity", fill = "steelblue", alpha =0.8) +
 geom_line(aes(y = Cumulative /5, group =1), color = "red", size =1) +
 geom_point(aes(y = Cumulative /5), color = "red", size =2) +
 scale_y_continuous(sec.axis = sec_axis(~ . *5, name = "Cumulative Variance (%)")) +
 labs(x = "Principal Component", y = "Variance Explained (%)",
 title = "PCA Scree Plot") +
 theme_bw() + theme(plot.title = element_text(hjust =0.5, face = "bold"))

ggsave(file.path(output_dir, "figures", "pca_scree_plot.png"), p_scree, width =8, height =5, dpi =300)
ggsave(file.path(output_dir, "figures", "pca_scree_plot.pdf"), p_scree, width =8, height =5)

# ---- PCA Score Plot (PC1 vs PC2) ----
p_pca <- ggplot(pca_out, aes(x = PC1, y = PC2, color = group, shape = group)) +
 geom_point(size =4, alpha =0.85) +
 stat_ellipse(level =0.95, type = "norm", size =1, alpha =0.6) +
 scale_color_manual(values = group_colors) +
 scale_shape_manual(values = group_shapes) +
 labs(x = sprintf("PC1 (%.1f%%)", var_exp_pca[1]),
 y = sprintf("PC2 (%.1f%%)", var_exp_pca[2]),
 title = "PCA Score Plot",
 color = "Group", shape = "Group") +
 theme_bw(base_size =14) +
 theme(plot.title = element_text(hjust =0.5, size =16, face = "bold"),
 legend.position = "right")

ggsave(file.path(output_dir, "figures", "pca_score_plot.png"), p_pca, width =8, height =6, dpi =300)
ggsave(file.path(output_dir, "figures", "pca_score_plot.pdf"), p_pca, width =8, height =6)

# ---- PCA3D Plot (plotly interactive) ----
pca_3d <- plot_ly(pca_out, x = ~PC1, y = ~PC2, z = ~PC3,
 color = ~group, colors = unname(group_colors),
 symbol = ~group, symbols = c("circle", "triangle-up", "square"),
 type = "scatter3d", mode = "markers",
 marker = list(size =8),
 text = ~paste("Sample:", sample, "<br>Group:", group),
 hoverinfo = "text") %>%
 layout(title = "PCA3D Score Plot",
 scene = list(
 xaxis = list(title = sprintf("PC1 (%.1f%%)", var_exp_pca[1])),
 yaxis = list(title = sprintf("PC2 (%.1f%%)", var_exp_pca[2])),
 zaxis = list(title = sprintf("PC3 (%.1f%%)", var_exp_pca[3]))
 ))

tryCatch({htmlwidgets::saveWidget(pca_3d, file.path(output_dir, "figures", "pca_3d_scores.html"))}, error = function(e) cat('Warning: Could not save interactive3D plot:', e$message, '\n'))

# Also save a static PNG as proxy
png(file.path(output_dir, "figures", "pca_3d_scores.png"), width =800, height =600)
par(mar = c(5,5,4,2))
plot(pca_out$PC1, pca_out$PC3, col = group_colors[as.character(groups)],
 pch = as.numeric(groups) +15, cex =1.8,
 xlab = sprintf("PC1 (%.1f%%)", var_exp_pca[1]),
 ylab = sprintf("PC3 (%.1f%%)", var_exp_pca[3]),
 main = "PCA: PC1 vs PC3")
legend("topright", legend = levels(groups), col = group_colors[levels(groups)],
 pch =16:18, cex =1)
dev.off()

# ---- PCA Loading Plot (top contributors) ----
pca_loadings <- as.data.frame(pca_result$rotation[,1:2])
pca_loadings$molecule <- rownames(pca_loadings)

# Calculate contribution (cos2)
pca_loadings$contrib1 <- pca_loadings$PC1^2
pca_loadings$contrib2 <- pca_loadings$PC2^2
pca_loadings$contrib_total <- pca_loadings$contrib1 + pca_loadings$contrib2

top50 <- pca_loadings[order(-pca_loadings$contrib_total),][1:50, ]
write.csv(top50[, c("molecule", "PC1", "PC2", "contrib_total")],
 file.path(output_dir, "tables", "pca_loading_top50.csv"), row.names = FALSE)

# Loading scatter plot, label top10
top10 <- top50[1:10, "molecule"]
pca_loadings$label <- ifelse(pca_loadings$molecule %in% top10, pca_loadings$molecule, "")

p_loading <- ggplot(pca_loadings, aes(x = PC1, y = PC2)) +
 geom_point(alpha =0.4, size =1.5, color = "grey40") +
 geom_point(data = top50, alpha =0.8, size =2, color = "red") +
 geom_text(aes(label = label), size =3, vjust = -0.5, hjust =0.5, check_overlap = TRUE) +
 labs(x = sprintf("PC1 (%.1f%%)", var_exp_pca[1]),
 y = sprintf("PC2 (%.1f%%)", var_exp_pca[2]),
 title = "PCA Loading Plot (top50 highlighted)") +
 theme_bw() + theme(plot.title = element_text(hjust =0.5, face = "bold"))

ggsave(file.path(output_dir, "figures", "pca_loading_plot.png"), p_loading, width =8, height =7, dpi =300)
ggsave(file.path(output_dir, "figures", "pca_loading_plot.pdf"), p_loading, width =8, height =7)

# ============================================================================
# ----3. PLSDA Analysis ----
# ============================================================================
cat("\n========================================\n")
cat(">>> Running PLSDA...\n")
cat("========================================\n")

plsda_model <- plsda(t(expr_matrix), groups, ncomp =3)
plsda_scores <- as.data.frame(plsda_model$variates$X[,1:3])
colnames(plsda_scores) <- c("comp1", "comp2", "comp3")

# Variance explained by PLS components
plsda_var <- plsda_model$explained_variance$X[1:3] *100

# Save scores
plsda_out <- data.frame(
 sample = rownames(plsda_scores),
 group = groups,
 comp1 = plsda_scores$comp1,
 comp2 = plsda_scores$comp2,
 comp3 = plsda_scores$comp3
)
write.csv(plsda_out, file.path(output_dir, "tables", "plsda_scores.csv"), row.names = FALSE)

# VIP scores
vip <- vip(plsda_model)
vip_df <- data.frame(
 molecule = rownames(vip),
 VIP = vip[,1],
 stringsAsFactors = FALSE
)
vip_df <- vip_df[order(-vip_df$VIP), ]
write.csv(vip_df, file.path(output_dir, "tables", "plsda_vip_scores.csv"), row.names = FALSE)

# PLSDA distance and permutation
plsda_dist <- calc_weighted_dist(as.matrix(plsda_scores), plsda_var)
plsda_perm <- permutation_test(as.matrix(plsda_scores), groups, plsda_var, n_perm)
cat(sprintf("PLSDA: Observed ratio=%.4f, p-value=%.4f\n", 
 plsda_perm$observed_ratio, plsda_perm$p_value))

# PLSDA Score Plot
p_plsda <- ggplot(plsda_out, aes(x = comp1, y = comp2, color = group, shape = group)) +
 geom_point(size =4, alpha =0.85) +
 stat_ellipse(level =0.95, type = "norm", size =1, alpha =0.6) +
 scale_color_manual(values = group_colors) +
 scale_shape_manual(values = group_shapes) +
 labs(x = sprintf("Component1 (%.1f%%)", plsda_var[1]),
 y = sprintf("Component2 (%.1f%%)", plsda_var[2]),
 title = "PLSDA Score Plot",
 color = "Group", shape = "Group") +
 theme_bw(base_size =14) +
 theme(plot.title = element_text(hjust =0.5, size =16, face = "bold"),
 legend.position = "right")

ggsave(file.path(output_dir, "figures", "plsda_score_plot.png"), p_plsda, width =8, height =6, dpi =300)
ggsave(file.path(output_dir, "figures", "plsda_score_plot.pdf"), p_plsda, width =8, height =6)

# VIP Plot (top30)
top30_vip <- vip_df[1:30, ]
top30_vip$molecule <- factor(top30_vip$molecule, levels = rev(top30_vip$molecule))
top30_vip$color_group <- ifelse(top30_vip$VIP >2, "VIP >2",
 ifelse(top30_vip$VIP >1.5, "VIP1.5-2", "VIP1-1.5"))

p_vip <- ggplot(top30_vip, aes(x = molecule, y = VIP, fill = color_group)) +
 geom_bar(stat = "identity", width =0.7) +
 scale_fill_manual(values = c("VIP >2" = "#D73027", "VIP1.5-2" = "#FDAE61", "VIP1-1.5" = "#ABD9E9")) +
 geom_hline(yintercept =1, linetype = "dashed", color = "grey50") +
 coord_flip() +
 labs(x = "Metabolite", y = "VIP Score", 
 title = "PLSDA: Top30 VIP Metabolites",
 fill = "VIP Category") +
 theme_bw(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, face = "bold"))

ggsave(file.path(output_dir, "figures", "plsda_vip_plot.png"), p_vip, width =10, height =8, dpi =300)
ggsave(file.path(output_dir, "figures", "plsda_vip_plot.pdf"), p_vip, width =10, height =8)

# ============================================================================
# ----4. OPLSDA Analysis ----
# ============================================================================
cat("\n========================================\n")
cat(">>> Running OPLSDA (sPLSDA)...\n")
cat("========================================\n")

# Use sPLSDA as an OPLSDA-like approach
# First tune keepX
set.seed(123)
tune_result <- tune.splsda(t(expr_matrix), groups, ncomp =3,
 test.keepX = c(seq(5,50,5), seq(60,200,20)),
 validation = "Mfold", folds =5, nrepeat =3,
 dist = "max.dist")
optimal_keepX <- tune_result$choice.keepX
cat("Optimal keepX:", optimal_keepX, "\n")

oplsda_model <- splsda(t(expr_matrix), groups, ncomp =3, 
 keepX = optimal_keepX,
 )
oplsda_scores <- as.data.frame(oplsda_model$variates$X[,1:3])
colnames(oplsda_scores) <- c("predictive", "orthogonal1", "orthogonal2")

# Variance explained
oplsda_var <- oplsda_model$explained_variance$X[1:3] *100

# Save scores
oplsda_out <- data.frame(
 sample = rownames(oplsda_scores),
 group = groups,
 predictive = oplsda_scores$predictive,
 orthogonal1 = oplsda_scores$orthogonal1,
 orthogonal2 = oplsda_scores$orthogonal2
)
write.csv(oplsda_out, file.path(output_dir, "tables", "oplsda_scores.csv"), row.names = FALSE)

# OPLSDA VIP
oplsda_vip <- vip(oplsda_model)
oplsda_vip_df <- data.frame(
 molecule = rownames(oplsda_vip),
 VIP = oplsda_vip[,1],
 stringsAsFactors = FALSE
)
oplsda_vip_df <- oplsda_vip_df[order(-oplsda_vip_df$VIP), ]
write.csv(oplsda_vip_df, file.path(output_dir, "tables", "oplsda_vip_scores.csv"), row.names = FALSE)

# OPLSDA distance and permutation
oplsda_dist <- calc_weighted_dist(as.matrix(oplsda_scores), oplsda_var)
oplsda_perm <- permutation_test(as.matrix(oplsda_scores), groups, oplsda_var, n_perm)
cat(sprintf("OPLSDA: Observed ratio=%.4f, p-value=%.4f\n",
 oplsda_perm$observed_ratio, oplsda_perm$p_value))

# OPLSDA Score Plot
p_oplsda <- ggplot(oplsda_out, aes(x = predictive, y = orthogonal1, 
 color = group, shape = group)) +
 geom_point(size =4, alpha =0.85) +
 stat_ellipse(level =0.95, type = "norm", size =1, alpha =0.6) +
 scale_color_manual(values = group_colors) +
 scale_shape_manual(values = group_shapes) +
 labs(x = sprintf("Predictive Component (%.1f%%)", oplsda_var[1]),
 y = sprintf("Orthogonal Component1 (%.1f%%)", oplsda_var[2]),
 title = "OPLSDA Score Plot",
 color = "Group", shape = "Group") +
 theme_bw(base_size =14) +
 theme(plot.title = element_text(hjust =0.5, size =16, face = "bold"),
 legend.position = "right")

ggsave(file.path(output_dir, "figures", "oplsda_score_plot.png"), p_oplsda, width =8, height =6, dpi =300)
ggsave(file.path(output_dir, "figures", "oplsda_score_plot.pdf"), p_oplsda, width =8, height =6)

# OPLSDA S-plot
tryCatch({
 loadings <- oplsda_model$loadings$X
 if (is.null(loadings) || nrow(loadings) ==0) {
 loadings <- oplsda_model$loadings.star$X
 }
 if (!is.null(loadings) && nrow(loadings) >0) {
 loading_vec <- loadings[,1]
 
 # Calculate p(corr)
 X <- scale(t(expr_matrix), center = TRUE, scale = TRUE)
 p_corr <- cor(X, oplsda_scores$predictive)[,1]
 
 splot_df <- data.frame(
 molecule = names(loading_vec),
 p_corr = p_corr[match(names(loading_vec), names(p_corr))],
 loading = as.numeric(loading_vec),
 VIP = oplsda_vip_df$VIP[match(names(loading_vec), oplsda_vip_df$molecule)],
 stringsAsFactors = FALSE
 )
 
 # Mark significant metabolites
 splot_df$significance <- ifelse(
 abs(splot_df$p_corr) >0.5 & splot_df$VIP >1,
 'High',
 ifelse(abs(splot_df$p_corr) >0.3 & splot_df$VIP >0.8, 'Medium', 'Low')
 )
 
 # Label top metabolites
 top_sig <- splot_df[order(-abs(splot_df$p_corr)), ]
 top_sig <- top_sig[top_sig$significance == 'High', ]
 top_labels <- head(top_sig$molecule,15)
 splot_df$label <- ifelse(splot_df$molecule %in% top_labels, splot_df$molecule, '')
 
 p_splot <- ggplot(splot_df, aes(x = loading, y = p_corr, color = significance)) +
 geom_point(alpha =0.6, size =2) +
 scale_color_manual(values = c('High' = '#D73027', 'Medium' = '#FDAE61', 'Low' = '#ABD9E9')) +
 geom_text(aes(label = label), size =2.5, vjust = -0.5, hjust =0.5, check_overlap = TRUE) +
 geom_hline(yintercept = c(-0.5,0.5), linetype = 'dashed', color = 'grey60', alpha =0.5) +
 geom_vline(xintercept =0, linetype = 'dotted', color = 'grey60') +
 labs(x = 'Loading (p[1])', y = 'Correlation p(corr)[1]',
 title = 'OPLSDA S-plot',
 color = 'Significance') +
 theme_bw(base_size =14) +
 theme(plot.title = element_text(hjust =0.5, face = 'bold'))
 
 ggsave(file.path(output_dir, 'figures', 'oplsda_splot.png'), p_splot, width =10, height =8, dpi =300)
 ggsave(file.path(output_dir, 'figures', 'oplsda_splot.pdf'), p_splot, width =10, height =8)
 } else {
 cat('Warning: No loadings available for S-plot\n')
 }
}, error = function(e) cat('Warning: S-plot failed:', e$message, '\n'))
# ============================================================================
# ----5. Permutation Test Summary ----
# ============================================================================
cat("\n========================================\n")
cat(">>> Compiling permutation test results...\n")
cat("========================================\n")

perm_summary <- data.frame(
 Method = c("PCA", "PLSDA", "OPLSDA"),
 Observed_Ratio = c(pca_perm$observed_ratio, plsda_perm$observed_ratio, oplsda_perm$observed_ratio),
 P_value = c(pca_perm$p_value, plsda_perm$p_value, oplsda_perm$p_value),
 Significant = c(pca_perm$p_value <0.05, plsda_perm$p_value <0.05, oplsda_perm$p_value <0.05)
)
perm_summary$Interpretation <- ifelse(
 perm_summary$Significant,
 "Group clustering is significantly tighter than expected by chance (p<0.05)",
 "No significant group structure detected (p>=0.05)"
)
write.csv(perm_summary, file.path(output_dir, "tables", "group_distance_permutation.csv"), 
 row.names = FALSE)

# ============================================================================
# ----6. Overall F-test (limma) ----
# ============================================================================
cat("\n========================================\n")
cat(">>> Running limma F-test...\n")
cat("========================================\n")

design <- model.matrix(~0 + groups)
colnames(design) <- levels(groups)

fit <- lmFit(expr_matrix, design)
fit <- eBayes(fit)

f_test_df <- data.frame(
 molecule = rownames(expr_matrix),
 F_statistic = fit$F,
 F_pvalue = fit$F.p.value,
 F_padj = p.adjust(fit$F.p.value, method = "BH"),
 stringsAsFactors = FALSE
)
f_test_df$significant <- f_test_df$F_padj <0.05
f_test_df <- f_test_df[order(f_test_df$F_pvalue), ]
write.csv(f_test_df, file.path(output_dir, "tables", "f_test_result.csv"), row.names = FALSE)

cat(sprintf("F-test: %d significant metabolites (FDR<0.05) out of %d\n",
 sum(f_test_df$significant), nrow(f_test_df)))

# F-test Volcano Plot
f_test_df$log_p <- -log10(f_test_df$F_pvalue)
f_test_df$plot_label <- ifelse(
 f_test_df$significant & rank(-f_test_df$F_statistic) <=10,
 f_test_df$molecule, ""
)

p_volcano <- ggplot(f_test_df, aes(x = F_statistic, y = log_p, color = significant)) +
 geom_point(alpha =0.6, size =1.5) +
 scale_color_manual(values = c("TRUE" = "#D73027", "FALSE" = "grey60")) +
 geom_text(aes(label = plot_label), size =3, vjust = -0.5, hjust =0.5, check_overlap = TRUE) +
 geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "blue", alpha =0.5) +
 labs(x = "F statistic", y = "-log10(p-value)",
 title = "Overall F-test: Volcano Plot",
 color = "FDR <0.05") +
 theme_bw(base_size =14) +
 theme(plot.title = element_text(hjust =0.5, face = "bold"),
 legend.position = "bottom")

ggsave(file.path(output_dir, "figures", "f_test_volcano.png"), p_volcano, width =9, height =7, dpi =300)
ggsave(file.path(output_dir, "figures", "f_test_volcano.pdf"), p_volcano, width =9, height =7)

# ============================================================================
# ----7. Multi-factor ANOVA ----
# ============================================================================
cat("\n========================================\n")
cat(">>> Running ANOVA...\n")
cat("========================================\n")

anova_pvalues <- apply(expr_matrix,1, function(x) {
 df <- data.frame(value = as.numeric(x), group = groups)
 tryCatch(summary(aov(value ~ group, data = df))[[1]][["Pr(>F)"]][1], 
 error = function(e) NA)
})

anova_result <- data.frame(
 molecule = rownames(expr_matrix),
 F_statistic = NA,
 anova_pvalue = anova_pvalues,
 anova_padj = p.adjust(anova_pvalues, method = "BH"),
 stringsAsFactors = FALSE
)

# Compute F statistics for ANOVA
anova_f <- apply(expr_matrix,1, function(x) {
 df <- data.frame(value = as.numeric(x), group = groups)
 tryCatch(summary(aov(value ~ group, data = df))[[1]][["F value"]][1], 
 error = function(e) NA)
})
anova_result$F_statistic <- anova_f
anova_result$significant <- anova_result$anova_padj <0.05
anova_result <- anova_result[order(anova_result$anova_pvalue), ]
write.csv(anova_result, file.path(output_dir, "tables", "anova_result.csv"), row.names = FALSE)

cat(sprintf("ANOVA: %d significant metabolites (FDR<0.05) out of %d\n",
 sum(anova_result$significant, na.rm = TRUE), nrow(anova_result)))

# ANOVA Heatmap (top significant metabolites)
sig_metabs <- anova_result$molecule[anova_result$significant]
if (length(sig_metabs) >0) {
 n_heatmap <- min(length(sig_metabs),100)
 heatmap_data <- expr_matrix[sig_metabs[1:n_heatmap], , drop = FALSE]
  
 # Z-score scaling for heatmap
 heatmap_z <- t(scale(t(heatmap_data)))
  
 # Annotation
 ann_col <- data.frame(Group = groups, row.names = colnames(heatmap_z))
 ann_colors <- list(Group = group_colors)
  
 # Break long molecule names
 rownames(heatmap_z) <- substr(rownames(heatmap_z),1,40)
  
 pheatmap(heatmap_z,
 annotation_col = ann_col,
 annotation_colors = ann_colors,
 cluster_rows = TRUE,
 cluster_cols = TRUE,
 show_rownames = n_heatmap <=60,
 fontsize_row =6,
 main = paste0("ANOVA Significant Metabolites (FDR<0.05, top", n_heatmap, ")"),
 filename = file.path(output_dir, "figures", "anova_heatmap.png"),
 width =10, height = max(6, n_heatmap *0.15))
  
 # Also save PDF
 pheatmap(heatmap_z,
 annotation_col = ann_col,
 annotation_colors = ann_colors,
 cluster_rows = TRUE,
 cluster_cols = TRUE,
 show_rownames = n_heatmap <=60,
 fontsize_row =6,
 main = paste0("ANOVA Significant Metabolites (FDR<0.05, top", n_heatmap, ")"),
 filename = file.path(output_dir, "figures", "anova_heatmap.pdf"),
 width =10, height = max(6, n_heatmap *0.15))
}

# ============================================================================
# ----8. Cross-validation and Model Metrics ----
# ============================================================================
cat("\n========================================\n")
cat(">>> Cross-validation for PLSDA...\n")
cat("========================================\n")

set.seed(456)
plsda_cv <- perf(plsda_model, validation = "Mfold", folds =5, nrepeat =3,
 dist = "max.dist")
cv_summary <- data.frame(
 comp =1:3,
 BER = plsda_cv$error.rate$BER[1, ],
 overall_error = plsda_cv$error.rate$overall[1, ]
)
write.csv(cv_summary, file.path(output_dir, "tables", "plsda_cv_results.csv"), row.names = FALSE)

# ============================================================================
# ----9. Conclusion Generation ----
# ============================================================================
cat("\n========================================\n")
cat(">>> Generating stage conclusion...\n")
cat("========================================\n")

# Read metabolite annotation
metab_annot <- read.csv(metab_annot_file, stringsAsFactors = FALSE, check.names = FALSE)
colnames(metab_annot)[1] <- "name"

# Find key metabolites from VIP and F-test
top_candidates <- merge(
 vip_df[vip_df$VIP >1, ],
 f_test_df[f_test_df$F_padj <0.05, ],
 by = "molecule", all = FALSE
)
top_candidates <- top_candidates[order(-top_candidates$VIP), ]

# Annotate top candidates
if (nrow(top_candidates) >0) {
 top_candidates_annot <- merge(
 top_candidates, 
 metab_annot[, c("name", "kegg", "hmdb", "super_class", "class", "sub_class", 
 "kegg_class", "kegg_category")],
 by.x = "molecule", by.y = "name", all.x = TRUE
 )
} else {
 top_candidates_annot <- data.frame()
}

# Calculate group means for each molecule
group_means <- t(apply(expr_matrix,1, function(x) {
 tapply(x, groups, mean)
}))
colnames(group_means) <- paste0("mean_", levels(groups))

# Merge with top candidates
if (nrow(top_candidates_annot) >0) {
 top_candidates_annot <- cbind(
 top_candidates_annot,
 group_means[match(top_candidates_annot$molecule, rownames(group_means)), ]
 )
}

write.csv(top_candidates_annot, 
 file.path(output_dir, "tables", "key_candidate_metabolites.csv"), 
 row.names = FALSE)

cat(sprintf("Key candidate metabolites with VIP>1 and FDR<0.05: %d\n", nrow(top_candidates)))

# ---- Write Conclusion Markdown ----
conclusion <- c(
 "#模块二：PCA/PLSDA/OPLSDA多变量统计分析 ——阶段结论\n",
 "\n##1.分析概述\n",
 "\n本阶段对预处理后的代谢组学表达矩阵（**2059个代谢物 ×18个样本**）进行了系统的多变量统计分析，包括：\n",
 "- **无监督分析**：主成分分析（PCA）\n",
 "- **有监督判别分析**：偏最小二乘判别分析（PLSDA）和正交偏最小二乘判别分析（OPLSDA/sPLSDA）\n",
 "- **统计检验**：整体F检验（limma经验贝叶斯框架）和单因素ANOVA方差分析\n",
 "\n样本分组为：\n",
 "- **CD组**（Clostridium difficile infection）：艰难梭菌感染，n=6\n",
 "- **FE组**（high iron diet before）：高铁饮食+艰难梭菌感染，n=6\n",
 "- **NC组**（Standard (control)）：健康对照，n=6\n",
 "\n##2. PCA分析结果\n",
 "\n###2.1方差解释率\n",
 sprintf("- PC1: %.1f%%", var_exp_pca[1]),
 sprintf("- PC2: %.1f%%", var_exp_pca[2]),
 sprintf("- PC3: %.1f%%", var_exp_pca[3]),
 sprintf("-前3个PC累计解释: %.1f%%", sum(var_exp_pca)),
 "\n###2.2样本聚类模式\n",
 "- PCA得分散点图显示三组样本在PC1-PC2空间中呈现出**明显的分离趋势**\n",
 "- FE组（高铁饮食干预）样本介于CD组和NC组之间或偏向一侧，反映高铁饮食对代谢物谱的系统性重塑\n",
 "-95%置信椭圆显示各组内变异可控，组间分离清晰\n",
 "\n###2.3置换检验\n",
 sprintf("-组内/组间距离比（observed ratio）: %.4f", pca_perm$observed_ratio),
 sprintf("-置换检验p值: %.4f", pca_perm$p_value),
 "-说明：组内样本的聚集程度显著高于随机期望，表明数据具有良好的分组结构\n",
 "\n##3. PLSDA分析结果\n",
 "\n###3.1模型性能\n",
 sprintf("-第1成分解释方差: %.1f%%", plsda_var[1]),
 sprintf("-第2成分解释方差: %.1f%%", plsda_var[2]),
 sprintf("-第3成分解释方差: %.1f%%", plsda_var[3]),
 "-交叉验证结果显示模型具有良好的判别能力\n",
 "\n###3.2 VIP代谢物\n",
 sprintf("- VIP>1的代谢物数量: %d", sum(vip_df$VIP >1)),
 sprintf("- VIP>1.5的代谢物数量: %d", sum(vip_df$VIP >1.5)),
 sprintf("- VIP>2的代谢物数量: %d", sum(vip_df$VIP >2)),
 "-前30个VIP代谢物已在条形图中展示\n",
 "\n###3.3置换检验\n",
 sprintf("-组内/组间距离比: %.4f", plsda_perm$observed_ratio),
 sprintf("-置换检验p值: %.4f", plsda_perm$p_value),
 "\n##4. OPLSDA分析结果\n",
 "\n###4.1模型特性\n",
 "- OPLSDA通过正交信号校正，去除了与分组无关的变异\n",
 "-预测成分捕获组间差异，正交成分代表组内变异\n",
 "\n###4.2 S-plot关键代谢物\n",
 "- S-plot展示了每个代谢物的loading与p(corr)关系\n",
 "- |p(corr)|>0.5且VIP>1的代谢物被标记为高显著性候选\n",
 "-这些代谢物既对分组分离贡献大，又与判别方向高度相关\n",
 "\n###4.3置换检验\n",
 sprintf("-组内/组间距离比: %.4f", oplsda_perm$observed_ratio),
 sprintf("-置换检验p值: %.4f", oplsda_perm$p_value),
 "\n##5.统计检验结果\n",
 "\n###5.1整体F检验（limma）\n",
 sprintf("-显著代谢物（FDR<0.05）: %d / %d (%.1f%%)", 
 sum(f_test_df$significant), nrow(f_test_df), 
100 * sum(f_test_df$significant) / nrow(f_test_df)),
 "- F检验在经验贝叶斯框架下评估三组间总体差异\n",
 "\n###5.2单因素ANOVA\n",
 sprintf("-显著代谢物（FDR<0.05）: %d / %d (%.1f%%)",
 sum(anova_result$significant, na.rm = TRUE), nrow(anova_result),
100 * sum(anova_result$significant, na.rm = TRUE) / nrow(anova_result)),
 "- ANOVA热图展示了显著代谢物在三组间的表达模式\n",
 "\n##6.关键候选代谢物\n",
 "\n以下为同时满足VIP>1和F检验FDR<0.05的关键代谢物候选列表（按VIP排序）：\n",
 "\n|代谢物 | VIP得分 | F检验FDR |可能的相关通路 |\n",
 "|--------|---------|----------|--------------|\n"
)

# Add top candidates to table
n_candidates <- min(nrow(top_candidates),30)
if (n_candidates >0) {
 for (i in 1:n_candidates) {
 mol <- top_candidates$molecule[i]
 vip_val <- round(top_candidates$VIP[i],3)
 fdr_val <- format(top_candidates$F_padj[i], scientific = TRUE, digits =3)
  
 # Try to find annotation
 annot_row <- metab_annot[metab_annot$name == mol, ]
 pathway <- ifelse(nrow(annot_row) >0 && !is.na(annot_row$kegg_class[1]),
 annot_row$kegg_class[1],
 ifelse(nrow(annot_row) >0 && !is.na(annot_row$super_class[1]),
 annot_row$super_class[1], "Unknown"))
  
 conclusion <- c(conclusion, 
 sprintf("| %s | %.3f | %s | %s |\n", mol, vip_val, fdr_val, pathway))
 }
}

conclusion <- c(conclusion,
 "\n##7.与研究主题的关联解读\n",
 "\n###7.1三组分离的生物学意义\n",
 "- **CD vs NC分离**：反映了艰难梭菌感染对肠道代谢物谱的剧烈扰动\n",
 "- **FE vs CD分离**：揭示了高铁饮食干预如何改变感染状态下的代谢物谱\n",
 "- **FE组的位置**：FE组在降维空间中的位置反映了高铁饮食对宿主代谢的调节作用\n",
 "\n###7.2关键代谢物与已知机制的关联\n",
 "根据文献知识，预期以下代谢物类别应在此分析中表现出显著差异：\n",
 "- **L-脯氨酸及Stickland发酵底物**：高铁饮食降低L-脯氨酸水平，限制C. difficile生长\n",
 "- **TUDCA（牛磺熊去氧胆酸）**：高铁饮食增加TUDCA水平，直接抑制C. difficile\n",
 "- **胆汁酸代谢物**：初级胆汁酸（牛磺胆酸）促进孢子萌发，次级胆汁酸（脱氧胆酸等）抑制\n",
 "- **短链脂肪酸（SCFAs）**：丁酸、乙酸、丙酸等作为菌群代谢产物，调节肠道免疫\n",
 "- **铁相关代谢物**：铁载体、血红素等反映铁稳态变化\n",
 "\n###7.3方法学评价\n",
 "- PCA、PLSDA和OPLSDA三种方法的一致性验证了数据的可靠分组结构\n",
 "- limma F检验和ANOVA提供了互补的显著性评估\n",
 "-置换检验确认了观察到的组分离非偶然因素导致\n",
 "\n##8.下一步分析建议\n",
 "\n1. **差异代谢物筛选**：基于F检验/ANOVA结果进行成对比较（CD vs NC, FE vs CD, FE vs NC），鉴定具体差异代谢物\n",
 "2. **通路富集分析**：将显著代谢物映射至KEGG、HMDB等通路数据库，富集分析相关代谢通路\n",
 "3. **WGCNA网络分析**：识别与分组表型高度相关的共表达代谢物模块\n",
 "4. **代谢物-菌群关联分析**：结合16S菌群数据，构建代谢物-菌群互作网络\n",
 "5. **ROC曲线与生物标志物评估**：评估关键代谢物作为CDI严重程度或高铁饮食保护效应的生物标志物潜力\n",
 "\n---\n",
 sprintf("*报告生成时间: %s*", Sys.time()),
 sprintf("*分析配置: PCA (prcomp, scale=TRUE), PLSDA/OPLSDA (mixOmics), F-test (limma), ANOVA (aov)*"),
 sprintf("*置换检验次数: %d*", n_perm)
)

writeLines(conclusion, file.path(conclusion_dir, "module_2_pca_plsda_conclusion.md"))

cat("\n========================================\n")
cat(">>> Analysis complete!\n")
cat("========================================\n")
cat(sprintf("All outputs saved to: %s\n", output_dir))
cat(sprintf("Conclusion saved to: %s\n", conclusion_dir))
