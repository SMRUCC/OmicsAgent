# ==============================================================================
# OmicsFlow: Linear Regression Model
# ==============================================================================
# Sample classification using linear regression
# ==============================================================================

#' Run linear regression classification model
#'
#' @description Builds a linear regression model for sample group prediction.
#'   For binary classification, uses logistic regression. For multi-class,
#'   uses multinomial logistic regression.
#'
#'   In addition, per-feature univariate ordinary least squares (OLS) regression
#'   is performed for each comparison (control group encoded as a=0 vs each
#'   other group encoded as b=1). The response variable y is the numeric group
#'   encoding and x is the feature abundance. Full statistics (slope, intercept,
#'   R2, adjusted R2, p-value, linear equation string, comparison label) are
#'   returned in the \code{coefficients} table.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param group_col Column name for group labels. Default: "sample_info".
#' @param exclude_groups Optional groups to exclude. Default: "QC".
#' @param control_group Character, reference group. Samples in this group are
#'   encoded as a=0 in each linear regression comparison. Default: NULL (uses
#'   the first factor level).
#' @param top_features Optional character vector of features to use. If NULL,
#'   uses all features. Default: NULL.
#' @param cv_folds Number of cross-validation folds. Default: 5.
#' @param seed Random seed. Default: 42.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{model}: Fitted classification model.
#'     \item \code{coefficients}: Per-feature univariate linear regression
#'       results (data.frame). Columns:
#'       \code{feature_id} feature name;
#'       \code{comparison} group comparison label, e.g.
#'         "Standard (control)(a=0) vs Clostridium difficile infection(b=1)";
#'       \code{slope} regression slope (a in y = a*x + b);
#'       \code{intercept} regression intercept (b in y = a*x + b);
#'       \code{r2} R-squared;
#'       \code{adj_r2} adjusted R-squared;
#'       \code{p_value} p-value of the slope;
#'       \code{p_adj} BH-adjusted p-value within each comparison;
#'       \code{n} number of samples used in the comparison;
#'       \code{equation} linear equation string, e.g. "y = 0.4275*x + 0.5388".
#'     \item \code{classification_coefficients}: Coefficients of the
#'       classification model (columns: group, feature, coefficient).
#'     \item \code{accuracy}: Classification accuracy.
#'     \item \code{predictions}: Predicted labels.
#'     \item \code{confusion_matrix}: Confusion matrix.
#'   }
#'
#' @examples
#' \dontrun{
#' lr <- run_linear_model(expr_matrix, sample_info)
#' print(lr$accuracy)
#' print(lr$coefficients)
#' }
#'
#' @export
run_linear_model <- function(expr_matrix, sample_info,
                            group_col = "sample_info",
                            exclude_groups = "QC", control_group = NULL,
                            top_features = NULL, cv_folds = 5, seed = 42) {
  set.seed(seed)

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
  if (!is.null(control_group)) {
    groups <- stats::relevel(groups, ref = control_group)
  }

  X <- t(as.matrix(expr_matrix))

  # Select top features if specified
  if (!is.null(top_features)) {
    top_features <- intersect(top_features, colnames(X))
    X <- X[, top_features, drop = FALSE]
  }

  # Keep original feature names before make.names (to restore in output)
  orig_feat_names <- colnames(X)

  # Build data.frame
  X <- as.matrix(X)
  colnames(X) <- make.names(colnames(X), unique = TRUE)
  safe_feat_names <- colnames(X)
  feat_name_map <- stats::setNames(orig_feat_names, safe_feat_names)
  data_df <- as.data.frame(X)
  data_df$group <- groups

  # Determine model type
  n_groups <- nlevels(groups)

  if (n_groups == 2) {
    # Binary: logistic regression
    formula_str <- "group ~ ."
    model <- stats::glm(as.formula(formula_str), data = data_df,
                        family = stats::binomial())
    predictions <- stats::predict(model, type = "response")
    predicted_class <- ifelse(predictions > 0.5, levels(groups)[2],
                              levels(groups)[1])
    predicted_class <- factor(predicted_class, levels = levels(groups))
  } else {
    # Multi-class: multinomial
    if (requireNamespace("nnet", quietly = TRUE)) {
      formula_str <- "group ~ ."
      model <- nnet::multinom(as.formula(formula_str), data = data_df,
                               trace = FALSE)
      predictions <- stats::predict(model, type = "class")
      predicted_class <- factor(predictions, levels = levels(groups))
    } else {
      # Fallback: LDA
      if (requireNamespace("MASS", quietly = TRUE)) {
        model <- MASS::lda(x = X, grouping = groups)
        predictions <- stats::predict(model, X)$class
        predicted_class <- factor(predictions, levels = levels(groups))
      } else {
        stop("Either 'nnet' or 'MASS' package is required for multi-class.")
      }
    }
  }

  # Accuracy
  accuracy <- mean(predicted_class == groups)
  conf_mat <- as.matrix(table(Predicted = predicted_class, Actual = groups))

  # Classification coefficients (kept for backward compatibility)
  class_coefs <- stats::coef(model)
  if (is.list(class_coefs)) {
    class_coef_df <- do.call(rbind, lapply(names(class_coefs), function(n) {
      data.frame(group = n, feature = names(class_coefs[[n]]),
                 coefficient = class_coefs[[n]], stringsAsFactors = FALSE)
    }))
    rownames(class_coef_df) <- NULL
  } else if (is.matrix(class_coefs)) {
    if (length(rownames(class_coefs)) > 1 &&
        all(rownames(class_coefs) %in% levels(groups))) {
      # Rows are group levels (multinomial logit)
      class_coef_df <- do.call(rbind, lapply(rownames(class_coefs), function(g) {
        data.frame(group = g, feature = colnames(class_coefs),
                   coefficient = as.numeric(class_coefs[g, ]),
                   stringsAsFactors = FALSE)
      }))
    } else {
      # Rows are features (e.g. LDA scaling), columns are group levels
      class_coef_df <- do.call(rbind, lapply(colnames(class_coefs), function(g) {
        data.frame(group = g, feature = rownames(class_coefs),
                   coefficient = as.numeric(class_coefs[, g]),
                   stringsAsFactors = FALSE)
      }))
    }
    rownames(class_coef_df) <- NULL
  } else {
    class_coef_df <- data.frame(
      group = levels(groups)[1],
      feature = names(class_coefs),
      coefficient = as.numeric(class_coefs),
      stringsAsFactors = FALSE
    )
    rownames(class_coef_df) <- NULL
  }

  # ============================================================================
  # Per-feature univariate linear regression:
  #   y = 0/1 group encoding (control a=0, each other group b=1)
  #   x = single feature abundance
  #   for each comparison: fit y ~ x and export slope/intercept/R2/adjR2/pvalue
  # ============================================================================
  ref_group <- levels(groups)[1]
  case_groups <- levels(groups)[-1]

  lm_parts <- list()
  for (cg in case_groups) {
    # Keep only samples belonging to the two groups of this comparison
    idx <- groups %in% c(ref_group, cg)
    x_sub <- X[idx, , drop = FALSE]
    y <- ifelse(as.character(groups[idx]) == cg, 1, 0)
    n <- length(y)
    if (n < 3 || length(unique(y)) < 2) {
      warning("Skipping comparison '", ref_group, "' vs '", cg,
              "': not enough samples for linear regression.")
      next
    }
    comparison_label <- paste0(ref_group, "(a=0) vs ", cg, "(b=1)")

    comp_rows <- lapply(seq_len(ncol(x_sub)), function(j) {
      safe_name <- colnames(x_sub)[j]
      feat_id <- if (safe_name %in% names(feat_name_map)) {
        feat_name_map[[safe_name]]
      } else {
        safe_name
      }
      x <- x_sub[, j]

      fit <- tryCatch(stats::lm(y ~ x), error = function(e) NULL)
      if (is.null(fit)) {
        warning("Linear regression failed for feature '", feat_id,
                "' in comparison '", comparison_label, "'.")
        return(data.frame(
          feature_id = feat_id, comparison = comparison_label,
          slope = NA_real_, intercept = NA_real_,
          r2 = NA_real_, adj_r2 = NA_real_,
          p_value = NA_real_, p_adj = NA_real_,
          n = as.integer(n), equation = NA_character_,
          stringsAsFactors = FALSE
        ))
      }

      s <- summary(fit)
      slope <- unname(stats::coef(fit)[2])
      intercept <- unname(stats::coef(fit)[1])
      r2 <- s$r.squared
      adj_r2 <- s$adj.r.squared
      p_value <- if (nrow(s$coefficients) >= 2) s$coefficients[2, 4] else NA_real_
      # Equation string "y = a*x + b" (handles negative intercept sign)
      eq_slope <- formatC(slope, format = "g", digits = 4)
      eq_intercept <- formatC(abs(intercept), format = "g", digits = 4)
      eq_sign <- ifelse(intercept < 0, "-", "+")
      equation <- paste0("y = ", eq_slope, "*x ", eq_sign, " ", eq_intercept)

      data.frame(
        feature_id = feat_id, comparison = comparison_label,
        slope = slope, intercept = intercept,
        r2 = r2, adj_r2 = adj_r2,
        p_value = p_value, p_adj = NA_real_,
        n = as.integer(n), equation = equation,
        stringsAsFactors = FALSE
      )
    })

    comp_df <- do.call(rbind, comp_rows)
    # BH adjust p-values within this comparison
    non_na <- !is.na(comp_df$p_value)
    if (any(non_na)) {
      comp_df$p_adj[non_na] <- stats::p.adjust(comp_df$p_value[non_na],
                                               method = "BH")
    }
    lm_parts[[cg]] <- comp_df
  }

  if (length(lm_parts) == 0) {
    coef_df <- data.frame(
      feature_id = character(0), comparison = character(0),
      slope = numeric(0), intercept = numeric(0),
      r2 = numeric(0), adj_r2 = numeric(0),
      p_value = numeric(0), p_adj = numeric(0),
      n = integer(0), equation = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    coef_df <- do.call(rbind, lm_parts)
    rownames(coef_df) <- NULL
  }

  return(list(
    model = model,
    coefficients = coef_df,
    classification_coefficients = class_coef_df,
    accuracy = accuracy,
    predictions = predicted_class,
    confusion_matrix = conf_mat
  ))
}
