# ============================================================================
# R 工具函数脚本 - 表达矩阵数据预处理
# ============================================================================
# 该脚本实现了表达矩阵数据预处理的标准流程：
# 1. 按行做分子表达数据最小阳性值的一半做缺失值填充
# 2. 按列总和归一化转化为相对表达量
# 3. 如有必要，针对归一化后的值做 log 转换
# 4. 按行做中位数缩放
#
# 使用方式：
#   source("preprocess_expression.R")
#   result <- preprocess_expression(
#     input_file = "expression.csv",
#     output_file = "preprocessed_expression.csv",
#     do_log = TRUE,
#     do_median_scale = TRUE
#   )
# ============================================================================

preprocess_expression <- function(input_file, output_file,
                                  do_log = TRUE, do_median_scale = TRUE,
                                  fill_na_method = "half_min_positive") {
  # 读取表达矩阵
  expr <- read.csv(input_file, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
  
  # 转换为数值矩阵
  expr_matrix <- as.matrix(expr)
  mode(expr_matrix) <- "numeric"
  
  cat("Original matrix:", nrow(expr_matrix), "molecules x", ncol(expr_matrix), "samples\n")
  cat("Missing values:", sum(is.na(expr_matrix)), "\n")
  
  # 1. 缺失值填充：按行做最小阳性值的一半
  if (fill_na_method == "half_min_positive") {
    for (i in 1:nrow(expr_matrix)) {
      row_vals <- expr_matrix[i, ]
      positive_vals <- row_vals[!is.na(row_vals) & row_vals > 0]
      if (length(positive_vals) > 0) {
        min_positive <- min(positive_vals)
        fill_value <- min_positive / 2
        na_indices <- is.na(row_vals)
        if (any(na_indices)) {
          expr_matrix[i, na_indices] <- fill_value
        }
      } else {
        expr_matrix[i, is.na(row_vals)] <- 0
      }
    }
    cat("Missing values filled with half of minimum positive value per row\n")
  }
  
  # 2. 按列总和归一化（转化为相对表达量）
  col_sums <- colSums(expr_matrix, na.rm = TRUE)
  col_sums[col_sums == 0] <- 1
  expr_matrix <- sweep(expr_matrix, 2, col_sums, "/")
  cat("Column sum normalization done\n")
  
  # 3. log 转换
  if (do_log) {
    expr_matrix[expr_matrix <= 0] <- min(expr_matrix[expr_matrix > 0]) / 2
    expr_matrix <- log2(expr_matrix)
    cat("Log2 transformation done\n")
  }
  
  # 4. 按行做中位数缩放
  if (do_median_scale) {
    row_medians <- apply(expr_matrix, 1, median, na.rm = TRUE)
    row_medians[row_medians == 0] <- 1
    expr_matrix <- sweep(expr_matrix, 1, row_medians, "-")
    cat("Row median scaling done\n")
  }
  
  # 保存结果
  result_df <- data.frame(id = rownames(expr_matrix), expr_matrix, check.names = FALSE)
  write.csv(result_df, output_file, row.names = FALSE)
  
  cat("Preprocessed matrix saved to:", output_file, "\n")
  cat("Final matrix:", nrow(expr_matrix), "molecules x", ncol(expr_matrix), "samples\n")
  
  return(list(
    matrix = expr_matrix,
    n_molecules = nrow(expr_matrix),
    n_samples = ncol(expr_matrix),
    output_file = output_file
  ))
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 2) {
    preprocess_expression(
      input_file = args[1],
      output_file = args[2],
      do_log = ifelse(length(args) >= 3, as.logical(args[3]), TRUE),
      do_median_scale = ifelse(length(args) >= 4, as.logical(args[4]), TRUE)
    )
  } else {
    cat("Usage: Rscript preprocess_expression.R <input_file> <output_file> [do_log] [do_median_scale]\n")
  }
}
