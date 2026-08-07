# ==============================================================================
# OmicsFlow: Limma 差异表达分析
# ==============================================================================
# 多种策略的差异分析
# ==============================================================================

#' 运行 limma 差异分析
#'
#' @description 使用 limma 包结合经验贝叶斯（empirical Bayes）收缩，进行差异表达分析。
#'   支持多种用于筛选显著Feature的策略。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param sample_info 含有样本元数据的数据框。
#' @param group_col 分组标签所在的列名。默认："sample_info"。
#' @param control_group 字符型，对照/参考分组名称。默认：NULL（按字母序取第一个分组）。
#' @param case_groups 字符向量，与对照组进行比较的分组。默认：NULL（所有非对照组）。
#' @param exclude_groups 要排除的可选分组（如 "QC"）。默认："QC"。
#' @param strategy 字符型，筛选策略：
#'   \itemize{
#'     \item \code{"pvalue_logFC"}：p 值 + logFC 阈值。
#'     \item \code{"pvalue_vip"}：p 值 + VIP 阈值。
#'     \item \code{"pvalue_topN"}：p 值显著 + 按 logFC 取前 N 个。
#'   }
#'   默认："pvalue_logFC"。
#' @param p_threshold p 值阈值。默认：0.05。
#' @param logfc_threshold logFC 绝对值阈值。默认：1。
#' @param vip_threshold VIP 阈值。默认：1.0。
#' @param top_n "pvalue_topN" 策略下的前 N 个Feature数量。默认：20。
#' @param p_adj_method P 值校正方法。默认："BH"。
#' @param vip_result 来自 PLS-DA 的可选 VIP 结果。"pvalue_vip" 策略必填。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{results}：合并结果数据框。行由 \code{feature_id} 列中的
#'       纯Feature名标识（无比较后缀）。包含 \code{significant} 逻辑列和
#'       \code{regulation} 列（取值为 "up"、"down" 或 "not sig"）。
#'     \item \code{significant}：显著Feature数据框（results 的子集）。
#'     \item \code{comparisons}：各比较结果列表。
#'     \item \code{strategy}：所使用的策略。
#'   }
#'
#' @examples
#' \dontrun{
#' # 基础：p 值 + logFC
#' de <- run_limma(expr_matrix, sample_info,
#'                 control_group = "Standard (control)",
#'                 strategy = "pvalue_logFC")
#'
#' # p 值 + VIP
#' plsda <- run_plsda(expr_matrix, sample_info)
#' de <- run_limma(expr_matrix, sample_info,
#'                 strategy = "pvalue_vip",
#'                 vip_result = plsda$vip)
#'
#' # 按 logFC 取前 N 个
#' de <- run_limma(expr_matrix, sample_info,
#'                 strategy = "pvalue_topN", top_n = 30)
#' }
#'
#' @export
run_limma <- function(expr_matrix, sample_info, group_col = "sample_info",
                     control_group = NULL, case_groups = NULL,
                     exclude_groups = "QC", strategy = "pvalue_logFC",
                     p_threshold = 0.05, logfc_threshold = 1,
                     vip_threshold = 1.0, top_n = 20,
                     p_adj_method = "BH", vip_result = NULL) {
  # 对齐样本
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]

  # 排除分组
  if (!is.null(exclude_groups)) {
    keep_samples <- rownames(sample_info)[!(sample_info[[group_col]] %in% exclude_groups)]
    expr_matrix <- expr_matrix[, keep_samples, drop = FALSE]
    sample_info <- sample_info[keep_samples, , drop = FALSE]
  }

  groups <- factor(sample_info[[group_col]])

  # 确定对照组与处理组
  if (is.null(control_group)) {
    control_group <- levels(groups)[1]
  }
  if (is.null(case_groups)) {
    case_groups <- setdiff(levels(groups), control_group)
  }

  # 清洗分组名以用于 makeContrasts
  orig_levels <- levels(groups)
  safe_levels <- make.names(orig_levels)
  names(safe_levels) <- orig_levels
  groups_safe <- factor(groups, levels = orig_levels, labels = safe_levels)

  # 检查 limma 是否可用
  if (requireNamespace("limma", quietly = TRUE)) {
    # 设计矩阵
    design <- stats::model.matrix(~ 0 + groups_safe)
    colnames(design) <- safe_levels

    # 拟合模型
    fit <- limma::lmFit(expr_matrix, design)

    # 对比矩阵
    safe_case <- safe_levels[orig_levels %in% case_groups]
    safe_control <- safe_levels[orig_levels == control_group]
    contrast_strs <- paste0(safe_case, " - ", safe_control)
    contrast_mat <- limma::makeContrasts(contrasts = contrast_strs,
                                          levels = design)
    colnames(contrast_mat) <- case_groups

    fit2 <- limma::contrasts.fit(fit, contrast_mat)
    fit2 <- limma::eBayes(fit2)

    # 提取结果
    all_results <- list()
    for (cg in case_groups) {
      tt <- limma::topTable(fit2, coef = cg, number = Inf, sort.by = "none")
      tt$feature_id <- rownames(tt)
      tt$comparison <- paste0(cg, "_vs_", control_group)
      all_results[[cg]] <- tt
    }
    combined <- do.call(rbind, all_results)
    rownames(combined) <- NULL

  } else {
    # 回退方案：使用基础 R 的 t 检验
    warning("Package 'limma' not installed, falling back to simple t-test.")
    combined <- .t_test_de(expr_matrix, groups, control_group, case_groups)
  }

  # 必要时重命名列
  colnames(combined)[colnames(combined) == "P.Value"] <- "p_value"
  colnames(combined)[colnames(combined) == "adj.P.Val"] <- "p_adj"
  colnames(combined)[colnames(combined) == "logFC"] <- "logFC"

  # 将策略名统一为小写以便不区分大小写匹配
  strategy_norm <- tolower(strategy)

  # 应用筛选策略
  if (strategy_norm == "pvalue_logfc") {
    combined$significant <- combined$p_adj < p_threshold &
                            abs(combined$logFC) >= logfc_threshold

  } else if (strategy_norm == "pvalue_vip") {
    if (is.null(vip_result)) {
      stop("vip_result must be provided when strategy = 'pvalue_vip'")
    }
    # 合并 VIP
    vip_df <- vip_result
    colnames(vip_df)[2] <- "vip"
    combined <- merge(combined, vip_df, by = "feature_id", all.x = TRUE)
    combined$significant <- combined$p_adj < p_threshold &
                            combined$vip >= vip_threshold

  } else if (strategy_norm == "pvalue_topn") {
    combined$significant <- FALSE
    for (comp in unique(combined$comparison)) {
      comp_idx <- combined$comparison == comp & combined$p_adj < p_threshold
      comp_data <- combined[comp_idx, ]
      if (nrow(comp_data) > 0) {
        # 按 logFC 绝对值降序排序
        comp_data <- comp_data[order(abs(comp_data$logFC), decreasing = TRUE), ]
        top_idx <- head(rownames(comp_data), top_n)
        combined[top_idx, "significant"] <- TRUE
      }
    }

  } else {
    # 未知策略 / 回退：默认采用 p 值 + logFC 规则
    warning("Unknown strategy '", strategy, "', falling back to 'pvalue_logFC'.")
    combined$significant <- combined$p_adj < p_threshold &
                            abs(combined$logFC) >= logfc_threshold
  }

  # 确保存在 significant 列（例如 t 检验回退路径）
  if (is.null(combined$significant)) {
    combined$significant <- combined$p_adj < p_threshold &
                            abs(combined$logFC) >= logfc_threshold
  }

  # 根据显著性与 logFC 方向添加 up/down/not sig 调节方向标记
  combined$regulation <- ifelse(combined$significant & combined$logFC > 0, "up",
                        ifelse(combined$significant & combined$logFC < 0, "down",
                               "not sig"))

  # 筛选显著结果
  sig_results <- combined[combined$significant, , drop = FALSE]

  # 保留 feature_id 作为真实列（纯Feature名，无比较后缀），
  # 并将行名重置为默认，避免 export_table 将行名派生出的重复
  # feature_id 列前置。
  rownames(combined) <- NULL
  rownames(sig_results) <- NULL

  # 将 feature_id 移到首列，以获得清晰一致的导出顺序。
  if ("feature_id" %in% colnames(combined)) {
    combined <- combined[, c("feature_id",
                             setdiff(colnames(combined), "feature_id")), drop = FALSE]
  }
  if ("feature_id" %in% colnames(sig_results)) {
    sig_results <- sig_results[, c("feature_id",
                                   setdiff(colnames(sig_results), "feature_id")), drop = FALSE]
  }

  return(list(
    results = combined,
    significant = sig_results,
    comparisons = all_results,
    strategy = strategy
  ))
}


#' 简单 t 检验差异分析（内部回退函数）
#'
#' @keywords internal
#' @noRd
.t_test_de <- function(expr_matrix, groups, control_group, case_groups) {
  control_samples <- colnames(expr_matrix)[groups == control_group]
  results_list <- list()

  for (cg in case_groups) {
    case_samples <- colnames(expr_matrix)[groups == cg]
    for (i in 1:nrow(expr_matrix)) {
      control_vals <- expr_matrix[i, control_samples]
      case_vals <- expr_matrix[i, case_samples]

      tt <- stats::t.test(case_vals, control_vals)
      logfc <- log2(mean(case_vals) / mean(control_vals))

      results_list[[length(results_list) + 1]] <- data.frame(
        feature_id = rownames(expr_matrix)[i],
        logFC = logfc,
        p_value = tt$p.value,
        comparison = paste0(cg, "_vs_", control_group),
        stringsAsFactors = FALSE
      )
    }
  }

  combined <- do.call(rbind, results_list)
  combined$p_adj <- stats::p.adjust(combined$p_value, method = "BH")
  return(combined)
}
