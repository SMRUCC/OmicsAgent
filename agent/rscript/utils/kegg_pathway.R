# ==============================================================================
# OmicsFlow: KEGG 通路映射与分析
# ==============================================================================
# 将 KEGG 化合物 ID 映射到 KEGG 通路，再进行通路层面的
# 富集分析与 GSVA。此举纠正了把化合物 ID 当作通路 ID 的科学性错误。
# ==============================================================================

#' 将 KEGG 化合物 ID 映射到 KEGG 通路
#'
#' @description 查询 KEGG REST API，将化合物 ID（如 C02845）映射到
#'   其关联的代谢通路（如 map00010）。一个化合物可关联多条通路。
#'   返回包含化合物-通路配对关系的数据框。
#'
#' @param kegg_ids KEGG 化合物 ID 的字符向量（如 "C02845"）。
#' @param cache_file 用于缓存/读取映射结果的缓存文件路径（可选）。默认：NULL。
#' @param batch_size 每次 API 请求的化合物数量（最多 10）。默认：10。
#' @param delay 两次 API 调用之间的间隔秒数。默认：0.3。
#'
#' @return 一个数据框，包含以下列：
#'   \itemize{
#'     \item \code{compound_id}：KEGG 化合物 ID。
#'     \item \code{pathway_id}：KEGG 通路 ID（如 "map00010"）。
#'     \item \code{pathway_name}：通路名称（如 "糖酵解 / 糖异生"）。
#'   }
#'
#' @examples
#' \dontrun{
#' mapping <- map_kegg_compound_to_pathway(c("C00022", "C00135"))
#' head(mapping)
#' }
#'
#' @export
map_kegg_compound_to_pathway <- function(kegg_ids, cache_dir = NULL,
                                          batch_size = 10, delay = 0.3) {
  # 清洗输入
  kegg_ids <- unique(kegg_ids[!is.na(kegg_ids) & kegg_ids != "" &
                                kegg_ids != "NULL" & kegg_ids != "NA"])
  if (length(kegg_ids) == 0) {
    warning("未提供有效的 KEGG 化合物 ID。")
    return(data.frame(
      compound_id = character(),
      pathway_id = character(),
      pathway_name = character(),
      stringsAsFactors = FALSE
    ))
  }

  # 检查缓存
  cache_file <- if (!is.null(cache_dir)) file.path(cache_dir, "kegg_pathway_mapping.csv") else NULL
  if (!is.null(cache_file) && file.exists(cache_file)) {
    cached <- utils::read.csv(cache_file, stringsAsFactors = FALSE)
    cached_ids <- unique(cached$compound_id)
    new_ids <- setdiff(kegg_ids, cached_ids)
    if (length(new_ids) == 0) {
      cat("  使用缓存的 KEGG 通路映射\n")
      return(cached[cached$compound_id %in% kegg_ids, ])
    }
    kegg_ids <- new_ids
    cached_data <- cached
  } else {
    cached_data <- NULL
  }

  # 确保带有 "cpd:" 前缀
  query_ids <- paste0("cpd:", kegg_ids)

  # 分批查询 KEGG API
  all_links <- character()
  n_batches <- ceiling(length(query_ids) / batch_size)

  for (b in seq_len(n_batches)) {
    start_idx <- (b - 1) * batch_size + 1
    end_idx <- min(b * batch_size, length(query_ids))
    batch <- query_ids[start_idx:end_idx]

    url <- paste0("https://rest.kegg.jp/link/pathway/", paste(batch, collapse = "+"))

    tryCatch({
      tmp <- tempfile()
      system2("curl", args = c("-s", url), stdout = tmp, stderr = NULL)
      lines <- readLines(tmp, warn = FALSE)
      unlink(tmp)
      if (length(lines) > 0 && any(nchar(lines) > 0)) {
        all_links <- c(all_links, lines[nchar(lines) > 0])
      }
    }, error = function(e) {
      warning("查询 KEGG API 失败（批次 ", b, "）")
    })

    if (b %% 10 == 0) cat("  KEGG API：批次", b, "/", n_batches, "\n")
    if (delay > 0) Sys.sleep(delay)
  }

  if (length(all_links) == 0) {
    warning("未找到任何化合物的通路关联。")
    return(data.frame(
      compound_id = character(),
      pathway_id = character(),
      pathway_name = character(),
      stringsAsFactors = FALSE
    ))
  }

  # 解析链接
  links <- strsplit(all_links, "\t")
  compound_ids <- gsub("cpd:", "", sapply(links, `[`, 1))
  pathway_ids <- sapply(links, `[`, 2)

  # 获取通路名称
  unique_pathways <- unique(pathway_ids)
  cat("  为", length(unique(compound_ids)), "个化合物找到", length(unique_pathways), "条唯一通路\n")

  pathway_names <- character(length(unique_pathways))
  names(pathway_names) <- unique_pathways

  for (i in seq_along(unique_pathways)) {
    pw <- unique_pathways[i]
    tryCatch({
      tmp <- tempfile()
      system2("curl", args = c("-s", paste0("https://rest.kegg.jp/get/", pw)),
              stdout = tmp, stderr = NULL)
      lines <- readLines(tmp, warn = FALSE)
      unlink(tmp)
      name_line <- grep("^NAME", lines, value = TRUE)[1]
      if (!is.na(name_line)) {
        pathway_names[pw] <- gsub("^NAME\\s+", "", name_line)
      } else {
        pathway_names[pw] <- pw
      }
    }, error = function(e) {
      pathway_names[pw] <- pw
    })
    if (i %% 20 == 0) cat("  通路名称：", i, "/", length(unique_pathways), "\n")
    if (delay > 0) Sys.sleep(delay)
  }

  result <- data.frame(
    compound_id = compound_ids,
    pathway_id = pathway_ids,
    pathway_name = pathway_names[pathway_ids],
    stringsAsFactors = FALSE
  )

  # 缓存
  if (!is.null(cache_file)) {
    if (!is.null(cached_data)) {
      result <- rbind(cached_data, result)
    }
    utils::write.csv(result, cache_file, row.names = FALSE)
    cat("  KEGG 映射已缓存至：", cache_file, "\n")
  } else if (!is.null(cached_data)) {
    result <- rbind(cached_data, result)
  }

  return(result)
}


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
    warning("未提供 KEGG 通路映射。")
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

  cat("  KEGG 通路富集：\n")
  cat("    背景化合物（带通路注释）：", n_bg, "\n")
  cat("    显著化合物（带通路注释）：", n_sig, "\n")

  if (n_sig == 0 || n_bg == 0) {
    warning("未找到带 KEGG 通路注释的化合物。")
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
    warning("未找到含有足够化合物的通路。")
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
#' @param expr_matrix 数值矩阵（特征 x 样本）。行名必须与
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

  # If feature_info provided, map KEGG compound IDs to feature row names
  if (!is.null(feature_info)) {
    # Create mapping: KEGG ID -> feature name in expression matrix
    valid <- !is.na(feature_info[[kegg_col]]) & feature_info[[kegg_col]] != ""
    kegg_to_feature <- setNames(feature_info[[feature_id_col]][valid],
                                feature_info[[kegg_col]][valid])
    # Add feature_name column to mapping
    mapping <- kegg_mapping
    mapping$feature_name <- kegg_to_feature[mapping$compound_id]
    mapping <- mapping[!is.na(mapping$feature_name), ]

    # Match to expression matrix
    common_features <- intersect(mapping$feature_name, rownames(expr_matrix))
  } else {
    # Direct match: compound IDs are row names in expr_matrix
    mapping <- kegg_mapping
    mapping$feature_name <- mapping$compound_id
    common_features <- intersect(mapping$compound_id, rownames(expr_matrix))
  }

  if (nrow(mapping) == 0 || length(common_features) == 0) {
    warning("No matching compounds between expression matrix and KEGG mapping.")
    return(NULL)
  }

  # Group compounds by pathway
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

  cat("  KEGG pathway GSVA:", length(pathways), "pathways\n")

  # Check if GSVA package is available
  use_gsva <- requireNamespace("GSVA", quietly = TRUE) && method %in% c("gsva", "ssgsea")

  if (use_gsva) {
    # Use GSVA package
    gene_sets <- lapply(pathways, function(x) x)
    gsva_mat <- GSVA::gsva(expr_matrix, gene_sets, method = method,
                           min.sz = min_size, max.sz = max_size,
                           verbose = FALSE)
    gsva_matrix <- as.matrix(gsva_mat)
    rownames(gsva_matrix) <- names(pathways)
  } else {
    # Fallback: mean z-score per pathway
    if (!use_gsva) {
      warning("Package 'GSVA' not available or method not one of c('gsva', 'ssgsea'). Using mean z-score per pathway.")
    }

    gsva_matrix <- matrix(NA, nrow = length(pathways), ncol = ncol(expr_matrix))
    rownames(gsva_matrix) <- names(pathways)
    colnames(gsva_matrix) <- colnames(expr_matrix)

    for (i in seq_along(pathways)) {
      pw_compounds <- pathways[[i]]
      pw_expr <- expr_matrix[pw_compounds, , drop = FALSE]

      # Z-score per compound, then mean across compounds per sample
      pw_t <- t(as.matrix(pw_expr))  # samples x compounds
      scaled_expr <- scale(pw_t)  # scale each column (compound)
      # rowMeans gives mean across compounds per sample
      gsva_matrix[i, ] <- rowMeans(scaled_expr, na.rm = TRUE)
    }
  }

  return(list(
    gsva_matrix = gsva_matrix,
    pathways = pathways,
    n_pathways = length(pathways)
  ))
}


#' KEGG pathway-level WGCNA module eigengenes
#'
#' @description Groups features by their KEGG pathway membership (via
#'   compound-to-pathway mapping) and calculates module eigengenes (first
#'   principal component) for each pathway. Returns a result compatible with
#'   \code{wgcna_module_trait()} for trait association analysis. This corrects
#'   the scientific error of treating compound IDs as module definitions.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param kegg_mapping Data.frame from \code{map_kegg_compound_to_pathway()}
#'   with columns: compound_id, pathway_id, pathway_name.
#' @param feature_info Data.frame with feature annotations. Must have a column
#'   matching \code{feature_id_col} (feature names in expression matrix) and
#'   \code{kegg_col} (KEGG compound IDs).
#' @param feature_id_col Column name for feature IDs in feature_info. Default: "name".
#' @param kegg_col Column name for KEGG compound IDs in feature_info. Default: "kegg".
#' @param min_size Minimum pathway size. Default: 2.
#' @param max_size Maximum pathway size. Default: 500.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{MEs}: Data.frame of module eigengenes (samples x pathways).
#'     \item \code{colors}: Named character vector of pathway assignment per feature.
#'     \item \code{module_sizes}: Named integer vector of pathway sizes.
#'     \item \code{modules}: Named list of feature vectors per pathway.
#'     \item \code{n_modules}: Number of pathways.
#'     \item \code{category_col}: "kegg_pathway".
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

  # Map KEGG compound IDs to feature names in expression matrix
  valid <- !is.na(feature_info[[kegg_col]]) & feature_info[[kegg_col]] != ""
  kegg_to_feature <- setNames(feature_info[[feature_id_col]][valid],
                              feature_info[[kegg_col]][valid])

  # Build expanded mapping: feature_name -> pathway
  mapping <- kegg_mapping
  mapping$feature_name <- kegg_to_feature[mapping$compound_id]
  mapping <- mapping[!is.na(mapping$feature_name), ]
  mapping <- mapping[mapping$feature_name %in% rownames(expr_matrix), ]

  if (nrow(mapping) == 0) {
    warning("No matching features between expression matrix and KEGG mapping.")
    return(NULL)
  }

  # Group features by pathway
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

  cat("  KEGG pathway modules:", length(modules), "pathways\n")

  # Calculate module eigengenes (first PC) per pathway
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

  # Combine eigengenes
  MEs <- as.data.frame(do.call(cbind, me_list))
  rownames(MEs) <- colnames(expr_matrix)

  # Module sizes
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
