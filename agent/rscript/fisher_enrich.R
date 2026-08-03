# ==============================================================================
# OmicsFlow: Fisher Enrichment Test
# ==============================================================================
# Fisher's exact test for over-representation analysis
# ==============================================================================

#' Fisher's exact enrichment test
#'
#' @description Performs Fisher's exact test to assess over-representation of
#'   categories (e.g., KEGG pathways, families, classes) among significant
#'   features compared to all measured features.
#'
#' @param significant_features Character vector of significant feature IDs.
#' @param all_features Character vector of all feature IDs (background).
#' @param feature_info Data.frame with feature annotations.
#' @param feature_id_col Column name for feature IDs in feature_info. Default: "ID".
#' @param category_col Column name for category (e.g., "kegg", "family", "class").
#' @param p_adj_method P-value adjustment method. Default: "BH".
#' @param min_size Minimum category size. Default: 2.
#'
#' @return A data.frame with:
#'   \itemize{
#'     \item \code{category}: Category name.
#'     \item \code{sig_count}: Count in significant set.
#'     \item \code{sig_total}: Total significant features.
#'     \item \code{bg_count}: Count in background.
#'     \item \code{bg_total}: Total background features.
#'     \item \code{p_value}: Raw p-value.
#'     \item \code{p_adj}: Adjusted p-value.
#'     \item \code{fold_enrichment}: Fold enrichment.
#'   }
#'
#' @examples
#' \dontrun{
#' # Test KEGG pathway enrichment
#' enrich <- run_fisher_enrich(
#'   significant_features = c("feature1", "feature2", "feature3"),
#'   all_features = rownames(expr_matrix),
#'   feature_info = metabolites_info,
#'   category_col = "kegg"
#' )
#' head(enrich)
#' }
#'
#' @export
run_fisher_enrich <- function(significant_features, all_features,
                              feature_info, feature_id_col = "ID",
                              category_col = "kegg",
                              p_adj_method = "BH", min_size = 2) {
  # Ensure feature_info rownames match
  if (feature_id_col %in% colnames(feature_info)) {
    rownames(feature_info) <- feature_info[[feature_id_col]]
  }

  # Get categories for significant and background features
  sig_categories <- feature_info[intersect(significant_features,
                                            rownames(feature_info)), category_col]
  bg_categories <- feature_info[intersect(all_features,
                                          rownames(feature_info)), category_col]

  # Remove NAs and empty strings
  sig_categories <- sig_categories[!is.na(sig_categories) & sig_categories != ""]
  bg_categories <- bg_categories[!is.na(bg_categories) & bg_categories != ""]

  # Count categories
  sig_counts <- table(sig_categories)
  bg_counts <- table(bg_categories)

  # Get all unique categories
  all_categories <- unique(c(names(sig_counts), names(bg_counts)))

  # Build contingency table for each category
  n_sig <- length(sig_categories)
  n_bg <- length(bg_categories)

  results <- data.frame(
    category = character(),
    sig_count = integer(),
    sig_total = integer(),
    bg_count = integer(),
    bg_total = integer(),
    p_value = numeric(),
    fold_enrichment = numeric(),
    stringsAsFactors = FALSE
  )

  for (cat in all_categories) {
    cat_sig <- as.numeric(sig_counts[cat])
    if (is.na(cat_sig)) cat_sig <- 0
    cat_bg <- as.numeric(bg_counts[cat])
    if (is.na(cat_bg)) cat_bg <- 0

    # Skip if too small
    if (cat_sig < min_size) next

    not_cat_sig <- n_sig - cat_sig
    not_cat_bg <- n_bg - cat_bg

    # Fisher's exact test
    contingency <- matrix(c(cat_sig, not_cat_sig, cat_bg, not_cat_bg), nrow = 2)
    ft <- stats::fisher.test(contingency, alternative = "greater")

    # Fold enrichment
    expected <- (cat_sig + cat_bg) * n_sig / (n_sig + n_bg)
    fold <- if (expected > 0) cat_sig / expected else 0

    results <- rbind(results, data.frame(
      category = cat,
      sig_count = cat_sig,
      sig_total = n_sig,
      bg_count = cat_bg,
      bg_total = n_bg,
      p_value = ft$p.value,
      fold_enrichment = fold,
      stringsAsFactors = FALSE
    ))
  }

  # Adjust p-values
  results$p_adj <- stats::p.adjust(results$p_value, method = p_adj_method)

  # Sort by p-value
  results <- results[order(results$p_value), ]
  rownames(results) <- make.unique(as.character(results$category))
  results$category <- NULL

  return(results)
}


#' Plot enrichment results
#'
#' @description Creates a bar plot of enrichment results showing fold enrichment
#'   and significance.
#'
#' @param enrich_result Result from \code{run_fisher_enrich()}.
#' @param top_n Number of top categories to show. Default: 20.
#' @param p_threshold P-value threshold for significance. Default: 0.05.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' enrich <- run_fisher_enrich(...)
#' p <- plot_enrichment(enrich, top_n = 15)
#' print(p)
#' }
#'
#' @export
plot_enrichment <- function(enrich_result, top_n = 20, p_threshold = 0.05) {
  top_df <- head(enrich_result, top_n)
  top_df$category <- factor(rownames(top_df), levels = rownames(top_df))

  p <- ggplot2::ggplot(top_df, ggplot2::aes(x = category, y = fold_enrichment,
                                            fill = p_adj < p_threshold)) +
    ggplot2::geom_bar(stat = "identity") +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = c("FALSE" = "grey70", "TRUE" = "#e74c3c"),
                                name = "Significant",
                                labels = c("Not Sig", paste0("p_adj < ", p_threshold))) +
    ggplot2::labs(
      title = "Enrichment Analysis",
      x = "Category",
      y = "Fold Enrichment"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 9),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right"
    )

  return(p)
}
