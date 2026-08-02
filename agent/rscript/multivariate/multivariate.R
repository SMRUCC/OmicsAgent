# ============================================================
# Required packages
# ============================================================
library(stats)
library(ggplot2)
library(grDevices)
library(ggrepel)
library(mixOmics)
library(ropls)

#' @title Perform PCA Analysis
#'
#' @description
#' 对表达矩阵执行主成分分析（PCA）。PCA是一种无监督降维方法，
#' 通过线性变换将原始高维数据投影到低维空间，保留数据中最大方差方向。
#' 该函数对样本做PCA分析，返回PCA结果对象和得分矩阵。
#'
#' @param expr_matrix 数值矩阵，表达矩阵（行：feature，列：样本）
#' @param scale 逻辑值，是否对feature做标准化，默认TRUE
#' @param center 逻辑值，是否中心化，默认TRUE
#' @param ncomp 整数，保留的主成分数，默认5
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item pca: prcomp结果对象
#'   \item scores: 得分矩阵（样本×主成分）
#'   \item loadings: 载荷矩阵（feature×主成分）
#'   \item variance_explained: 各主成分解释的方差比例
#'   \item cumulative_variance: 累计方差比例
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' pca_result <- perform_pca(expr, scale = TRUE)
#' print(pca_result$variance_explained[1:3])
#' }
#'
#' @export
perform_pca <- function(expr_matrix, scale = TRUE, center = TRUE, ncomp = 5) {
  pca_data <- t(expr_matrix)
  pca_data[is.na(pca_data)] <- 0

  pca_result <- stats::prcomp(pca_data, scale. = scale, center = center)

  variance_explained <- (pca_result$sdev)^2 / sum((pca_result$sdev)^2)
  ncomp <- min(ncomp, length(pca_result$sdev))

  result <- list(
    pca = pca_result,
    scores = pca_result$x[, 1:ncomp, drop = FALSE],
    loadings = pca_result$rotation[, 1:ncomp, drop = FALSE],
    variance_explained = variance_explained[1:ncomp],
    cumulative_variance = cumsum(variance_explained)[1:ncomp]
  )

  message("PCA completed. PC1 explains ",
          round(variance_explained[1] * 100, 2), "% of variance.")
  return(result)
}


#' @title Plot PCA Score Plot
#'
#' @description
#' 绘制PCA得分图，展示样本在主成分空间中的分布。不同分组用不同颜色
#' 表示，并绘制各组95%置信椭圆。该图用于评估样本分组是否在PCA空间
#' 中分离，是组学数据分析中最常用的无监督可视化方法。
#'
#' @param pca_result 列表，由perform_pca函数返回
#' @param sample_meta 数据框，样本元数据
#' @param pc_x 整数，X轴主成分编号，默认1
#' @param pc_y 整数，Y轴主成分编号，默认2
#' @param show_ellipse 逻辑值，是否绘制置信椭圆，默认TRUE
#' @param show_labels 逻辑值，是否显示样本标签，默认FALSE
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认8
#' @param height 数值，图片高度（英寸），默认7
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' pca_result <- perform_pca(expr)
#' plot_pca_scores(pca_result, meta, output_dir = "./figures")
#' }
#'
#' @export
plot_pca_scores <- function(pca_result, sample_meta, pc_x = 1, pc_y = 2,
                            show_ellipse = TRUE, show_labels = FALSE,
                            output_dir = ".", width = 8, height = 7) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  scores <- as.data.frame(pca_result$scores[, c(pc_x, pc_y)])
  colnames(scores) <- c("PC1", "PC2")

  matched_meta <- sample_meta[match(rownames(scores), sample_meta$ID), ]
  scores$Group <- matched_meta$sample_info
  scores$SampleName <- matched_meta$sample_name

  var_x <- pca_result$variance_explained[pc_x] * 100
  var_y <- pca_result$variance_explained[pc_y] * 100

  p <- ggplot2::ggplot(scores, ggplot2::aes(x = PC1, y = PC2,
                                             color = Group)) +
    ggplot2::geom_point(size = 3, alpha = 0.8) +
    ggplot2::labs(
      title = "PCA Score Plot",
      x = paste0("PC", pc_x, " (", round(var_x, 1), "%)"),
      y = paste0("PC", pc_y, " (", round(var_y, 1), "%)"),
      color = "Group"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold"),
      legend.position = "right",
      axis.title = ggplot2::element_text(size = 12),
      axis.text = ggplot2::element_text(size = 10)
    )

  if (show_ellipse) {
    p <- p + ggplot2::stat_ellipse(level = 0.95, type = "t",
                                    linewidth = 0.8)
  }

  if (show_labels) {
    p <- p + ggrepel::geom_text_repel(ggplot2::aes(label = SampleName),
                                       size = 3, max.overlaps = 20)
  }

  pdf_file <- file.path(output_dir, "PCA_score_plot.pdf")
  png_file <- file.path(output_dir, "PCA_score_plot.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("PCA score plot saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}


#' @title Perform PLSDA Analysis
#'
#' @description
#' 对表达矩阵执行偏最小二乘判别分析（PLS-DA）。PLS-DA是一种有监督
#' 降维方法，通过最大化组间差异寻找最优投影方向。该函数基于mixOmics包
#' 实现，返回PLS-DA结果对象、得分矩阵和VIP值。
#'
#' VIP（Variable Importance in Projection）值衡量每个feature对分类的贡献，
#' VIP > 1通常被认为是重要feature。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param sample_meta 数据框，样本元数据
#' @param ncomp 整数，保留的成分数，默认2
#' @param scale 逻辑值，是否标准化，默认TRUE
#' @param center 逻辑值，是否中心化，默认TRUE
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item plsda: mixOmics结果对象
#'   \item scores: 得分矩阵
#'   \item vip: VIP值矩阵（feature×主成分）
#'   \item loadings: 载荷矩阵
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' meta <- load_sample_metadata("meta.csv")
#' plsda_result <- perform_plsda(expr, meta, ncomp = 2)
#' }
#'
#' @export
perform_plsda <- function(expr_matrix, sample_meta, ncomp = 2,
                         scale = TRUE, center = TRUE) {
  if (!requireNamespace("mixOmics", quietly = TRUE)) {
    stop("Package 'mixOmics' is required. Please install it: ",
         "BiocManager::install('mixOmics')")
  }

  X <- t(expr_matrix)
  Y <- factor(sample_meta$sample_info[match(rownames(X), sample_meta$ID)])

  plsda_result <- mixOmics::plsda(X, Y, ncomp = ncomp,
                                   scale = scale, center = center)

  scores <- plsda_result$variates$X
  colnames(scores) <- paste0("Comp", 1:ncol(scores))

  vip_values <- mixOmics::vip(plsda_result)
  rownames(vip_values) <- rownames(expr_matrix)
  colnames(vip_values) <- paste0("Comp", 1:ncol(vip_values))

  result <- list(
    plsda = plsda_result,
    scores = scores,
    vip = vip_values,
    loadings = plsda_result$loadings$X
  )

  message("PLS-DA completed with ", ncomp, " components.")
  return(result)
}


#' @title Plot PLSDA Score Plot
#'
#' @description
#' 绘制PLS-DA得分图，展示样本在判别空间中的分布。不同分组用不同颜色
#' 表示，并绘制各组95%置信椭圆。该图用于评估分组判别效果。
#'
#' @param plsda_result 列表，由perform_plsda函数返回
#' @param sample_meta 数据框，样本元数据
#' @param comp_x 整数，X轴成分编号，默认1
#' @param comp_y 整数，Y轴成分编号，默认2
#' @param show_ellipse 逻辑值，是否绘制置信椭圆，默认TRUE
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认8
#' @param height 数值，图片高度（英寸），默认7
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' plsda_result <- perform_plsda(expr, meta)
#' plot_plsda_scores(plsda_result, meta, output_dir = "./figures")
#' }
#'
#' @export
plot_plsda_scores <- function(plsda_result, sample_meta, comp_x = 1,
                               comp_y = 2, show_ellipse = TRUE,
                               output_dir = ".", width = 8, height = 7) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  scores <- as.data.frame(plsda_result$scores[, c(comp_x, comp_y)])
  colnames(scores) <- c("Comp1", "Comp2")

  matched_meta <- sample_meta[match(rownames(scores), sample_meta$ID), ]
  scores$Group <- matched_meta$sample_info
  scores$SampleName <- matched_meta$sample_name

  p <- ggplot2::ggplot(scores, ggplot2::aes(x = Comp1, y = Comp2,
                                             color = Group)) +
    ggplot2::geom_point(size = 3, alpha = 0.8) +
    ggplot2::labs(
      title = "PLS-DA Score Plot",
      x = paste0("Comp", comp_x),
      y = paste0("Comp", comp_y),
      color = "Group"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold"),
      legend.position = "right"
    )

  if (show_ellipse) {
    p <- p + ggplot2::stat_ellipse(level = 0.95, type = "t", linewidth = 0.8)
  }

  pdf_file <- file.path(output_dir, "PLSDA_score_plot.pdf")
  png_file <- file.path(output_dir, "PLSDA_score_plot.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("PLS-DA score plot saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}


#' @title Plot VIP Values
#'
#' @description
#' 绘制VIP（Variable Importance in Projection）值条形图，展示对分类
#' 贡献最大的feature。VIP > 1通常被认为是重要feature。该图显示
#' Top N个VIP值最高的feature。
#'
#' @param plsda_result 列表，由perform_plsda或perform_oplsda函数返回
#' @param feature_anno 数据框，feature注释信息（可选，用于显示feature name）
#' @param top_n 整数，显示的Top feature数，默认20
#' @param comp 整数，使用哪个成分的VIP值，默认1
#' @param vip_threshold 数值，VIP阈值线，默认1
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认8
#' @param height 数值，图片高度（英寸），默认7
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' plsda_result <- perform_plsda(expr, meta)
#' plot_vip_values(plsda_result, feature_anno, top_n = 20,
#'                 output_dir = "./figures")
#' }
#'
#' @export
plot_vip_values <- function(plsda_result, feature_anno = NULL, top_n = 20,
                            comp = 1, vip_threshold = 1,
                            output_dir = ".", width = 8, height = 7) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  vip_values <- plsda_result$vip[, comp]
  vip_df <- data.frame(
    Feature = names(vip_values),
    VIP = as.numeric(vip_values),
    stringsAsFactors = FALSE
  )

  if (!is.null(feature_anno)) {
    name_map <- setNames(feature_anno$name, feature_anno$ID)
    vip_df$Name <- name_map[vip_df$Feature]
    vip_df$Name[is.na(vip_df$Name)] <- vip_df$Feature[is.na(vip_df$Name)]
  } else {
    vip_df$Name <- vip_df$Feature
  }

  vip_df <- vip_df[order(-vip_df$VIP), ]
  vip_df <- head(vip_df, top_n)
  vip_df$Name <- factor(vip_df$Name, levels = vip_df$Name[order(vip_df$VIP)])

  p <- ggplot2::ggplot(vip_df, ggplot2::aes(x = Name, y = VIP, fill = VIP)) +
    ggplot2::geom_bar(stat = "identity") +
    ggplot2::coord_flip() +
    ggplot2::geom_hline(yintercept = vip_threshold, color = "red",
                         linetype = "dashed", linewidth = 0.8) +
    ggplot2::scale_fill_gradient(low = "lightblue", high = "darkred") +
    ggplot2::labs(
      title = paste0("Top ", top_n, " VIP Values (Comp", comp, ")"),
      x = "Feature",
      y = "VIP Score"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold"),
      legend.position = "none"
    )

  pdf_file <- file.path(output_dir, "VIP_barplot.pdf")
  png_file <- file.path(output_dir, "VIP_barplot.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("VIP barplot saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}


#' @title Perform OPLSDA Analysis
#' @description Perform Orthogonal PLS-DA
#' @param expr_matrix 数值矩阵
#' @param sample_meta 数据框
#' @param ncomp 整数，预测成分数，默认1
#' @param orthI 整数，正交成分数，默认1
#' @return 列表
#' @export
perform_oplsda <- function(expr_matrix, sample_meta, ncomp = 1, orthI = 1) {
  if (!requireNamespace("ropls", quietly = TRUE)) {
    stop("Package 'ropls' is required. Please install it: ",
         "BiocManager::install('ropls')")
  }

  X <- t(expr_matrix)
  Y <- as.character(sample_meta$sample_info[match(rownames(X), sample_meta$ID)])

  oplsda_result <- ropls::opls(X, Y, predI = ncomp, orthoI = orthI,
                                fig.pdf.nb = 0, info.txt = FALSE)

  scores <- ropls::getScoreMN(oplsda_result)
  vip_values <- ropls::getVipVn(oplsda_result)

  result <- list(
    opls = oplsda_result,
    scores = scores,
    vip = vip_values,
    loadings = ropls::getLoadingMN(oplsda_result)
  )

  message("OPLS-DA completed with ", ncomp, " predictive and ",
          orthI, " orthogonal components.")
  return(result)
}


#' @title Plot OPLSDA Score Plot
#' @description Plot OPLS-DA scores
#' @param oplsda_result 列表
#' @param sample_meta 数据框
#' @param show_ellipse 逻辑值
#' @param output_dir 字符串
#' @param width 数值
#' @param height 数值
#' @return ggplot对象
#' @export
plot_oplsda_scores <- function(oplsda_result, sample_meta, show_ellipse = TRUE,
                                output_dir = ".", width = 8, height = 7) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  scores <- as.data.frame(oplsda_result$scores[, 1:2])
  colnames(scores) <- c("Comp1", "OrthComp1")

  matched_meta <- sample_meta[match(rownames(scores), sample_meta$ID), ]
  scores$Group <- matched_meta$sample_info

  p <- ggplot2::ggplot(scores, ggplot2::aes(x = Comp1, y = OrthComp1,
                                             color = Group)) +
    ggplot2::geom_point(size = 3, alpha = 0.8) +
    ggplot2::labs(
      title = "OPLS-DA Score Plot",
      x = "Predictive Component 1",
      y = "Orthogonal Component 1",
      color = "Group"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold"),
      legend.position = "right"
    )

  if (show_ellipse) {
    p <- p + ggplot2::stat_ellipse(level = 0.95, type = "t", linewidth = 0.8)
  }

  pdf_file <- file.path(output_dir, "OPLSDA_score_plot.pdf")
  png_file <- file.path(output_dir, "OPLSDA_score_plot.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("OPLS-DA score plot saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}
