# ==============================================================================
# OmicsFlow: PLS-PM (Partial Least Squares Path Modeling)
# ==============================================================================
# Multi-omics or single-omics latent variable network
# ==============================================================================

#' Run PLS-PM analysis
#'
#' @description Performs Partial Least Squares Path Modeling to construct
#'   networks of latent variables from observed feature groups (e.g., families
#'   or KEGG pathways). Suitable for multi-omics integration.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param feature_info Data.frame with feature annotations.
#' @param latent_def Named list where each element is a character vector of
#'   feature IDs or a column name from feature_info defining the latent variable.
#'   E.g., \code{list(Metabolism = "kegg", Lipids = "super_class")}.
#' @param inner_model Optional matrix defining relationships between latent
#'   variables. If NULL, all latent variables are connected. Default: NULL.
#' @param feature_id_col Column name for feature IDs. Default: "ID".
#' @param ncomp Number of PLS components. Default: 2.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{scores}: Latent variable scores (samples x latent vars).
#'     \item \code{outer_model}: Loadings of features on latent variables.
#'     \item \code{inner_model}: Path coefficients between latent variables.
#'     \item \code{path_coefficients}: Matrix of path coefficients.
#'   }
#'
#' @examples
#' \dontrun{
#' # Define latent variables by KEGG pathway
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

  # Align feature info
  if (feature_id_col %in% colnames(feature_info)) {
    rownames(feature_info) <- feature_info[[feature_id_col]]
  }
  common_features <- intersect(rownames(expr_matrix), rownames(feature_info))

  # Build latent variable data
  latent_scores <- list()
  outer_loadings <- list()

  for (lv_name in names(latent_def)) {
    lv_def <- latent_def[[lv_name]]

    if (length(lv_def) == 1 && lv_def %in% colnames(feature_info)) {
      # Group by column
      lv_features <- common_features[
        feature_info[common_features, lv_def] == lv_def[1]
      ]
    } else {
      lv_features <- intersect(lv_def, common_features)
    }

    if (length(lv_features) < 2) next

    # PCA to get latent score
    sub_mat <- t(as.matrix(expr_matrix[lv_features, , drop = FALSE]))
    pca_result <- stats::prcomp(sub_mat, scale. = TRUE, center = TRUE)
    latent_scores[[lv_name]] <- pca_result$x[, 1]

    # Loadings
    outer_loadings[[lv_name]] <- data.frame(
      feature_id = lv_features,
      loading = pca_result$rotation[, 1],
      stringsAsFactors = FALSE
    )
  }

  # Combine scores
  scores_df <- as.data.frame(do.call(cbind, latent_scores))
  rownames(scores_df) <- colnames(expr_matrix)

  # Inner model: path coefficients
  lv_names <- names(latent_scores)
  n_lv <- length(lv_names)

  if (is.null(inner_model)) {
    # All-to-all path coefficients
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

  # Outer model
  outer_model <- do.call(rbind, lapply(names(outer_loadings), function(lv) {
    df <- outer_loadings[[lv]]
    df$latent_variable <- lv
    return(df)
  }))

  # Inner model summary
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


#' Plot PLS-PM path diagram
#'
#' @description Creates a path diagram showing latent variables and their
#'   relationships.
#'
#' @param plspm_result Result from \code{run_plspm()}.
#' @param p_threshold P-value threshold for significance. Default: 0.05.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' result <- run_plspm(expr_matrix, feature_info, latent_def)
#' p <- plot_plspm_network(result)
#' print(p)
#' }
#'
#' @export
plot_plspm_network <- function(plspm_result, p_threshold = 0.05) {
  scores <- plspm_result$scores
  inner <- plspm_result$inner_model

  lv_names <- colnames(scores)
  n_lv <- length(lv_names)

  # Layout in circle
  angles <- seq(0, 2 * pi, length.out = n_lv + 1)[1:n_lv]
  node_pos <- data.frame(
    node = lv_names,
    x = cos(angles),
    y = sin(angles),
    stringsAsFactors = FALSE
  )

  # Edge data
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
