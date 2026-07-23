# ============================================================
# Required packages
# ============================================================
library(stats)
library(ggplot2)
library(grDevices)

#' @title Compute QC Group Variability
#'
#' @description
#' 计算QC分组的样本变异度，用于评估仪器稳定性和数据质量。
#' QC样本通常是混合样本或标准品，在不同时间点重复进样。
#' 该函数计算每个feature在QC样本中的变异系数（CV），
#' 并返回整体QC变异度统计。
#'
#' 变异系数CV = 标准差 / 均值 × 100%
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param sample_meta 数据框，样本元数据
#' @param qc_label 字符串，QC样本在sample_info列中的标签，默认"QC"
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item feature_cv: 每个feature在QC样本中的CV值
#'   \item median_cv: 中位CV值
#'   \item mean_cv: 平均CV值
#'   \item cv_distribution: CV分布的分位数
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' meta <- load_sample_metadata("meta.csv")
#'
#' qc_stats <- compute_qc_variability(expr, meta, qc_label = "QC")
#' print(qc_stats$median_cv)
#' }
#'
#' @export
compute_qc_variability <- function(expr_matrix, sample_meta, qc_label = "QC") {
  qc_samples <- sample_meta$ID[sample_meta$sample_info == qc_label]
  qc_samples <- intersect(qc_samples, colnames(expr_matrix))

  if (length(qc_samples) < 2) {
    stop("At least 2 QC samples are required for variability computation.")
  }

  qc_data <- expr_matrix[, qc_samples, drop = FALSE]

  feature_means <- rowMeans(qc_data, na.rm = TRUE)
  feature_sds <- apply(qc_data, 1, sd, na.rm = TRUE)

  feature_cv <- ifelse(feature_means != 0,
                       feature_sds / abs(feature_means) * 100,
                       NA)

  cv_distribution <- stats::quantile(feature_cv, na.rm = TRUE,
                                      probs = c(0, 0.25, 0.5, 0.75, 1))

  result <- list(
    feature_cv = feature_cv,
    median_cv = stats::median(feature_cv, na.rm = TRUE),
    mean_cv = mean(feature_cv, na.rm = TRUE),
    cv_distribution = cv_distribution,
    qc_samples = qc_samples
  )

  message("QC variability: median CV = ", round(result$median_cv, 2),
          "%, mean CV = ", round(result$mean_cv, 2), "%")

  return(result)
}


#' @title QCQA Plot: CV Distribution
#'
#' @description
#' 绘制QC样本的CV分布图，用于评估数据质量。该图显示每个feature
#' 在QC样本中的变异系数分布，通常以直方图或密度图形式展示。
#' CV值越低表示仪器稳定性越好。一般要求QC样本的中位CV < 30%。
#'
#' @param qc_stats 列表，由compute_qc_variability函数返回
#' @param output_dir 字符串，输出目录路径
#' @param cv_threshold 数值，CV阈值线，默认30
#' @param width 数值，图片宽度（英寸），默认8
#' @param height 数值，图片高度（英寸），默认6
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' qc_stats <- compute_qc_variability(expr, meta, qc_label = "QC")
#' plot_qc_cv_distribution(qc_stats, output_dir = "./figures")
#' }
#'
#' @export
plot_qc_cv_distribution <- function(qc_stats, output_dir = ".",
                                     cv_threshold = 30,
                                     width = 8, height = 6) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  cv_data <- data.frame(CV = qc_stats$feature_cv)
  cv_data <- cv_data[!is.na(cv_data$CV) & is.finite(cv_data$CV), , drop = FALSE]

  p <- ggplot2::ggplot(cv_data, ggplot2::aes(x = CV)) +
    ggplot2::geom_histogram(ggplot2::aes(y = ggplot2::after_stat(density)),
                             bins = 50, fill = "steelblue",
                             color = "white", alpha = 0.7) +
    ggplot2::geom_density(color = "darkblue", linewidth = 1) +
    ggplot2::geom_vline(xintercept = cv_threshold, color = "red",
                         linetype = "dashed", linewidth = 1) +
    ggplot2::annotate("text", x = cv_threshold, y = Inf,
                       vjust = 2, hjust = -0.1,
                       label = paste0("Threshold: ", cv_threshold, "%"),
                       color = "red") +
    ggplot2::labs(
      title = "QC Sample Coefficient of Variation Distribution",
      x = "Coefficient of Variation (%)",
      y = "Density"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold"),
      axis.title = ggplot2::element_text(size = 12),
      axis.text = ggplot2::element_text(size = 10)
    )

  pdf_file <- file.path(output_dir, "QC_CV_distribution.pdf")
  png_file <- file.path(output_dir, "QC_CV_distribution.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300,
                 res = 300)
  print(p)
  grDevices::dev.off()

  message("QC CV distribution plot saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}


#' @title QCQA: PCA-based Unsupervised Evaluation
#'
#' @description
#' 使用PCA无监督分析评估组内差异与组间差异的显著性。该函数对表达矩阵
#' 做PCA分析，并计算每个分组的组内离散度（基于到组内中心的欧氏距离）
#' 和组间离散度（基于组间中心到全局中心的距离）。通过比较组内与组间
#' 离散度评估分组是否合理。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param sample_meta 数据框，样本元数据
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item pca_result: PCA结果对象
#'   \item scores: PCA得分矩阵
#'   \item within_group_dispersion: 各组组内离散度
#'   \item between_group_dispersion: 组间离散度
#'   \item ratio: 组间/组内离散度比
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' meta <- load_sample_metadata("meta.csv")
#'
#' qcqa_result <- qcqa_pca_evaluation(expr, meta)
#' print(qcqa_result$ratio)
#' }
#'
#' @export
qcqa_pca_evaluation <- function(expr_matrix, sample_meta) {
  # Transpose: samples as rows for PCA
  pca_data <- t(expr_matrix)
  pca_data[is.na(pca_data)] <- 0

  pca_result <- stats::prcomp(pca_data, scale. = TRUE, center = TRUE)

  scores <- pca_result$x[, 1:2]
  groups <- sample_meta$sample_info[match(rownames(scores), sample_meta$ID)]

  global_center <- colMeans(scores)

  group_centers <- tapply(1:nrow(scores), groups, function(idx) {
    colMeans(scores[idx, , drop = FALSE])
  })
  group_centers <- do.call(rbind, group_centers)

  between_disp <- mean(sqrt(rowSums((group_centers - matrix(global_center,
                                                            nrow = nrow(group_centers),
                                                            ncol = ncol(group_centers),
                                                            byrow = TRUE))^2)))

  within_disp <- tapply(1:nrow(scores), groups, function(idx) {
    if (length(idx) < 2) return(NA)
    group_center <- colMeans(scores[idx, , drop = FALSE])
    mean(sqrt(rowSums((scores[idx, , drop = FALSE] -
                         matrix(group_center, nrow = length(idx),
                                ncol = ncol(scores), byrow = TRUE))^2)))
  })

  ratio <- between_disp / mean(within_disp, na.rm = TRUE)

  result <- list(
    pca_result = pca_result,
    scores = scores,
    within_group_dispersion = within_disp,
    between_group_dispersion = between_disp,
    ratio = ratio
  )

  message("QCQA PCA evaluation: between/within ratio = ", round(ratio, 3))
  message("Higher ratio (>1) suggests good group separation.")
  return(result)
}
