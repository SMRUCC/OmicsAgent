#' @title Perform CMeans Fuzzy Clustering
#'
#' @description
#' 执行CMeans模糊聚类分析。CMeans（Fuzzy C-Means）是一种软聚类方法，
#' 允许feature以不同的隶属度属于多个聚类。该方法适用于表达模式
#' 渐变或具有多个调控模式的feature。
#'
#' 隶属度（membership）范围0-1，表示feature属于某个聚类的程度。
#' 所有聚类的隶属度之和为1。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param centers 整数，聚类数，默认6
#' @param m 数值，模糊指数，默认2（越大越模糊）
#' @param scale 逻辑值，是否对feature做标准化，默认TRUE
#' @param max_iter 整数，最大迭代次数，默认100
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item cluster: 每个feature的硬聚类标签
#'   \item membership: 隶属度矩阵（feature×cluster）
#'   \item centers: 聚类中心
#'   \item within_cluster_ss: 簇内平方和
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' cmeans_result <- perform_cmeans(expr, centers = 6)
#' table(cmeans_result$cluster)
#' }
#'
#' @export
perform_cmeans <- function(expr_matrix, centers = 6, m = 2,
                           scale = TRUE, max_iter = 100) {
  if (!requireNamespace("e1071", quietly = TRUE)) {
    stop("Package 'e1071' is required. Please install it.")
  }

  # Scale features if requested
  data_for_clustering <- expr_matrix
  if (scale) {
    data_for_clustering <- t(scale(t(expr_matrix)))
  }

  # Remove rows with NA
  complete_rows <- complete.cases(data_for_clustering)
  if (sum(!complete_rows) > 0) {
    message("Removed ", sum(!complete_rows), " features with NA values.")
  }
  data_for_clustering <- data_for_clustering[complete_rows, , drop = FALSE]

  # Transpose: features as rows for clustering
  cmeans_result <- e1071::cmeans(data_for_clustering, centers = centers,
                                  m = m, maxiter = max_iter)

  result <- list(
    cluster = cmeans_result$cluster,
    membership = cmeans_result$membership,
    centers = cmeans_result$centers,
    within_cluster_ss = cmeans_result$withincluster,
    iter = cmeans_result$iter,
    converged = cmeans_result$converged
  )

  message("CMeans clustering completed. ", centers, " clusters identified.")
  message("Converged: ", cmeans_result$converged, " in ",
          cmeans_result$iter, " iterations.")
  return(result)
}


#' @title Plot CMeans Clustering Profiles
#'
#' @description
#' 绘制CMeans聚类结果的表达模式图。每个聚类一个子图，显示该聚类中
#' 所有feature的表达模式（细线）和聚类中心（粗线）。颜色表示隶属度。
#'
#' @param cmeans_result 列表，由perform_cmeans返回
#' @param expr_matrix 数值矩阵，原始表达矩阵
#' @param sample_meta 数据框，样本元数据（可选，用于X轴分组）
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认12
#' @param height 数值，图片高度（英寸），默认8
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' cmeans_result <- perform_cmeans(expr, centers = 6)
#' plot_cmeans_profiles(cmeans_result, expr, meta, output_dir = "./figures")
#' }
#'
#' @export
plot_cmeans_profiles <- function(cmeans_result, expr_matrix, sample_meta = NULL,
                                 output_dir = ".", width = 12, height = 8) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  # Build long format data
  membership <- cmeans_result$membership
  cluster_assignment <- cmeans_result$cluster

  # For each cluster, gather features
  plot_data_list <- lapply(seq_len(nrow(cmeans_result$centers)), function(k) {
    features_in_cluster <- names(cluster_assignment)[cluster_assignment == k]
    if (length(features_in_cluster) == 0) return(NULL)

    expr_subset <- expr_matrix[features_in_cluster, , drop = FALSE]
    expr_long <- reshape2::melt(as.matrix(expr_subset))
    colnames(expr_long) <- c("Feature", "Sample", "Expression")

    expr_long$Cluster <- paste0("Cluster", k)

    # Add membership
    membership_vals <- membership[features_in_cluster, k]
    expr_long$Membership <- membership_vals[expr_long$Feature]

    # Add center
    center_vals <- cmeans_result$centers[k, ]
    center_df <- data.frame(
      Sample = colnames(expr_matrix),
      Expression = as.numeric(center_vals),
      Cluster = paste0("Cluster", k),
      Type = "Center"
    )

    expr_long$Type <- "Feature"
    rbind(expr_long, center_df)
  })

  plot_data <- do.call(rbind, plot_data_list[!sapply(plot_data_list, is.null)])

  # Add group info if available
  if (!is.null(sample_meta)) {
    group_map <- setNames(as.character(sample_meta$sample_info),
                          sample_meta$ID)
    plot_data$Group <- group_map[plot_data$Sample]
  }

  p <- ggplot2::ggplot(plot_data[plot_data$Type == "Feature", ],
                       ggplot2::aes(x = Sample, y = Expression,
                                    group = Feature,
                                    color = Membership)) +
    ggplot2::geom_line(alpha = 0.3) +
    ggplot2::geom_line(data = plot_data[plot_data$Type == "Center", ],
                        ggplot2::aes(group = Cluster), color = "black",
                        linewidth = 1.5, inherit.aes = FALSE) +
    ggplot2::scale_color_gradient(low = "grey80", high = "darkred") +
    ggplot2::facet_wrap(~ Cluster, scales = "free_y") +
    ggplot2::labs(
      title = "CMeans Clustering Expression Profiles",
      x = "Sample",
      y = "Expression",
      color = "Membership"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold"),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 7)
    )

  pdf_file <- file.path(output_dir, "CMeans_profiles.pdf")
  png_file <- file.path(output_dir, "CMeans_profiles.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("CMeans profile plot saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}
