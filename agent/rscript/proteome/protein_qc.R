# ==============================================================================
# OmicsFlow: Protein Quality Control Analysis
# ==============================================================================
# 蛋白质组学数据质量控制：覆盖率、变异系数、缺失率、动态范围
# 肽段统计、样本相关性、PCA 异常值检测
# ==============================================================================

#' 蛋白质组学质量控制报告
#'
#' @description 对蛋白质组学表达矩阵进行全面的质控分析，包括：
#'   1. 蛋白鉴定数量和样本覆盖度
#'   2. 缺失率统计（样本和蛋白两个维度）
#'   3. 变异系数（CV）分布
#'   4. 动态范围分析（丰度分布跨度）
#'   5. 样本相关性矩阵
#'   6. PCA 异常值检测
#'
#' @param expr_matrix 数值矩阵（features × samples），行为蛋白质，列为样本。
#' @param sample_info 样本元数据 data.frame。
#' @param group_col 分组列名。默认 "sample_info"。
#' @param cv_threshold CV 阈值，百分比。默认 20。
#' @param missing_rate_threshold 缺失率阈值，百分比。默认 30。
#' @param log_transform 是否对数据做 log2 变换。默认 FALSE（假设已转换）。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{sample_summary}: 样本级别质控指标。
#'     \item \code{feature_summary}: 蛋白级别质控指标。
#'     \item \code{cv_distribution}: CV 分布数据。
#'     \item \item \code{missing_rate}: 缺失率数据。
#'     \item \code{correlation_matrix}: 样本相关性矩阵。
#'     \item \code{pca_result}: PCA 结果（用于异常值检测）。
#'     \item \code{flags}: 标记有问题的样本/蛋白。
#'   }
#'
#' @examples
#' \dontrun{
#' qc <- run_protein_qc(expr_matrix, sample_info, group_col = "sample_info")
#' }
#'
#' @export
run_protein_qc <- function(expr_matrix, sample_info,
                          group_col = "sample_info",
                          cv_threshold = 20,
                          missing_rate_threshold = 30,
                          log_transform = FALSE) {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)

  if (isTRUE(log_transform)) {
    expr_matrix <- log2(expr_matrix + 1)
  }

  common <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common, drop = FALSE]
  sample_info <- sample_info[common, , drop = FALSE]
  groups <- sample_info[[group_col]]

  n_features <- nrow(expr_matrix)
  n_samples <- ncol(expr_matrix)
  feature_names <- rownames(expr_matrix)
  sample_names <- colnames(expr_matrix)

  # ---- 样本级质控 ----
  sample_summary <- data.frame(
    sample = sample_names,
    group = groups,
    n_identified = colSums(!is.na(expr_matrix) & expr_matrix > 0),
    n_missing = colSums(is.na(expr_matrix) | expr_matrix == 0),
    missing_rate = round(colMeans(is.na(expr_matrix) | expr_matrix == 0) * 100, 2),
    mean_abundance = colMeans(expr_matrix, na.rm = TRUE),
    median_abundance = apply(expr_matrix, 2, stats::median, na.rm = TRUE),
    stringsAsFactors = FALSE
  )

  # 样本内 CV
  sample_cv <- apply(expr_matrix, 2, function(x) {
    x <- x[!is.na(x) & x > 0]
    if (length(x) < 2) return(NA)
    stats::sd(x) / mean(x) * 100
  })
  sample_summary$cv <- round(sample_cv, 2)
  rownames(sample_summary) <- NULL

  # ---- 蛋白级质控 ----
  feature_summary <- data.frame(
    protein = feature_names,
    n_detected = rowSums(!is.na(expr_matrix) & expr_matrix > 0),
    missing_rate = round(rowMeans(is.na(expr_matrix) | expr_matrix == 0) * 100, 2),
    mean_abundance = rowMeans(expr_matrix, na.rm = TRUE),
    stringsAsFactors = FALSE
  )

  # 分组内 CV
  feature_cv <- sapply(seq_len(n_features), function(i) {
    v <- expr_matrix[i, , drop = FALSE]
    cv_by_group <- sapply(unique(groups), function(g) {
      vals <- v[groups == g]
      vals <- vals[!is.na(vals) & vals > 0]
      if (length(vals) < 2) return(NA)
      stats::sd(vals) / mean(vals) * 100
    })
    mean(cv_by_group, na.rm = TRUE)
  })
  feature_summary$group_cv <- round(feature_cv, 2)
  rownames(feature_summary) <- NULL

  # ---- CV 分布 ----
  cv_dist <- feature_summary$group_cv[!is.na(feature_summary$group_cv)]

  # ---- 缺失率分布 ----
  missing_rates <- feature_summary$missing_rate

  # ---- 样本相关性 ----
  cor_mat <- stats::cor(expr_matrix, method = "pearson",
                        use = "pairwise.complete.obs")
  diag(cor_mat) <- NA  # 对角线设为 NA，便于可视化

  # ---- PCA 异常值检测 ----
  # 用零填充 NA
  mat_imputed <- expr_matrix
  mat_imputed[is.na(mat_imputed)] <- min(expr_matrix, na.rm = TRUE) / 2

  pca_res <- stats::prcomp(t(mat_imputed), scale. = TRUE, center = TRUE)
  pca_df <- data.frame(
    sample = sample_names,
    PC1 = pca_res$x[, 1],
    PC2 = pca_res$x[, 2],
    group = groups,
    stringsAsFactors = FALSE
  )
  # Hotelling T2
  eigenvalues <- pca_res$sdev^2
  n_pc <- min(5, length(eigenvalues))
  t2 <- rowSums(scale(pca_res$x[, 1:n_pc, drop = FALSE])^2)
  pca_df$T2 <- t2
  pca_df$outlier <- t2 > stats::qchisq(0.95, n_pc)
  rownames(pca_df) <- NULL

  # ---- 标记问题样本 ----
  flagged_samples <- sample_summary[
    sample_summary$missing_rate > missing_rate_threshold |
    sample_summary$cv > cv_threshold, , drop = FALSE]

  flagged_features <- feature_summary[
    feature_summary$missing_rate > missing_rate_threshold, , drop = FALSE]

  cat(sprintf("[protein-qc] 样本: %d, 蛋白: %d\n", n_samples, n_features))
  cat(sprintf("[protein-qc] 问题样本: %d (缺失率 > %d%% 或 CV > %d%%)\n",
              nrow(flagged_samples), missing_rate_threshold, cv_threshold))
  cat(sprintf("[protein-qc] 问题蛋白: %d (缺失率 > %d%%)\n",
              nrow(flagged_features), missing_rate_threshold))
  cat(sprintf("[protein-qc] PCA 异常值: %d\n", sum(pca_df$outlier)))

  return(list(
    sample_summary = sample_summary,
    feature_summary = feature_summary,
    cv_distribution = cv_dist,
    missing_rates = missing_rates,
    correlation_matrix = cor_mat,
    pca_result = pca_df,
    flagged_samples = flagged_samples,
    flagged_features = flagged_features,
    params = list(
      n_features = n_features,
      n_samples = n_samples,
      cv_threshold = cv_threshold,
      missing_rate_threshold = missing_rate_threshold,
      group_levels = unique(groups)
    )
  ))
}


#' 绘制蛋白质组质控概览图
#'
#' @description 生成一个综合质控图，包含：
#'   1. 蛋白鉴定数量柱状图
#'   2. 缺失率分布图
#'   3. CV 分布图
#'   4. 动态范围图
#'
#' @param qc_result \code{run_protein_qc()} 的返回结果。
#'
#' @return ggplot 对象列表。
#'
#' @examples
#' \dontrun{
#' plots <- plot_protein_qc(qc_result)
#' }
#'
#' @export
plot_protein_qc <- function(qc_result) {
  plots <- list()

  # 1. 蛋白鉴定数量
  p1 <- ggplot2::ggplot(qc_result$sample_summary,
                        ggplot2::aes(x = sample, y = n_identified, fill = group)) +
    ggplot2::geom_bar(stat = "identity") +
    ggplot2::scale_fill_manual(values = make_group_colors(
      unique(qc_result$sample_summary$group))) +
    ggplot2::labs(title = "Protein Identification Count",
                  x = NULL, y = "Number of Proteins") +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold", hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 8),
      legend.position = "right"
    )
  plots$identification <- p1

  # 2. 缺失率
  p2 <- ggplot2::ggplot(qc_result$sample_summary,
                        ggplot2::aes(x = sample, y = missing_rate, fill = group)) +
    ggplot2::geom_bar(stat = "identity") +
    ggplot2::geom_hline(yintercept = qc_result$params$missing_rate_threshold,
                        linetype = "dashed", color = "#e74c3c") +
    ggplot2::scale_fill_manual(values = make_group_colors(
      unique(qc_result$sample_summary$group))) +
    ggplot2::labs(title = "Missing Rate (%)",
                  x = NULL, y = "Missing Rate (%)") +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold", hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 8),
      legend.position = "right"
    )
  plots$missing_rate <- p2

  # 3. CV 分布
  cv_df <- data.frame(cv = qc_result$cv_distribution)
  p3 <- ggplot2::ggplot(cv_df, ggplot2::aes(x = cv)) +
    ggplot2::geom_histogram(bins = 50, fill = "#4a90d9", color = "white") +
    ggplot2::geom_vline(xintercept = qc_result$params$cv_threshold,
                        linetype = "dashed", color = "#e74c3c") +
    ggplot2::labs(title = "CV Distribution (within group)",
                  x = "Coefficient of Variation (%)",
                  y = "Count") +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold", hjust = 0.5)
    )
  plots$cv_distribution <- p3

  # 4. 样本相关性热图
  cor_mat <- qc_result$correlation_matrix
  cor_df <- as.data.frame(as.table(cor_mat))
  colnames(cor_df) <- c("Sample1", "Sample2", "Correlation")

  p4 <- ggplot2::ggplot(cor_df, ggplot2::aes(x = Sample1, y = Sample2,
                                               fill = Correlation)) +
    ggplot2::geom_tile() +
    ggplot2::scale_fill_gradient2(low = "#2c7bb6", mid = "white",
                                   high = "#d7191c", midpoint = 0.5,
                                   limits = c(0, 1)) +
    ggplot2::labs(title = "Sample Correlation",
                  x = NULL, y = NULL) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold", hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 90, hjust = 1, size = 6),
      axis.text.y = ggplot2::element_text(size = 6),
      legend.position = "right"
    )
  plots$correlation <- p4

  # 5. PCA 异常值检测
  pca_df <- qc_result$pca_result
  group_colors <- make_group_colors(unique(pca_df$group))

  p5 <- ggplot2::ggplot(pca_df, ggplot2::aes(x = PC1, y = PC2,
                                              color = group, shape = outlier)) +
    ggplot2::geom_point(size = 3, alpha = 0.8) +
    ggplot2::scale_color_manual(values = group_colors) +
    ggplot2::scale_shape_manual(values = c("FALSE" = 16, "TRUE" = 4)) +
    ggplot2::labs(title = "PCA Outlier Detection",
                  x = "PC1", y = "PC2") +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold", hjust = 0.5),
      legend.position = "right"
    )
  plots$pca_outlier <- p5

  return(plots)
}
