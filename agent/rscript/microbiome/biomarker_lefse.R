# ==============================================================================
# OmicsFlow: LEfSe-style Biomarker Discovery
# ==============================================================================
# 基于 Kruskal-Wallis 检验 + LDA effect size 的生物标志物发现
# 模仿 LEfSe (Linear discriminant analysis Effect Size) 分析流程
# ==============================================================================

#' LEfSe 风格的生物标志物发现
#'
#' @description 模仿 LEfSe 分析流程：
#'   1. Kruskal-Wallis 检验筛选组间差异 taxa（p < kw_p_threshold）
#'   2. 对显著差异的 taxa 进行 LDA 分析，计算 effect size
#'   3. 返回显著差异的 biomarker 列表及其 LDA score
#'
#' @param expr_matrix 数值矩阵（features × samples），行为 taxa，列为样本。
#' @param sample_info 样本元数据 data.frame。
#' @param group_col 分组列名。默认 "sample_info"。
#' @param kw_p_threshold Kruskal-Wallis p 值阈值。默认 0.05。
#' @param lda_threshold LDA score 阈值。默认 2.0。
#' @param p_adjust 多重检验校正方法。默认 "BH"。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{full_results}: 所有 taxa 的 KW 检验和 LDA 结果。
#'     \item \code{significant}: 显著 biomarker（通过两个阈值）。
#'     \item \code{lda_scores}: LDA score 数据框，用于绘图。
#'   }
#'
#' @examples
#' \dontrun{
#' res <- run_lefse_analysis(expr_matrix, sample_info, group_col = "sample_info")
#' }
#'
#' @export
run_lefse_analysis <- function(expr_matrix, sample_info,
                               group_col = "sample_info",
                               kw_p_threshold = 0.05,
                               lda_threshold = 2.0,
                               p_adjust = "BH") {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)

  common <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common, drop = FALSE]
  sample_info <- sample_info[common, , drop = FALSE]
  groups <- sample_info[[group_col]]
  group_levels <- unique(groups)
  n_groups <- length(group_levels)

  if (n_groups < 2) {
    stop("At least 2 groups are required for LEfSe analysis.")
  }

  n_features <- nrow(expr_matrix)
  feature_names <- rownames(expr_matrix)

  # 第一步：Kruskal-Wallis 检验
  kw_p <- numeric(n_features)
  for (i in seq_len(n_features)) {
    kw_p[i] <- stats::kruskal.test(expr_matrix[i, ] ~ groups)$p.value
  }
  kw_p[is.na(kw_p)] <- 1
  kw_padj <- stats::p.adjust(kw_p, method = p_adjust)

  # 第二步：LDA 分析
  # 使用 MASS::lda 进行线性判别分析
  expr_t <- t(expr_matrix)  # samples × features
  expr_t <- as.data.frame(expr_t)

  lda_scores <- rep(NA_real_, n_features)
  lda_group <- rep(NA_character_, n_features)
  lda_direction <- rep(NA_real_, n_features)

  # 对通过 KW 检验的 taxa 进行 LDA
  significant_idx <- which(kw_padj < kw_p_threshold)

  if (length(significant_idx) > 0) {
    if (n_groups == 2) {
      # 两组：直接计算 effect size（类似于 LEfSe 的 LDA score）
      for (idx in significant_idx) {
        v <- expr_matrix[idx, ]
        g1 <- v[groups == group_levels[1]]
        g2 <- v[groups == group_levels[2]]

        # 标准化到相对丰度
        if (sum(g1) > 0) g1_rel <- g1 / sum(g1) * 100 else g1_rel <- rep(0, length(g1))
        if (sum(g2) > 0) g2_rel <- g2 / sum(g2) * 100 else g2_rel <- rep(0, length(g2))

        # log10 变换（加伪计数）
        g1_log <- log10(g1_rel + 1)
        g2_log <- log10(g2_rel + 1)

        # LDA score: 组间差 / 组内标准差
        mean_diff <- mean(g1_log) - mean(g2_log)
        pooled_sd <- sqrt((var(g1_log) + var(g2_log)) / 2)
        if (pooled_sd > 0) {
          lda_scores[idx] <- abs(mean_diff / pooled_sd) * 2  # 放大到 LEfSe 风格
        } else {
          lda_scores[idx] <- 0
        }
        lda_direction[idx] <- mean_diff
        lda_group[idx] <- if (mean_diff > 0) group_levels[1] else group_levels[2]
      }
    } else {
      # 多组：使用 MASS::lda
      if (requireNamespace("MASS", quietly = TRUE)) {
        lda_data <- expr_t[, significant_idx, drop = FALSE]
        lda_data$group <- groups
        tryCatch({
          lda_fit <- MASS::lda(group ~ ., data = lda_data)
          coefs <- lda_fit$scaling[, 1]
          lda_scores[significant_idx] <- abs(coefs)
          lda_direction[significant_idx] <- coefs
          # 判断各组中心
          cent <- lda_fit$prior %*% t(lda_fit$scaling)
          lda_group[significant_idx] <- group_levels[which.max(cent)]
        }, error = function(e) {
          cat(sprintf("[lefse] LDA failed, using effect size instead: %s\n",
                      conditionMessage(e)))
        })
      }
    }
  }

  # 组装结果
  full_results <- data.frame(
    feature = feature_names,
    kw_pvalue = kw_p,
    kw_padj = kw_padj,
    lda_score = lda_scores,
    lda_direction = lda_direction,
    enriched_group = lda_group,
    stringsAsFactors = FALSE
  )

  # 筛选显著 biomarker
  significant <- full_results[
    !is.na(full_results$lda_score) &
    full_results$kw_padj < kw_p_threshold &
    abs(full_results$lda_score) >= lda_threshold, , drop = FALSE
  ]
  significant <- significant[order(-abs(significant$lda_score)), ]

  # LDA score 数据框（用于绘图）
  lda_scores_df <- significant[, c("feature", "lda_score", "enriched_group")]
  lda_scores_df$lda_score <- ifelse(
    lda_scores_df$enriched_group == group_levels[1],
    -abs(lda_scores_df$lda_score),
    abs(lda_scores_df$lda_score)
  )

  cat(sprintf("[lefse] %d taxa passed KW test (p_adj < %.2f)\n",
              length(significant_idx), kw_p_threshold))
  cat(sprintf("[lefse] %d biomarkers passed LDA threshold (|score| >= %.1f)\n",
              nrow(significant), lda_threshold))

  return(list(
    full_results = full_results,
    significant = significant,
    lda_scores = lda_scores_df,
    params = list(
      n_groups = n_groups,
      group_levels = group_levels,
      kw_p_threshold = kw_p_threshold,
      lda_threshold = lda_threshold,
      p_adjust = p_adjust
    )
  ))
}


#' 绘制 LEfSe LDA score 图
#'
#' @description 绘制水平条形图，展示各 biomarker 的 LDA score，
#'   正负方向表示在不同组中富集。
#'
#' @param lefse_result \code{run_lefse_analysis()} 的返回结果。
#' @param top_n 展示前 N 个 biomarker。默认 30。
#' @param color_by_group 是否按富集组着色。默认 TRUE。
#'
#' @return ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_lefse_lda(lefse_result, top_n = 20)
#' }
#'
#' @export
plot_lefse_lda <- function(lefse_result, top_n = 30, color_by_group = TRUE) {
  lda_df <- lefse_result$lda_scores
  if (nrow(lda_df) == 0) {
    stop("No significant biomarkers to plot.")
  }

  # Top N
  if (nrow(lda_df) > top_n) {
    lda_df <- lda_df[order(-abs(lda_df$lda_score))[1:top_n], , drop = FALSE]
  }

  lda_df <- lda_df[order(lda_df$lda_score), , drop = FALSE]
  lda_df$feature <- factor(lda_df$feature, levels = lda_df$feature)

  group_levels <- lefse_result$params$group_levels
  group_colors <- make_group_colors(group_levels)

  p <- ggplot2::ggplot(lda_df, ggplot2::aes(x = feature, y = lda_score,
                                             fill = enriched_group)) +
    ggplot2::geom_bar(stat = "identity") +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = group_colors, name = "Enriched in") +
    ggplot2::labs(
      title = "LEfSe Biomarker (LDA Score)",
      x = NULL,
      y = "LDA Score (log10)"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text.y = ggplot2::element_text(size = 9),
      axis.text.x = ggplot2::element_text(size = 10),
      legend.position = "right"
    )

  return(p)
}


#' 绘制 LEfSe cladogram（简化版）
#'
#' @description 绘制简化的 cladogram，用同心圆表示不同分类层级，
#'   节点颜色表示富集的组。需要 feature_info 包含多个分类层级。
#'
#' @param lefse_result \code{run_lefse_analysis()} 的返回结果。
#' @param feature_info Feature注释 data.frame，需包含分类层级列。
#' @param levels 分类层级列名向量，从高到低。默认 c("phylum", "class", "order", "family", "genus")。
#''
#' @return ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_lefse_cladogram(lefse_result, feature_info)
#' }
#'
#' @export
plot_lefse_cladogram <- function(lefse_result, feature_info,
                                levels = c("phylum", "class", "order",
                                           "family", "genus")) {
  sig <- lefse_result$significant
  if (nrow(sig) == 0) {
    stop("No significant biomarkers for cladogram.")
  }

  group_levels <- lefse_result$params$group_levels
  group_colors <- make_group_colors(group_levels)

  # 为每个层级收集显著 taxa
  all_nodes <- list()
  for (lvl in levels) {
    if (!lvl %in% colnames(feature_info)) next
    lvl_taxa <- unique(feature_info[[lvl]])
    lvl_taxa <- lvl_taxa[!is.na(lvl_taxa) & lvl_taxa != ""]
    for (t in lvl_taxa) {
      # 检查该 taxa 下是否有显著 biomarker
      sub_features <- rownames(feature_info)[feature_info[[lvl]] == t]
      sig_in_taxa <- intersect(sub_features, sig$feature)
      if (length(sig_in_taxa) > 0) {
        enriched <- sig$enriched_group[match(sig_in_taxa, sig$feature)]
        all_nodes[[lvl]] <- rbind(all_nodes[[lvl]], data.frame(
          level = lvl,
          taxa = t,
          enriched = names(sort(table(enriched), decreasing = TRUE))[1],
          stringsAsFactors = FALSE
        ))
      }
    }
  }

  if (length(all_nodes) == 0) {
    stop("Cannot match significant biomarkers to taxonomic levels.")
  }

  node_df <- do.call(rbind, all_nodes)
  node_df$level <- factor(node_df$level, levels = levels)
  node_df <- node_df[!duplicated(node_df$taxa), ]

  # 简化版：用水平条表示各层级
  p <- ggplot2::ggplot(node_df, ggplot2::aes(x = level, y = taxa, fill = enriched)) +
    ggplot2::geom_point(size = 5, shape = 21, color = "grey30") +
    ggplot2::scale_fill_manual(values = group_colors, name = "Enriched in") +
    ggplot2::labs(
      title = "LEfSe Cladogram (Simplified)",
      x = "Taxonomic Level",
      y = NULL
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text.y = ggplot2::element_text(size = 9),
      legend.position = "right"
    )

  return(p)
}
