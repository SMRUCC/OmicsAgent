# ==============================================================================
# OmicsFlow: Alpha Diversity Analysis
# ==============================================================================
# 计算α多样性指数（Shannon, Simpson, Chao1, ACE, Pielou, Goods_coverage）
# 并进行组间统计比较与可视化
# ==============================================================================

#' 计算α多样性指数
#'
#' @description 对每个样本计算多种α多样性指数。支持 Shannon、Simpson、
#'   inv_Simpson、Chao1、ACE、Pielou 均匀度、Goods_coverage 以及 observed
#'   species 数。输入可以是计数矩阵（16S ITS）或相对丰度矩阵。
#'
#' @param expr_matrix 数值矩阵（features × samples），行为微生物 taxa，列为样本。
#' @param method 计算方法，"count" 使用绝对计数数据，"abundance" 使用相对
#'   丰度数据（先乘以伪计数再计算）。默认 "count"。
#' @param digits 保留小数位数。默认 4。
#'
#' @return 数据框（样本 × 指数），含以下列：
#'   \itemize{
#'     \item \code{sample}: 样本ID
#'     \item \code{observed_species}: 观测到的 species 数
#'     \item \code{shannon}: Shannon 指数
#'     \item \code{simpson}: Simpson 指数
#'     \item \code{inv_simpson}: 逆 Simpson 指数
#'     \item \code{chao1}: Chao1 丰富度估计
#'     \item \code{ace}: ACE 丰富度估计
#'     \item \code{pielou}: Pielou 均匀度
#'     \item \code{goods_coverage}: Goods 覆盖度
#'   }
#'
#' @examples
#' \dontrun{
#' div <- calc_alpha_diversity(expr_matrix, method = "count")
#' head(div)
#' }
#'
#' @export
calc_alpha_diversity <- function(expr_matrix, method = "count",
                                 digits = 4) {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)
  method <- match.arg(method, c("count", "abundance"))
  
  # 如果是相对丰度数据，转换为伪计数
  if (method == "abundance") {
    expr_matrix <- expr_matrix * 1e5
  }
  
  # 去除全零样本
  sample_sums <- colSums(expr_matrix, na.rm = TRUE)
  valid_samples <- names(sample_sums)[sample_sums > 0]
  if (length(valid_samples) == 0) {
    stop("All samples have zero total count, cannot calculate alpha diversity.")
  }
  expr_matrix <- expr_matrix[, valid_samples, drop = FALSE]
  
  n_samples <- ncol(expr_matrix)
  results <- data.frame(
    sample = valid_samples,
    observed_species = numeric(n_samples),
    shannon = numeric(n_samples),
    simpson = numeric(n_samples),
    inv_simpson = numeric(n_samples),
    chao1 = numeric(n_samples),
    ace = numeric(n_samples),
    pielou = numeric(n_samples),
    goods_coverage = numeric(n_samples),
    stringsAsFactors = FALSE
  )
  
  for (i in seq_len(n_samples)) {
    x <- expr_matrix[, i]
    x <- x[x > 0]  # 只保留非零 taxa
    
    if (length(x) == 0) next
    
    n <- sum(x)
    p <- x / n
    
    # Observed species
    results$observed_species[i] <- length(x)
    
    # Shannon: H = -sum(p * log(p))
    results$shannon[i] <- -sum(p * log(p))
    
    # Simpson: D = 1 - sum(p^2)  (Gini-Simpson)
    results$simpson[i] <- 1 - sum(p^2)
    
    # Inverse Simpson: 1 / sum(p^2)
    results$inv_simpson[i] <- 1 / sum(p^2)
    
    # Pielou evenness: H / log(S)
    s <- length(x)
    results$pielou[i] <- if (s > 1) results$shannon[i] / log(s) else 1
    
    # Goods coverage: 1 - (n1 / N)，其中 n1 是 singletons 数量
    n1 <- sum(x == 1)
    results$goods_coverage[i] <- 1 - n1 / n
    
    # Chao1 丰富度估计
    s_obs <- s
    f1 <- sum(x == 1)  # singletons
    f2 <- sum(x == 2)  # doubletons
    if (f2 > 0) {
      results$chao1[i] <- s_obs + (f1^2) / (2 * f2)
    } else {
      results$chao1[i] <- s_obs + f1 * (f1 - 1) / 2
    }
    
    # ACE 丰富度估计
    threshold <- max(10, ceiling(n * 0.01))  # rare 的阈值
    rare <- x[x <= threshold]
    s_rare <- length(rare)
    n_rare <- sum(rare)
    if (n_rare > 0 && s_rare > 0) {
      c_ace <- 1 - sum(rare == 1) / n_rare
      if (c_ace > 0) {
        f1_rare <- sum(rare == 1)
        results$ace[i] <- s_obs + s_rare / c_ace + f1_rare / c_ace
      } else {
        results$ace[i] <- s_obs
      }
    } else {
      results$ace[i] <- s_obs
    }
  }
  
  # 四舍五入
  numeric_cols <- c("observed_species", "shannon", "simpson", "inv_simpson",
                    "chao1", "ace", "pielou", "goods_coverage")
  results[, numeric_cols] <- round(results[, numeric_cols], digits)
  rownames(results) <- results$sample
  return(results)
}


#' α多样性组间统计检验
#'
#' @description 对每个多样性指数进行组间差异检验，支持 Kruskal-Wallis 检验
#'   （多组）和 Wilcoxon 秩和检验（两组），返回检验统计量和 p 值。
#'
#' @param diversity_result \code{calc_alpha_diversity()} 的返回结果。
#' @param sample_info 样本元数据 data.frame。
#' @param group_col 分组列名。默认 "sample_info"。
#' @param method 检验方法，"kruskal" 或 "wilcoxon"。默认 "kruskal"。
#' @param p_adjust 多重检验校正方法。默认 "BH"。
#'
#' @return 数据框，每行一个多样性指数，含：
#'   \itemize{
#'     \item \code{index}: 多样性指数名
#'     \item \code{statistic}: 检验统计量
#'     \item \code{p_value}: 原始 p 值
#'     \item \code{p_adj}: 校正后 p 值
#'     \item \code{method}: 检验方法
#'   }
#'
#' @examples
#' \dontrun{
#' test_res <- test_alpha_diversity(div, sample_info, group_col = "sample_info")
#' }
#'
#' @export
test_alpha_diversity <- function(diversity_result, sample_info,
                                 group_col = "sample_info",
                                 method = "kruskal",
                                 p_adjust = "BH") {
  method <- match.arg(method, c("kruskal", "wilcoxon"))
  
  common <- intersect(diversity_result$sample, rownames(sample_info))
  if (length(common) == 0) {
    stop("Sample names do not match, cannot perform statistical test.")
  }
  
  diversity_result <- diversity_result[common, , drop = FALSE]
  groups <- sample_info[common, group_col]
  n_groups <- length(unique(groups))
  
  # 如果只有两组，强制使用 wilcoxon
  if (n_groups == 2 && method == "kruskal") {
    method <- "wilcoxon"
    cat("[alpha-div] 2 groups detected, switching to Wilcoxon test.\n")
  }
  
  indices <- c("observed_species", "shannon", "simpson", "inv_simpson",
               "chao1", "ace", "pielou", "goods_coverage")
  
  results <- data.frame(
    index = character(length(indices)),
    statistic = numeric(length(indices)),
    p_value = numeric(length(indices)),
    method = method,
    stringsAsFactors = FALSE
  )
  
  for (i in seq_along(indices)) {
    idx <- indices[i]
    vals <- diversity_result[[idx]]
    if (method == "kruskal") {
      test <- stats::kruskal.test(vals ~ groups)
    } else {
      g1 <- unique(groups)[1]
      g2 <- unique(groups)[2]
      v1 <- vals[groups == g1]
      v2 <- vals[groups == g2]
      test <- stats::wilcox.test(v1, v2)
    }
    results$index[i] <- idx
    results$statistic[i] <- test$statistic
    results$p_value[i] <- test$p.value
  }
  
  results$p_adj <- stats::p.adjust(results$p_value, method = p_adjust)
  results <- results[order(results$p_value), ]
  rownames(results) <- NULL
  return(results)
}


#' 绘制α多样性箱线图
#'
#' @description 为每个多样性指数绘制分组箱线图，可选叠加显著性标记。
#'
#' @param diversity_result \code{calc_alpha_diversity()} 的返回结果。
#' @param sample_info 样本元数据 data.frame。
#' @param group_col 分组列名。默认 "sample_info"。
#' @param indices 要绘制的指数向量。默认绘制全部。
#' @param show_pvalue 逻辑值，是否在图中显示 p 值。默认 TRUE。
#' @param test_result \code{test_alpha_diversity()} 的返回结果。如果为 NULL
#'   且 show_pvalue = TRUE，会自动计算。默认 NULL。
#'
#' @return ggplot 对象列表，每个指数一个图。
#'
#' @examples
#' \dontrun{
#' plots <- plot_alpha_diversity(div, sample_info, group_col = "sample_info")
#' }
#'
#' @export
plot_alpha_diversity <- function(diversity_result, sample_info,
                                 group_col = "sample_info",
                                 indices = NULL,
                                 show_pvalue = TRUE,
                                 test_result = NULL) {
  common <- intersect(diversity_result$sample, rownames(sample_info))
  if (length(common) == 0) {
    stop("Sample names do not match.")
  }
  
  diversity_result <- diversity_result[common, , drop = FALSE]
  groups <- sample_info[common, group_col]
  group_colors <- make_group_colors(unique(groups))
  
  if (is.null(indices)) {
    indices <- c("shannon", "simpson", "chao1", "pielou",
                 "observed_species", "goods_coverage")
    indices <- intersect(indices, colnames(diversity_result))
  }
  
  if (isTRUE(show_pvalue) && is.null(test_result)) {
    test_result <- test_alpha_diversity(diversity_result, sample_info, group_col)
  }
  
  plots <- list()
  for (idx in indices) {
    plot_df <- data.frame(
      value = diversity_result[[idx]],
      group = groups,
      stringsAsFactors = FALSE
    )
    
    p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = group, y = value, fill = group)) +
      ggplot2::geom_boxplot(alpha = 0.7, outlier.size = 1, outlier.colour = "grey40") +
      ggplot2::geom_jitter(width = 0.15, size = 1.5, alpha = 0.6) +
      ggplot2::scale_fill_manual(values = group_colors) +
      ggplot2::labs(
        title = idx,
        x = NULL,
        y = idx
      ) +
      ggplot2::theme_bw() +
      ggplot2::theme(
        plot.title = ggplot2::element_text(size = 13, face = "bold", hjust = 0.5),
        axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 10),
        axis.text.y = ggplot2::element_text(size = 10),
        legend.position = "none"
      )
    
    # 添加 p 值标注
    if (isTRUE(show_pvalue) && !is.null(test_result)) {
      p_row <- test_result[test_result$index == idx, ]
      if (nrow(p_row) > 0) {
        p_val <- p_row$p_value[1]
        p_label <- if (p_val < 0.001) "p < 0.001" else sprintf("p = %.3f", p_val)
        p <- p + ggplot2::annotate("text", x = 1.5, y = max(plot_df$value, na.rm = TRUE),
                                   label = p_label, size = 4, fontface = "italic",
                                   vjust = 1.5)
      }
    }
    
    plots[[idx]] <- p
  }
  
  return(plots)
}
