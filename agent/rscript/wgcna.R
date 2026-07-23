# ============================================================
# Required packages
# ============================================================
library(WGCNA)
library(stats)
library(ggplot2)
library(grDevices)
library(reshape2)

#' @title Build WGCNA Co-expression Modules
#'
#' @description
#' 构建WGCNA（Weighted Gene Co-expression Network Analysis）共表达模块。
#' WGCNA通过计算feature之间的相关性，将高度相关的feature聚类为模块，
#' 用于发现生物学功能相关的feature集合。
#'
#' 该函数执行完整的WGCNA流程：软阈值选择、邻接矩阵构建、TOM计算、
#' 层次聚类和模块识别。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param min_module_size 整数，最小模块大小，默认30
#' @param merge_cut_height 数值，模块合并阈值，默认0.25
#' @param power 整数，软阈值（可选，默认自动选择）
#' @param cor_type 字符串，相关性类型，"pearson"或"bicor"，默认"pearson"
#' @param network_type 字符串，网络类型，"unsigned"或"signed"，默认"signed"
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item module_colors: 每个feature的模块颜色
#'   \item module_labels: 模块标签
#'   \item MEs: 模块特征值（Module Eigengenes）
#'   \item power: 使用的软阈值
#'   \item TOM: TOM矩阵（如果保留）
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' wgcna_result <- build_wgcna_modules(expr, min_module_size = 30)
#' table(wgcna_result$module_colors)
#' }
#'
#' @export
build_wgcna_modules <- function(expr_matrix, min_module_size = 30,
                                merge_cut_height = 0.25, power = NULL,
                                cor_type = "pearson",
                                network_type = "signed") {
  if (!requireNamespace("WGCNA", quietly = TRUE)) {
    stop("Package 'WGCNA' is required. Please install it.")
  }

  # Transpose: samples as rows
  dat_expr <- as.data.frame(t(expr_matrix))

  # Choose soft threshold if not provided
  if (is.null(power)) {
    powers <- c(1:10, seq(12, 20, by = 2))
    sft <- WGCNA::pickSoftThreshold(dat_expr, powerVector = powers,
                                    networkType = network_type,
                                    verbose = 0)
    power <- sft$powerEstimate
    if (is.na(power)) {
      power <- 6
      warning("Soft threshold estimation failed. Using default power = 6.")
    }
    message("Selected soft threshold power = ", power)
  }

  # Build adjacency
  adjacency <- WGCNA::adjacency(dat_expr, power = power,
                                type = network_type,
                                corFnc = ifelse(cor_type == "bicor",
                                                "bicor", "cor"))

  # Build TOM
  TOM <- WGCNA::TOMsimilarity(adjacency)

  # Hierarchical clustering
  gene_tree <- stats::hclust(stats::as.dist(1 - TOM), method = "average")

  # Module identification
  dynamic_tree_cut <- WGCNA::cutreeDynamic(dendro = gene_tree,
                                            method = "tree",
                                            minClusterSize = min_module_size,
                                            distM = 1 - TOM)

  # Convert to colors
  module_colors <- WGCNA::labels2colors(dynamic_tree_cut)

  # Calculate module eigengenes
  MEs <- WGCNA::moduleEigengenes(dat_expr, module_colors)$eigengenes
  MEs <- WGCNA::orderMEs(MEs)

  # Merge close modules
  merge <- WGCNA::mergeCloseModules(dat_expr, module_colors,
                                     cutHeight = merge_cut_height)
  merged_colors <- merge$colors
  merged_MEs <- merge$newMEs

  result <- list(
    module_colors = merged_colors,
    module_labels = dynamic_tree_cut,
    MEs = merged_MEs,
    power = power,
    TOM = TOM,
    gene_tree = gene_tree,
    adjacency = adjacency
  )

  n_modules <- length(unique(merged_colors))
  message("WGCNA completed. ", n_modules, " modules identified.")
  return(result)
}


#' @title WGCNA Module-Trait Association Analysis
#'
#' @description
#' 在WGCNA共表达模块的基础上，计算共表达模块与生物性状的关联性。
#' 该函数计算每个模块特征值（Module Eigengene, ME）与每个生物性状
#' 之间的相关性及其显著性，识别与性状关联最强的模块。
#'
#' @param wgcna_result 列表，由build_wgcna_modules返回
#' @param traits 数据框，生物性状数据（行：样本，列：性状）
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item cor: 模块-性状相关系数矩阵
#'   \item pvalue: 模块-性状相关性P值矩阵
#'   \item module_trait_df: 长格式数据框，用于绘图
#' }
#'
#' @examples
#' \dontrun{
#' wgcna_result <- build_wgcna_modules(expr)
#' traits <- data.frame(
#'   BMI = rnorm(ncol(expr)),
#'   Age = rnorm(ncol(expr))
#' )
#' module_trait <- wgcna_module_trait_association(wgcna_result, traits)
#' }
#'
#' @export
wgcna_module_trait_association <- function(wgcna_result, traits) {
  MEs <- wgcna_result$MEs

  # Ensure sample order matches
  common_samples <- intersect(rownames(MEs), rownames(traits))
  MEs <- MEs[common_samples, , drop = FALSE]
  traits <- traits[common_samples, , drop = FALSE]

  n_modules <- ncol(MEs)
  n_traits <- ncol(traits)

  cor_matrix <- matrix(NA, nrow = n_modules, ncol = n_traits)
  pvalue_matrix <- matrix(NA, nrow = n_modules, ncol = n_traits)
  rownames(cor_matrix) <- colnames(MEs)
  colnames(cor_matrix) <- colnames(traits)
  rownames(pvalue_matrix) <- colnames(MEs)
  colnames(pvalue_matrix) <- colnames(traits)

  for (i in seq_len(n_modules)) {
    for (j in seq_len(n_traits)) {
      cor_test <- stats::cor.test(MEs[, i], traits[, j], use = "complete.obs")
      cor_matrix[i, j] <- cor_test$estimate
      pvalue_matrix[i, j] <- cor_test$p.value
    }
  }

  # Build long format for plotting
  module_trait_df <- reshape2::melt(cor_matrix, varnames = c("Module", "Trait"),
                                     value.name = "Correlation")
  pvalue_df <- reshape2::melt(pvalue_matrix, varnames = c("Module", "Trait"),
                               value.name = "pvalue")
  module_trait_df$pvalue <- pvalue_df$pvalue
  module_trait_df$significant <- module_trait_df$pvalue < 0.05

  result <- list(
    cor = cor_matrix,
    pvalue = pvalue_matrix,
    module_trait_df = module_trait_df
  )

  message("Module-trait association computed for ", n_modules,
          " modules and ", n_traits, " traits.")
  return(result)
}


#' @title WGCNA Feature-Trait Association Analysis
#'
#' @description
#' 在WGCNA共表达模块的基础上，计算feature与生物性状的关联性。
#' 该函数计算每个feature的表达值与每个生物性状之间的相关性，
#' 用于识别与性状直接关联的feature。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param traits 数据框，生物性状数据
#' @param method 字符串，相关性方法，"pearson"或"spearman"，默认"pearson"
#'
#' @return 返回一个列表，包含cor和pvalue矩阵
#'
#' @examples
#' \dontrun{
#' feature_trait <- wgcna_feature_trait_association(expr, traits)
#' }
#'
#' @export
wgcna_feature_trait_association <- function(expr_matrix, traits,
                                             method = "pearson") {
  common_samples <- intersect(colnames(expr_matrix), rownames(traits))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  traits <- traits[common_samples, , drop = FALSE]

  n_features <- nrow(expr_matrix)
  n_traits <- ncol(traits)

  cor_matrix <- matrix(NA, nrow = n_features, ncol = n_traits)
  pvalue_matrix <- matrix(NA, nrow = n_features, ncol = n_traits)
  rownames(cor_matrix) <- rownames(expr_matrix)
  colnames(cor_matrix) <- colnames(traits)
  rownames(pvalue_matrix) <- rownames(expr_matrix)
  colnames(pvalue_matrix) <- colnames(traits)

  for (i in seq_len(n_features)) {
    for (j in seq_len(n_traits)) {
      cor_test <- stats::cor.test(as.numeric(expr_matrix[i, ]),
                                    as.numeric(traits[, j]),
                                    method = method)
      cor_matrix[i, j] <- cor_test$estimate
      pvalue_matrix[i, j] <- cor_test$p.value
    }
  }

  result <- list(
    cor = cor_matrix,
    pvalue = pvalue_matrix
  )

  message("Feature-trait association computed for ", n_features,
          " features and ", n_traits, " traits.")
  return(result)
}


#' @title WGCNA Feature-Trait Linear Regression
#'
#' @description
#' 在WGCNA共表达模块的基础上，计算feature与生物学性状的线性回归。
#' 该函数对每个feature执行多元线性回归，评估多个性状对feature表达
#' 的联合影响，返回回归系数、R²和P值。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param traits 数据框，生物性状数据
#' @param adjust_for 字符向量，需要校正的协变量列名（可选）
#'
#' @return 返回一个数据框，包含每个feature的回归结果
#'
#' @examples
#' \dontrun{
#' regression_result <- wgcna_feature_trait_regression(expr, traits)
#' }
#'
#' @export
wgcna_feature_trait_regression <- function(expr_matrix, traits,
                                           adjust_for = NULL) {
  common_samples <- intersect(colnames(expr_matrix), rownames(traits))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  traits <- traits[common_samples, , drop = FALSE]

  trait_cols <- setdiff(colnames(traits), adjust_for)

  results_list <- lapply(rownames(expr_matrix), function(feat) {
    df <- data.frame(expr = as.numeric(expr_matrix[feat, ]))
    df <- cbind(df, traits)
    df <- df[complete.cases(df), , drop = FALSE]

    if (nrow(df) < length(trait_cols) + 2) return(NULL)

    formula_str <- paste("expr ~", paste(trait_cols, collapse = " + "))
    if (!is.null(adjust_for)) {
      formula_str <- paste(formula_str, "+",
                           paste(adjust_for, collapse = " + "))
    }

    fit <- stats::lm(stats::as.formula(formula_str), data = df)
    fit_summary <- summary(fit)

    coefs <- fit_summary$coefficients[trait_cols, , drop = FALSE]
    if (nrow(coefs) == 0) return(NULL)

    data.frame(
      Feature = feat,
      Trait = rownames(coefs),
      Estimate = coefs[, "Estimate"],
      StdError = coefs[, "Std. Error"],
      tvalue = coefs[, "t value"],
      pvalue = coefs[, "Pr(>|t|)"],
      R_squared = fit_summary$r.squared,
      Adj_R_squared = fit_summary$adj.r.squared,
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, results_list[!sapply(results_list, is.null)])
  result$pvalue_adj <- stats::p.adjust(result$pvalue, method = "BH")

  message("Feature-trait linear regression completed for ",
          nrow(expr_matrix), " features.")
  return(result)
}


#' @title Plot WGCNA Module-Trait Heatmap
#'
#' @description
#' 绘制WGCNA模块-性状关联热图，展示每个模块与每个性状之间的相关性。
#' 颜色表示相关系数（红正蓝负），星号表示显著性。
#'
#' @param module_trait_result 列表，由wgcna_module_trait_association返回
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认10
#' @param height 数值，图片高度（英寸），默认8
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' plot_module_trait_heatmap(module_trait_result, output_dir = "./figures")
#' }
#'
#' @export
plot_module_trait_heatmap <- function(module_trait_result, output_dir = ".",
                                       width = 10, height = 8) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  plot_df <- module_trait_result$module_trait_df
  plot_df$label <- ifelse(plot_df$pvalue < 0.001, "***",
                          ifelse(plot_df$pvalue < 0.01, "**",
                                 ifelse(plot_df$pvalue < 0.05, "*", "")))

  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = Trait, y = Module,
                                             fill = Correlation)) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::geom_text(ggplot2::aes(label = label), size = 5, color = "black") +
    ggplot2::scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                                    midpoint = 0, limits = c(-1, 1)) +
    ggplot2::labs(
      title = "Module-Trait Relationship",
      x = "Trait",
      y = "Module",
      fill = "Correlation"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold"),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)
    )

  pdf_file <- file.path(output_dir, "Module_trait_heatmap.pdf")
  png_file <- file.path(output_dir, "Module_trait_heatmap.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("Module-trait heatmap saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}
