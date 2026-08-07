# ==============================================================================
# OmicsFlow: CMeans 模糊聚类
# ==============================================================================
# 特征的模糊 c 均值聚类
# ==============================================================================

#' CMeans 模糊聚类
#'
#' @description 执行模糊 c 均值（fuzzy c-means）聚类，以识别具有相似表达模式的
#'   特征组。与硬聚类不同，每个特征对每个聚类都会获得一个隶属度（membership）值。
#'
#'   聚类引擎为 \code{e1071::cmeans}（经典 FCM）。之所以使用它而非
#'   \code{cluster::fanny}，是因为 FANNY 算法在高维 z-score 标准化矩阵上会退化
#'   为均匀隶属度（全部 \eqn{= 1/k}），并把每个特征都分配到同一个聚类。
#'   由于经典 FCM 可能留下某些空中心（没有任何特征被硬分配到该中心），本函数会
#'   在检测到空聚类时自动用逐渐减小的模糊度指数 \code{m} 重试，
#'   以保证所有请求的聚类都被填充。
#'
#' @param expr_matrix 数值矩阵（特征 x 样本）。
#' @param n_clusters 聚类数量。默认：6。
#' @param m 模糊度参数（> 1）。越大越模糊。默认：2。
#' @param max_iter 最大迭代次数。默认：100。
#' @param seed 随机种子。默认：42。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{cluster}：硬聚类分配的整数向量。
#'     \item \code{membership}：隶属度矩阵（特征 x 聚类）。
#'     \item \code{centers}：聚类中心（聚类 x 样本）。
#'     \item \code{model}：原始的聚类对象。
#'   }
#'
#' @examples
#' \dontrun{
#' cm <- run_cmeans(expr_matrix, n_clusters = 6)
#' print(table(cm$cluster))
#' }
#'
#' @export
run_cmeans <- function(expr_matrix, n_clusters = 6, m = 2,
                      max_iter = 100, seed = 42) {
  if (!requireNamespace("e1071", quietly = TRUE)) {
    stop("需要安装 'e1071' 包，请先安装。")
  }

  set.seed(seed)

  # 对特征进行标度变换以便聚类
  scaled_mat <- t(scale(t(as.matrix(expr_matrix))))
  scaled_mat[is.na(scaled_mat)] <- 0

  # 模糊 c 均值（通过 e1071::cmeans 实现的经典 FCM）。
  # 注意：不使用 cluster::fanny，因为 FANNY 算法在高维 z-score 数据上会退化
  # 为均匀隶属度（全部 == 1/k），并将每个特征都分配到聚类 1。
  #
  # 经典 FCM 可能留下某些空中心（没有特征被硬分配到这些中心），
  # 从而导致这些聚类的图消失。为保证所有请求的聚类都被填充，
  # 一旦检测到空聚类，就使用逐渐减小的模糊度指数 m 重试。
  candidates <- unique(c(m, 1.5, 1.4, 1.3, 1.2))
  cm <- NULL
  used_m <- m
  for (mm in candidates) {
    set.seed(seed)
    tmp <- e1071::cmeans(scaled_mat, centers = n_clusters, m = mm,
                         iter.max = max_iter)
    if (length(unique(tmp$cluster)) == n_clusters) {
      cm <- tmp
      used_m <- mm
      break
    }
    cm <- tmp
  }

  # 提取结果
  membership <- cm$membership
  rownames(membership) <- rownames(expr_matrix)
  colnames(membership) <- paste0("Cluster", 1:n_clusters)

  # 硬分配
  cluster <- apply(membership, 1, which.max)
  names(cluster) <- rownames(expr_matrix)

  # 聚类中心（聚类 x 样本）
  centers <- cm$centers
  rownames(centers) <- paste0("Cluster", 1:n_clusters)
  colnames(centers) <- colnames(expr_matrix)

  # 非空聚类数量
  n_nonempty <- length(unique(cluster))
  if (n_nonempty < n_clusters) {
    message(sprintf(
      "[run_cmeans] WARNING: only %d of %d clusters are non-empty after retry.",
      n_nonempty, n_clusters
    ))
  } else if (used_m != m) {
    message(sprintf(
      "[run_cmeans] Used fuzziness m = %.2f (instead of %.2f) to obtain %d non-empty clusters.",
      used_m, m, n_nonempty
    ))
  }

  return(list(
    cluster = cluster,
    membership = membership,
    centers = centers,
    model = cm
  ))
}


#' 绘制 CMeans 聚类轮廓
#'
#' @description 创建折线图，展示每个聚类内部最具代表性特征在分组层面的表达模式。
#'   x 轴为样本分组 id（\code{sample_info[[group_col]]}），y 轴为每个特征在各组中
#'   平均表达的 z-score（即每个特征在各组内的表达先求平均，再对所得的特征 x 组
#'   矩阵按行做 z-score 标准化）。对每个聚类，选取对该聚类隶属度最高的
#'   \code{top_n} 个特征并以折線画出。线宽（\code{linewidth}）与颜色深浅
#'   （\code{alpha}）均映射到特征的隶属度，隶属度越高的特征线条越粗、越深。
#'
#' @param cmeans_result 来自 \code{run_cmeans()} 的结果。
#' @param sample_info 样本元数据。
#' @param expr_matrix 可选的数值矩阵（特征 x 样本），保存用于绘制各特征曲线的
#'   表达值。应与传入 \code{run_cmeans()} 的矩阵相同。若为 \code{NULL}，则回退为
#'   每个聚类仅绘制单条聚类中心折线（旧行为）。
#' @param top_n 每个聚类绘制的隶属度最高特征数量。默认：100。
#' @param group_col 分组标签所在的列。默认："sample_info"。
#' @param feature_names 可选的显示名称命名向量。
#' @param palette 可选的 RColorBrewer 调色板名称（如 "Set1"、"Dark2"、
#'   "Paired"）。设置后，每个聚类面板使用调色板中一种不同的颜色；否则所有曲线
#'   以单一颜色绘制（默认：\code{NULL}）。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_cmeans_profiles(cmeans_result, sample_info, expr_matrix = scaled_mat)
#' print(p)
#' }
#'
#' @export
plot_cmeans_profiles <- function(cmeans_result, sample_info,
                                 expr_matrix = NULL,
                                 top_n = 100,
                                 group_col = "sample_info",
                                 feature_names = NULL,
                                 palette = NULL) {
  centers <- cmeans_result$centers
  if (is.null(centers)) {
    stop("cmeans_result$centers is NULL; cannot plot profiles.")
  }

  cluster_names <- rownames(centers)
  sample_ids <- colnames(centers)
  membership <- cmeans_result$membership
  cluster_vec <- cmeans_result$cluster

  if (is.null(membership) || is.null(cluster_vec)) {
    stop("cmeans_result$membership / cluster is NULL; cannot plot feature curves.")
  }

  # 校验并对齐表达矩阵（特征 x 样本）
  expr_mat <- as.matrix(expr_matrix)
  if (is.null(expr_mat) || nrow(expr_mat) == 0) {
    stop("expr_matrix is required for plotting group-level feature curves.")
  }
  if (!all(sample_ids %in% colnames(expr_mat))) {
    stop("expr_matrix columns do not match cmeans_result sample names.")
  }
  expr_mat <- expr_mat[, sample_ids, drop = FALSE]

  feat_ids <- rownames(expr_mat)
  if (is.null(feat_ids)) feat_ids <- rownames(membership)
  if (is.null(feat_ids)) stop("Cannot determine feature ids from expr_matrix.")

  # Map membership rows to expression rows by feature id
  mb <- membership
  rownames(mb) <- rownames(membership)
  mem_idx <- match(feat_ids, rownames(mb))
  if (any(is.na(mem_idx))) stop("expr_matrix rownames do not match membership rownames.")
  mb <- mb[mem_idx, , drop = FALSE]

  # --- 分组层面均值 + 按行 z-score --------------------------------
  # 按分组标签对样本分组，计算每组内每个特征的均值，
  # 再对每个特征跨组做 z-score 标准化。
  grp_vec <- sample_info[sample_ids, group_col]
  grp_lev <- unique(grp_vec)

  group_mean <- sapply(grp_lev, function(g) {
    cols <- which(grp_vec == g)
    if (length(cols) == 1) {
      return(as.numeric(expr_mat[, cols]))
    }
    rowMeans(expr_mat[, cols, drop = FALSE], na.rm = TRUE)
  })
  group_mean <- as.matrix(group_mean)
  rownames(group_mean) <- feat_ids
  colnames(group_mean) <- grp_lev

  # 跨组按行 z-score
  gm_z <- t(scale(t(group_mean)))
  gm_z[is.na(gm_z)] <- 0

  # --- 每个聚类选取隶属度最高的特征 -------------------------
  rows <- list()
  for (cl in cluster_names) {
    k <- match(cl, colnames(mb))
    if (is.na(k)) next
    in_cl <- (as.integer(cluster_vec) == k)
    cl_feats <- feat_ids[in_cl]
    if (length(cl_feats) == 0) next
    cl_mem <- mb[in_cl, k]
    o <- order(cl_mem, decreasing = TRUE)
    top_feats <- head(cl_feats[o], top_n)
    top_mem <- cl_mem[o][seq_len(length(top_feats))]

    for (j in seq_along(top_feats)) {
      rows[[length(rows) + 1L]] <- data.frame(
        cluster = cl,
        group = grp_lev,
        value = as.numeric(gm_z[top_feats[j], , drop = TRUE]),
        membership = top_mem[j],
        feature_id = top_feats[j],
        stringsAsFactors = FALSE
      )
    }
  }
  plot_data_long <- do.call(rbind, rows)
  plot_data_long$feature_id <- as.character(plot_data_long$feature_id)

  # 设置聚类因子顺序，使所有聚类按请求顺序显示
  plot_data_long$cluster <- factor(plot_data_long$cluster,
                                    levels = cluster_names)
  # 一致地设置分组因子顺序
  plot_data_long$group <- factor(plot_data_long$group, levels = grp_lev)

  # 将隶属度映射到线宽与透明度（深浅）。
  # 线宽上限适中，使相互重叠的高隶属度线条不会
  # 融合成实心色块；低隶属度线条保持浅淡但仍可见。
  mem_range <- range(plot_data_long$membership, na.rm = TRUE)
  if (diff(mem_range) == 0) mem_range <- c(mem_range[1] - 1, mem_range[2])

  # --- 调色板处理 ----------------------------------------------------
  # 提供调色板名称时，每个聚类从 RColorBrewer 调色板中获得各自颜色；
  # 否则所有曲线共用单一颜色。
  use_palette <- !is.null(palette) && !is.na(palette) &&
    nzchar(palette) && palette != ""
  cluster_colors <- NULL
  if (use_palette) {
    if (!requireNamespace("RColorBrewer", quietly = TRUE)) {
      stop("Package 'RColorBrewer' is required when 'palette' is set.")
    }
    pal_info <- RColorBrewer::brewer.pal.info
    if (!palette %in% rownames(pal_info)) {
      stop(sprintf("Unknown RColorBrewer palette '%s'.", palette))
    }
    n_cl <- length(cluster_names)
    max_col <- pal_info[palette, "maxcolors"]
    if (n_cl <= max_col) {
      cluster_colors <- RColorBrewer::brewer.pal(n_cl, palette)
    } else {
      base_cols <- RColorBrewer::brewer.pal(max_col, palette)
      cluster_colors <- grDevices::colorRampPalette(base_cols)(n_cl)
    }
    names(cluster_colors) <- cluster_names
  }

  # Common membership scales and theme
  common <- list(
    ggplot2::scale_linewidth(range = c(0.2, 0.9),
                             name = "Membership",
                             breaks = scales::pretty_breaks(4)),
    ggplot2::scale_alpha_continuous(range = c(0.20, 0.75),
                                    name = "Membership",
                                    breaks = scales::pretty_breaks(4)),
    ggplot2::labs(
      title = "CMeans Cluster Profiles (top features)",
      subtitle = paste0(
        "Top ", top_n, " features per cluster; ",
        "x = group mean z-score, line thickness/colour map to membership"
      ),
      x = "Group",
      y = "Group-mean expression (z-score)"
    ),
    ggplot2::theme_bw(),
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      plot.subtitle = ggplot2::element_text(size = 10, hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      strip.text = ggplot2::element_text(face = "bold")
    )
  )

  if (use_palette) {
    # One colour per cluster
    p <- ggplot2::ggplot(plot_data_long,
                         ggplot2::aes(x = group, y = value,
                                      group = feature_id,
                                      color = cluster,
                                      linewidth = membership,
                                      alpha = membership)) +
      ggplot2::geom_line() +
      ggplot2::geom_point(size = 0.5) +
      ggplot2::facet_wrap(~ cluster, scales = "free_y") +
      ggplot2::scale_color_manual(values = cluster_colors,
                                  name = "Cluster",
                                  breaks = cluster_names,
                                  drop = FALSE) +
      ggplot2::guides(color = ggplot2::guide_legend(title = "Cluster",
                                                    override.aes = list(
                                                      linewidth = 1.2,
                                                      alpha = 1
                                                    )))
  } else {
    # Single colour for all curves (default)
    p <- ggplot2::ggplot(plot_data_long,
                         ggplot2::aes(x = group, y = value,
                                      group = feature_id,
                                      linewidth = membership,
                                      alpha = membership)) +
      ggplot2::geom_line(color = "#2c3e50") +
      ggplot2::geom_point(color = "#2c3e50", size = 0.5) +
      ggplot2::facet_wrap(~ cluster, scales = "free_y")
  }

  # 追加共享的隶属度标度、图例引导与主题
  p <- p +
    ggplot2::guides(linewidth = ggplot2::guide_legend(title = "Membership"),
                    alpha = ggplot2::guide_legend(title = "Membership")) +
    common

  return(p)
}


#' 将 CMeans 隶属度表导出为 CSV
#'
#' @description 将模糊 c 均值聚类结果导出为 CSV 文件。
#'   输出每行对应一个特征，每列对应一个聚类（隶属度 / 归属度），
#'   并额外包含一列 \code{cluster} 记录硬聚类分配（即每个特征隶属度最高的聚类）。
#'
#' @param cmeans_result 来自 \code{run_cmeans()} 的结果。
#' @param output_dir 输出目录。
#' @param filename 基础文件名（不含扩展名）。默认："cmeans_membership"。
#' @param id_col_name 特征 id 列的名称。默认："feature_id"。
#'
#' @return 导出 CSV 文件的可视（invisible）路径。
#'
#' @examples
#' \dontrun{
#' export_cmeans_membership(cm, "results/tables", "cmeans_membership")
#' }
#'
#' @export
export_cmeans_membership <- function(cmeans_result, output_dir = ".",
                                      filename = "cmeans_membership",
                                      id_col_name = "feature_id") {
  membership <- cmeans_result$membership
  if (is.null(membership)) {
    stop("cmeans_result$membership is NULL; nothing to export.")
  }

  # 构建数据框：特征为行，聚类隶属度为列
  out <- as.data.frame(membership)
  out[[id_col_name]] <- rownames(membership)
  out$cluster <- cmeans_result$cluster

  # 重新排列列顺序，使特征 id 列与硬分配列在前，
  # 随后才是各聚类的隶属度列
  member_cols <- setdiff(colnames(out), c(id_col_name, "cluster"))
  out <- out[, c(id_col_name, member_cols, "cluster")]

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  if (!grepl("\\.csv$", filename)) filename <- paste0(filename, ".csv")
  file_path <- file.path(output_dir, filename)
  utils::write.csv(out, file_path, row.names = FALSE)

  invisible(file_path)
}
