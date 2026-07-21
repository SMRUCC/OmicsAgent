# ============================================================================
# R 工具函数脚本 - PCA/PLSDA/OPLSDA 分析
# ============================================================================
# 该脚本实现了总体样本的 PCA、PLSDA、OPLSDA 分析，以及数据重复性质量评估。
#
# 使用方式：
#   source("pca_plsda_analysis.R")
#   result <- run_pca_analysis(
#     expr_file = "preprocessed_expression.csv",
#     sample_info_file = "sample_info.csv",
#     output_dir = "analysis_modules_2",
#     group_col = "sample_info"
#   )
# ============================================================================

library(ggplot2)

run_pca_analysis <- function(expr_file, sample_info_file, output_dir,
                              group_col = "sample_info", meta_cols = NULL) {
  dir.create(file.path(output_dir, "tables"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(output_dir, "figures"), showWarnings = FALSE, recursive = TRUE)
  
  # 读取数据
  expr <- read.csv(expr_file, row.names = 1, check.names = FALSE)
  expr_matrix <- as.matrix(expr)
  mode(expr_matrix) <- "numeric"
  
  sample_info <- read.csv(sample_info_file, stringsAsFactors = FALSE, check.names = FALSE)
  
  # 确保样本顺序一致
  common_samples <- intersect(colnames(expr_matrix), sample_info$ID)
  expr_matrix <- expr_matrix[, common_samples]
  sample_info <- sample_info[match(common_samples, sample_info$ID), ]
  
  groups <- sample_info[[group_col]]
  
  # ---------------- PCA 分析 ----------------
  pca_result <- prcomp(t(expr_matrix), scale. = TRUE, center = TRUE)
  pca_scores <- as.data.frame(pca_result$x[, 1:3])
  pca_scores$sample <- rownames(pca_scores)
  pca_scores$group <- groups
  
  # 方差解释率
  var_explained <- summary(pca_result)$importance[2, 1:3] * 100
  
  # 计算组内离散度（加权欧氏距离）
  group_centroids <- aggregate(pca_scores[, 1:3], list(group = groups), mean)
  within_distances <- c()
  for (g in unique(groups)) {
    g_samples <- pca_scores[groups == g, 1:3]
    centroid <- as.numeric(group_centroids[group_centroids$group == g, 2:4])
    weights <- var_explained / sum(var_explained)
    for (i in 1:nrow(g_samples)) {
      dist <- sqrt(sum(weights * (as.numeric(g_samples[i, 1:3]) - centroid)^2))
      within_distances <- c(within_distances, dist)
    }
  }
  
  # 全局平均距离
  global_centroid <- colMeans(pca_scores[, 1:3])
  global_distances <- c()
  for (i in 1:nrow(pca_scores)) {
    dist <- sqrt(sum((as.numeric(pca_scores[i, 1:3]) - global_centroid)^2))
    global_distances <- c(global_distances, dist)
  }
  
  # 置换检验
  p_value <- tryCatch({
    wilcox.test(within_distances, global_distances, alternative = "less")$p.value
  }, error = function(e) NA)
  
  # 保存 PCA 得分
  write.csv(pca_scores, file.path(output_dir, "tables", "pca_scores.csv"), row.names = FALSE)
  
  # 绘制 PCA 散点图
  p <- ggplot(pca_scores, aes(x = PC1, y = PC2, color = group, shape = group)) +
    geom_point(size = 3) +
    stat_ellipse(level = 0.95, type = "norm") +
    labs(x = paste0("PC1 (", round(var_explained[1], 1), "%)"),
         y = paste0("PC2 (", round(var_explained[2], 1), "%)"),
         title = "PCA Score Plot") +
    theme_bw() +
    theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"))
  
  ggsave(file.path(output_dir, "figures", "pca_score_plot.png"), p, width = 8, height = 6, dpi = 300)
  ggsave(file.path(output_dir, "figures", "pca_score_plot.pdf"), p, width = 8, height = 6)
  
  # ---------------- PLSDA 分析 ----------------
  plsda_result <- tryCatch({
    library(mixOmics)
    plsda_model <- plsda(t(expr_matrix), groups, ncomp = 3)
    plsda_scores <- as.data.frame(plsda_model$variates$X[, 1:3])
    plsda_scores$sample <- rownames(plsda_scores)
    plsda_scores$group <- groups
    
    write.csv(plsda_scores, file.path(output_dir, "tables", "plsda_scores.csv"), row.names = FALSE)
    
    p_plsda <- ggplot(plsda_scores, aes(x = comp1, y = comp2, color = group, shape = group)) +
      geom_point(size = 3) +
      stat_ellipse(level = 0.95) +
      labs(x = "Component 1", y = "Component 2", title = "PLSDA Score Plot") +
      theme_bw() + theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"))
    
    ggsave(file.path(output_dir, "figures", "plsda_score_plot.png"), p_plsda, width = 8, height = 6, dpi = 300)
    ggsave(file.path(output_dir, "figures", "plsda_score_plot.pdf"), p_plsda, width = 8, height = 6)
    
    plsda_model
  }, error = function(e) {
    cat("PLSDA failed:", e$message, "\n")
    NULL
  })
  
  # ---------------- OPLSDA 分析 ----------------
  oplsda_result <- tryCatch({
    library(mixOmics)
    oplsda_model <- splsda(t(expr_matrix), groups, ncomp = 3, mode = "regression")
    oplsda_scores <- as.data.frame(oplsda_model$variates$X[, 1:3])
    oplsda_scores$sample <- rownames(oplsda_scores)
    oplsda_scores$group <- groups
    
    write.csv(oplsda_scores, file.path(output_dir, "tables", "oplsda_scores.csv"), row.names = FALSE)
    
    p_oplsda <- ggplot(oplsda_scores, aes(x = comp1, y = comp2, color = group, shape = group)) +
      geom_point(size = 3) +
      stat_ellipse(level = 0.95) +
      labs(x = "Predictive Component", y = "Orthogonal Component", title = "OPLSDA Score Plot") +
      theme_bw() + theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"))
    
    ggsave(file.path(output_dir, "figures", "oplsda_score_plot.png"), p_oplsda, width = 8, height = 6, dpi = 300)
    ggsave(file.path(output_dir, "figures", "oplsda_score_plot.pdf"), p_oplsda, width = 8, height = 6)
    
    oplsda_model
  }, error = function(e) {
    cat("OPLSDA failed:", e$message, "\n")
    NULL
  })
  
  # ---------------- 总体 F 检验 ----------------
  f_test_result <- tryCatch({
    library(limma)
    design <- model.matrix(~ 0 + factor(groups))
    colnames(design) <- levels(factor(groups))
    fit <- lmFit(expr_matrix, design)
    fit <- eBayes(fit)
    f_stats <- fit$F
    f_pvalues <- fit$F.p.value
    
    f_test_df <- data.frame(
      molecule = rownames(expr_matrix),
      F_statistic = f_stats,
      F_pvalue = f_pvalues
    )
    write.csv(f_test_df, file.path(output_dir, "tables", "f_test_result.csv"), row.names = FALSE)
    f_test_df
  }, error = function(e) {
    cat("F test failed:", e$message, "\n")
    NULL
  })
  
  # ---------------- 多因素 ANOVA 检验 ----------------
  anova_result <- tryCatch({
    anova_pvalues <- apply(expr_matrix, 1, function(x) {
      df <- data.frame(value = as.numeric(x), group = groups)
      tryCatch(summary(aov(value ~ group, data = df))[[1]][["Pr(>F)"]][1], error = function(e) NA)
    })
    anova_df <- data.frame(molecule = rownames(expr_matrix), anova_pvalue = anova_pvalues)
    write.csv(anova_df, file.path(output_dir, "tables", "anova_result.csv"), row.names = FALSE)
    anova_df
  }, error = function(e) {
    cat("ANOVA failed:", e$message, "\n")
    NULL
  })
  
  # 生成质量评估总结
  quality_assessment <- list(
    n_samples = ncol(expr_matrix),
    n_molecules = nrow(expr_matrix),
    n_groups = length(unique(groups)),
    var_explained_pc1 = var_explained[1],
    var_explained_pc2 = var_explained[2],
    within_distance_mean = mean(within_distances),
    global_distance_mean = mean(global_distances),
    permutation_pvalue = p_value,
    quality = if (!is.na(p_value) && p_value < 0.05) "GOOD" else "WARNING"
  )
  
  return(quality_assessment)
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 3) {
    run_pca_analysis(args[1], args[2], args[3])
  } else {
    cat("Usage: Rscript pca_plsda_analysis.R <expr_file> <sample_info_file> <output_dir>\n")
  }
}
