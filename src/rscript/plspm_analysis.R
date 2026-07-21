# ============================================================================
# R 工具函数脚本 - PLS-PM 因果路径分析
# ============================================================================
# 该脚本实现：
# 1. 多组学数据按不同的组学层次构建潜变量
# 2. PLS-PM 因果路径分析
# 3. 路径系数可视化
# ============================================================================

library(plspm)
library(ggplot2)

run_plspm_analysis <- function(omics_files, sample_info_file, output_dir,
                                path_matrix = NULL, blocks = NULL) {
  dir.create(file.path(output_dir, "tables"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(output_dir, "figures"), showWarnings = FALSE, recursive = TRUE)
  
  if (is.null(path_matrix) || is.null(blocks)) {
    cat("Path matrix and blocks must be provided for PLS-PM analysis\n")
    return(NULL)
  }
  
  # 读取多组学数据
  omics_data_list <- list()
  for (i in seq_along(omics_files)) {
    expr <- read.csv(omics_files[i], row.names = 1, check.names = FALSE)
    expr_matrix <- as.matrix(expr)
    mode(expr_matrix) <- "numeric"
    omics_data_list[[i]] <- expr_matrix
  }
  
  sample_info <- read.csv(sample_info_file, stringsAsFactors = FALSE, check.names = FALSE)
  
  # 合并数据（按样本）
  common_samples <- Reduce(intersect, lapply(omics_data_list, colnames))
  common_samples <- intersect(common_samples, sample_info$ID)
  
  merged_data <- data.frame(ID = common_samples)
  for (i in seq_along(omics_data_list)) {
    omics_data_list[[i]] <- omics_data_list[[i]][, common_samples]
    # 取每个组学的 top 主成分作为潜变量指标
    pca_result <- prcomp(t(omics_data_list[[i]]), scale. = TRUE, center = TRUE)
    merged_data[[paste0("omics", i, "_PC1")]] <- pca_result$x[, 1]
    if (ncol(pca_result$x) >= 2) {
      merged_data[[paste0("omics", i, "_PC2")]] <- pca_result$x[, 2]
    }
  }
  
  rownames(merged_data) <- merged_data$ID
  merged_data <- merged_data[, -1]
  
  # 运行 PLS-PM
  pls_result <- tryCatch({
    plspm(merged_data, path_matrix, blocks, scaled = TRUE)
  }, error = function(e) {
    cat("PLS-PM failed:", e$message, "\n")
    NULL
  })
  
  if (!is.null(pls_result)) {
    # 保存路径系数
    path_coeffs <- pls_result$path_coefs
    write.csv(as.data.frame(path_coeffs), file.path(output_dir, "tables", "plspm_path_coeffs.csv"))
    
    # 保存 R²
    r_squared <- pls_result$inner_summary
    write.csv(as.data.frame(r_squared), file.path(output_dir, "tables", "plspm_r_squared.csv"))
    
    # 路径图
    png(file.path(output_dir, "figures", "plspm_path_diagram.png"), width = 2400, height = 2000, res = 300)
    plot(pls_result)
    title("PLS-PM Path Diagram")
    dev.off()
    
    pdf(file.path(output_dir, "figures", "plspm_path_diagram.pdf"), width = 12, height = 10)
    plot(pls_result)
    title("PLS-PM Path Diagram")
    dev.off()
    
    return(list(
      path_coeffs = path_coeffs,
      r_squared = r_squared,
      gof = pls_result$gof
    ))
  }
  
  return(NULL)
}

if (sys.nframe() == 0) {
  cat("Usage: source this script and call run_plspm_analysis() function\n")
}
