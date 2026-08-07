# =============================================================================
# check_data_structure.R  --  数据核对：为参数选择提供实测依据
# 产物：results/00_data_structure_report.csv (分组/列覆盖度汇总)
# =============================================================================
source("g:/OmicsWorks/test/multiple_omics/proteome_demo/config.R")

section("数据核对：维度、主键、注释覆盖、分组分布、数值尺度")

expr    <- read.csv(EXPR_FILE, check.names = FALSE)
feat    <- read.csv(FEATURE_FILE, check.names = FALSE)
sample  <- read.csv(SAMPLE_FILE, check.names = FALSE)

step("表达矩阵")
mat_dim(expr, "expr(full)")
expr_id <- expr[[1]]
mat_dim(length(unique(expr_id)), "expr unique ids")

step("注释表列与覆盖度")
cat("  feature cols:", paste(colnames(feat), collapse = " | "), "\n")
cov_rows <- data.frame(
  column = character(),
  nonempty = integer(),
  n_levels = integer(),
  stringsAsFactors = FALSE
)
for (cc in colnames(feat)) {
  v <- feat[[cc]]
  nonempty <- sum(!is.na(v) & v != "" & v != "#NAME?")
  nlev <- length(unique(v[!is.na(v) & v != "" & v != "#NAME?"]))
  cov_rows <- rbind(cov_rows, data.frame(column = cc, nonempty = nonempty, n_levels = nlev))
}
print(cov_rows)

step("注释表主键候选（name vs gene_id）与表达矩阵匹配率")
name_match  <- sum(expr_id %in% feat$name)
gene_match  <- sum(expr_id %in% feat$gene_id)
cat(sprintf("  expr_id in feat$name : %d / %d\n", name_match,  length(expr_id)))
cat(sprintf("  expr_id in feat$gene_id: %d / %d\n", gene_match, length(expr_id)))
cat(sprintf("  feat$name duplicated: %d ; feat$gene_id duplicated: %d\n",
            sum(duplicated(feat$name)), sum(duplicated(feat$gene_id))))
cat(sprintf("  '#NAME?' in name: %d ; in id: %d\n",
            sum(feat$name == "#NAME?"), sum(feat$id == "#NAME?")))

step("样本信息分组分布")
cat("  sample cols:", paste(colnames(sample), collapse = " | "), "\n")
for (g in c("sample_info", "phase", "variety", "location", "timepoint")) {
  if (g %in% colnames(sample)) {
    tb <- table(sample[[g]])
    cat(sprintf("  %-12s levels=%d  (top: %s)\n", g, length(tb),
                paste(head(names(sort(tb, decreasing = TRUE)), 4), collapse = ",")))
  }
}
cat(sprintf("  sample columns match expr columns: %d / %d\n",
            sum(colnames(expr)[-1] %in% sample$sample_name), length(colnames(expr)) - 1))

step("数值尺度诊断（是否已 log）")
m <- as.matrix(expr[, -1])
rng <- range(m, na.rm = TRUE)
cat(sprintf("  value range: [%.3f, %.3f]  median=%.3f  NA=%d zeros=%d\n",
            rng[1], rng[2], median(m, na.rm = TRUE), sum(is.na(m)), sum(m == 0, na.rm = TRUE)))
cat(sprintf("  max<50 ? => %s  (推断%s尺度)\n", max(m, na.rm = TRUE) < 50,
            ifelse(max(m, na.rm = TRUE) < 50, "log", "linear")))

step("导出核对报告")
write.csv(cov_rows, file.path(RESULTS_DIR, "00_feature_annotation_coverage.csv"), row.names = FALSE)
df_dist <- data.frame(
  metric = c("n_features", "n_samples", "name_match_rate", "linear_scale", "phase_levels", "variety_levels"),
  value  = c(nrow(expr), nrow(sample), round(name_match / length(expr_id), 4),
             as.integer(max(m, na.rm = TRUE) >= 50),
             length(unique(sample$phase)), length(unique(sample$variety)))
)
write.csv(df_dist, file.path(RESULTS_DIR, "00_data_structure_report.csv"), row.names = FALSE)
cat("  -> results/00_feature_annotation_coverage.csv\n")
cat("  -> results/00_data_structure_report.csv\n")
section("数据核对完成")
