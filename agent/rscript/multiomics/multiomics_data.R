# ==============================================================================
# OmicsFlow：多组学数据容器
# ==============================================================================
# 用于多组学整合分析的容器构建、样本对齐与批量预处理。
# ==============================================================================

#' 创建 MultiOmicsData 容器
#'
#' @description 由多个共享同一份样本元数据表的表达矩阵构建多组学容器。每个组学层
#'   都用 \code{create_omics_data()} 包装，且所有层都被对齐到每个层中都存在的样本
#'   集合，以便下游跨组学函数可以假定各层样本顺序完全一致。
#'
#' @param expr_list 数值矩阵的有名列表（Feature x 样本）。名称用作组学层名。
#' @param sample_info 含样本元数据的 data.frame，行名为样本 ID（由
#'   \code{load_sample_info()} 返回）。
#' @param feature_info_list Feature注释 data.frame 的有名列表，名称与 \code{expr_list}
#'   相同。该列表中缺失的层会获得自动生成的最小注释。
#' @param match_cols 字符向量，给出传给每层 \code{create_omics_data()} 的
#'   \code{match_col}。可为长度 1（循环使用）或每层一个条目的有名向量。默认："name"。
#'
#' @return 一个 MultiOmicsData 对象（列表），包含：
#'   \itemize{
#'     \item \code{omics}: OmicsData 对象的有名列表。
#'     \item \code{sample_info}: 仅保留共有样本的样本元数据。
#'     \item \code{common_samples}: 共有样本 ID 的字符向量。
#'     \item \code{metadata}: 含 n_omics、omics_names、n_samples 与
#'       n_features_per_omics 的列表。
#'   }
#'
#' @examples
#' \dontrun{
#' mo <- create_multiomics_data(
#'   expr_list = list(metabolome = m1, microbiome = m2),
#'   sample_info = sample_info,
#'   feature_info_list = list(metabolome = f1, microbiome = f2),
#'   match_cols = c(metabolome = "name", microbiome = "ID")
#' )
#' print(mo)
#' }
#'
#' @export
create_multiomics_data <- function(expr_list, sample_info,
                                   feature_info_list = NULL,
                                   match_cols = "name") {
  if (!is.list(expr_list) || length(expr_list) == 0) {
    stop("expr_list must be a non-empty named list of expression matrices.")
  }
  if (is.null(names(expr_list)) || any(names(expr_list) == "")) {
    stop("expr_list must be a named list; names are used as omics layer names.")
  }
  if (is.null(sample_info) || nrow(sample_info) == 0) {
    stop("sample_info must be a non-empty data.frame.")
  }
  
  layer_names <- names(expr_list)
  n_layers <- length(layer_names)
  
  # 解析每层的匹配列 -------------------------------------------
  if (length(match_cols) == 1 && is.null(names(match_cols))) {
    match_cols <- stats::setNames(rep(match_cols, n_layers), layer_names)
  } else if (!is.null(names(match_cols))) {
    missing_match <- setdiff(layer_names, names(match_cols))
    if (length(missing_match) > 0) {
      match_cols <- c(match_cols,
                      stats::setNames(rep("name", length(missing_match)),
                                      missing_match))
    }
    match_cols <- match_cols[layer_names]
  } else if (length(match_cols) == n_layers) {
    match_cols <- stats::setNames(match_cols, layer_names)
  } else {
    stop("match_cols must be length 1, length(expr_list), or a named vector.")
  }
  
  # 确定每层与元数据表共享的样本 --------
  common_samples <- rownames(sample_info)
  for (nm in layer_names) {
    mat <- expr_list[[nm]]
    if (is.null(colnames(mat))) {
      stop(sprintf("Expression matrix '%s' has no column (sample) names.", nm))
    }
    common_samples <- intersect(common_samples, colnames(mat))
  }
  
  if (length(common_samples) == 0) {
    stop("No samples are shared by all omics layers and the sample metadata.")
  }
  
  dropped <- nrow(sample_info) - length(common_samples)
  if (dropped > 0) {
    cat(sprintf("[multiomics] %d sample(s) dropped, not present in all layers.\n",
                dropped))
  }
  
  aligned_info <- sample_info[common_samples, , drop = FALSE]
  
  # 在对齐的样本集上为每个层构建一个 OmicsData -------------------
  omics <- vector("list", n_layers)
  names(omics) <- layer_names
  
  for (nm in layer_names) {
    mat <- expr_list[[nm]][, common_samples, drop = FALSE]
    
    finfo <- NULL
    if (!is.null(feature_info_list) && nm %in% names(feature_info_list)) {
      finfo <- feature_info_list[[nm]]
    }
    
    if (is.null(finfo)) {
      finfo <- data.frame(
        ID = rownames(mat),
        name = rownames(mat),
        type = "unknown",
        kegg = NA_character_,
        stringsAsFactors = FALSE
      )
      rownames(finfo) <- rownames(mat)
      this_match <- "name"
    } else {
      this_match <- match_cols[[nm]]
    }
    
    omics[[nm]] <- create_omics_data(
      expr_matrix = mat,
      sample_info = aligned_info,
      feature_info = finfo,
      match_col = this_match
    )
    
    kept <- omics[[nm]]$metadata$n_features
    lost <- nrow(mat) - kept
    if (lost > 0) {
      cat(sprintf("[multiomics] layer '%s': %d/%d features matched annotation (%d dropped).\n",
                  nm, kept, nrow(mat), lost))
    }
  }
  
  n_features <- vapply(omics, function(x) nrow(x$expression), integer(1))
  
  mo <- list(
    omics = omics,
    sample_info = aligned_info,
    common_samples = common_samples,
    metadata = list(
      n_omics = n_layers,
      omics_names = layer_names,
      n_samples = length(common_samples),
      n_features_per_omics = n_features
    )
  )
  
  class(mo) <- "MultiOmicsData"
  return(mo)
}


#' MultiOmicsData 对象的打印方法
#'
#' @description MultiOmicsData 对象的打印方法，显示各层维度和样本对齐情况。
#'
#' @param x 一个 MultiOmicsData 对象。
#' @param ... 额外参数（忽略）。
#'
#' @return 不可见的 MultiOmicsData 对象（仅用于打印）。
#'
#' @export
print.MultiOmicsData <- function(x, ...) {
  cat("=== OmicsFlow Multi-Omics Dataset ===\n")
  cat("Omics layers:", x$metadata$n_omics, "\n")
  cat("Common samples:", x$metadata$n_samples, "\n")
  cat("Layer details:\n")
  for (nm in x$metadata$omics_names) {
    om <- x$omics[[nm]]
    cat(sprintf("  - %-15s %6d features x %4d samples\n",
                nm, nrow(om$expression), ncol(om$expression)))
  }
  if (!is.null(x$sample_info$sample_info)) {
    cat("Group details:\n")
    group_tab <- table(x$sample_info$sample_info)
    for (g in names(group_tab)) {
      cat("  -", g, ":", group_tab[[g]], "samples\n")
    }
  }
  invisible(x)
}


#' 从 MultiOmicsData 对象中提取单个表达矩阵
#'
#' @description 从 MultiOmicsData 容器中提取指定组学层的表达矩阵。
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param name 组学层的名称。
#'
#' @return 一个数值矩阵（Feature x 样本）。
#'
#' @examples
#' \dontrun{
#' mat <- get_omics_matrix(mo, "metabolome")
#' }
#'
#' @export
get_omics_matrix <- function(mo, name) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (!name %in% names(mo$omics)) {
    stop(sprintf("Omics layer '%s' not found. Available: %s",
                 name, paste(names(mo$omics), collapse = ", ")))
  }
  return(mo$omics[[name]]$expression)
}


#' 从 MultiOmicsData 对象中提取全部表达矩阵
#'
#' @description 从 MultiOmicsData 容器中提取多个组学层的表达矩阵列表。
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param layers 可选字符向量，限定返回的层。默认：NULL（所有层）。
#'
#' @return 数值矩阵的有名列表（Feature x 样本）。
#'
#' @examples
#' \dontrun{
#' mats <- get_omics_list(mo)
#' }
#'
#' @export
get_omics_list <- function(mo, layers = NULL) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (is.null(layers)) layers <- names(mo$omics)
  missing_layers <- setdiff(layers, names(mo$omics))
  if (length(missing_layers) > 0) {
    stop(sprintf("Unknown omics layer(s): %s",
                 paste(missing_layers, collapse = ", ")))
  }
  out <- lapply(layers, function(nm) mo$omics[[nm]]$expression)
  names(out) <- layers
  return(out)
}


#' 提取某个组学层的Feature注释
#'
#' @description 从 MultiOmicsData 容器中提取指定组学层的特征注释表。
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param name 组学层的名称。
#'
#' @return 含Feature注释的 data.frame。
#'
#' @examples
#' \dontrun{
#' fi <- get_feature_info(mo, "transcriptome")
#' }
#'
#' @export
get_feature_info <- function(mo, name) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (!name %in% names(mo$omics)) {
    stop(sprintf("Omics layer '%s' not found.", name))
  }
  return(mo$omics[[name]]$feature_info)
}


#' 对所有组学层进行批量预处理
#'
#' @description 将标准的 OmicsFlow 预处理链路（缺失值过滤、插补、样本归一化与
#'   标准化）应用到 MultiOmicsData 对象的每一层。每个步骤都可在全局关闭，或针对
#'   特定层跳过。
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param filter 逻辑值，是否执行 \code{filter_missing_values()}。默认：TRUE。
#' @param filter_threshold 保留某一Feature所需的有效值最小比例。默认：0.5。
#' @param filter_method 过滤策略，"group" 或 "overall"。默认："group"。
#' @param group_col 组过滤所用的 sample_info 分组列。默认："sample_info"。
#' @param impute 逻辑值，是否执行 \code{impute_min_half()}。默认：TRUE。
#' @param normalize 逻辑值，是否执行 \code{normalize_sample_total()}。默认：TRUE。
#' @param scale 逻辑值，是否执行 \code{scale_pareto()}。默认：TRUE。
#' @param log_transform 逻辑值，标准化前是否应用 \code{log2(x + 1)}。默认：FALSE。
#' @param skip_normalize 字符向量，指定跳过样本总量归一化的层名
#'   （例如已归一化的层）。默认：NULL。
#'
#' @return 一个携带预处理后表达矩阵的 MultiOmicsData 对象。\code{preprocessing}
#'   元素记录了所执行的步骤及各层保留的Feature数。
#'
#' @examples
#' \dontrun{
#' mo_proc <- preprocess_multiomics(mo, filter_threshold = 0.5)
#' }
#'
#' @export
preprocess_multiomics <- function(mo,
                                  filter = TRUE,
                                  filter_threshold = 0.5,
                                  filter_method = "group",
                                  group_col = "sample_info",
                                  impute = TRUE,
                                  normalize = TRUE,
                                  scale = TRUE,
                                  log_transform = FALSE,
                                  skip_normalize = NULL) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  
  report <- data.frame(
    omics = character(0),
    n_features_before = integer(0),
    n_features_after = integer(0),
    stringsAsFactors = FALSE
  )
  
  for (nm in names(mo$omics)) {
    mat <- mo$omics[[nm]]$expression
    n_before <- nrow(mat)
    
    if (isTRUE(filter)) {
      flt <- tryCatch({
        filter_missing_values(
          expr_matrix = mat,
          sample_info = mo$sample_info,
          threshold = filter_threshold,
          method = filter_method,
          group_col = group_col
        )
      }, error = function(e) {
        cat(sprintf("[multiomics] layer '%s': filtering skipped (%s)\n",
                    nm, conditionMessage(e)))
        NULL
      })
      if (!is.null(flt)) mat <- flt$filtered_matrix
    }
    
    if (nrow(mat) == 0) {
      cat(sprintf("[multiomics] layer '%s': all features removed by filtering.\n", nm))
    }
    
    if (isTRUE(impute) && nrow(mat) > 0) {
      mat <- impute_min_half(mat)
    }
    
    if (isTRUE(normalize) && nrow(mat) > 0 && !(nm %in% skip_normalize)) {
      mat <- normalize_sample_total(mat)
    }
    
    if (isTRUE(log_transform) && nrow(mat) > 0) {
      mat <- log2(mat + 1)
    }
    
    if (isTRUE(scale) && nrow(mat) > 0) {
      mat <- scale_pareto(mat)
    }
    
    # 使Feature注释与保留下来的Feature保持一致
    finfo <- mo$omics[[nm]]$feature_info
    keep <- intersect(rownames(mat), rownames(finfo))
    if (length(keep) == nrow(mat)) {
      finfo <- finfo[rownames(mat), , drop = FALSE]
    }
    
    mo$omics[[nm]]$expression <- mat
    mo$omics[[nm]]$feature_info <- finfo
    mo$omics[[nm]]$metadata$n_features <- nrow(mat)
    
    report <- rbind(report, data.frame(
      omics = nm,
      n_features_before = n_before,
      n_features_after = nrow(mat),
      stringsAsFactors = FALSE
    ))
    
    cat(sprintf("[multiomics] layer '%s' preprocessed: %d -> %d features\n",
                nm, n_before, nrow(mat)))
  }
  
  mo$metadata$n_features_per_omics <-
    vapply(mo$omics, function(x) nrow(x$expression), integer(1))
  
  mo$preprocessing <- list(
    steps = c(
      if (isTRUE(filter)) "filter_missing_values",
      if (isTRUE(impute)) "impute_min_half",
      if (isTRUE(normalize)) "normalize_sample_total",
      if (isTRUE(log_transform)) "log2",
      if (isTRUE(scale)) "scale_pareto"
    ),
    report = report
  )
  
  return(mo)
}


#' 按样本对 MultiOmicsData 对象取子集
#'
#' @description 将每个组学层与样本元数据限制为样本的一个子集，例如某一地理区域
#'   或某一发酵阶段。
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param samples 要保留的样本 ID 字符向量。提供 \code{subset_col} 时忽略。
#' @param subset_col sample_info 中用于筛选的列名。默认：NULL。
#' @param subset_values 要保留的 \code{subset_col} 取值。默认：NULL。
#'
#' @return 限定为所选样本的 MultiOmicsData 对象。
#'
#' @examples
#' \dontrun{
#' mo_yn <- subset_multiomics(mo, subset_col = "location", subset_values = "Yunnan")
#' }
#'
#' @export
subset_multiomics <- function(mo, samples = NULL, subset_col = NULL,
                              subset_values = NULL) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  
  if (!is.null(subset_col)) {
    if (!subset_col %in% colnames(mo$sample_info)) {
      stop(sprintf("Column '%s' not found in sample_info.", subset_col))
    }
    if (is.null(subset_values)) {
      stop("subset_values must be supplied together with subset_col.")
    }
    keep <- rownames(mo$sample_info)[
      as.character(mo$sample_info[[subset_col]]) %in% as.character(subset_values)
    ]
  } else {
    if (is.null(samples)) stop("Either samples or subset_col must be supplied.")
    keep <- intersect(samples, mo$common_samples)
  }
  
  if (length(keep) == 0) {
    stop("No samples left after subsetting.")
  }
  
  mo$sample_info <- mo$sample_info[keep, , drop = FALSE]
  mo$common_samples <- keep
  for (nm in names(mo$omics)) {
    mo$omics[[nm]]$expression <- mo$omics[[nm]]$expression[, keep, drop = FALSE]
    mo$omics[[nm]]$sample_info <- mo$sample_info
    mo$omics[[nm]]$metadata$n_samples <- length(keep)
  }
  mo$metadata$n_samples <- length(keep)
  
  return(mo)
}


#' 从矩阵中移除零方差Feature
#'
#' @description 跨组学相关与整合函数使用的工具。零方差或方差未定义的Feature会产生
#'   NaN 相关，必须在分析前剔除。
#'
#' @param mat 数值矩阵（Feature x 样本）。
#' @param label 报告信息中使用的可选标签。默认："matrix"。
#' @param verbose 逻辑值，是否报告移除的Feature数。默认：TRUE。
#'
#' @return 不含零方差Feature的数值矩阵。
#'
#' @examples
#' \dontrun{
#' mat <- drop_zero_variance(mat, label = "metabolome")
#' }
#'
#' @export
drop_zero_variance <- function(mat, label = "matrix", verbose = TRUE) {
  if (!is.matrix(mat)) mat <- as.matrix(mat)
  v <- apply(mat, 1, function(x) stats::var(x, na.rm = TRUE))
  keep <- !is.na(v) & v > 0
  n_drop <- sum(!keep)
  if (n_drop > 0 && isTRUE(verbose)) {
    cat(sprintf("[multiomics] %s: %d zero-variance feature(s) removed.\n",
                label, n_drop))
  }
  return(mat[keep, , drop = FALSE])
}
