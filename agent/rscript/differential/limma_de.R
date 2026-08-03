# ==============================================================================
# OmicsFlow: Limma Differential Expression Analysis
# ==============================================================================
# Multiple strategies for differential analysis
# ==============================================================================

#' Run limma differential analysis
#'
#' @description Performs differential expression analysis using the limma
#'   package with empirical Bayes moderation. Supports multiple selection
#'   strategies for significant features.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param group_col Column name for group labels. Default: "sample_info".
#' @param control_group Character, name of control/reference group.
#'   Default: NULL (uses first group alphabetically).
#' @param case_groups Character vector, groups to compare against control.
#'   Default: NULL (all non-control groups).
#' @param exclude_groups Optional groups to exclude (e.g., "QC"). Default: "QC".
#' @param strategy Character, selection strategy:
#'   \itemize{
#'     \item \code{"pvalue_logFC"}: p-value + logFC threshold.
#'     \item \code{"pvalue_vip"}: p-value + VIP threshold.
#'     \item \code{"pvalue_topN"}: p-value significance + top N by logFC.
#'   }
#'   Default: "pvalue_logFC".
#' @param p_threshold P-value threshold. Default: 0.05.
#' @param logfc_threshold Absolute logFC threshold. Default: 1.
#' @param vip_threshold VIP threshold. Default: 1.0.
#' @param top_n Number of top features for "pvalue_topN" strategy. Default: 20.
#' @param p_adj_method P-value adjustment method. Default: "BH".
#' @param vip_result Optional VIP result from PLS-DA. Required for "pvalue_vip".
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{results}: Combined results data.frame.
#'     \item \code{significant}: Significant features data.frame.
#'     \item \code{comparisons}: List of per-comparison results.
#'     \item \code{strategy}: Strategy used.
#'   }
#'
#' @examples
#' \dontrun{
#' # Basic: p-value + logFC
#' de <- run_limma(expr_matrix, sample_info,
#'                 control_group = "Standard (control)",
#'                 strategy = "pvalue_logFC")
#'
#' # p-value + VIP
#' plsda <- run_plsda(expr_matrix, sample_info)
#' de <- run_limma(expr_matrix, sample_info,
#'                 strategy = "pvalue_vip",
#'                 vip_result = plsda$vip)
#'
#' # Top N by logFC
#' de <- run_limma(expr_matrix, sample_info,
#'                 strategy = "pvalue_topN", top_n = 30)
#' }
#'
#' @export
run_limma <- function(expr_matrix, sample_info, group_col = "sample_info",
                     control_group = NULL, case_groups = NULL,
                     exclude_groups = "QC", strategy = "pvalue_logFC",
                     p_threshold = 0.05, logfc_threshold = 1,
                     vip_threshold = 1.0, top_n = 20,
                     p_adj_method = "BH", vip_result = NULL) {
  # Align samples
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]

  # Exclude groups
  if (!is.null(exclude_groups)) {
    keep_samples <- rownames(sample_info)[!(sample_info[[group_col]] %in% exclude_groups)]
    expr_matrix <- expr_matrix[, keep_samples, drop = FALSE]
    sample_info <- sample_info[keep_samples, , drop = FALSE]
  }

  groups <- factor(sample_info[[group_col]])

  # Determine control and case groups
  if (is.null(control_group)) {
    control_group <- levels(groups)[1]
  }
  if (is.null(case_groups)) {
    case_groups <- setdiff(levels(groups), control_group)
  }

  # Sanitize group names for use in makeContrasts
  orig_levels <- levels(groups)
  safe_levels <- make.names(orig_levels)
  names(safe_levels) <- orig_levels
  groups_safe <- factor(groups, levels = orig_levels, labels = safe_levels)

  # Check limma availability
  if (requireNamespace("limma", quietly = TRUE)) {
    # Design matrix
    design <- stats::model.matrix(~ 0 + groups_safe)
    colnames(design) <- safe_levels

    # Fit model
    fit <- limma::lmFit(expr_matrix, design)

    # Contrast matrix
    safe_case <- safe_levels[orig_levels %in% case_groups]
    safe_control <- safe_levels[orig_levels == control_group]
    contrast_strs <- paste0(safe_case, " - ", safe_control)
    contrast_mat <- limma::makeContrasts(contrasts = contrast_strs,
                                          levels = design)
    colnames(contrast_mat) <- case_groups

    fit2 <- limma::contrasts.fit(fit, contrast_mat)
    fit2 <- limma::eBayes(fit2)

    # Extract results
    all_results <- list()
    for (cg in case_groups) {
      tt <- limma::topTable(fit2, coef = cg, number = Inf, sort.by = "none")
      tt$feature_id <- rownames(tt)
      tt$comparison <- paste0(cg, "_vs_", control_group)
      all_results[[cg]] <- tt
    }
    combined <- do.call(rbind, all_results)
    rownames(combined) <- NULL

  } else {
    # Fallback: use base R t-test
    warning("Package 'limma' not available. Using simple t-test.")
    combined <- .t_test_de(expr_matrix, groups, control_group, case_groups)
  }

  # Rename columns if needed
  colnames(combined)[colnames(combined) == "P.Value"] <- "p_value"
  colnames(combined)[colnames(combined) == "adj.P.Val"] <- "p_adj"
  colnames(combined)[colnames(combined) == "logFC"] <- "logFC"

  # Apply selection strategy
  if (strategy == "pvalue_logFC") {
    combined$significant <- combined$p_adj < p_threshold &
                            abs(combined$logFC) >= logfc_threshold
    combined$direction <- ifelse(combined$logFC > 0, "up", "down")

  } else if (strategy == "pvalue_vip") {
    if (is.null(vip_result)) {
      stop("vip_result is required for strategy = 'pvalue_vip'")
    }
    # Merge VIP
    vip_df <- vip_result
    colnames(vip_df)[2] <- "vip"
    combined <- merge(combined, vip_df, by = "feature_id", all.x = TRUE)
    combined$significant <- combined$p_adj < p_threshold &
                            combined$vip >= vip_threshold
    combined$direction <- ifelse(combined$logFC > 0, "up", "down")

  } else if (strategy == "pvalue_topN") {
    combined$significant <- FALSE
    combined$direction <- ifelse(combined$logFC > 0, "up", "down")
    for (comp in unique(combined$comparison)) {
      comp_idx <- combined$comparison == comp & combined$p_adj < p_threshold
      comp_data <- combined[comp_idx, ]
      if (nrow(comp_data) > 0) {
        # Sort by absolute logFC descending
        comp_data <- comp_data[order(abs(comp_data$logFC), decreasing = TRUE), ]
        top_idx <- head(rownames(comp_data), top_n)
        combined[top_idx, "significant"] <- TRUE
      }
    }
  }

  # Select significant
  sig_results <- combined[combined$significant, , drop = FALSE]

  # Set feature_id as row names (with comparison to ensure uniqueness)
  rownames(combined) <- make.unique(paste(combined$feature_id,
                                           combined$comparison, sep = "__"))
  combined$feature_id <- NULL

  return(list(
    results = combined,
    significant = sig_results,
    comparisons = all_results,
    strategy = strategy
  ))
}


#' Simple t-test DE (internal fallback)
#'
#' @keywords internal
#' @noRd
.t_test_de <- function(expr_matrix, groups, control_group, case_groups) {
  control_samples <- colnames(expr_matrix)[groups == control_group]
  results_list <- list()

  for (cg in case_groups) {
    case_samples <- colnames(expr_matrix)[groups == cg]
    for (i in 1:nrow(expr_matrix)) {
      control_vals <- expr_matrix[i, control_samples]
      case_vals <- expr_matrix[i, case_samples]

      tt <- stats::t.test(case_vals, control_vals)
      logfc <- log2(mean(case_vals) / mean(control_vals))

      results_list[[length(results_list) + 1]] <- data.frame(
        feature_id = rownames(expr_matrix)[i],
        logFC = logfc,
        p_value = tt$p.value,
        comparison = paste0(cg, "_vs_", control_group),
        stringsAsFactors = FALSE
      )
    }
  }

  combined <- do.call(rbind, results_list)
  combined$p_adj <- stats::p.adjust(combined$p_value, method = "BH")
  return(combined)
}
