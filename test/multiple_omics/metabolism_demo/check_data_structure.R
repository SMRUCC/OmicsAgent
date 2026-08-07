# ==============================================================================
# 前置数据核对脚本
# ==============================================================================
# 职责：核实表达矩阵首列取值形态、与注释表 ID/name 列的匹配率、kegg 列非空比例、
#       class/super_class/family 分类分布、候选分组列取值分布、缺失值与零值比例。
# 产出：results/00_data_check_summary.csv 等核对摘要，用于确定后续脚本中
#       id_col / category_col / 分组列 / KEGG 可行性的正确取值。
# ==============================================================================

source("g:/OmicsWorks/test/multiple_omics/metabolism_demo/config.R", encoding = "UTF-8")

section("代谢组学 Demo - 数据结构核对")

# ------------------------------------------------------------------------------
# 加载模块
# ------------------------------------------------------------------------------
step("加载模块 utils/load_data.R")
source_modules(c("utils/load_data.R", "utils/export.R"))

summary_rows <- list()
add_row <- function(item, value) {
  summary_rows[[length(summary_rows) + 1]] <<-
    data.frame(item = item, value = as.character(value),
               stringsAsFactors = FALSE)
}

# ------------------------------------------------------------------------------
# 1. 原始 CSV 结构
# ------------------------------------------------------------------------------
section("1. 原始 CSV 结构", 2)

raw_expr <- utils::read.csv(FILE_EXPR, check.names = FALSE,
                            stringsAsFactors = FALSE, nrows = 5)
cat("表达矩阵前 5 列列名:\n")
print(utils::head(colnames(raw_expr), 5))
cat("表达矩阵第一列列名:", colnames(raw_expr)[1], "\n")
cat("表达矩阵第一列前 5 个取值:\n")
print(utils::head(raw_expr[[1]], 5))

add_row("expr_first_col_name", colnames(raw_expr)[1])
add_row("expr_first_col_example", paste(utils::head(raw_expr[[1]], 3), collapse = " | "))

# ------------------------------------------------------------------------------
# 2. 表达矩阵加载
# ------------------------------------------------------------------------------
section("2. 表达矩阵加载", 2)

expr <- load_expression_matrix(FILE_EXPR)
mat_dim("expression matrix", expr)
add_row("n_features", nrow(expr))
add_row("n_samples", ncol(expr))

na_ratio <- sum(is.na(expr)) / length(expr)
zero_ratio <- sum(expr == 0, na.rm = TRUE) / length(expr)
cat(sprintf("    NA 比例   : %.4f\n", na_ratio))
cat(sprintf("    零值比例  : %.4f\n", zero_ratio))
cat(sprintf("    数值范围  : [%.4g, %.4g]\n", min(expr, na.rm = TRUE), max(expr, na.rm = TRUE)))
add_row("na_ratio", sprintf("%.4f", na_ratio))
add_row("zero_ratio", sprintf("%.4f", zero_ratio))
add_row("value_min", sprintf("%.6g", min(expr, na.rm = TRUE)))
add_row("value_max", sprintf("%.6g", max(expr, na.rm = TRUE)))

# 每特征缺失率分布
feat_na <- rowSums(is.na(expr)) / ncol(expr)
cat("    每特征缺失率分位数:\n")
print(round(stats::quantile(feat_na, c(0, .25, .5, .75, .9, 1)), 4))
add_row("feature_na_max", sprintf("%.4f", max(feat_na)))
add_row("feature_na_gt_50pct", sum(feat_na > 0.5))

# ------------------------------------------------------------------------------
# 3. 注释表核对 —— 决定 id_col
# ------------------------------------------------------------------------------
section("3. 注释表核对（决定 load_feature_info 的 id_col）", 2)

raw_feat <- utils::read.csv(FILE_FEATURE, check.names = FALSE,
                            stringsAsFactors = FALSE)
cat("注释表列名:", paste(colnames(raw_feat), collapse = ", "), "\n")
cat("注释表行数:", nrow(raw_feat), "\n")
add_row("featureinfo_cols", paste(colnames(raw_feat), collapse = ";"))
add_row("featureinfo_nrow", nrow(raw_feat))

expr_ids <- rownames(expr)
match_ID   <- sum(expr_ids %in% as.character(raw_feat$ID))
match_name <- sum(expr_ids %in% as.character(raw_feat$name))
cat(sprintf("    表达矩阵行名 命中 featureinfo$ID   : %d / %d (%.1f%%)\n",
            match_ID, length(expr_ids), 100 * match_ID / length(expr_ids)))
cat(sprintf("    表达矩阵行名 命中 featureinfo$name : %d / %d (%.1f%%)\n",
            match_name, length(expr_ids), 100 * match_name / length(expr_ids)))
add_row("match_rate_ID", sprintf("%.1f%%", 100 * match_ID / length(expr_ids)))
add_row("match_rate_name", sprintf("%.1f%%", 100 * match_name / length(expr_ids)))

FEATURE_ID_COL <- if (match_ID >= match_name) "ID" else "name"
cat(sprintf("    => 结论: 应使用 id_col = \"%s\"\n", FEATURE_ID_COL))
add_row("RECOMMENDED_feature_id_col", FEATURE_ID_COL)

# ------------------------------------------------------------------------------
# 4. KEGG 列可行性
# ------------------------------------------------------------------------------
section("4. KEGG 列可行性评估", 2)

kegg_vals <- as.character(raw_feat$kegg)
kegg_vals[is.na(kegg_vals)] <- ""
kegg_vals <- trimws(kegg_vals)
n_kegg <- sum(nzchar(kegg_vals))
uniq_kegg <- unique(kegg_vals[nzchar(kegg_vals)])
cat(sprintf("    kegg 非空条目 : %d / %d (%.1f%%)\n",
            n_kegg, nrow(raw_feat), 100 * n_kegg / nrow(raw_feat)))
cat(sprintf("    唯一 KEGG 化合物数 : %d\n", length(uniq_kegg)))
if (length(uniq_kegg) > 0) {
  cat("    示例:", paste(utils::head(uniq_kegg, 10), collapse = ", "), "\n")
}
add_row("kegg_nonempty", n_kegg)
add_row("kegg_nonempty_pct", sprintf("%.1f%%", 100 * n_kegg / nrow(raw_feat)))
add_row("kegg_unique_compounds", length(uniq_kegg))
add_row("kegg_example", paste(utils::head(uniq_kegg, 5), collapse = ";"))

# ------------------------------------------------------------------------------
# 5. 化学分类列分布 —— 决定富集与 PLSPM 的 category_col
# ------------------------------------------------------------------------------
section("5. 化学分类列分布", 2)

cat_report <- list()
for (cc in c("super_class", "class", "family", "type")) {
  if (!cc %in% colnames(raw_feat)) next
  v <- as.character(raw_feat[[cc]])
  v[is.na(v)] <- ""
  v <- trimws(v)
  nonempty <- sum(nzchar(v))
  tb <- sort(table(v[nzchar(v)]), decreasing = TRUE)
  n_ge3 <- sum(tb >= 3)
  cat(sprintf("  [%s] 非空 %d (%.1f%%) | 类别数 %d | 成员>=3 的类别数 %d\n",
              cc, nonempty, 100 * nonempty / nrow(raw_feat), length(tb), n_ge3))
  if (length(tb) > 0) {
    cat("      Top5: ",
        paste(sprintf("%s(%d)", names(utils::head(tb, 5)), utils::head(tb, 5)),
              collapse = ", "), "\n")
  }
  add_row(paste0("cat_", cc, "_n_levels"), length(tb))
  add_row(paste0("cat_", cc, "_n_levels_ge3"), n_ge3)
  add_row(paste0("cat_", cc, "_nonempty_pct"), sprintf("%.1f%%", 100 * nonempty / nrow(raw_feat)))

  if (length(tb) > 0) {
    cat_report[[cc]] <- data.frame(
      column = cc, category = names(tb), n = as.integer(tb),
      stringsAsFactors = FALSE
    )
  }
}
if (length(cat_report) > 0) {
  cat_df <- do.call(rbind, cat_report)
  export_table(cat_df, RESULT_DIR, "00_feature_category_distribution",
               use_rownames = FALSE)
  step("已导出 00_feature_category_distribution.csv")
}

# ------------------------------------------------------------------------------
# 6. 样本信息表核对
# ------------------------------------------------------------------------------
section("6. 样本信息表核对", 2)

sinfo <- load_sample_info(FILE_SAMPLE)
cat("样本信息列名:", paste(colnames(sinfo), collapse = ", "), "\n")
cat("样本信息行数:", nrow(sinfo), "\n")
add_row("sampleinfo_cols", paste(colnames(sinfo), collapse = ";"))
add_row("sampleinfo_nrow", nrow(sinfo))

common_s <- intersect(colnames(expr), rownames(sinfo))
cat(sprintf("    表达矩阵列名 与 sampleinfo$ID 交集: %d / %d\n",
            length(common_s), ncol(expr)))
add_row("sample_match_count", length(common_s))

cat("\n候选分组列取值分布:\n")
group_report <- list()
for (gc in colnames(sinfo)) {
  v <- as.character(sinfo[[gc]])
  nu <- length(unique(v))
  if (nu < 2 || nu > 30) {
    cat(sprintf("  [%-14s] 唯一值 %-4d  (跳过: %s)\n", gc, nu,
                if (nu < 2) "常量列" else "粒度过细"))
    next
  }
  tb <- sort(table(v), decreasing = TRUE)
  cat(sprintf("  [%-14s] 唯一值 %-4d : %s\n", gc, nu,
              paste(sprintf("%s=%d", names(tb), tb), collapse = ", ")))
  group_report[[gc]] <- data.frame(
    column = gc, level = names(tb), n = as.integer(tb),
    stringsAsFactors = FALSE
  )
  add_row(paste0("group_", gc, "_n_levels"), nu)
}
if (length(group_report) > 0) {
  grp_df <- do.call(rbind, group_report)
  export_table(grp_df, RESULT_DIR, "00_sample_group_distribution",
               use_rownames = FALSE)
  step("已导出 00_sample_group_distribution.csv")
}

# ------------------------------------------------------------------------------
# 7. QC 样本存在性（多模块 exclude_groups 默认 "QC"）
# ------------------------------------------------------------------------------
section("7. QC 样本存在性检查", 2)
has_qc <- any(grepl("QC", unlist(lapply(sinfo, as.character)), ignore.case = TRUE))
cat("    数据集中是否存在 QC 标记:", has_qc, "\n")
add_row("has_QC_samples", has_qc)

# ------------------------------------------------------------------------------
# 8. create_omics_data 对齐测试（同时测试 print.OmicsData）
# ------------------------------------------------------------------------------
section("8. create_omics_data 对齐测试", 2)

finfo <- load_feature_info(FILE_FEATURE, id_col = FEATURE_ID_COL)
cat("feature_info rownames 示例:", paste(utils::head(rownames(finfo), 3), collapse = ", "), "\n")

od <- create_omics_data(expr, sinfo, finfo, match_col = FEATURE_ID_COL)
print(od)

# ------------------------------------------------------------------------------
# 导出核对摘要
# ------------------------------------------------------------------------------
section("导出核对摘要")
summary_df <- do.call(rbind, summary_rows)
export_table(summary_df, RESULT_DIR, "00_data_check_summary", use_rownames = FALSE)
step("已导出 00_data_check_summary.csv")

cat("\n[done] 数据结构核对完成。\n")
