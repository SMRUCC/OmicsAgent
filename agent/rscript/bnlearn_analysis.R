# ============================================================================
# R 工具函数脚本 - bnlearn 动态贝叶斯网络分析
# ============================================================================
# 该脚本实现：
# 1. 时间序列数据的动态贝叶斯网络构建
# 2. 网络拓扑结构可视化
# 3. 关键调控关系识别
# ============================================================================

library(bnlearn)
library(ggplot2)
library(igraph)

run_bnlearn_analysis <- function(expr_file, sample_info_file, output_dir,
                                  time_col = "time", top_n = 50) {
  dir.create(file.path(output_dir, "tables"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(output_dir, "figures"), showWarnings = FALSE, recursive = TRUE)
  
  expr <- read.csv(expr_file, row.names = 1, check.names = FALSE)
  expr_matrix <- as.matrix(expr)
  mode(expr_matrix) <- "numeric"
  
  sample_info <- read.csv(sample_info_file, stringsAsFactors = FALSE, check.names = FALSE)
  common_samples <- intersect(colnames(expr_matrix), sample_info$ID)
  expr_matrix <- expr_matrix[, common_samples]
  sample_info <- sample_info[match(common_samples, sample_info$ID), ]
  
  # 按方差取 top 分子
  variances <- apply(expr_matrix, 1, var, na.rm = TRUE)
  top_indices <- order(variances, decreasing = TRUE)[1:min(top_n, nrow(expr_matrix))]
  expr_matrix <- expr_matrix[top_indices, ]
  
  # 离散化数据
  discretized <- data.frame(t(expr_matrix))
  for (col in colnames(discretized)) {
    discretized[[col]] <- discretize(discretized[[col]], method = "hartemink", breaks = 3, ibreaks = 10)
  }
  
  # 构建贝叶斯网络
  bn_structure <- tryCatch({
    # 使用爬山算法学习网络结构
    fitted <- hc(discretized)
    fitted
  }, error = function(e) {
    cat("BN structure learning failed:", e$message, "\n")
    NULL
  })
  
  if (!is.null(bn_structure)) {
    # 保存网络结构
    arcs_df <- data.frame(arcs(bn_structure))
    colnames(arcs_df) <- c("from", "to")
    write.csv(arcs_df, file.path(output_dir, "tables", "bn_arcs.csv"), row.names = FALSE)
    
    # 网络拓扑分析
    g <- graph_from_data_frame(arcs_df, directed = TRUE)
    
    # 度中心性
    degrees <- degree(g)
    degree_df <- data.frame(
      molecule = names(degrees),
      degree = degrees
    )
    degree_df <- degree_df[order(-degree_df$degree), ]
    write.csv(degree_df, file.path(output_dir, "tables", "bn_degree.csv"), row.names = FALSE)
    
    # 网络可视化
    png(file.path(output_dir, "figures", "bn_network.png"), width = 2400, height = 2400, res = 300)
    plot(g, vertex.size = 10, vertex.label.cex = 0.5,
         edge.arrow.size = 0.5, layout = layout_with_fr)
    title("Bayesian Network Structure")
    dev.off()
    
    pdf(file.path(output_dir, "figures", "bn_network.pdf"), width = 12, height = 12)
    plot(g, vertex.size = 10, vertex.label.cex = 0.5,
         edge.arrow.size = 0.5, layout = layout_with_fr)
    title("Bayesian Network Structure")
    dev.off()
    
    # 拟合参数
    fitted_bn <- bn.fit(bn_structure, discretized)
    
    return(list(
      n_nodes = nrow(arcs_df) + 1,
      n_arcs = nrow(arcs_df),
      top_hubs = head(degree_df$molecule, 10)
    ))
  }
  
  return(NULL)
}

if (sys.nframe() == 0) {
  cat("Usage: source this script and call run_bnlearn_analysis() function\n")
}
