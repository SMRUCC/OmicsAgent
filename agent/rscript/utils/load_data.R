# ==============================================================================
# OmicsFlow: Data Loading Utilities
# ==============================================================================
# Functions for loading omics data from CSV files
# ==============================================================================

#' Load expression matrix from CSV file
#'
#' @description Loads an expression matrix from a CSV file where rows are
#'   features (genes, metabolites, etc.) and columns are samples. The first
#'   column contains feature IDs and the first row contains sample IDs.
#'
#' @param file Path to the expression matrix CSV file.
#' @param feature_id_col Name of the column containing feature IDs. If NULL,
#'   uses the first column. Default: NULL.
#' @param na_values Character vector of strings to interpret as NA. Default:
#'   c("", "NA", "N/A", "null").
#'
#' @return A numeric matrix with features as rows and samples as columns.
#'   Row names are feature IDs, column names are sample IDs.
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
    warning("Duplicate feature IDs detected. Making unique.")
    feature_ids <- make.unique(feature_ids)
  }

  mat <- as.matrix(df)
  mode(mat) <- "numeric"
  rownames(mat) <- feature_ids
  colnames(mat) <- colnames(df)

  return(mat)
}


#' Load sample metadata from CSV file
#'
#' @description Loads sample metadata from a CSV file. Required columns are
#'   \code{ID} (matching expression matrix column names), \code{sample_name}
#'   (display label for plots), and \code{sample_info} (grouping label).
#'
#' @param file Path to the sample metadata CSV file.
#'
#' @return A data.frame with sample metadata. Row names are set to sample IDs.
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
    stop(paste("Missing required columns in sample info:",
               paste(missing_cols, collapse = ", ")))
  }

  rownames(df) <- as.character(df$ID)
  return(df)
}


#' Load feature annotation from CSV file
#'
#' @description Loads feature annotation from a CSV file. Required columns are
#'   \code{ID} (matching expression matrix feature IDs), \code{name} (common
#'   name), \code{type} (feature category), and \code{kegg} (KEGG pathway ID).
#'   Optional columns include \code{pfam} and \code{family}.
#'
#' @param file Path to the feature annotation CSV file.
#' @param id_col Column name to use as feature ID. Default: "ID".
#'
#' @return A data.frame with feature annotation. Row names are set to feature IDs.
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
    # Try case-insensitive matching
    colnames(df) <- tolower(colnames(df))
    id_col <- tolower(id_col)
    required_cols <- c(id_col, "name", "type", "kegg")
    missing_cols <- setdiff(required_cols, colnames(df))
    if (length(missing_cols) > 0) {
      stop(paste("Missing required columns in feature annotation:",
                 paste(missing_cols, collapse = ", ")))
    }
  }

  # Normalize type column - handle aliases
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

  rownames(df) <- as.character(df[[id_col]])
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
#' @param x An OmicsData object.
#' @param ... Additional arguments (ignored).
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
  cat("Matched features:", x$metadata$matched, "/",
      x$metadata$matched + x$metadata$unmatched, "\n")
  invisible(x)
}
