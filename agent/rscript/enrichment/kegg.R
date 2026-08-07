
#' KEGG 通路 Fisher 富集分析
#'
#' @description 对显著化合物进行 KEGG 通路过表达（over-representation）的
#'   Fisher 精确检验。与化合物层面的富集不同，本方法先正确地将化合物映射到
#'   通路，再对每条通路分别检验。
#'
#' @param significant_compounds 显著化合物 ID 的字符向量
#'   （KEGG 化合物 ID，如 "C02845"）。
#' @param all_compounds 全部化合物 ID 的字符向量（背景集）。
#' @param kegg_mapping 来自 \code{map_kegg_compound_to_pathway()} 的数据框，
#'   包含列：compound_id、pathway_id、pathway_name。
#' @param p_adj_method P 值校正方法。默认："BH"。
#' @param min_size 每条通路的最少化合物数量。默认：2。
#'
#' @return 含通路富集结果的数据框（以 pathway_name 作为行名）。
#'
#' @examples
#' \dontrun{
#' mapping <- map_kegg_compound_to_pathway(kegg_ids)
#' enrich <- run_kegg_pathway_enrich(sig_compounds, all_compounds, mapping)
#' }
#'
#' @export
run_kegg_pathway_enrich <- function(significant_compounds, all_compounds,
                                     kegg_mapping, p_adj_method = "BH",
                                     min_size = 2) {
  if (is.null(kegg_mapping) || nrow(kegg_mapping) == 0) {
    warning("No KEGG pathway mapping provided.")
    return(data.frame())
  }

  # 将映射筛选到 all_compounds 中的化合物
  mapping <- kegg_mapping[kegg_mapping$compound_id %in% all_compounds, ]

  # 获取带有通路注释的唯一化合物（背景集）
  bg_compounds <- unique(mapping$compound_id)
  n_bg <- length(bg_compounds)

  # 带有通路注释的显著化合物
  sig_compounds <- unique(significant_compounds[significant_compounds %in% bg_compounds])
  n_sig <- length(sig_compounds)

  cat("  KEGG pathway enrichment:\n")
  cat("    Background compounds (with pathway annotation): ", n_bg, "\n")
  cat("    Significant compounds (with pathway annotation): ", n_sig, "\n")

  if (n_sig == 0 || n_bg == 0) {
    warning("No compounds with KEGG pathway annotation found.")
    return(data.frame())
  }

  # 获取通路列表
  pathways <- unique(mapping$pathway_id)

  results <- data.frame(
    pathway_id = character(),
    pathway_name = character(),
    sig_count = integer(),
    sig_total = integer(),
    bg_count = integer(),
    bg_total = integer(),
    p_value = numeric(),
    fold_enrichment = numeric(),
    stringsAsFactors = FALSE
  )

  for (pw in pathways) {
    pw_compounds <- unique(mapping$compound_id[mapping$pathway_id == pw])

    if (length(pw_compounds) < min_size) next

    cat_bg <- length(pw_compounds)
    cat_sig <- sum(sig_compounds %in% pw_compounds)
    not_cat_bg <- n_bg - cat_bg
    not_cat_sig <- n_sig - cat_sig

    # Fisher 精确检验（单侧，greater）
    contingency <- matrix(c(cat_sig, not_cat_sig, cat_bg, not_cat_bg), nrow = 2)
    ft <- stats::fisher.test(contingency, alternative = "greater")

    # 富集倍数
    expected <- (cat_sig + cat_bg) * n_sig / (n_sig + n_bg)
    fold <- if (expected > 0) cat_sig / expected else 0

    pw_name <- mapping$pathway_name[mapping$pathway_id == pw][1]

    results <- rbind(results, data.frame(
      pathway_id = pw,
      pathway_name = pw_name,
      sig_count = cat_sig,
      sig_total = n_sig,
      bg_count = cat_bg,
      bg_total = n_bg,
      p_value = ft$p.value,
      fold_enrichment = fold,
      stringsAsFactors = FALSE
    ))
  }

  if (nrow(results) == 0) {
    warning("No pathways with sufficient compounds found.")
    return(data.frame())
  }

  # 校正 P 值
  results$p_adj <- stats::p.adjust(results$p_value, method = p_adj_method)
  results$significant <- results$p_adj < 0.05

  # 按 P 值排序
  results <- results[order(results$p_value), ]

  # 将 pathway_id 设为行名（保持唯一），同时保留 pathway_name 列
  rownames(results) <- make.unique(as.character(results$pathway_id))
  results$pathway_id <- NULL

  return(results)
}


#' KEGG 通路 GSVA 分析
#'
#' @description 在 KEGG 通路层面执行 GSVA（基因集变异分析）。化合物按其
#'   KEGG 通路归属分组，并为每个样本计算通路层面的活性得分。一个化合物可
#'   对多条通路产生贡献。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。行名必须与
#'   \code{kegg_mapping$compound_id} 中的化合物名一致。
#' @param kegg_mapping 来自 \code{map_kegg_compound_to_pathway()} 的数据框，
#'   包含列：compound_id、pathway_id、pathway_name。
#' @param method 得分计算方法："gsva"、"ssgsea"、"zscore" 或
#'   "mean"。默认："mean"（当 GSVA 包不可用时使用平均 z-score）。
#' @param min_size 通路最小规模。默认：2。
#' @param max_size 通路最大规模。默认：500。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{gsva_matrix}：数值矩阵（通路 x 样本）。
#'     \item \code{pathways}：每条通路的化合物向量命名列表。
#'     \item \code{n_pathways}：通路数量。
#'   }
#'
#' @examples
#' \dontrun{
#' mapping <- map_kegg_compound_to_pathway(kegg_ids)
#' gsva_res <- run_kegg_pathway_gsva(expr_matrix, mapping)
#' }
#'
#' @export
run_kegg_pathway_gsva <- function(expr_matrix, kegg_mapping,
                                   feature_info = NULL, feature_id_col = "name",
                                   kegg_col = "kegg",
                                   method = "mean", min_size = 2,
                                   max_size = 500) {
  if (is.null(kegg_mapping) || nrow(kegg_mapping) == 0) {
    warning("No KEGG pathway mapping provided.")
    return(NULL)
  }

  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # 若提供了 feature_info，则将 KEGG 化合物 ID 映射到表达矩阵的行名
  if (!is.null(feature_info)) {
    # 建立映射：KEGG ID -> 表达矩阵中的Feature名
    valid <- !is.na(feature_info[[kegg_col]]) & feature_info[[kegg_col]] != ""
    kegg_to_feature <- setNames(feature_info[[feature_id_col]][valid],
                                feature_info[[kegg_col]][valid])
    # 在映射中加入 feature_name 列
    mapping <- kegg_mapping
    mapping$feature_name <- kegg_to_feature[mapping$compound_id]
    mapping <- mapping[!is.na(mapping$feature_name), ]

    # 与表达矩阵匹配
    common_features <- intersect(mapping$feature_name, rownames(expr_matrix))
  } else {
    # 直接匹配：化合物 ID 即表达矩阵的行名
    mapping <- kegg_mapping
    mapping$feature_name <- mapping$compound_id
    common_features <- intersect(mapping$compound_id, rownames(expr_matrix))
  }

  if (nrow(mapping) == 0 || length(common_features) == 0) {
    warning("No matching compounds found between expression matrix and KEGG mapping.")
    return(NULL)
  }

  # 按通路对化合物分组
  pathways <- list()
  pathway_names <- character()

  for (pw in unique(mapping$pathway_id)) {
    pw_mapping <- mapping[mapping$pathway_id == pw, ]
    pw_features <- unique(pw_mapping$feature_name)
    pw_features <- intersect(pw_features, rownames(expr_matrix))

    if (length(pw_features) >= min_size && length(pw_features) <= max_size) {
      pw_name <- mapping$pathway_name[mapping$pathway_id == pw][1]
      if (is.na(pw_name) || pw_name == "") pw_name <- pw
      pathways[[pw_name]] <- pw_features
    }
  }

  if (length(pathways) == 0) {
    warning("No KEGG pathways with sufficient compounds found.")
    return(NULL)
  }

  cat("  KEGG pathway GSVA: ", length(pathways), " pathways\n")

  # 检查 GSVA 包是否可用
  use_gsva <- requireNamespace("GSVA", quietly = TRUE) && method %in% c("gsva", "ssgsea")

  if (use_gsva) {
    # 使用 GSVA 包
    gene_sets <- lapply(pathways, function(x) x)
    gsva_mat <- GSVA::gsva(expr_matrix, gene_sets, method = method,
                           min.sz = min_size, max.sz = max_size,
                           verbose = FALSE)
    gsva_matrix <- as.matrix(gsva_mat)
    rownames(gsva_matrix) <- names(pathways)
  } else {
    # 回退方案：每条通路使用平均 z-score
    if (!use_gsva) {
      warning("Package 'GSVA' not installed, or method not in c('gsva', 'ssgsea'). Using mean z-score per pathway.")
    }

    gsva_matrix <- matrix(NA, nrow = length(pathways), ncol = ncol(expr_matrix))
    rownames(gsva_matrix) <- names(pathways)
    colnames(gsva_matrix) <- colnames(expr_matrix)

    for (i in seq_along(pathways)) {
      pw_compounds <- pathways[[i]]
      pw_expr <- expr_matrix[pw_compounds, , drop = FALSE]

      # 先对每个化合物做 z-score，再在每个样本上对各化合物取均值
      pw_t <- t(as.matrix(pw_expr))  # 样本 x 化合物
      scaled_expr <- scale(pw_t)  # 对每一列（化合物）标准化
      # rowMeans 给出每个样本跨化合物的均值
      gsva_matrix[i, ] <- rowMeans(scaled_expr, na.rm = TRUE)
    }
  }

  return(list(
    gsva_matrix = gsva_matrix,
    pathways = pathways,
    n_pathways = length(pathways)
  ))
}

# =============================================================================
# KEGG 通路可视化（通用能力补全）
# 说明：run_kegg_pathway_enrich / run_kegg_pathway_gsva 此前缺少配套绘图函数，
#       调用方无法获得可视化产出。此处补实现两个通用 ggplot2 绘图函数，
#       仅读取既有返回结构，不引入新的分析语义，向后兼容。
# =============================================================================

plot_kegg_enrichment <- function(enrich_res, top_n = 20) {
  if (is.null(enrich_res) || nrow(enrich_res) == 0) {
    warning("plot_kegg_enrichment: 富集结果为空，返回 NULL。")
    return(NULL)
  }
  df <- enrich_res
  df$pathway_id <- rownames(enrich_res)
  df$label <- ifelse(!is.na(df$pathway_name) & df$pathway_name != "",
                     df$pathway_name, df$pathway_id)
  # pathway_name 可能重复（不同 pathway_id 同名），用 make.unique 去重避免 factor 报错
  df$label <- make.unique(as.character(df$label), sep = "·")
  df$neg_log10_p <- -log10(pmax(df$p_value, 1e-300))
  df <- df[order(df$p_value), ][seq_len(min(top_n, nrow(df))), , drop = FALSE]
  df$label <- factor(df$label, levels = rev(df$label))
  df$sig <- ifelse(is.na(df$p_adj), FALSE, df$p_adj < 0.05)
  ggplot2::ggplot(df, ggplot2::aes(x = neg_log10_p, y = label, fill = sig)) +
    ggplot2::geom_col() +
    ggplot2::scale_fill_manual(values = c("FALSE" = "#B0B0B0", "TRUE" = "#E64B35"),
                               guide = "none") +
    ggplot2::labs(x = expression(-log[10](p)), y = "KEGG Pathway",
                  title = "KEGG Pathway Enrichment") +
    ggplot2::theme_bw() +
    ggplot2::theme(plot.title = ggplot2::element_text(hjust = 0.5))
}

plot_kegg_pathway_activity <- function(gsva_res, top_n = 30,
                                       sample_info = NULL, group_col = NULL) {
  if (is.null(gsva_res) || is.null(gsva_res$gsva_matrix)) {
    warning("plot_kegg_pathway_activity: gsva_matrix 为空，返回 NULL。")
    return(NULL)
  }
  mat <- gsva_res$gsva_matrix
  rv <- matrixStats::rowVars(mat)
  keep <- order(rv, decreasing = TRUE)[seq_len(min(top_n, nrow(mat)))]
  sub <- mat[keep, , drop = FALSE]
  long <- reshape2::melt(sub)
  colnames(long) <- c("pathway", "sample", "activity")
  if (!is.null(sample_info) && !is.null(group_col) &&
      nrow(sample_info) == ncol(mat)) {
    long$group <- sample_info[[group_col]][match(long$sample, rownames(sample_info))]
  }
  ggplot2::ggplot(long, ggplot2::aes(x = sample, y = pathway, fill = activity)) +
    ggplot2::geom_tile() +
    ggplot2::scale_fill_gradient2(low = "#1F77B4", mid = "white", high = "#D62728") +
    ggplot2::labs(x = "Sample", y = "KEGG Pathway", fill = "Activity\n(z-score)") +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_blank())
}


#' KEGG 通路层面的 WGCNA 模块Feature基因（module eigengenes）
#'
#' @description 按Feature的 KEGG 通路归属（经由化合物-通路映射）进行分组，
#'   并为每条通路计算模块Feature基因（第一主成分）。返回的结果与
#'   \code{wgcna_module_trait()} 兼容，可用于性状关联分析。此举纠正了把
#'   化合物 ID 当作模块定义的科学性错误。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param kegg_mapping 来自 \code{map_kegg_compound_to_pathway()} 的数据框，
#'   包含列：compound_id、pathway_id、pathway_name。
#' @param feature_info 含有Feature注释的数据框。必须包含与 \code{feature_id_col}
#'   （表达矩阵中的Feature名）和 \code{kegg_col}（KEGG 化合物 ID）对应的列。
#' @param feature_id_col feature_info 中Feature ID 的列名。默认："name"。
#' @param kegg_col feature_info 中 KEGG 化合物 ID 的列名。默认："kegg"。
#' @param min_size 通路最小规模。默认：2。
#' @param max_size 通路最大规模。默认：500。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{MEs}：模块Feature基因的数据框（样本 x 通路）。
#'     \item \code{colors}：每个Feature的通路归属命名字符向量。
#'     \item \code{module_sizes}：通路规模的命名整数向量。
#'     \item \code{modules}：每条通路的特向量命名列表。
#'     \item \code{n_modules}：通路数量。
#'     \item \code{category_col}："kegg_pathway"。
#'   }
#'
#' @examples
#' \dontrun{
#' mapping <- map_kegg_compound_to_pathway(kegg_ids)
#' modules <- run_kegg_pathway_wgcna(expr_matrix, mapping, feature_info)
#' trait_assoc <- wgcna_module_trait(modules, traits)
#' }
#'
#' @export
run_kegg_pathway_wgcna <- function(expr_matrix, kegg_mapping, feature_info,
                                    feature_id_col = "name", kegg_col = "kegg",
                                    min_size = 2, max_size = 500) {
  if (is.null(kegg_mapping) || nrow(kegg_mapping) == 0) {
    warning("No KEGG pathway mapping provided.")
    return(NULL)
  }

  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # 将 KEGG 化合物 ID 映射到表达矩阵中的Feature名
  valid <- !is.na(feature_info[[kegg_col]]) & feature_info[[kegg_col]] != ""
  kegg_to_feature <- setNames(feature_info[[feature_id_col]][valid],
                              feature_info[[kegg_col]][valid])

  # 构建扩展映射：feature_name -> pathway
  mapping <- kegg_mapping
  mapping$feature_name <- kegg_to_feature[mapping$compound_id]
  mapping <- mapping[!is.na(mapping$feature_name), ]
  mapping <- mapping[mapping$feature_name %in% rownames(expr_matrix), ]

  if (nrow(mapping) == 0) {
    warning("No matching features found between expression matrix and KEGG mapping.")
    return(NULL)
  }

  # 按通路对Feature分组
  modules <- list()
  for (pw in unique(mapping$pathway_id)) {
    pw_mapping <- mapping[mapping$pathway_id == pw, ]
    pw_features <- unique(pw_mapping$feature_name)
    pw_features <- intersect(pw_features, rownames(expr_matrix))

    if (length(pw_features) >= min_size && length(pw_features) <= max_size) {
      pw_name <- mapping$pathway_name[mapping$pathway_id == pw][1]
      if (is.na(pw_name) || pw_name == "") pw_name <- pw
      modules[[pw_name]] <- pw_features
    }
  }

  if (length(modules) == 0) {
    warning("No KEGG pathways with sufficient features found.")
    return(NULL)
  }

  cat("  KEGG pathway modules: ", length(modules), " pathways\n")

  # 为每条通路计算模块Feature基因（第一主成分）
  me_list <- list()
  colors <- setNames(rep("grey", nrow(expr_matrix)), rownames(expr_matrix))

  for (mod_name in names(modules)) {
    mod_features <- modules[[mod_name]]
    mod_expr <- expr_matrix[mod_features, , drop = FALSE]

    if (nrow(mod_expr) == 1) {
      me <- as.numeric(mod_expr[1, ])
    } else {
      data_t <- t(mod_expr)
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
    colors[mod_features] <- mod_name
  }

  # 合并Feature基因
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
    category_col = "kegg_pathway"
  ))
}
