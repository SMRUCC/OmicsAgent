# ==============================================================================
# OmicsFlow: Multi-factor ANOVA
# ==============================================================================
# Multi-factor ANOVA for overall differential analysis
# ==============================================================================

#' Multi-factor ANOVA analysis
#'
#' @description Performs multi-factor ANOVA for each feature, allowing
#'   multiple factors (e.g., treatment, time, batch) to be tested simultaneously.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param factors Character vector of column names to use as factors.
#'   Default: "sample_info".
#' @param exclude_groups Optional named list specifying groups to exclude per
#'   factor. E.g., \code{list(sample_info = "QC")}. Default: NULL.
#' @param p_adj_method P-value adjustment method. Default: "BH".
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{results}: Data.frame with feature_id, F-stat, p-value, p_adj
#'       for each factor.
#'     \item \code{factor_results}: List of data.frames per factor.
#'   }
#'
#' @examples
#' \dontrun{
#' # Single factor
#' anova_result <- run_anova(expr_matrix, sample_info, factors = "sample_info")
#'
#' # Multi-factor
#' anova_result <- run_anova(expr_matrix, sample_info,
#'                           factors = c("sample_info", "condition"))
#' }
#'
#' @export
run_anova <- function(expr_matrix, sample_info, factors = "sample_info",
                     exclude_groups = NULL, p_adj_method = "BH") {
  # Align samples
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]

  # Exclude groups
  if (!is.null(exclude_groups)) {
    for (fac in names(exclude_groups)) {
      if (fac %in% colnames(sample_info)) {
        excl <- exclude_groups[[fac]]
        keep <- !(sample_info[[fac]] %in% excl)
        expr_matrix <- expr_matrix[, keep, drop = FALSE]
        sample_info <- sample_info[keep, , drop = FALSE]
      }
    }
  }

  # Ensure factors are factors
  for (f in factors) {
    if (f %in% colnames(sample_info)) {
      sample_info[[f]] <- factor(sample_info[[f]])
    }
  }

  # Build formula
  formula_str <- paste0("value ~ ", paste(factors, collapse = " * "))
  formula_obj <- as.formula(formula_str)

  n_features <- nrow(expr_matrix)
  n_factors <- length(factors)

  # Results storage
  factor_results <- list()

  for (i in 1:n_features) {
    data_tmp <- data.frame(
      value = expr_matrix[i, ],
      sample_info,
      stringsAsFactors = FALSE
    )

    fit <- stats::aov(formula_obj, data = data_tmp)
    anova_summary <- summary(fit)[[1]]

    for (j in 1:n_factors) {
      fac <- factors[j]
      if (fac %in% rownames(anova_summary)) {
        if (is.null(factor_results[[fac]])) {
          factor_results[[fac]] <- data.frame(
            feature_id = character(n_features),
            F_stat = numeric(n_features),
            p_value = numeric(n_features),
            stringsAsFactors = FALSE
          )
        }
        factor_results[[fac]]$feature_id[i] <- rownames(expr_matrix)[i]
        factor_results[[fac]]$F_stat[i] <- anova_summary[fac, "F value"]
        factor_results[[fac]]$p_value[i] <- anova_summary[fac, "Pr(>F)"]
      }
    }
  }

  # Adjust p-values
  for (fac in names(factor_results)) {
    factor_results[[fac]]$p_adj <- stats::p.adjust(factor_results[[fac]]$p_value,
                                                     method = p_adj_method)
    factor_results[[fac]]$significant <- factor_results[[fac]]$p_adj < 0.05
  }

  # Combined results
  combined <- do.call(rbind, lapply(names(factor_results), function(fac) {
    df <- factor_results[[fac]]
    df$factor <- fac
    return(df)
  }))

  # Set feature_id as row names (may have duplicates from multiple factors,
  # so create unique row names)
  rownames(combined) <- make.unique(combined$feature_id)
  combined$feature_id <- NULL

  return(list(
    results = combined,
    factor_results = factor_results
  ))
}
