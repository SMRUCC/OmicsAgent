' ============================================================================
' R# 工具函数脚本 - 表达矩阵数据导入导出
' ============================================================================
' 该脚本提供表达矩阵数据的导入、导出、格式转换等工具函数。
' R# 是 GCModeller 项目提供的 R 语言变体解释器。
' ============================================================================

imports "dataframe" from "base";
imports "csv" from "data";

read_omics_matrix <- function(file) {
    ' 读取组学表达矩阵 CSV 文件
    ' 要求格式：行为分子，列为样本
    ' 第一行为样本 ID，第一列为分子 ID
    matrix <- csv::load(file);
    matrix <- dataframe::cast(matrix);
    
    ' 第一列作为行名
    rownames(matrix) <- matrix[, 1];
    matrix <- matrix[, -1];
    
    ' 转换为数值
    for (col in colnames(matrix)) {
        matrix[, col] <- as.numeric(matrix[, col]);
    }
    
    return(matrix);
}

write_omics_matrix <- function(matrix, file) {
    ' 写入组学表达矩阵 CSV 文件
    ' 格式：行为分子，列为样本
    df <- dataframe::create(molecule_id = rownames(matrix));
    for (col in colnames(matrix)) {
        df[, col] <- matrix[, col];
    }
    csv::save(df, file = file);
}

validate_matrix_format <- function(file) {
    ' 验证表达矩阵格式是否符合要求
    ' 返回 list(valid, n_molecules, n_samples, error_message)
    result <- list(valid = TRUE, n_molecules = 0, n_samples = 0, error_message = "");
    
    tryCatch({
        matrix <- csv::load(file);
        if (ncol(matrix) < 2) {
            result$valid <- FALSE;
            result$error_message <- "Matrix must have at least 2 columns (molecule ID + 1 sample)";
            return(result);
        }
        if (nrow(matrix) < 2) {
            result$valid <- FALSE;
            result$error_message <- "Matrix must have at least 2 rows (header + 1 molecule)";
            return(result);
        }
        
        result$n_molecules <- nrow(matrix) - 1;
        result$n_samples <- ncol(matrix) - 1;
    }, error = function(e) {
        result$valid <- FALSE;
        result$error_message <- e$message;
    });
    
    return(result);
}

if (sys.nframe() == 0) {
    cat("Usage: source this script and call the functions\n");
}
