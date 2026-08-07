# ==============================================================================
# OmicsFlow: PCA 分析与可视化
# ==============================================================================
# 主成分分析（含得分图）
# ==============================================================================

#' 执行 PCA 分析
#'
#' @description 对表达矩阵执行主成分分析（PCA）。返回得分、载荷与方差解释率。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param scale 逻辑值，是否对Feature进行标度变换。默认：TRUE。
#' @param center 逻辑值，是否对Feature进行中心化。默认：TRUE。
#' @param ncomp 要计算的组分数量。默认：min(样本数 - 1, 10)。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{pca_result}：prcomp 结果对象。
#'     \item \code{scores}：PC 得分数据框（样本 x 组分）。
#'     \item \code{loadings}：PC Loading数据框（Feature x 组分）。
#'     \item \code{var_explained}：方差解释率（%）的数值向量。
#'     \item \code{ncomp}：计算得到的组分数。
#'   }
#'
#' @examples
#' \dontrun{
#' pca <- run_pca(expr_matrix)
#' print(pca$var_explained[1:3])
#' }
#'
#' @export
run_pca <- function(expr_matrix, scale = TRUE, center = TRUE,
                    ncomp = NULL) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # 转置以进行 PCA（样本作为行）
  data_t <- t(expr_matrix)

  # 移除零方差Feature
  feature_var <- apply(data_t, 2, stats::var, na.rm = TRUE)
  data_t <- data_t[, feature_var > 0, drop = FALSE]

  # 设定组分数
  if (is.null(ncomp)) {
    ncomp <- min(nrow(data_t) - 1, ncol(data_t), 10)
  }

  # 执行 PCA（计算全部组分以获得正确的方差解释率）
  pca_result <- stats::prcomp(data_t, scale. = scale, center = center)

  # 提取结果
  scores <- as.data.frame(pca_result$x[, 1:ncomp, drop = FALSE])
  scores$sample_id <- rownames(scores)
  scores <- scores[, c("sample_id", setdiff(colnames(scores), "sample_id")), drop = FALSE]
  rownames(scores) <- NULL

  loadings <- as.data.frame(pca_result$rotation[, 1:ncomp, drop = FALSE])
  loadings$feature_id <- rownames(loadings)
  loadings <- loadings[, c("feature_id", setdiff(colnames(loadings), "feature_id")), drop = FALSE]
  rownames(loadings) <- NULL

  # 方差解释率：使用总方差（所有 sdev^2 之和）
  var_explained <- (pca_result$sdev^2 / sum(pca_result$sdev^2) * 100)[1:ncomp]

  return(list(
    pca_result = pca_result,
    scores = scores,
    loadings = loadings,
    var_explained = var_explained,
    ncomp = ncomp
  ))
}


#' 绘制 PCA Score Plot
#'
#' @description 使用 ggplot2 创建发表级质量的 PCA Score Plot。
#'
#' @param pca_result 来自 \code{run_pca()} 的结果。
#' @param sample_info 含有样本元数据的数据框。
#' @param color_col 用于颜色分组的列名。默认："sample_info"。
#' @param shape_col 用于形状分组的列名。默认：NULL。
#' @param pc_x 整数，x 轴使用的 PC。默认：1。
#' @param pc_y 整数，y 轴使用的 PC。默认：2。
#' @param show_ellipse 逻辑值，是否绘制置信椭圆。默认：TRUE。
#' @param ellipse_level 数值，椭圆的置信水平。默认：0.95。
#' @param show_labels 逻辑值，是否显示样本标签。默认：FALSE。
#' @param label_col 标签所用的列名。默认："sample_name"。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' pca <- run_pca(expr_matrix)
#' p <- plot_pca_scores(pca, sample_info, color_col = "sample_info")
#' print(p)
#' }
#'
#' @export
plot_pca_scores <- function(pca_result, sample_info,
                            color_col = "sample_info", shape_col = NULL,
                            pc_x = 1, pc_y = 2,
                            show_ellipse = TRUE, ellipse_level = 0.95,
                            show_labels = FALSE, label_col = "sample_name") {
  # 获取得分
  scores <- pca_result$scores
  var_explained <- pca_result$var_explained

  # 对齐样本信息
  common_samples <- intersect(scores$sample_id, rownames(sample_info))
  scores <- scores[scores$sample_id %in% common_samples, ]
  sample_info <- sample_info[scores$sample_id, , drop = FALSE]

  # 准备数据
  pc_cols <- paste0("PC", c(pc_x, pc_y))
  plot_data <- data.frame(
    sample_id = scores$sample_id,
    PCx = scores[[pc_cols[1]]],
    PCy = scores[[pc_cols[2]]]
  )

  # 添加颜色
  if (color_col %in% colnames(sample_info)) {
    plot_data$color <- sample_info[[color_col]]
  } else {
    plot_data$color <- "all"
  }

  # 添加形状
  if (!is.null(shape_col) && shape_col %in% colnames(sample_info)) {
    plot_data$shape <- sample_info[[shape_col]]
  } else {
    plot_data$shape <- plot_data$color
  }

  # 添加标签
  if (show_labels && label_col %in% colnames(sample_info)) {
    plot_data$label <- sample_info[[label_col]]
  } else {
    plot_data$label <- plot_data$sample_id
  }

  # 颜色
  groups <- unique(plot_data$color)
  colors <- make_group_colors(groups)

  # 形状
  n_shapes <- length(unique(plot_data$shape))
  shapes <- 0:(n_shapes - 1) %% 25 + 1

  # 构建图形
  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = PCx, y = PCy)) +
    ggplot2::geom_point(ggplot2::aes(color = color, shape = shape),
                        size = 3, alpha = 0.85) +
    ggplot2::scale_color_manual(values = colors, name = color_col) +
    ggplot2::scale_shape_manual(values = shapes, name = ifelse(is.null(shape_col), color_col, shape_col)) +
    ggplot2::labs(
      title = "PCA Score Plot",
      x = paste0("PC", pc_x, " (", round(var_explained[pc_x], 1), "%)"),
      y = paste0("PC", pc_y, " (", round(var_explained[pc_y], 1), "%)")
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 11),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right",
      legend.text = ggplot2::element_text(size = 10),
      legend.title = ggplot2::element_text(size = 11)
    ) +
    ggplot2::coord_equal()

  # 添加椭圆
  if (show_ellipse) {
    for (g in groups) {
      g_data <- plot_data[plot_data$color == g, , drop = FALSE]
      if (nrow(g_data) >= 3) {
        # 使用与 stat_ellipse 等价的方式计算椭圆
        # 采用手动计算以获得更好的控制
        center <- c(mean(g_data$PCx), mean(g_data$PCy))
        cov_mat <- stats::cov(g_data[, c("PCx", "PCy")])

        # 若为奇异矩阵则跳过
        if (det(cov_mat) > 1e-10) {
          chi_sq <- stats::qchisq(ellipse_level, 2)
          eig <- eigen(cov_mat)
          n_pts <- 100
          angles <- seq(0, 2 * pi, length.out = n_pts)
          ellipse_df <- data.frame(
            PCx = center[1] + sqrt(chi_sq) * eig$vectors[1, 1] * sqrt(eig$values[1]) * cos(angles) +
                   sqrt(chi_sq) * eig$vectors[1, 2] * sqrt(eig$values[2]) * sin(angles),
            PCy = center[2] + sqrt(chi_sq) * eig$vectors[2, 1] * sqrt(eig$values[1]) * cos(angles) +
                   sqrt(chi_sq) * eig$vectors[2, 2] * sqrt(eig$values[2]) * sin(angles)
          )
          p <- p + ggplot2::geom_path(data = ellipse_df,
                                      ggplot2::aes(x = PCx, y = PCy),
                                      color = colors[g], linewidth = 0.6,
                                      linetype = "dashed", inherit.aes = FALSE)
        }
      }
    }
  }

  # 添加标签
  if (show_labels) {
    p <- p + ggrepel::geom_text_repel(
      ggplot2::aes(label = label), size = 2.5, max.overlaps = 20
    )
  }

  return(p)
}


#' 绘制 PCA Loading Plot
#'
#' @description 创建展示Feature贡献的 PCA Loading Plot。
#'
#' @param pca_result 来自 \code{run_pca()} 的结果。
#' @param pc_x 整数，x 轴使用的 PC。默认：1。
#' @param pc_y 整数，y 轴使用的 PC。默认：2。
#' @param top_n 整数，标注的前 N 个Feature数量。默认：10。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_pca_loadings(pca_result, top_n = 15)
#' }
#'
#' @export
plot_pca_loadings <- function(pca_result, pc_x = 1, pc_y = 2, top_n = 10) {
  loadings <- pca_result$loadings
  pc_cols <- paste0("PC", c(pc_x, pc_y))

  plot_data <- data.frame(
    feature_id = loadings$feature_id,
    loading_x = loadings[[pc_cols[1]]],
    loading_y = loadings[[pc_cols[2]]]
  )

  # 计算到原点的距离
  plot_data$dist <- sqrt(plot_data$loading_x^2 + plot_data$loading_y^2)

  # 选取前 N 个Feature
  top_features <- plot_data[order(plot_data$dist, decreasing = TRUE), ][1:min(top_n, nrow(plot_data)), ]

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = loading_x, y = loading_y)) +
    ggplot2::geom_point(size = 1.5, alpha = 0.5, color = "#4a90d9") +
    ggrepel::geom_text_repel(
      data = top_features,
      ggplot2::aes(label = feature_id), size = 2.5, max.overlaps = 20
    ) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
    ggplot2::geom_vline(xintercept = 0, linetype = "dotted", color = "grey50") +
    ggplot2::labs(
      title = "PCA Loading Plot",
      x = paste0("PC", pc_x, " Loading"),
      y = paste0("PC", pc_y, " Loading")
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 11),
      axis.title = ggplot2::element_text(size = 12)
    )

  return(p)
}
