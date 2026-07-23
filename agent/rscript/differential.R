#' @title F-test for Overall Differential Analysis
#'
#' @description
#' 执行F检验（方差分析）对每个feature做整体差异分析。F检验通过比较
#' 组间方差与组内方差评估各组均值是否存在显著差异。该函数对每个feature
#' 独立执行单因素方差分析，返回F值、P值和调整后的P值。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param sample_meta 数据框，样本元数据
#' @param p_adjust_method 字符串，P值校正方法，默认"BH"
#'
#' @return 返回一个数据框，包含：
#' \itemize{
#'   \item Feature: feature ID
#'   \item F_statistic: F统计量
#'   \item pvalue: 原始P值
#'   \item pvalue_adj: 校正后P值
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' meta <- load_sample_metadata("meta.csv")
#' ftest_result <- perform_ftest(expr, meta)
#' head(ftest_result)
#' }
#'
#' @export
perform_ftest <- function(expr_matrix, sample_meta,
                          p_adjust_method = "BH") {
  groups <- factor(sample_meta$sample_info[match(colnames(expr_matrix),
                                                  sample_meta$ID)])

  if (nlevels(groups) < 2) {
    stop("At least 2 groups are required for F-test.")
  }

  f_results <- apply(expr_matrix, 1, function(row) {
    df <- data.frame(value = as.numeric(row), group = groups)
    df <- df[complete.cases(df), , drop = FALSE]
    if (nrow(df) < 3 || length(unique(df$group)) < 2) {
      return(c(F = NA, p = NA))
    }
    fit <- stats::aov(value ~ group, data = df)
    f_summary <- summary(fit)[[1]]
    c(f_summary$`F value`[1], f_summary$`Pr(>F)`[1])
  })

  result <- data.frame(
    Feature = rownames(expr_matrix),
    F_statistic = f_results[1, ],
    pvalue = f_results[2, ],
    stringsAsFactors = FALSE
  )
  result$pvalue_adj <- stats::p.adjust(result$pvalue, method = p_adjust_method)

  message("F-test completed for ", nrow(result), " features. ",
          sum(result$pvalue_adj < 0.05, na.rm = TRUE),
          " significant (FDR < 0.05).")
  return(result)
}


#' @title Multi-factor ANOVA for Overall Differential Analysis
#'
#' @description
#' 执行多因素方差分析（multi-factor ANOVA），评估多个因素（如处理、
#' 时间、批次等）对feature表达的影响。该函数对每个feature独立执行
#' 多因素ANOVA，返回每个因素及其交互项的F值和P值。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param sample_meta 数据框，样本元数据，包含多个因素列
#' @param factors 字符向量，因素列名
#' @param interactions 逻辑值，是否包含交互项，默认TRUE
#' @param p_adjust_method 字符串，P值校正方法，默认"BH"
#'
#' @return 返回一个数据框，包含每个feature的各因素F值、P值和校正P值
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' meta <- load_sample_metadata("meta.csv")
#'
#' # 多因素ANOVA：处理 + 时间 + 处理:时间交互
#' anova_result <- perform_multifactor_anova(
#'   expr, meta, factors = c("treatment", "time"),
#'   interactions = TRUE
#' )
#' }
#'
#' @export
perform_multifactor_anova <- function(expr_matrix, sample_meta, factors,
                                       interactions = TRUE,
                                       p_adjust_method = "BH") {
  if (!all(factors %in% colnames(sample_meta))) {
    stop("Some factors not found in sample_meta: ",
         paste(setdiff(factors, colnames(sample_meta)), collapse = ", "))
  }

  groups <- lapply(factors, function(f) {
    factor(sample_meta[[f]][match(colnames(expr_matrix), sample_meta$ID)])
  })
  names(groups) <- factors

  formula_str <- paste("value ~", paste(factors, collapse = " * "))
  if (!interactions) {
    formula_str <- paste("value ~", paste(factors, collapse = " + "))
  }
  formula_obj <- stats::as.formula(formula_str)

  results_list <- lapply(rownames(expr_matrix), function(feat) {
    df <- data.frame(value = as.numeric(expr_matrix[feat, ]))
    for (f in factors) df[[f]] <- groups[[f]]
    df <- df[complete.cases(df), , drop = FALSE]
    if (nrow(df) < length(factors) + 2) return(NULL)

    fit <- stats::aov(formula_obj, data = df)
    aov_summary <- summary(fit)[[1]]

    data.frame(
      Feature = feat,
      Term = rownames(aov_summary),
      F_statistic = aov_summary$`F value`,
      pvalue = aov_summary$`Pr(>F)`,
      stringsAsFactors = FALSE
    )
  })

  results_df <- do.call(rbind, results_list[!sapply(results_list, is.null)])

  results_df$pvalue_adj <- stats::p.adjust(results_df$pvalue,
                                            method = p_adjust_method)

  message("Multi-factor ANOVA completed for ", nrow(expr_matrix),
          " features and ", length(factors), " factors.")
  return(results_df)
}


#' @title Limma Differential Expression Analysis
#'
#' @description
#' 使用limma包执行差异表达分析。limma基于线性模型和经验贝叶斯方法，
#' 在小样本量下提供稳定的方差估计。该函数支持多种差异筛选策略：
#'
#' 策略1（pvalue_logFC）：按pvalue + logFC差异，即同时满足P值和logFC阈值
#' 策略2（pvalue_vip）：按pvalue + VIP差异，即同时满足P值和VIP阈值
#' 策略3（pvalue_topn）：按pvalue筛选显著性，然后按logFC绝对值降序排序后取top N
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param sample_meta 数据框，样本元数据
#' @param design_matrix 矩阵，设计矩阵（可选，默认自动构建）
#' @param contrast 字符串或矩阵，比较组合，如"GroupB-GroupA"
#' @param strategy 字符串，差异筛选策略，"pvalue_logFC"、"pvalue_vip"或"pvalue_topn"
#' @param pvalue_threshold 数值，P值阈值，默认0.05
#' @param logfc_threshold 数值，logFC阈值，默认1
#' @param vip_threshold 数值，VIP阈值，默认1
#' @param vip_values 数值向量，VIP值（命名向量，名为feature ID），仅在pvalue_vip策略下使用，默认NULL
#' @param top_n 整数，top N feature数，默认50
#' @param p_adjust_method 字符串，P值校正方法，默认"BH"
#'
#' @return 返回一个数据框，包含：
#' \itemize{
#'   \item Feature: feature ID
#'   \item logFC: log2 fold change
#'   \item pvalue: 原始P值
#'   \item pvalue_adj: 校正后P值
#'   \item significant: 是否为差异feature（逻辑值）
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' meta <- load_sample_metadata("meta.csv")
#'
#' # 策略1：pvalue + logFC
#' dea_result <- perform_limma(expr, meta, strategy = "pvalue_logFC",
#'                              pvalue_threshold = 0.05,
#'                              logfc_threshold = 1)
#'
#' # 策略2：pvalue + VIP（需要先做PLS-DA）
#' plsda_result <- perform_plsda(expr, meta)
#' dea_result <- perform_limma(expr, meta, strategy = "pvalue_vip",
#'                              pvalue_threshold = 0.05,
#'                              vip_threshold = 1)
#'
#' # 策略3：pvalue + top N
#' dea_result <- perform_limma(expr, meta, strategy = "pvalue_topn",
#'                              pvalue_threshold = 0.05, top_n = 50)
#' }
#'
#' @export
perform_limma <- function(expr_matrix, sample_meta, design_matrix = NULL,
                         contrast = NULL, strategy = "pvalue_logFC",
                         pvalue_threshold = 0.05, logfc_threshold = 1,
                         vip_threshold = 1, vip_values = NULL, top_n = 50,
                         p_adjust_method = "BH") {
  if (!requireNamespace("limma", quietly = TRUE)) {
    stop("Package 'limma' is required. Please install it: ",
         "BiocManager::install('limma')")
  }

  groups <- factor(sample_meta$sample_info[match(colnames(expr_matrix),
                                                  sample_meta$ID)])

  if (is.null(design_matrix)) {
    design_matrix <- model.matrix(~ 0 + groups)
    colnames(design_matrix) <- levels(groups)
  }

  if (is.null(contrast)) {
    if (nlevels(groups) == 2) {
      contrast <- paste(levels(groups)[2], "-", levels(groups)[1])
    } else {
      stop("contrast must be specified when there are more than 2 groups.")
    }
  }

  fit <- limma::lmFit(expr_matrix, design_matrix)

  if (is.character(contrast)) {
    contrast_matrix <- limma::makeContrasts(contrasts = contrast,
                                             levels = design_matrix)
    fit2 <- limma::eBayes(limma::contrasts.fit(fit, contrast_matrix))
  } else {
    fit2 <- limma::eBayes(limma::contrasts.fit(fit, contrast))
  }

  toptable <- limma::topTable(fit2, number = Inf, adjust.method = p_adjust_method,
                              sort.by = "none")

  result <- data.frame(
    Feature = rownames(toptable),
    logFC = toptable$logFC,
    pvalue = toptable$P.Value,
    pvalue_adj = toptable$adj.P.Val,
    stringsAsFactors = FALSE
  )

  # Apply strategy
  if (strategy == "pvalue_logFC") {
    result$significant <- result$pvalue_adj < pvalue_threshold &
      abs(result$logFC) >= logfc_threshold
  } else if (strategy == "pvalue_vip") {
    if (is.null(vip_values)) {
      warning("VIP values not provided. Falling back to pvalue_logFC strategy.")
      result$significant <- result$pvalue_adj < pvalue_threshold &
        abs(result$logFC) >= logfc_threshold
    } else {
      result$VIP <- vip_values[result$Feature]
      result$significant <- result$pvalue_adj < pvalue_threshold &
        result$VIP >= vip_threshold
    }
  } else if (strategy == "pvalue_topn") {
    sig_idx <- which(result$pvalue_adj < pvalue_threshold)
    ordered_idx <- sig_idx[order(-abs(result$logFC[sig_idx]))]
    top_idx <- head(ordered_idx, top_n)
    result$significant <- seq_len(nrow(result)) %in% top_idx
  } else {
    stop("Unknown strategy: ", strategy)
  }

  message("Limma DE analysis (", strategy, "): ",
          sum(result$significant, na.rm = TRUE), " significant features.")
  return(result)
}


#' @title Compute Log2 Fold Change Between Groups
#'
#' @description
#' 计算两组之间每个feature的log2 fold change。该函数计算两组均值的
#' log2比值，正值表示第二组上调，负值表示第二组下调。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param sample_meta 数据框，样本元数据
#' @param group1 字符串，第一组标签
#' @param group2 字符串，第二组标签
#' @param pseudo_count 数值，伪计数，默认1
#'
#' @return 返回一个数值向量，名为feature ID，值为log2FC
#'
#' @examples
#' \dontrun{
#' logfc <- compute_logfc(expr, meta, group1 = "Control", group2 = "Treatment")
#' }
#'
#' @export
compute_logfc <- function(expr_matrix, sample_meta, group1, group2,
                          pseudo_count = 1) {
  samples1 <- sample_meta$ID[sample_meta$sample_info == group1]
  samples2 <- sample_meta$ID[sample_meta$sample_info == group2]

  samples1 <- intersect(samples1, colnames(expr_matrix))
  samples2 <- intersect(samples2, colnames(expr_matrix))

  if (length(samples1) == 0 || length(samples2) == 0) {
    stop("No samples found for one or both groups.")
  }

  mean1 <- rowMeans(expr_matrix[, samples1, drop = FALSE], na.rm = TRUE)
  mean2 <- rowMeans(expr_matrix[, samples2, drop = FALSE], na.rm = TRUE)

  logfc <- log2(mean2 + pseudo_count) - log2(mean1 + pseudo_count)
  names(logfc) <- rownames(expr_matrix)

  message("Log2FC computed: ", group2, " vs ", group1)
  return(logfc)
}
