# ==============================================================================
# OmicsFlow: Core Microbiome Analysis
# ==============================================================================
# 核心微生物组分析：识别在大部分样本中稳定出现的 taxa
# 支持按丰度阈值和出现频率阈值筛选
# ==============================================================================

#' 识别核心微生物组
#'
#' @description 根据出现频率（prevalence）和相对丰度阈值识别核心微生物组。
#'   一个 taxa 被认为是"核心"的条件是：在至少 prevalence_threshold 比例的
#'   样本中出现，且在所有样本中的平均相对丰度不低于 abundance_threshold。
#'
#' @param expr_matrix 数值矩阵（features × samples），行为 taxa，列为样本。
#' @param sample_info 样本元数据 data.frame（可选，用于分组分析）。
#' @param group_col 分组列名。默认 "sample_info"。
#' @param prevalence_threshold 出现频率阈值（0-1）。默认 0.8（80% 样本中出现）。
#' @param abundance_threshold 平均相对丰度阈值。默认 1e-4。
#' @param detection_limit 检出限，低于此值视为未检出。默认 0。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{core_features}: 核心 taxa 名称向量。
#'     \item \code{prevalence}: 所有 taxa 的出现频率数据框。
#'     \item \code{core_by_group}: 按分组的核心 taxa 列表（如果提供了 group_col）。
#'     \item \code{params}: 参数设置。
#'   }
#'
#' @examples
#' \dontrun{
#' core <- identify_core_microbiome(expr_matrix, sample_info,
#'                                  prevalence_threshold = 0.8)
#' }
#'
#' @export
identify_core_microbiome <- function(expr_matrix, sample_info = NULL,
                                     group_col = "sample_info",
                                     prevalence_threshold = 0.8,
                                     abundance_threshold = 1e-4,
                                     detection_limit = 0) {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)

  # 计算相对丰度
  rel_abund <- calc_relative_abundance(expr_matrix)

  # 检出/未检出
  presence <- ifelse(expr_matrix > detection_limit, 1, 0)

  # 全局出现频率
  prevalence <- rowSums(presence) / ncol(presence)

  # 平均相对丰度
  mean_abund <- rowMeans(rel_abund, na.rm = TRUE)

  # 全局核心
  core_idx <- which(prevalence >= prevalence_threshold &
                      mean_abund >= abundance_threshold)
  core_features <- rownames(expr_matrix)[core_idx]

  cat(sprintf("[core] 全局核心 taxa: %d / %d (prevalence >= %.0f%%, abund >= %.1e)\n",
              length(core_features), nrow(expr_matrix),
              prevalence_threshold * 100, abundance_threshold))

  # 出现频率数据框
  prev_df <- data.frame(
    feature = rownames(expr_matrix),
    prevalence = prevalence,
    mean_abundance = mean_abund,
    is_core = prevalence >= prevalence_threshold & mean_abund >= abundance_threshold,
    stringsAsFactors = FALSE
  )
  prev_df <- prev_df[order(-prev_df$prevalence, -prev_df$mean_abundance), ]
  rownames(prev_df) <- NULL

  # 按分组的核心
  core_by_group <- NULL
  if (!is.null(sample_info) && group_col %in% colnames(sample_info)) {
    common <- intersect(colnames(expr_matrix), rownames(sample_info))
    rel_abund_sub <- rel_abund[, common, drop = FALSE]
    presence_sub <- presence[, common, drop = FALSE]
    groups <- sample_info[common, group_col]

    core_by_group <- list()
    for (g in unique(groups)) {
      g_samples <- common[groups == g]
      if (length(g_samples) < 2) next

      prev_g <- rowSums(presence_sub[, g_samples, drop = FALSE]) / length(g_samples)
      abund_g <- rowMeans(rel_abund_sub[, g_samples, drop = FALSE], na.rm = TRUE)
      core_g <- rownames(expr_matrix)[prev_g >= prevalence_threshold &
                                        abund_g >= abundance_threshold]
      core_by_group[[g]] <- core_g
      cat(sprintf("[core] %s 组核心 taxa: %d / %d\n",
                  g, length(core_g), nrow(expr_matrix)))
    }

    # 识别共有核心（所有组中都核心）
    if (length(core_by_group) > 1) {
      shared_core <- Reduce(intersect, core_by_group)
      cat(sprintf("[core] 各组共有核心 taxa: %d\n", length(shared_core)))
    }
  }

  return(list(
    core_features = core_features,
    prevalence = prev_df,
    core_by_group = core_by_group,
    params = list(
      prevalence_threshold = prevalence_threshold,
      abundance_threshold = abundance_threshold,
      detection_limit = detection_limit
    )
  ))
}


#' 绘制出现频率图
#'
#' @description 绘制 taxa 出现频率 vs 平均丰度的散点图，
#'   标出核心 taxa。横轴为出现频率，纵轴为平均相对丰度（log10）。
#'
#' @param core_result \code{identify_core_microbiome()} 的返回结果。
#' @param top_n 标注前 N 个核心 taxa 的名称。默认 20。
#'
#' @return ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_prevalence(core_result, top_n = 20)
#' }
#'
#' @export
plot_prevalence <- function(core_result, top_n = 20) {
  prev_df <- core_result$prevalence

  p <- ggplot2::ggplot(prev_df, ggplot2::aes(x = prevalence,
                                               y = mean_abundance,
                                               color = is_core)) +
    ggplot2::geom_point(size = 2, alpha = 0.6) +
    ggplot2::scale_y_log10() +
    ggplot2::scale_color_manual(
      values = c("FALSE" = "grey70", "TRUE" = "#e74c3c"),
      labels = c("Non-core", "Core"),
      name = "Status"
    ) +
    ggplot2::geom_vline(xintercept = core_result$params$prevalence_threshold,
                        linetype = "dashed", color = "grey50") +
    ggplot2::geom_hline(yintercept = core_result$params$abundance_threshold,
                        linetype = "dashed", color = "grey50") +
    ggplot2::labs(
      title = "Taxa Prevalence vs Abundance",
      x = "Prevalence (proportion of samples)",
      y = "Mean Relative Abundance (log10)"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 10),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right"
    )

  # 标注核心 taxa 名称
  if (sum(prev_df$is_core) > 0) {
    core_taxa <- prev_df[prev_df$is_core, , drop = FALSE]
    if (nrow(core_taxa) > top_n) {
      core_taxa <- core_taxa[1:top_n, , drop = FALSE]
    }
    p <- p + ggrepel::geom_text_repel(
      data = core_taxa,
      ggplot2::aes(label = feature),
      size = 2.5, max.overlaps = 15
    )
  }

  return(p)
}


#' 绘制核心微生物组热图
#'
#' @description 绘制核心 taxa 在所有样本中的相对丰度热图。
#'
#' @param expr_matrix 数值矩阵（features × samples）。
#' @param core_result \code{identify_core_microbiome()} 的返回结果。
#' @param sample_info 样本元数据 data.frame。
#' @param group_col 分组列名。默认 "sample_info"。
#' @param scale 是否行标准化。默认 TRUE。
#'
#' @return ComplexHeatmap 或 pheatmap 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_core_heatmap(expr_matrix, core_result, sample_info)
#' }
#'
#' @export
plot_core_heatmap <- function(expr_matrix, core_result, sample_info,
                             group_col = "sample_info",
                             scale = TRUE) {
  core_features <- core_result$core_features
  if (length(core_features) == 0) {
    stop("没有核心 taxa 可绘制。")
  }

  # 提取核心 taxa
  core_mat <- expr_matrix[core_features, , drop = FALSE]

  # 转为相对丰度
  core_mat <- calc_relative_abundance(core_mat)

  # 对数变换
  core_mat <- log10(core_mat + 1e-6)

  # 行标准化
  if (scale) {
    core_mat <- t(scale(t(core_mat)))
  }

  # 使用现有的 heatmap_plot 函数
  hm <- plot_heatmap(core_mat, sample_info,
                    feature_info = NULL,
                    group_col = group_col,
                    scale = "none",  # 已经做了
                    n_features = nrow(core_mat))
  return(hm)
}
