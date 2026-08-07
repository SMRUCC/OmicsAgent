# ==============================================================================
# OmicsFlow: 多因素方差分析（Multi-factor ANOVA）
# ==============================================================================
# 用于总体差异分析的多因素方差分析
# ==============================================================================

#' 多因素方差分析
#'
#' @description 对每个Feature执行多因素方差分析，可同时检验多个因素
#'   （如处理、时间、批次）。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param sample_info 含有样本元数据的数据框。
#' @param factors 用作因素的列名字符向量。默认："sample_info"。
#' @param exclude_groups 可选的命名列表，指定每个因素要排除的分组。
#'   例如 \code{list(sample_info = "QC")}。默认：NULL。
#' @param p_adj_method P 值校正方法。默认："BH"。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{results}：含 feature_id、F 统计量、p 值、各因素的 p_adj 的数据框。
#'     \item \code{factor_results}：每个因素的数据框列表。
#'   }
#'
#' @examples
#' \dontrun{
#' # 单因素
#' anova_result <- run_anova(expr_matrix, sample_info, factors = "sample_info")
#'
#' # 多因素
#' anova_result <- run_anova(expr_matrix, sample_info,
#'                           factors = c("sample_info", "condition"))
#' }
#'
#' @export
run_anova <- function(expr_matrix, sample_info, factors = "sample_info",
                      exclude_groups = NULL, p_adj_method = "BH") {
  # 对齐样本
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]
  
  # 排除分组
  if (!is.null(exclude_groups)) {
    for (fac in names(exclude_groups)) {
      if (fac %in% colnames(sample_info)) {
        excl <- exclude_groups[[fac]]
        keep <- !(sample_info[[fac]] %in% excl)
        expr_matrix <- expr_matrix[, keep, drop = FALSE]
        sample_info <- sample_info[keep, , drop = FALSE]
      }
    }
  }
  
  # 确保因素为因子类型
  for (f in factors) {
    if (f %in% colnames(sample_info)) {
      sample_info[[f]] <- factor(sample_info[[f]])
    }
  }
  
  # 构建公式
  formula_str <- paste0("value ~ ", paste(factors, collapse = " * "))
  formula_obj <- as.formula(formula_str)
  
  n_features <- nrow(expr_matrix)
  n_factors <- length(factors)
  
  # 结果存储
  factor_results <- list()
  
  feature_ids <- rownames(expr_matrix)
  if (is.null(feature_ids)) feature_ids <- paste0("feature_", seq_len(n_features))

  for (i in seq_len(n_features)) {
    data_tmp <- data.frame(
      value = as.numeric(expr_matrix[i, ]),
      sample_info,
      stringsAsFactors = FALSE
    )

    # 常量特征会让 aov 秩亏或报错，跳过（对应行保持 NA）
    if (all(is.na(data_tmp$value)) ||
        length(unique(data_tmp$value[!is.na(data_tmp$value)])) < 2) {
      next
    }

    anova_summary <- tryCatch({
      s <- summary(stats::aov(formula_obj, data = data_tmp))[[1]]
      # summary.aov 的行名带有对齐用的尾部空格（如 "variety    "），
      # 直接用 fac %in% rownames(anova_summary) 永远不匹配，
      # 会导致 factor_results 始终为空、下游 combined 为 NULL。
      rownames(s) <- trimws(rownames(s))
      s
    }, error = function(e) NULL)
    if (is.null(anova_summary)) next

    for (j in seq_len(n_factors)) {
      fac <- factors[j]
      if (fac %in% rownames(anova_summary)) {
        if (is.null(factor_results[[fac]])) {
          # 预填 NA 而非 character(n)/numeric(n)。原实现留下的 "" 与 0
          # 会在某特征该因素缺失（秩亏/aov 失败）时残留，随后被
          # p.adjust 当作真实 p = 0 参与 BH 校正，静默污染全部校正结果。
          factor_results[[fac]] <- data.frame(
            feature_id = feature_ids,
            F_stat = rep(NA_real_, n_features),
            p_value = rep(NA_real_, n_features),
            stringsAsFactors = FALSE
          )
        }
        factor_results[[fac]]$F_stat[i] <- anova_summary[fac, "F value"]
        factor_results[[fac]]$p_value[i] <- anova_summary[fac, "Pr(>F)"]
      }
    }
  }

  # 校正 P 值（p.adjust 忽略 NA；significant 显式排除 NA）
  for (fac in names(factor_results)) {
    factor_results[[fac]]$p_adj <- stats::p.adjust(factor_results[[fac]]$p_value,
                                                   method = p_adj_method)
    factor_results[[fac]]$significant <- !is.na(factor_results[[fac]]$p_adj) &
      factor_results[[fac]]$p_adj < 0.05
  }
  
  # 合并结果
  # 若所有因素都未出现在 aov 表中（例如因素为常量列），factor_results 为空，
  # do.call(rbind, list()) 会返回 NULL，需显式构造空结果避免下游报错。
  if (length(factor_results) == 0) {
    warning("No factor produced valid ANOVA terms; returning empty result.")
    combined <- data.frame(
      F_stat = numeric(0), p_value = numeric(0),
      p_adj = numeric(0), significant = logical(0),
      factor = character(0), stringsAsFactors = FALSE
    )
    return(list(results = combined, factor_results = factor_results))
  }
  
  combined <- do.call(rbind, lapply(names(factor_results), function(fac) {
    df <- factor_results[[fac]]
    df$factor <- fac
    return(df)
  }))
  
  # 将 feature_id 设为行名（多个因素可能产生重复，
  # 因此创建唯一行名）
  rownames(combined) <- make.unique(as.character(combined$feature_id))
  combined$feature_id <- NULL
  
  return(list(
    results = combined,
    factor_results = factor_results
  ))
}
