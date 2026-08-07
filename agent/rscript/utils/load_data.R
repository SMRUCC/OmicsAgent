# ==============================================================================
# OmicsFlow: 数据加载工具
# ==============================================================================
# 用于从 CSV 文件加载组学数据的函数
# ==============================================================================

#' 从 CSV 文件加载表达矩阵
#'
#' @description 从 CSV 文件加载表达矩阵，其中行为Feature（基因、代谢物等），
#'   列为样本。第一列包含Feature ID，第一行包含样本 ID。
#'
#' @param file 表达矩阵 CSV 文件的路径。
#' @param feature_id_col 含有Feature ID 的列名。若为 NULL，则使用第一列。默认：NULL。
#' @param na_values 解释为 NA 的字符串字符向量。默认：
#'   c("", "NA", "N/A", "null")。
#'
#' @return 一个数值矩阵，行为Feature、列为样本。行名为Feature ID，列名为样本 ID。
#'
#' @examples
#' \dontrun{
#' expr_mat <- load_expression_matrix("expression.csv")
#' }
#'
#' @export
load_expression_matrix <- function(file, feature_id_col = NULL,
                                    na_values = c("", "NA", "N/A", "null")) {
  df <- utils::read.csv(file, check.names = FALSE, stringsAsFactors = FALSE,
                        na.strings = na_values, row.names = NULL)

  if (is.null(feature_id_col)) {
    feature_ids <- as.character(df[, 1])
    df <- df[, -1, drop = FALSE]
  } else {
    feature_ids <- as.character(df[[feature_id_col]])
    df <- df[, !(colnames(df) == feature_id_col), drop = FALSE]
  }

  if (any(duplicated(feature_ids))) {
    warning("Duplicate feature IDs detected, making them unique.")
    feature_ids <- make.unique(feature_ids)
  }

  mat <- as.matrix(df)
  mode(mat) <- "numeric"
  rownames(mat) <- feature_ids
  colnames(mat) <- colnames(df)

  return(mat)
}


#' 从 CSV 文件加载样本元数据
#'
#' @description 从 CSV 文件加载样本元数据。必需列包括
#'   \code{ID}（与表达矩阵的列名对应）、\code{sample_name}
#'   （绘图时显示的标签）和 \code{sample_info}（分组标签）。
#'
#' @param file 样本元数据 CSV 文件的路径。
#'
#' @return 含有样本元数据的数据框。行名设为样本 ID。
#'
#' @examples
#' \dontrun{
#' sample_info <- load_sample_info("sampleinfo.csv")
#' }
#'
#' @export
load_sample_info <- function(file) {
  df <- utils::read.csv(file, check.names = FALSE, stringsAsFactors = FALSE)

  required_cols <- c("ID", "sample_name", "sample_info")
  missing_cols <- setdiff(required_cols, colnames(df))
  if (length(missing_cols) > 0) {
    stop(paste("Missing required columns in sample info: ",
               paste(missing_cols, collapse = ", ")))
  }

  rownames(df) <- as.character(df$ID)
  return(df)
}


#' 从 CSV 文件加载Feature注释
#'
#' @description 从 CSV 文件加载Feature注释。必需列包括
#'   \code{ID}（与表达矩阵的Feature ID 对应）、\code{name}（常用名）、
#'   \code{type}（Feature类别）和 \code{kegg}（KEGG 通路 ID）。
#'   可选列包括 \code{pfam} 和 \code{family}。
#'
#' @param file Feature注释 CSV 文件的路径。
#' @param id_col 用作Feature ID 的列名。默认："ID"。
#'
#' @return 含有Feature注释的数据框。行名设为Feature ID。
#'
#' @examples
#' \dontrun{
#' metab <- load_feature_info("metabolites.csv", id_col = "name")
#' }
#'
#' @export
load_feature_info <- function(file, id_col = "ID") {
  df <- utils::read.csv(file, check.names = FALSE, stringsAsFactors = FALSE)

  required_cols <- c(id_col, "name", "type", "kegg")
  missing_cols <- setdiff(required_cols, colnames(df))
  if (length(missing_cols) > 0) {
    # 尝试大小写不敏感的匹配
    colnames(df) <- tolower(colnames(df))
    id_col <- tolower(id_col)
    required_cols <- c(id_col, "name", "type", "kegg")
    missing_cols <- setdiff(required_cols, colnames(df))
    if (length(missing_cols) > 0) {
      stop(paste("Missing required columns in feature annotation:",
                 paste(missing_cols, collapse = ", ")))
    }
  }

  # 规范化 type 列 - 处理别名
  type_aliases <- list(
    gene = c("gene"),
    rna = c("rna", "transcript"),
    protein = c("protein", "proteome"),
    metabolite = c("metabolite", "metabolomics"),
    lipid = c("lipid", "lipidome", "lipidomics"),
    organism = c("organism", "microbiome"),
    bacterial = c("bacterial", "bacteria"),
    taxonomy = c("taxonomy", "taxon")
  )

  if ("type" %in% colnames(df)) {
    df$type <- tolower(df$type)
    for (canonical in names(type_aliases)) {
      df$type[df$type %in% type_aliases[[canonical]]] <- canonical
    }
  }

  # 重复 ID 兜底：与 load_expression_matrix() 行为保持一致
  # （对重复 id 做 make.unique 并给出警告，而非直接 stop）。
  # 注意：原始输入可能存在 Excel 损坏值（如 "#NAME?"）造成的重复，
  # 此处统一用 make.unique 保证行名唯一，避免后续行名赋值直接报错。
  id_vals <- as.character(df[[id_col]])
  if (any(duplicated(id_vals))) {
    warning(sprintf("Duplicate values in id_col='%s' (%d 个)，已通过 make.unique 去重。",
                    id_col, sum(duplicated(id_vals))))
    id_vals <- make.unique(id_vals)
  }
  rownames(df) <- id_vals
  return(df)
}


#' Create OmicsData object from loaded data
#'
#' @description Convenience function to combine expression matrix, sample
#'   metadata, and feature annotation into an aligned OmicsData object.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param feature_info A data.frame with feature annotation.
#' @param match_col Column name in feature_info matching row names of
#'   expr_matrix. Default: "name".
#'
#' @return An OmicsData object (list) with:
#'   \itemize{
#'     \item \code{expression}: Numeric matrix.
#'     \item \code{sample_info}: Sample metadata data.frame.
#'     \item \code{feature_info}: Feature annotation data.frame.
#'     \item \code{metadata}: List with dataset info.
#'   }
#'
#' @examples
#' \dontrun{
#' omics <- create_omics_data(expr_mat, sample_info, feat_info, match_col = "name")
#' print(omics)
#' }
#'
#' @export
create_omics_data <- function(expr_matrix, sample_info, feature_info,
                              match_col = "name") {
  # Align samples
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  if (length(common_samples) == 0) {
    stop("No common sample IDs between expression matrix and sample info.")
  }

  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]

  # Align features
  if (match_col == "rownames" || match_col == "ID") {
    annot_ids <- rownames(feature_info)
  } else {
    annot_ids <- as.character(feature_info[[match_col]])
  }

  matched_idx <- match(rownames(expr_matrix), annot_ids)
  matched_count <- sum(!is.na(matched_idx))

  matched_annot <- feature_info[matched_idx[!is.na(matched_idx)], , drop = FALSE]
  matched_matrix <- expr_matrix[!is.na(matched_idx), , drop = FALSE]

  if (nrow(matched_annot) == nrow(matched_matrix)) {
    rownames(matched_annot) <- rownames(matched_matrix)
  }

  omics_data <- list(
    expression = matched_matrix,
    sample_info = sample_info,
    feature_info = matched_annot,
    metadata = list(
      n_features = nrow(matched_matrix),
      n_samples = ncol(matched_matrix),
      n_groups = length(unique(sample_info$sample_info)),
      groups = unique(as.character(sample_info$sample_info)),
      matched_features = matched_count,
      unmatched_features = sum(is.na(matched_idx)),
      match_col = match_col
    )
  )

  class(omics_data) <- "OmicsData"
  return(omics_data)
}


#' Print method for OmicsData object
#'
#' @description OmicsData 对象的打印方法，显示特征数、样本数、
#'   分组信息和匹配统计。
#'
#' @param x An OmicsData object.
#' @param ... Additional arguments (ignored).
#'
#' @return 不可见的 OmicsData 对象（仅用于打印）。
#'
#' @export
print.OmicsData <- function(x, ...) {
  cat("=== OmicsFlow Dataset ===\n")
  cat("Features:", x$metadata$n_features, "\n")
  cat("Samples:", x$metadata$n_samples, "\n")
  cat("Groups:", x$metadata$n_groups, "\n")
  cat("Group details:\n")
  group_tab <- table(x$sample_info$sample_info)
  for (g in names(group_tab)) {
    cat("  -", g, ":", group_tab[g], "samples\n")
  }
  # 使用完整字段名，避免依赖 `$` 的部分匹配（partial matching）
  n_matched <- x$metadata$matched_features
  n_unmatched <- x$metadata$unmatched_features
  if (is.null(n_matched)) n_matched <- 0L
  if (is.null(n_unmatched)) n_unmatched <- 0L
  cat("Matched features:", n_matched, "/", n_matched + n_unmatched, "\n")
  invisible(x)
}
