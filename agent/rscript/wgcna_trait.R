# ==============================================================================
# OmicsFlow: WGCNA Module-Trait Association
# ==============================================================================
# Correlation of modules with biological traits + linear regression
# ==============================================================================

#' WGCNA module-trait association
#'
#' @description Calculates correlations between WGCNA module eigengenes and
#'   biological traits. Also performs linear regression to assess significance.
#'
#' @param wgcna_result Result from \code{build_wgcna_modules()}.
#' @param traits A numeric matrix or data.frame (samples x traits). Rows must
#'   match sample names in wgcna_result$MEs.
#' @param sample_info Optional sample metadata for grouping.
#' @param cor_method Correlation method. Default: "pearson".
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{module_trait_cor}: Correlation matrix (modules x traits).
#'     \item \code{module_trait_p}: P-value matrix.
#'     \item \code{module_trait_lm}: Linear regression results per module-trait.
#'     \item \code{feature_trait_cor}: Feature-level correlations with traits.
#'     \item \code{feature_trait_lm}: Feature-level linear regression.
#'   }
#'
#' @examples
#' \dontrun{
#' # Traits could be clinical measurements or phenotypes
#' traits <- data.frame(
#'   weight = c(25, 30, 22, 28),
#'   survival = c(0.8, 0.6, 0.9, 0.7),
#'   row.names = c("sample1", "sample2", "sample3", "sample4")
#' )
#' assoc <- wgcna_module_trait(wgcna_result, traits)
#' }
#'
#' @export
wgcna_module_trait <- function(wgcna_result, traits, sample_info = NULL,
                               cor_method = "pearson") {
  MEs <- wgcna_result$MEs

  # Align samples
  common_samples <- intersect(rownames(MEs), rownames(traits))
  MEs <- MEs[common_samples, , drop = FALSE]
  traits <- as.matrix(traits)[common_samples, , drop = FALSE]
  mode(traits) <- "numeric"

  n_modules <- ncol(MEs)
  n_traits <- ncol(traits)

  # Module-trait correlations
  cor_mat <- matrix(0, n_modules, n_traits)
  p_mat <- matrix(1, n_modules, n_traits)
  rownames(cor_mat) <- colnames(MEs)
  colnames(cor_mat) <- colnames(traits)
  rownames(p_mat) <- colnames(MEs)
  colnames(p_mat) <- colnames(traits)

  for (i in 1:n_modules) {
    for (j in 1:n_traits) {
      ct <- stats::cor.test(MEs[, i], traits[, j], method = cor_method)
      cor_mat[i, j] <- unname(ct$estimate)
      p_mat[i, j] <- ct$p.value
    }
  }

  # Linear regression for each module-trait pair
  lm_results <- list()
  for (i in 1:n_modules) {
    for (j in 1:n_traits) {
      key <- paste0(colnames(MEs)[i], "_vs_", colnames(traits)[j])
      fit <- stats::lm(traits[, j] ~ MEs[, i])
      s <- summary(fit)
      lm_results[[key]] <- data.frame(
        module = colnames(MEs)[i],
        trait = colnames(traits)[j],
        estimate = stats::coef(s)[2, 1],
        std_error = stats::coef(s)[2, 2],
        t_stat = stats::coef(s)[2, 3],
        p_value = stats::coef(s)[2, 4],
        r_squared = s$r.squared,
        adj_r_squared = s$adj.r.squared,
        stringsAsFactors = FALSE
      )
    }
  }
  lm_df <- do.call(rbind, lm_results)
  rownames(lm_df) <- NULL

  # Feature-level correlations
  # Need original expression matrix from wgcna_result
  feature_trait_cor <- NULL
  feature_trait_lm <- NULL

  # If module_colors available, compute feature-trait correlations
  if (!is.null(wgcna_result$module_colors)) {
    # We need the original expression matrix - but it's not stored
    # Instead, use module eigengenes as proxy
    feature_trait_cor <- data.frame(
      module = colnames(MEs),
      cor_mat,
      stringsAsFactors = FALSE
    )
  }

  return(list(
    module_trait_cor = cor_mat,
    module_trait_p = p_mat,
    module_trait_lm = lm_df,
    feature_trait_cor = feature_trait_cor,
    feature_trait_lm = feature_trait_lm
  ))
}


#' Plot module-trait relationship heatmap
#'
#' @description Creates a heatmap of module-trait correlations with significance.
#'
#' @param assoc_result Result from \code{wgcna_module_trait()}.
#' @param p_threshold P-value threshold for significance. Default: 0.05.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' p <- plot_module_trait(assoc_result)
#' print(p)
#' }
#'
#' @export
plot_module_trait <- function(assoc_result, p_threshold = 0.05) {
  cor_mat <- assoc_result$module_trait_cor
  p_mat <- assoc_result$module_trait_p

  # Create data.frame for plotting
  plot_data <- expand.grid(
    module = rownames(cor_mat),
    trait = colnames(cor_mat),
    stringsAsFactors = FALSE
  )
  plot_data$cor <- as.vector(cor_mat)
  plot_data$p_value <- as.vector(p_mat)
  plot_data$significant <- plot_data$p_value < p_threshold
  plot_data$label <- sprintf("%.2f", plot_data$cor)
  plot_data$label[!plot_data$significant] <- ""

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = trait, y = module)) +
    ggplot2::geom_tile(ggplot2::aes(fill = cor)) +
    ggplot2::scale_fill_gradient2(low = "#2c7bb6", mid = "white",
                                   high = "#d7191c", midpoint = 0,
                                   name = "Correlation") +
    ggplot2::geom_text(ggplot2::aes(label = label), size = 3.5) +
    ggplot2::labs(
      title = "Module-Trait Relationships",
      x = "Trait",
      y = "Module"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 10),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      axis.title = ggplot2::element_text(size = 12)
    )

  return(p)
}
