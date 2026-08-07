# ==============================================================================
# 线性回归表型预测脚本
# ==============================================================================
# 职责：读取 cache 的 log2 矩阵 -> run_linear_model 分别以 variety（二分类）
#       与 phase（多分类）为响应变量建模 -> 导出逐特征单变量回归统计表、
#       分类模型系数表、混淆矩阵表 -> 打印训练与交叉验证准确率。
#
# 说明：run_linear_model 的分类器使用全部传入特征，当特征数 >= 样本数时
#       会完全分离训练数据。因此显式传入 top_features 限制预测变量集，
#       并以交叉验证准确率作为泛化能力指标。
# ==============================================================================

source("g:/OmicsWorks/test/multiple_omics/metabolism_demo/config.R", encoding = "UTF-8")

set.seed(RANDOM_SEED)

section("线性回归表型预测")

step("加载 agent/rscript 模块")
source_modules(c(
  "utils/export.R",
  "utils/plot_helpers.R",
  "theme_palette.R",
  "machine_learning/linear_model.R"
))

log2_mat     <- readRDS(file.path(CACHE_DIR, "log2_mat.rds"))
sample_info  <- readRDS(file.path(CACHE_DIR, "sample_info.rds"))
feature_info <- readRDS(file.path(CACHE_DIR, "feature_info.rds"))
mat_dim("缓存 log2 矩阵", log2_mat)

# ------------------------------------------------------------------------------
# 预测变量集：按方差取 top N，避免 p >= n 导致分类器饱和
# ------------------------------------------------------------------------------
N_PREDICTORS <- 40
feat_var <- apply(log2_mat, 1, stats::var, na.rm = TRUE)
top_features <- rownames(log2_mat)[order(feat_var, decreasing = TRUE)][seq_len(N_PREDICTORS)]
cat(sprintf("    分类器预测变量数: %d (样本数 %d)\n",
            N_PREDICTORS, ncol(log2_mat)))

# ==============================================================================
# 建模：对每个表型分别运行
# ==============================================================================
run_one <- function(group_col, control_group, tag) {
  section(sprintf("表型 = %s (control = %s)", group_col, control_group))

  grp_tab <- table(as.character(sample_info[[group_col]]))
  cat("    分组分布:",
      paste(sprintf("%s=%d", names(grp_tab), grp_tab), collapse = ", "), "\n")

  step("run_linear_model")
  lm_res <- timed(sprintf("run_linear_model(%s)", group_col),
                  run_linear_model(
                    log2_mat, sample_info,
                    group_col = group_col,
                    exclude_groups = NULL,      # 本数据集无 QC 样本
                    control_group = control_group,
                    top_features = top_features,
                    cv_folds = 5,
                    seed = RANDOM_SEED
                  ))

  section("模型表现", 2)
  cat(sprintf("    特征数 / 样本数     : %d / %d\n",
              lm_res$n_features, lm_res$n_samples))
  cat(sprintf("    训练(重代入)准确率  : %.4f\n", lm_res$train_accuracy))
  cat(sprintf("    %d 折交叉验证准确率 : %.4f\n",
              lm_res$cv_folds, lm_res$cv_accuracy))
  cat(sprintf("    基线(多数类)准确率  : %.4f\n", max(grp_tab) / sum(grp_tab)))

  cat("\n    训练混淆矩阵:\n")
  print(lm_res$confusion_matrix)
  if (!is.null(lm_res$cv_confusion_matrix)) {
    cat("\n    交叉验证混淆矩阵:\n")
    print(lm_res$cv_confusion_matrix)
  }

  # --- 导出 ---
  cm_df <- as.data.frame.matrix(lm_res$confusion_matrix)
  export_table(cm_df, RESULT_DIR, sprintf("30_regression_%s_confusion_train", tag),
               use_rownames = TRUE, id_col_name = "predicted")
  if (!is.null(lm_res$cv_confusion_matrix)) {
    cmcv_df <- as.data.frame.matrix(lm_res$cv_confusion_matrix)
    export_table(cmcv_df, RESULT_DIR,
                 sprintf("30_regression_%s_confusion_cv", tag),
                 use_rownames = TRUE, id_col_name = "predicted")
  }

  export_table(lm_res$classification_coefficients, RESULT_DIR,
               sprintf("30_regression_%s_classifier_coef", tag),
               use_rownames = FALSE)

  # 逐特征单变量回归统计
  cf <- lm_res$coefficients
  cat(sprintf("\n    逐特征单变量回归结果行数: %d\n", nrow(cf)))
  cat("    比较标签:", paste(unique(cf$comparison), collapse = " | "), "\n")
  cat(sprintf("    p_adj < 0.05 的 (特征,比较) 对: %d\n",
              sum(cf$p_adj < 0.05, na.rm = TRUE)))

  # 附化学分类注释
  ai <- match(cf$feature_id, rownames(feature_info))
  cf$super_class <- as.character(feature_info$super_class[ai])
  cf$class <- as.character(feature_info$class[ai])
  cf <- cf[order(cf$comparison, cf$p_value), ]
  export_table(cf, RESULT_DIR, sprintf("30_regression_%s_feature_lm", tag),
               use_rownames = FALSE)

  cat("\n    各比较 Top5 (按 R2 降序):\n")
  for (cmp in unique(cf$comparison)) {
    sub <- cf[cf$comparison == cmp, ]
    sub <- sub[order(sub$r2, decreasing = TRUE), ]
    cat(sprintf("      [%s]\n", cmp))
    for (i in seq_len(min(5, nrow(sub)))) {
      cat(sprintf("        %-38s R2=%.4f  p_adj=%.3g  %s\n",
                  substr(sub$feature_id[i], 1, 38), sub$r2[i],
                  sub$p_adj[i], sub$equation[i]))
    }
  }

  # --- 可视化：Top R2 特征条形图 ---
  best <- cf[!is.na(cf$r2), ]
  best <- best[order(best$r2, decreasing = TRUE), ][seq_len(min(20, nrow(best))), ]
  best$lab <- factor(paste0(substr(best$feature_id, 1, 30), " | ", best$comparison),
                     levels = rev(paste0(substr(best$feature_id, 1, 30), " | ",
                                         best$comparison)))
  p <- ggplot2::ggplot(best, ggplot2::aes(x = lab, y = r2,
                                          fill = p_adj < 0.05)) +
    ggplot2::geom_col() +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = c("FALSE" = "grey70", "TRUE" = "#2c7fb8"),
                               name = "p_adj < 0.05") +
    ggplot2::labs(title = sprintf("Top univariate linear fits (%s)", group_col),
                  x = NULL, y = expression(R^2)) +
    theme_pub()
  export_plot(p, FIGURE_DIR, sprintf("31_regression_%s_top_r2", tag),
              width = 10, height = 8)

  invisible(lm_res)
}

res_variety <- run_one(GROUP_VARIETY, "Burley", "variety")
res_phase   <- run_one(GROUP_PHASE, NULL, "phase")

# ==============================================================================
# 汇总
# ==============================================================================
section("模型表现汇总")

summ <- data.frame(
  phenotype = c(GROUP_VARIETY, GROUP_PHASE),
  n_groups = c(length(res_variety$groups), length(res_phase$groups)),
  n_features = c(res_variety$n_features, res_phase$n_features),
  n_samples = c(res_variety$n_samples, res_phase$n_samples),
  train_accuracy = c(res_variety$train_accuracy, res_phase$train_accuracy),
  cv_accuracy = c(res_variety$cv_accuracy, res_phase$cv_accuracy),
  stringsAsFactors = FALSE
)
print(summ)
export_table(summ, RESULT_DIR, "30_regression_summary", use_rownames = FALSE)

saveRDS(list(variety = res_variety, phase = res_phase),
        file.path(CACHE_DIR, "regression.rds"))
step("已缓存 regression.rds")

cat("\n[done] 线性回归表型预测完成。\n")
