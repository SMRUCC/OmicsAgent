# ==============================================================================
# OmicsFlow: Proteome Functional Profile Analysis
# ==============================================================================
# 蛋白质组功能谱分析：按功能类别（KEGG通路/COG分类/超类）聚合蛋白丰度
# 计算功能类别的活性得分并可视化
# ==============================================================================

#' 计算蛋白质组功能谱
#'
#' @description 按功能类别（如 KEGG 通路、COG 分类、super_class）聚合蛋白质丰度，
#'   计算每个功能类别在样本中的平均活性得分。可用于比较不同组别或时间点的
#'   功能变化。
#'
#' @param expr_matrix 数值矩阵（features × samples），行为蛋白质，列为样本。
#' @param feature_info Feature注释 data.frame，需包含功能类别列。
#' @param category_col 功能类别列名（如 "kegg_pathway"、"cog_category"、"super_class"）。
#' @param agg_method 聚合方法，"mean"、"median"、"sum" 或 "pc1"（第一主成分）。
#'   默认 "mean"。
#' @param min_size 功能类别最小蛋白数。默认 3。
#' @param max_size 功能类别最大蛋白数。默认 100（过大类别可能不够特异）。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{profile_matrix}: 功能类别 × 样本的丰度矩阵。
#'     \item \code{category_info}: 各功能类别的蛋白数量等信息。
#'     \item \code{params}: 参数设置。
#'   }
#'
#' @examples
#' \dontrun{
#' res <- calc_protein_functional_profile(expr_matrix, feature_info,
#'                                        category_col = "kegg_pathway")
#' }
#'
#' @export
calc_protein_functional_profile <- function(expr_matrix, feature_info,
                                           category_col,
                                           agg_method = "mean",
                                           min_size = 3,
                                           max_size = 100) {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)

  # 确保Feature注释行名与矩阵行名对应
  common <- intersect(rownames(expr_matrix), rownames(feature_info))
  if (length(common) == 0) {
    # 尝试用 ID 列匹配
    id_col <- if ("ID" %in% colnames(feature_info)) "ID" else names(feature_info)[1]
    common <- intersect(rownames(expr_matrix), feature_info[[id_col]])
    feature_info <- feature_info[match(common, feature_info[[id_col]]), , drop = FALSE]
    rownames(feature_info) <- common
  } else {
    feature_info <- feature_info[common, , drop = FALSE]
    expr_matrix <- expr_matrix[common, , drop = FALSE]
  }

  if (!category_col %in% colnames(feature_info)) {
    stop(sprintf("Category column '%s' not found in feature_info.", category_col))
  }

  # 按功能类别分组
  categories <- feature_info[[category_col]]
  categories[is.na(categories) | categories == ""] <- "Unknown"

  # 统计各类别大小
  cat_sizes <- table(categories)
  valid_cats <- names(cat_sizes)[cat_sizes >= min_size & cat_sizes <= max_size]
  valid_cats <- setdiff(valid_cats, "Unknown")

  if (length(valid_cats) == 0) {
    stop(sprintf("No functional categories met the size requirement (%d-%d proteins).", min_size, max_size))
  }

  cat(sprintf("[func-profile] %d functional categories (size %d-%d)\n",
              length(valid_cats), min_size, max_size))

  # 聚合
  profile_mat <- matrix(NA_real_, nrow = length(valid_cats),
                        ncol = ncol(expr_matrix))
  rownames(profile_mat) <- valid_cats
  colnames(profile_mat) <- colnames(expr_matrix)

  for (cat in valid_cats) {
    cat_proteins <- rownames(feature_info)[feature_info[[category_col]] == cat]
    cat_mat <- expr_matrix[cat_proteins, , drop = FALSE]

    if (agg_method == "mean") {
      profile_mat[cat, ] <- colMeans(cat_mat, na.rm = TRUE)
    } else if (agg_method == "median") {
      profile_mat[cat, ] <- apply(cat_mat, 2, stats::median, na.rm = TRUE)
    } else if (agg_method == "sum") {
      profile_mat[cat, ] <- colSums(cat_mat, na.rm = TRUE)
    } else if (agg_method == "pc1") {
      # 第一主成分
      cat_t <- t(cat_mat)
      if (nrow(cat_t) > 1 && ncol(cat_t) > 1) {
        tryCatch({
          pca <- stats::prcomp(cat_t, scale. = TRUE, center = TRUE)
          profile_mat[cat, ] <- pca$x[, 1]
        }, error = function(e) {
          profile_mat[cat, ] <- colMeans(cat_mat, na.rm = TRUE)
        })
      } else {
        profile_mat[cat, ] <- colMeans(cat_mat, na.rm = TRUE)
      }
    } else {
      stop("Unsupported aggregation method. Use 'mean', 'median', 'sum', or 'pc1'.")
    }
  }

  # 类别信息
  category_info <- data.frame(
    category = valid_cats,
    n_proteins = as.integer(cat_sizes[valid_cats]),
    mean_abundance = rowMeans(profile_mat, na.rm = TRUE),
    variance = apply(profile_mat, 1, stats::var, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
  category_info <- category_info[order(-category_info$variance), , drop = FALSE]
  rownames(category_info) <- NULL

  return(list(
    profile_matrix = profile_mat,
    category_info = category_info,
    params = list(
      category_col = category_col,
      agg_method = agg_method,
      min_size = min_size,
      max_size = max_size,
      n_categories = length(valid_cats)
    )
  ))
}


#' 绘制功能谱热图
#'
#' @description 绘制功能类别丰度热图，按分组排列样本。
#'
#' @param func_result \code{calc_protein_functional_profile()} 的返回结果。
#' @param sample_info 样本元数据 data.frame。
#' @param group_col 分组列名。默认 "sample_info"。
#' @param top_n 展示方差最大的前 N 个功能类别。默认 30。
#' @param scale 行标准化。默认 TRUE。
#'
#' @return ComplexHeatmap 或 pheatmap 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_functional_heatmap(func_result, sample_info, top_n = 30)
#' }
#'
#' @export
plot_functional_heatmap <- function(func_result, sample_info,
                                   group_col = "sample_info",
                                   top_n = 30,
                                   scale = TRUE) {
  profile_mat <- func_result$profile_matrix

  # 按方差选 Top N
  var_order <- order(-func_result$category_info$variance)[1:min(top_n, nrow(profile_mat))]
  profile_mat <- profile_mat[var_order, , drop = FALSE]

  if (scale) {
    profile_mat <- t(scale(t(profile_mat)))
  }

  # 使用现有 heatmap 函数
  hm <- plot_heatmap(profile_mat, sample_info,
                    feature_info = NULL,
                    group_col = group_col,
                    scale = "none",
                    n_features = nrow(profile_mat))
  return(hm)
}


#' 绘制功能类别比较图
#'
#' @description 绘制分组间功能类别活性比较图，展示不同组别中各功能类别的
#'   平均活性。
#'
#' @param func_result \code{calc_protein_functional_profile()} 的返回结果。
#' @param sample_info 样本元数据 data.frame。
#' @param group_col 分组列名。默认 "sample_info"。
#' @param top_n 展示前 N 个差异最大的功能类别。默认 15。
#'
#' @return ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_functional_comparison(func_result, sample_info, top_n = 15)
#' }
#'
#' @export
plot_functional_comparison <- function(func_result, sample_info,
                                      group_col = "sample_info",
                                      top_n = 15) {
  profile_mat <- func_result$profile_matrix
  common <- intersect(colnames(profile_mat), rownames(sample_info))
  groups <- sample_info[common, group_col]
  group_levels <- unique(groups)

  # 计算各组均值
  group_means <- sapply(group_levels, function(g) {
    g_samples <- common[groups == g]
    rowMeans(profile_mat[, g_samples, drop = FALSE], na.rm = TRUE)
  })
  if (!is.matrix(group_means)) group_means <- t(as.matrix(group_means))
  colnames(group_means) <- group_levels

  # 计算组间最大差异
  max_diff <- apply(group_means, 1, function(x) max(x, na.rm = TRUE) - min(x, na.rm = TRUE))
  top_idx <- order(-max_diff)[1:min(top_n, length(max_diff))]
  group_means <- group_means[top_idx, , drop = FALSE]

  # 转为长格式
  plot_df <- as.data.frame(as.table(group_means))
  colnames(plot_df) <- c("category", "group", "value")
  plot_df$category <- factor(plot_df$category,
                             levels = rownames(group_means))

  group_colors <- make_group_colors(group_levels)

  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = category, y = value,
                                               fill = group)) +
    ggplot2::geom_bar(stat = "identity", position = "dodge") +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = group_colors) +
    ggplot2::labs(
      title = "Functional Category Comparison",
      x = NULL,
      y = "Mean Activity"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text.y = ggplot2::element_text(size = 9),
      legend.position = "right"
    )

  return(p)
}


#' 对功能类别做差异分析
#'
#' @description 对功能类别丰度矩阵进行分组间差异分析（limma 或 t 检验）。
#'
#' @param func_result \code{calc_protein_functional_profile()} 的返回结果。
#' @param sample_info 样本元数据 data.frame。
#' @param group_col 分组列名。默认 "sample_info"。
#' @param control_group 对照组名称。默认 NULL（使用第一组）。
#' @param p_adjust p 值校正方法。默认 "BH"。
#' @param p_threshold p 值阈值。默认 0.05。
#' @param fc_threshold logFC 阈值。默认 0.5。
#'
#' @return 差异分析结果数据框。
#'
#' @examples
#' \dontrun{
#' de <- diff_functional_category(func_result, sample_info,
#'                                control_group = "Fresh")
#' }
#'
#' @export
diff_functional_category <- function(func_result, sample_info,
                                     group_col = "sample_info",
                                     control_group = NULL,
                                     p_adjust = "BH",
                                     p_threshold = 0.05,
                                     fc_threshold = 0.5) {
  profile_mat <- func_result$profile_matrix

  # 使用 limma（run_limma 返回 list，取 $results 为差异结果数据框）
  de_res <- run_limma(profile_mat, sample_info,
                      group_col = group_col,
                      control_group = control_group,
                      exclude_groups = NULL,
                      p_adj_method = p_adjust)$results

  # 添加显著性标记
  de_res$significant <- abs(de_res$logFC) >= fc_threshold &
                        de_res$p_adj < p_threshold

  cat(sprintf("[func-diff] %d functional categories significantly different (|logFC| >= %.1f, p_adj < %.2f)\n",
              sum(de_res$significant), fc_threshold, p_threshold))

  return(de_res)
}
