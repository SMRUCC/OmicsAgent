# ==============================================================================
# OmicsFlow: GSVA（基因集变异分析，Gene Set Variation Analysis）
# ==============================================================================
# 每个样本的通路层面分析
# ==============================================================================

#' 运行 GSVA 分析
#'
#' @description 执行基因集变异分析（GSVA），为每个样本计算通路层面的得分。
#'   支持代谢相关的基因集。
#'
#' @param expr_matrix 数值矩阵（特征 x 样本）。
#' @param feature_info 含有特征注释的数据框。
#' @param feature_id_col 特征 ID 的列名。默认："ID"。
#' @param pathway_col 通路/类别所在的列名。默认："kegg"。
#' @param method GSVA 方法："gsva"、"ssgsea"、"zscore" 或 "plage"。
#'   默认："gsva"。
#' @param min_size 通路最小规模。默认：5。
#' @param max_size 通路最大规模。默认：500。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{gsva_matrix}：数值矩阵（通路 x 样本）。
#'     \item \code{pathways}：各通路的基因集特征列表。
#'     \item \code{n_pathways}：通路数量。
#'   }
#'
#' @examples
#' \dontrun{
#' gsva_result <- run_gsva(expr_matrix, metabolites_info, pathway_col = "kegg")
#' print(gsva_result$gsva_matrix[1:5, 1:5])
#' }
#'
#' @export
run_gsva <- function(expr_matrix, feature_info, feature_id_col = "ID",
                     pathway_col = "kegg", method = "gsva",
                     min_size = 5, max_size = 500) {
  # 构建通路集合
  if (feature_id_col %in% colnames(feature_info)) {
    rownames(feature_info) <- feature_info[[feature_id_col]]
  }

  # 获取公共特征
  common_features <- intersect(rownames(expr_matrix), rownames(feature_info))
  feature_info_subset <- feature_info[common_features, , drop = FALSE]

  # 构建基因集
  pathways <- split(rownames(feature_info_subset),
                    feature_info_subset[[pathway_col]])
  pathways <- pathways[names(pathways) != "" & !is.na(names(pathways))]

  # 按规模过滤
  pathway_sizes <- sapply(pathways, length)
  pathways <- pathways[pathway_sizes >= min_size & pathway_sizes <= max_size]

  if (length(pathways) == 0) {
    warning("没有满足规模标准的通路。请尝试调整 min_size/max_size。")
    return(list(gsva_matrix = NULL, pathways = list(), n_pathways = 0))
  }

  # 运行 GSVA
  if (requireNamespace("GSVA", quietly = TRUE)) {
    gsva_result <- GSVA::gsva(
      as.matrix(expr_matrix),
      pathways,
      method = method,
      min.sz = min_size,
      max.sz = max_size,
      verbose = FALSE
    )
    gsva_matrix <- gsva_result
  } else {
    # 回退方案：每条通路使用简单的平均 z-score
    warning("未安装 'GSVA' 包，改用简单的平均 z-score。")
    gsva_matrix <- sapply(names(pathways), function(pw) {
      pw_features <- intersect(pathways[[pw]], rownames(expr_matrix))
      if (length(pw_features) == 0) return(rep(NA, ncol(expr_matrix)))
      sub_mat <- expr_matrix[pw_features, , drop = FALSE]
      colMeans(sub_mat, na.rm = TRUE)
    })
    gsva_matrix <- t(gsva_matrix)
  }

  return(list(
    gsva_matrix = gsva_matrix,
    pathways = pathways,
    n_pathways = length(pathways)
  ))
}


#' 绘制 GSVA 热图
#'
#' @description 创建 GSVA 通路得分的热图。
#'
#' @param gsva_result 来自 \code{run_gsva()} 的结果。
#' @param sample_info 样本元数据。
#' @param group_col 分组标签所在的列。默认："sample_info"。
#'
#' @return 一个热图对象。
#'
#' @examples
#' \dontrun{
#' gsva <- run_gsva(expr_matrix, metabolites_info)
#' hm <- plot_gsva_heatmap(gsva, sample_info)
#' }
#'
#' @export
plot_gsva_heatmap <- function(gsva_result, sample_info,
                              group_col = "sample_info") {
  gsva_matrix <- gsva_result$gsva_matrix
  if (is.null(gsva_matrix)) stop("没有可供绘制的 GSVA 矩阵。")

  # 使用 plot_heatmap 函数
  hm <- plot_heatmap(gsva_matrix, sample_info, feature_info = NULL,
                     group_col = group_col, scale = "row",
                     n_features = nrow(gsva_matrix))
  return(hm)
}
