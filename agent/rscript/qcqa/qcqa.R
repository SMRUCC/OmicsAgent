# ==============================================================================
# OmicsFlow：质控 / 质量保证评估
# ==============================================================================
# 质量控制与质量保证相关函数
# ==============================================================================

#' 计算 QC 样本变异
#'
#' @description 计算 QC 样本的Coefficient变异（CV），以评估数据采集的稳定性。QC 样本中
#'   CV 较高的Feature说明分析重复性较差。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param sample_info 含样本元数据的 data.frame。
#' @param qc_group 字符，\code{sample_info[[group_col]]} 中 QC 样本的分组标签。默认："QC"。
#' @param group_col sample_info 中用于分组标签的列名。默认："sample_info"。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{qc_cv}: 各Feature CV（%）的有名数值向量。
#'     \item \code{qc_mean}: 各Feature均值的有名数值向量。
#'     \item \code{qc_sd}: 各Feature标准差的有名数值向量。
#'     \item \code{summary}: 含 QC 统计量的数据框。
#'     \item \code{plot}: 展示 CV 分布的 ggplot 对象。
#'   }
#'
#' @examples
#' \dontrun{
#' qc_result <- qc_variation(expr_matrix, sample_info, qc_group = "QC")
#' print(qc_result$summary)
#' }
#'
#' @export
qc_variation <- function(expr_matrix, sample_info, qc_group = "QC",
                         group_col = "sample_info") {
  # 校验
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # 对齐样本
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]

  # 获取 QC 样本
  qc_samples <- rownames(sample_info)[sample_info[[group_col]] == qc_group]
  if (length(qc_samples) == 0) {
    stop(paste("No QC samples found for group:", qc_group))
  }

  qc_data <- expr_matrix[, qc_samples, drop = FALSE]

  # 计算统计量
  qc_mean <- rowMeans(qc_data, na.rm = TRUE)
  qc_sd <- apply(qc_data, 1, stats::sd, na.rm = TRUE)
  qc_cv <- (qc_sd / abs(qc_mean)) * 100  # CV as percentage

  # 汇总数据框
  summary_df <- data.frame(
    feature_id = rownames(qc_data),
    qc_mean = qc_mean,
    qc_sd = qc_sd,
    qc_cv = qc_cv,
    stringsAsFactors = FALSE
  )

  # 绘图：CV 分布
  cv_df <- data.frame(cv = qc_cv)
  p <- ggplot2::ggplot(cv_df, ggplot2::aes(x = cv)) +
    ggplot2::geom_histogram(bins = 50, fill = "#4a90d9", color = "white") +
    ggplot2::geom_vline(xintercept = 30, color = "#e74c3c", linetype = "dashed",
                        linewidth = 0.8) +
    ggplot2::labs(
      title = "QC Sample Coefficient of Variation",
      x = "CV (%)", y = "Feature Count"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 11),
      axis.title = ggplot2::element_text(size = 12)
    )

  return(list(
    qc_cv = qc_cv,
    qc_mean = qc_mean,
    qc_sd = qc_sd,
    summary = summary_df,
    plot = p
  ))
}


#' 基于 PCA 的质控评估
#'
#' @description 对整个数据集（含 QC 样本）执行 PCA，以可视化方式评估数据质量。
#'   若数据质量良好，QC 样本应在 PCA Score Plot中紧密聚成一簇。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param sample_info 含样本元数据的 data.frame。
#' @param qc_group 字符，QC 分组标签。默认："QC"。
#' @param group_col 用于分组标签的列名。默认："sample_info"。
#' @param color_col 用于颜色分组的列名。默认：group_col。
#' @param scale 逻辑值，是否对Feature进行标准化。默认：TRUE。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{pca_result}: PCA 结果对象。
#'     \item \code{scores}: PC 得分数据框。
#'     \item \code{qc_dispersion}: QC 样本的离散度（到 QC 质心的平均距离）。
#'     \item \code{plot}: 高亮 QC 的 ggplot PCA Score Plot。
#'   }
#'
#' @examples
#' \dontrun{
#' qc_pca <- qc_pca_assessment(expr_matrix, sample_info, qc_group = "QC")
#' print(qc_pca$plot)
#' }
#'
#' @export
qc_pca_assessment <- function(expr_matrix, sample_info, qc_group = "QC",
                              group_col = "sample_info", color_col = NULL,
                              scale = TRUE) {
  # 校验
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]

  # 执行 PCA
  pca_result <- stats::prcomp(t(expr_matrix), scale. = scale, center = TRUE)

  # 提取得分
  scores <- as.data.frame(pca_result$x[, 1:2])
  colnames(scores) <- c("PC1", "PC2")
  scores$sample_id <- rownames(scores)
  scores$group <- sample_info[rownames(scores), group_col]

  # 颜色列
  if (is.null(color_col)) color_col <- group_col
  if (color_col %in% colnames(sample_info)) {
    scores$color_group <- sample_info[rownames(scores), color_col]
  } else {
    scores$color_group <- scores$group
  }

  # QC 离散度
  qc_scores <- scores[scores$group == qc_group, ]
  if (nrow(qc_scores) > 0) {
    qc_centroid <- colMeans(qc_scores[, c("PC1", "PC2")])
    qc_dist <- sqrt(rowSums((qc_scores[, c("PC1", "PC2")] - qc_centroid)^2))
    qc_dispersion <- mean(qc_dist)
  } else {
    qc_dispersion <- NA
  }

  # 解释方差
  var_explained <- pca_result$sdev^2 / sum(pca_result$sdev^2) * 100

  # 颜色
  groups <- unique(scores$color_group)
  colors <- make_group_colors(groups)

  # 绘图
  p <- ggplot2::ggplot(scores, ggplot2::aes(x = PC1, y = PC2)) +
    ggplot2::geom_point(ggplot2::aes(color = color_group, shape = group),
                        size = 3) +
    ggplot2::scale_color_manual(values = colors) +
    ggplot2::labs(
      title = "PCA Score Plot (QC Assessment)",
      x = paste0("PC1 (", round(var_explained[1], 1), "%)"),
      y = paste0("PC2 (", round(var_explained[2], 1), "%)")
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      legend.position = "right"
    ) +
    ggplot2::coord_equal()

  # 若 QC 样本足够，则添加 QC 椭圆
  if (nrow(qc_scores) >= 3) {
    # 计算 QC 的 95% 置信椭圆
    qc_mat <- as.matrix(qc_scores[, c("PC1", "PC2")])
    if (nrow(qc_mat) >= 3) {
      # 使用均值与协方差构造简单椭圆
      centroid <- colMeans(qc_mat)
      cov_mat <- cov(qc_mat)
      eig <- eigen(cov_mat)
      # 95% CI radius
      chi_sq <- stats::qchisq(0.95, 2)
      n_pts <- 100
      angles <- seq(0, 2 * pi, length.out = n_pts)
      ellipse_pts <- data.frame(
        PC1 = centroid[1] + sqrt(chi_sq) * eig$vectors[1, 1] * eig$values[1] * cos(angles) +
              sqrt(chi_sq) * eig$vectors[1, 2] * eig$values[2] * sin(angles),
        PC2 = centroid[2] + sqrt(chi_sq) * eig$vectors[2, 1] * eig$values[1] * cos(angles) +
              sqrt(chi_sq) * eig$vectors[2, 2] * eig$values[2] * sin(angles)
      )
      p <- p + ggplot2::geom_path(data = ellipse_pts,
                                  ggplot2::aes(x = PC1, y = PC2),
                                  color = colors[qc_group], linewidth = 0.8)
    }
  }

  return(list(
    pca_result = pca_result,
    scores = scores,
    qc_dispersion = qc_dispersion,
    var_explained = var_explained,
    plot = p
  ))
}
