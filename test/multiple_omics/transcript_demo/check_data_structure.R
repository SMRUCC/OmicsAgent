# =============================================================================
# check_data_structure.R  --  转录组输入数据结构核对
# 读取三个输入文件，输出维度、ID 列匹配、分组水平、注释覆盖与数值统计，
# 并导出 00_ 前缀 CSV 供 DEBUG_REPORT 引用。
# =============================================================================
source("config.R")

section("数据加载")
step("读取表达矩阵")
expr_raw <- read.csv(EXPR_FILE, check.names = FALSE, stringsAsFactors = FALSE)
expr_id_col <- colnames(expr_raw)[1]
expr_ids <- as.character(expr_raw[[expr_id_col]])
expr_ids <- make.unique(expr_ids)
expr_mat <- as.matrix(expr_raw[, -1, drop = FALSE])
mode(expr_mat) <- "numeric"
rownames(expr_mat) <- expr_ids
colnames(expr_mat) <- colnames(expr_raw)[-1]
mat_dim(expr_mat, "expression matrix")

step("读取特征注释")
feat <- read.csv(FEATURE_FILE, check.names = FALSE, stringsAsFactors = FALSE)
mat_dim(feat, "feature_info")
feat_id_col <- colnames(feat)[1]

step("读取样本信息")
samp <- read.csv(SAMPLE_FILE, check.names = FALSE, stringsAsFactors = FALSE)
rownames(samp) <- as.character(samp$ID)
mat_dim(samp, "sample_info")

section("ID 列匹配关系")
cat("  表达矩阵首列名:", expr_id_col, "\n")
cat("  特征注释首列名:", feat_id_col, "\n")
overlap_name  <- length(intersect(rownames(expr_mat), feat$name))
overlap_gid   <- length(intersect(rownames(expr_mat), feat[[feat_id_col]]))
dup_expr      <- sum(duplicated(rownames(expr_mat)))
dup_feat_name <- sum(duplicated(feat$name))
dup_feat_gid  <- sum(duplicated(feat[[feat_id_col]]))
cat(sprintf("  表达矩阵 vs 特征 name 交集: %d / %d\n", overlap_name, nrow(expr_mat)))
cat(sprintf("  表达矩阵 vs 特征 %s 交集: %d / %d\n", feat_id_col, overlap_gid, nrow(expr_mat)))
cat(sprintf("  表达矩阵首列重复数: %d\n", dup_expr))
cat(sprintf("  特征 name 重复数: %d ; %s 重复数: %d\n", dup_feat_name, feat_id_col, dup_feat_gid))
sample_match <- length(intersect(colnames(expr_mat), rownames(samp)))
cat(sprintf("  样本匹配数: %d / %d\n", sample_match, ncol(expr_mat)))

section("数值与缺失统计")
cat(sprintf("  值范围: [%.4f, %.4f]\n", min(expr_mat), max(expr_mat)))
cat(sprintf("  中位数: %.4f\n", median(expr_mat)))
cat(sprintf("  NA 数: %d ; 零值数: %d\n", sum(is.na(expr_mat)), sum(expr_mat == 0, na.rm = TRUE)))
cat(sprintf("  is_integer_like: %s\n", all(abs(expr_mat - round(expr_mat)) < 1e-9, na.rm = TRUE)))

section("分组水平分布")
for (c in c("phase", "variety", "location", "timepoint")) {
  if (c %in% colnames(samp)) {
    tb <- table(samp[[c]])
    cat(sprintf("  %s (%d 水平): %s\n", c, length(tb),
                paste(sprintf("%s=%d", names(tb), tb), collapse = ", ")))
  }
}

section("注释列覆盖率")
for (c in c("kegg", "category", "super_class", "family", "description")) {
  if (c %in% colnames(feat)) {
    non_empty <- sum(nzchar(as.character(feat[[c]])) & !is.na(feat[[c]]))
    cat(sprintf("  %s: 非空 %d / %d (%.1f%%) ; 水平数 %d\n",
                c, non_empty, nrow(feat), 100 * non_empty / nrow(feat),
                length(unique(feat[[c]]))))
  }
}

section("导出核对结果")
summary_df <- data.frame(
  item = c("expr_rows", "expr_cols", "feat_rows", "feat_cols", "samp_rows", "samp_cols",
           "overlap_name", "overlap_gene_id", "dup_expr_id", "dup_feat_name",
           "sample_match", "value_min", "value_max", "value_median",
           "n_na", "n_zero", "kegg_nonempty", "super_class_levels"),
  value = c(nrow(expr_mat), ncol(expr_mat), nrow(feat), ncol(feat), nrow(samp), ncol(samp),
            overlap_name, overlap_gid, dup_expr, dup_feat_name,
            sample_match, round(min(expr_mat), 4), round(max(expr_mat), 4),
            round(median(expr_mat), 4), sum(is.na(expr_mat)),
            sum(expr_mat == 0, na.rm = TRUE),
            sum(nzchar(as.character(feat$kegg)) & !is.na(feat$kegg)),
            length(unique(feat$super_class))))
write.csv(summary_df, file.path(RESULTS_DIR, "00_data_structure_summary.csv"),
          row.names = FALSE)
cat("  已导出: results/00_data_structure_summary.csv\n")
step("完成")
