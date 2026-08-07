# ==============================================================================
# OmicsFlow: 预定义模块特征基因（Module Eigengenes）
# ==============================================================================
# 为预定义的特征分组（KEGG 通路、super_class 类别等）计算模块特征基因，
# 并与生物学性状做相关性分析
# ==============================================================================

#' 为预定义特征分组计算模块特征基因
#'
#' @description 按某一类别列（如 KEGG 通路、super_class）对特征分组，并为每个
#'   分组计算模块特征基因（第一主成分）。返回的结果与 \code{wgcna_module_trait()}
#'   兼容，可用于性状关联分析。
#'
#' @param expr_matrix 数值矩阵（特征 x 样本）。
#' @param feature_info 含有特征注释的数据框。
#' @param feature_id_col 特征 ID 的列名。默认："name"。
#' @param category_col 类别所在的列名（如 "kegg"、"super_class"）。
#' @param min_size 每个模块的最少特征数。默认：2。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{MEs}：模块特征基因（样本 x 模块）。
#'     \item \code{colors}：每个特征的模块归属命名向量。
#'     \item \code{module_sizes}：模块规模表。
#'     \item \code{modules}：每个模块的特征 ID 列表。
#'     \item \code{n_modules}：模块数量。
#'   }
#'
#' @examples
#' \dontrun{
#' # 基于 KEGG 的模块
#' kegg_mods <- predefined_module_eigengenes(expr_mat, feat_info,
#'                                           category_col = "kegg")
#'
#' # 基于 super_class 的模块
#' sc_mods <- predefined_module_eigengenes(expr_mat, feat_info,
#'                                          category_col = "super_class")
#' }
#'
#' @export
predefined_module_eigengenes <- function(expr_matrix, feature_info,
                                          feature_id_col = "name",
                                          category_col = "kegg",
                                          min_size = 2) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # 匹配特征
  feat_ids <- intersect(rownames(expr_matrix),
                        feature_info[[feature_id_col]])
  expr_sub <- expr_matrix[feat_ids, , drop = FALSE]

  # 获取每个特征的类别
  cat_map <- feature_info[[category_col]][match(feat_ids,
                                                  feature_info[[feature_id_col]])]

  # 移除类别为 NA 或空的特征
  valid_idx <- !is.na(cat_map) & cat_map != "" & cat_map != "NULL" &
               cat_map != "NA"
  expr_sub <- expr_sub[valid_idx, , drop = FALSE]
  cat_map <- cat_map[valid_idx]

  if (length(cat_map) == 0) {
    warning("在列 ", category_col, " 中未找到有效的类别分配。")
    return(NULL)
  }

  # 按类别对特征分组
  modules <- split(rownames(expr_sub), as.character(cat_map))

  # 按最小规模过滤
  modules <- modules[sapply(modules, length) >= min_size]

  if (length(modules) == 0) {
    warning("未找到规模 >= ", min_size, " 的模块。")
    return(NULL)
  }

  # 为每个模块计算模块特征基因（第一主成分）
  me_list <- list()
  colors <- character(nrow(expr_sub))
  names(colors) <- rownames(expr_sub)

  for (mod_name in names(modules)) {
    mod_features <- modules[[mod_name]]
    mod_expr <- expr_sub[mod_features, , drop = FALSE]

    # 计算特征基因（通过 prcomp 或 svd 取第一主成分）
    if (length(mod_features) == 1) {
      # 单个特征：以该特征自身作为特征基因
      me <- as.numeric(mod_expr[1, ])
    } else {
      # 多特征：取第一主成分
      data_t <- t(mod_expr)
      # 移除零方差特征
      feat_var <- apply(data_t, 2, stats::var, na.rm = TRUE)
      if (any(feat_var == 0)) {
        data_t <- data_t[, feat_var > 0, drop = FALSE]
      }
      if (ncol(data_t) >= 1) {
        pca <- stats::prcomp(data_t, scale. = FALSE, center = TRUE)
        me <- pca$x[, 1]
      } else {
        me <- as.numeric(mod_expr[1, ])
      }
    }
    me_list[[mod_name]] <- me

    # 分配模块颜色
    colors[mod_features] <- mod_name
  }

  # 不属于任何模块的特征标记为 "grey"
  unassigned <- names(colors)[colors == ""]
  colors[unassigned] <- "grey"

  # 合并特征基因
  MEs <- as.data.frame(do.call(cbind, me_list))
  rownames(MEs) <- colnames(expr_matrix)

  # 模块规模
  module_sizes <- sapply(modules, length)

  return(list(
    MEs = MEs,
    colors = colors,
    module_sizes = module_sizes,
    modules = modules,
    n_modules = length(modules),
    category_col = category_col
  ))
}
