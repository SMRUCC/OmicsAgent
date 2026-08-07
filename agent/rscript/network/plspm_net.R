# ==============================================================================
# OmicsFlow: PLS-PM（偏最小二乘路径建模，Partial Least Squares Path Modeling）
# ==============================================================================
# 多组学或单组学的潜变量网络
# ==============================================================================

#' 运行 PLS-PM 分析
#'
#' @description 执行偏最小二乘路径建模，从观测到的特征组（如家族或 KEGG 通路）
#'   构建潜变量网络。适用于多组学整合。
#'
#' @param expr_matrix 数值矩阵（特征 x 样本）。
#' @param feature_info 含有特征注释的数据框。
#' @param latent_def 命名列表，每个元素为定义潜变量的特征 ID 字符向量，或
#'   feature_info 中某列名。例如 \code{list(Metabolism = "kegg", Lipids = "super_class")}。
#' @param inner_model 可选的矩阵，定义潜变量之间的关系。若为 NULL，则所有潜变量
#'   互连。默认：NULL。
#' @param feature_id_col 特征 ID 的列名。默认："ID"。
#' @param ncomp PLS 组分数。默认：2。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{scores}：潜变量得分（样本 x 潜变量）。
#'     \item \code{outer_model}：特征在潜变量上的载荷。
#'     \item \code{inner_model}：潜变量之间的路径系数。
#'     \item \code{path_coefficients}：路径系数矩阵。
#'   }
#'
#' @examples
#' \dontrun{
#' # 按 KEGG 通路定义潜变量
#' latent_def <- list(
#'   AminoAcid = c("feature1", "feature2", "feature3"),
#'   Lipid = c("feature4", "feature5", "feature6")
#' )
#' result <- run_plspm(expr_matrix, feature_info, latent_def)
#' }
#'
#' @export
run_plspm <- function(expr_matrix, feature_info, latent_def,
                     inner_model = NULL, feature_id_col = "ID",
                     ncomp = 2) {
  if (!requireNamespace("plsdepot", quietly = TRUE)) {
    warning("Package 'plsdepot' not available. Using simplified PLS-PM.")
  }

  # 对齐特征信息
  if (feature_id_col %in% colnames(feature_info)) {
    rownames(feature_info) <- feature_info[[feature_id_col]]
  }
  common_features <- intersect(rownames(expr_matrix), rownames(feature_info))

  # 构建潜变量数据
  latent_scores <- list()
  outer_loadings <- list()

  for (lv_name in names(latent_def)) {
    lv_def <- latent_def[[lv_name]]

    if (length(lv_def) == 1 && lv_def %in% colnames(feature_info)) {
      # 列名：每个不同（非空）的取值成为一个独立的潜变量。
      # 若调用方未预期多分组行为，则发出警告，但仍仅构建第一个类别分组后继续。
      warning(
        "latent_def element '", lv_name, "' is a column name ('", lv_def,
        "'). Grouping is ambiguous; use build_latent_def_from_annotation() ",
        "to expand a column into multiple latent variables."
      )
      lv_features <- common_features[
        !is.na(feature_info[common_features, lv_def]) &
          feature_info[common_features, lv_def] != "" &
          feature_info[common_features, lv_def] != lv_def[1]
      ]
      if (length(lv_features) < 2) {
        lv_features <- intersect(feature_info[common_features, lv_def],
                                 common_features)
      }
    } else {
      lv_features <- intersect(lv_def, common_features)
    }

    if (length(lv_features) < 2) next

    # 通过 PCA 获取潜变量得分
    sub_mat <- t(as.matrix(expr_matrix[lv_features, , drop = FALSE]))
    pca_result <- stats::prcomp(sub_mat, scale. = TRUE, center = TRUE)
    latent_scores[[lv_name]] <- pca_result$x[, 1]

    # 载荷
    outer_loadings[[lv_name]] <- data.frame(
      feature_id = lv_features,
      loading = pca_result$rotation[, 1],
      stringsAsFactors = FALSE
    )
  }

  # 合并得分
  scores_df <- as.data.frame(do.call(cbind, latent_scores))
  rownames(scores_df) <- colnames(expr_matrix)

  # 内模型：路径系数
  lv_names <- names(latent_scores)
  n_lv <- length(lv_names)

  if (is.null(inner_model)) {
    # 全连接路径系数
    path_mat <- matrix(0, n_lv, n_lv)
    rownames(path_mat) <- colnames(path_mat) <- lv_names

    for (i in 1:n_lv) {
      for (j in 1:n_lv) {
        if (i != j) {
          fit <- stats::lm(scores_df[, j] ~ scores_df[, i])
          s <- summary(fit)
          path_mat[i, j] <- stats::coef(s)[2, 1]
        }
      }
    }
  } else {
    path_mat <- inner_model
  }

  # 外模型
  outer_model <- do.call(rbind, lapply(names(outer_loadings), function(lv) {
    df <- outer_loadings[[lv]]
    df$latent_variable <- lv
    return(df)
  }))

  # 内模型汇总
  inner_summary <- data.frame(
    from = character(),
    to = character(),
    path_coeff = numeric(),
    p_value = numeric(),
    stringsAsFactors = FALSE
  )

  for (i in 1:n_lv) {
    for (j in 1:n_lv) {
      if (i != j && path_mat[i, j] != 0) {
        fit <- stats::lm(scores_df[, j] ~ scores_df[, i])
        s <- summary(fit)
        inner_summary <- rbind(inner_summary, data.frame(
          from = lv_names[i],
          to = lv_names[j],
          path_coeff = stats::coef(s)[2, 1],
          p_value = stats::coef(s)[2, 4],
          stringsAsFactors = FALSE
        ))
      }
    }
  }

  return(list(
    scores = scores_df,
    outer_model = outer_model,
    inner_model = inner_summary,
    path_coefficients = path_mat
  ))
}


#' 绘制 PLS-PM 路径图
#'
#' @description 创建展示潜变量及其相互关系的路径图。
#'
#' @param plspm_result 来自 \code{run_plspm()} 的结果。
#' @param p_threshold 显著性 p 值阈值。默认：0.05。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' result <- run_plspm(expr_matrix, feature_info, latent_def)
#' p <- plot_plspm_network(result)
#' print(p)
#' }
#' 根据特征注释构建潜变量定义
#'
#' @description 通过按 KEGG 通路归属（经由 compound->pathway 映射）或
#'   \code{super_class} 注释对实测特征进行分组，构建传给 \code{run_plspm()} 的
#'   \code{latent_def} 列表。单个特征可属于多个 KEGG 通路，因此会被包含在多个
#'   潜变量中；每个潜变量的得分由 \code{run_plspm()} 内部通过 PCA 独立计算。
#'
#' @param expr_matrix 数值矩阵（特征 x 样本）。
#' @param feature_info 含有特征注释的数据框（行名或用于标识特征的
#'   \code{feature_id_col} 列）。必须包含 \code{kegg_col} 与 \code{category_col} 列。
#' @param kegg_mapping 含有 \code{compound_id}、\code{pathway_id}、\code{pathway_name}
#'   列的数据框（由 \code{load_kegg_mapping()} 生成）。可为 NULL 以跳过 KEGG 通路。
#' @param feature_id_col \code{feature_info} 中特征 ID 的列名。默认："name"。
#' @param kegg_col 保存 KEGG 化合物 ID 的列名。默认："kegg"。
#' @param category_col 保存 super class 的列名。默认："super_class"。
#' @param min_size 每个潜变量的最少特征数。实测特征少于该值的分组会被丢弃。默认：2。
#' @param use_kegg 逻辑值；是否构建 KEGG 通路潜变量。默认：TRUE。
#' @param use_super_class 逻辑值；是否构建 super_class 潜变量。默认：TRUE。
#' @param prefix_kegg 添加到 KEGG 通路潜变量名的前缀。默认："KEGG:"。
#' @param prefix_super 添加到 super_class 潜变量名的前缀。默认："SC:"。
#'
#' @return 适用于 \code{run_plspm()} 的字符向量命名列表（特征 ID）。
#'
#' @examples
#' \dontrun{
#' latent_def <- build_latent_def_from_annotation(scaled_mat, feat_info, kegg_mapping)
#' result <- run_plspm(scaled_mat, feat_info, latent_def)
#' }
#'
#' @export
build_latent_def_from_annotation <- function(expr_matrix, feature_info,
                                             kegg_mapping = NULL,
                                             feature_id_col = "name",
                                             kegg_col = "kegg",
                                             category_col = "super_class",
                                             min_size = 2,
                                             use_kegg = TRUE,
                                             use_super_class = TRUE,
                                             prefix_kegg = "KEGG:",
                                             prefix_super = "SC:") {
  # 识别特征 ID 及其与表达矩阵的交集
  if (feature_id_col %in% colnames(feature_info)) {
    feat_ids <- feature_info[[feature_id_col]]
  } else {
    feat_ids <- rownames(feature_info)
  }
  feat_ids <- as.character(feat_ids)
  avail <- intersect(feat_ids, rownames(expr_matrix))
  info <- feature_info[match(avail, feat_ids), , drop = FALSE]
  rownames(info) <- avail

  latent_def <- list()

  # ---- KEGG 通路分组（compound -> pathway，多对多）----
  if (use_kegg && !is.null(kegg_mapping) && nrow(kegg_mapping) > 0) {
    if (!all(c("compound_id", "pathway_name") %in% colnames(kegg_mapping))) {
      warning("kegg_mapping missing 'compound_id'/'pathway_name'; skipping KEGG LVs.")
    } else {
      kegg_vals <- as.character(info[[kegg_col]])
      names(kegg_vals) <- rownames(info)
      keep <- kegg_vals != "" & !is.na(kegg_vals)
      map_sub <- kegg_mapping[
        kegg_mapping$compound_id %in% kegg_vals[keep],
        c("compound_id", "pathway_name")
      ]
      map_sub$pathway_name <- as.character(map_sub$pathway_name)
      map_sub$compound_id <- as.character(map_sub$compound_id)
      for (pid in unique(map_sub$pathway_name)) {
        members <- map_sub$compound_id[map_sub$pathway_name == pid]
        lv_features <- intersect(members, rownames(info))
        lv_features <- lv_features[lv_features %in% rownames(info)]
        if (length(lv_features) >= min_size) {
          latent_def[[paste0(prefix_kegg, pid)]] <- lv_features
        }
      }
    }
  }

  # ---- super_class 分组（每个特征单一取值）----
  if (use_super_class && category_col %in% colnames(info)) {
    sc_vals <- as.character(info[[category_col]])
    names(sc_vals) <- rownames(info)
    for (cat in unique(sc_vals)) {
      if (is.na(cat) || cat == "") next
      lv_features <- names(sc_vals)[sc_vals == cat]
      lv_features <- lv_features[lv_features %in% rownames(info)]
      if (length(lv_features) >= min_size) {
        latent_def[[paste0(prefix_super, cat)]] <- lv_features
      }
    }
  }

  if (length(latent_def) == 0) {
    warning("No latent variables built (all groups below min_size or no annotation).")
  }
  return(latent_def)
}


#'
#' @export
plot_plspm_network <- function(plspm_result, p_threshold = 0.05) {
  scores <- plspm_result$scores
  inner <- plspm_result$inner_model

  lv_names <- colnames(scores)
  n_lv <- length(lv_names)

  # 环形布局
  angles <- seq(0, 2 * pi, length.out = n_lv + 1)[1:n_lv]
  node_pos <- data.frame(
    node = lv_names,
    x = cos(angles),
    y = sin(angles),
    stringsAsFactors = FALSE
  )

  # 边数据
  if (nrow(inner) > 0) {
    edge_data <- merge(inner, node_pos, by.x = "from", by.y = "node")
    colnames(edge_data)[5:6] <- c("x_from", "y_from")
    edge_data <- merge(edge_data, node_pos, by.x = "to", by.y = "node")
    colnames(edge_data)[7:8] <- c("x_to", "y_to")
    edge_data$significant <- edge_data$p_value < p_threshold
  } else {
    edge_data <- data.frame()
  }

  p <- ggplot2::ggplot() +
    ggplot2::geom_segment(data = edge_data,
                          ggplot2::aes(x = x_from, y = y_from,
                                       xend = x_to, yend = y_to,
                                       color = path_coeff,
                                       linetype = significant),
                          arrow = grid::arrow(length = grid::unit(0.2, "cm")),
                          linewidth = 0.8) +
    ggplot2::scale_color_gradient2(low = "#2c7bb6", mid = "white",
                                   high = "#d7191c", midpoint = 0,
                                   name = "Path Coefficient") +
    ggplot2::scale_linetype_manual(values = c("TRUE" = "solid",
                                               "FALSE" = "dashed"),
                                    name = "Significant") +
    ggplot2::geom_point(data = node_pos, ggplot2::aes(x = x, y = y),
                        size = 8, color = "#4a90d9", fill = "white",
                        shape = 21, stroke = 1.5) +
    ggrepel::geom_label_repel(data = node_pos,
                              ggplot2::aes(x = x, y = y, label = node),
                              size = 3, fontface = "bold") +
    ggplot2::labs(title = "PLS-PM Network") +
    ggplot2::theme_void() +
    ggplot2::theme(plot.title = ggplot2::element_text(size = 14, face = "bold"))

  return(p)
}
