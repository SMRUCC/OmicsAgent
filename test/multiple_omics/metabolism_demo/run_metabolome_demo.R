# ==============================================================================
# 代谢组学 Demo 基础流程主脚本
# ==============================================================================
# 职责：数据加载对齐 -> 预处理链路 -> PCA -> PLS-DA -> limma 两组差异 -> 火山图
#       -> ANOVA/F 多组差异 -> 聚类热图 -> 化学分类富集
# 末尾将中间矩阵缓存为 cache/*.rds 供进阶脚本复用。
#
# 本脚本只调用 agent/rscript 中的模块函数，不重写任何分析逻辑。
# ==============================================================================

source("g:/OmicsWorks/test/multiple_omics/metabolism_demo/config.R", encoding = "UTF-8")

set.seed(RANDOM_SEED)

section("代谢组学 Demo 基础流程")

# ------------------------------------------------------------------------------
# 加载模块
# ------------------------------------------------------------------------------
step("加载 agent/rscript 模块")
source_modules(c(
  "utils/load_data.R",
  "utils/export.R",
  "utils/plot_helpers.R",
  "preprocessing/filter_missing.R",
  "preprocessing/impute_missing.R",
  "preprocessing/normalize.R",
  "preprocessing/scale.R",
  "multivariate/pca.R",
  "multivariate/plsda.R",
  "differential/limma_de.R",
  "differential/anova.R",
  "differential/f_test.R",
  "visualization/volcano_plot.R",
  "visualization/heatmap_plot.R",
  "enrichment/fisher_enrich.R"
))

# ==============================================================================
# SECTION 1: 数据加载与对齐
# ==============================================================================
section("SECTION 1  数据加载与对齐")

# 由 check_data_structure.R 实测确认：表达矩阵行名为化合物名，100% 命中
# featureinfo$name，因此 id_col 必须为 "name"（而非默认的 "ID"）。
FEATURE_ID_COL <- "name"

expr_raw <- load_expression_matrix(FILE_EXPR)
sample_info <- load_sample_info(FILE_SAMPLE)
feature_info <- load_feature_info(FILE_FEATURE, id_col = FEATURE_ID_COL)

mat_dim("原始表达矩阵", expr_raw)
cat(sprintf("    样本信息 : %d 行 x %d 列\n", nrow(sample_info), ncol(sample_info)))
cat(sprintf("    特征注释 : %d 行 x %d 列\n", nrow(feature_info), ncol(feature_info)))

omics <- create_omics_data(expr_raw, sample_info, feature_info,
                           match_col = FEATURE_ID_COL)
print(omics)

expr_raw     <- omics$expression
sample_info  <- omics$sample_info
feature_info <- omics$feature_info

cat("\n分组分布:\n")
for (gc in c(GROUP_VARIETY, GROUP_PHASE, GROUP_LOCATION)) {
  cat(sprintf("  %-10s : %s\n", gc,
              paste(sprintf("%s=%d", names(table(sample_info[[gc]])),
                            table(sample_info[[gc]])), collapse = ", ")))
}

# ==============================================================================
# SECTION 2: 预处理链路
# ==============================================================================
section("SECTION 2  预处理链路")

# --- 2.1 缺失值过滤 -----------------------------------------------------------
step("2.1 缺失值过滤 filter_missing_values (method='group', group_col=phase)")
filt <- filter_missing_values(
  expr_raw, sample_info,
  threshold = 0.8, method = "group", group_col = GROUP_PHASE
)
mat_dim("过滤后", filt$filtered_matrix)
cat(sprintf("    移除特征数: %d, 保留: %d\n",
            length(filt$removed_features), length(filt$kept_features)))
export_table(filt$missing_report, RESULT_DIR, "01_missing_value_report",
             use_rownames = FALSE)

mat_filt <- filt$filtered_matrix

# --- 2.2 缺失值填补 -----------------------------------------------------------
step("2.2 缺失值填补 impute_min_half")
mat_imp <- impute_min_half(mat_filt)
mat_dim("填补后", mat_imp)
cat(sprintf("    剩余 NA 数: %d\n", sum(is.na(mat_imp))))

# --- 2.3 归一化 ---------------------------------------------------------------
step("2.3 中位数归一化 normalize_median")
mat_norm <- normalize_median(mat_imp)
mat_dim("归一化后", mat_norm)
cat(sprintf("    样本中位数范围: [%.4g, %.4g]\n",
            min(apply(mat_norm, 2, stats::median)),
            max(apply(mat_norm, 2, stats::median))))

# --- 2.4 log2 变换 ------------------------------------------------------------
# 模块库未提供独立 log 变换函数，此处为极薄内联步骤（非分析逻辑）
step("2.4 log2(x+1) 变换")
log2_mat <- log2(mat_norm + 1)
mat_dim("log2 矩阵", log2_mat)
cat(sprintf("    数值范围: [%.4g, %.4g]\n", min(log2_mat), max(log2_mat)))

# --- 2.5 Pareto 标度 ----------------------------------------------------------
step("2.5 Pareto 标度 scale_pareto (作用于 log2 矩阵)")
pareto_mat <- scale_pareto(log2_mat)
mat_dim("Pareto 矩阵", pareto_mat)
cat(sprintf("    数值范围: [%.4g, %.4g]\n", min(pareto_mat), max(pareto_mat)))

export_table(as.data.frame(log2_mat), RESULT_DIR, "01_matrix_log2",
             use_rownames = TRUE, id_col_name = "metabolite")

# ==============================================================================
# SECTION 3: PCA 主成分分析
# ==============================================================================
section("SECTION 3  PCA 主成分分析")

step("run_pca (Pareto 矩阵, 已标度故 scale=FALSE)")
pca_res <- run_pca(pareto_mat, scale = FALSE, center = TRUE, ncomp = 5)
cat(sprintf("    组分数: %d\n", pca_res$ncomp))
cat("    方差解释率(%):",
    paste(sprintf("PC%d=%.2f", seq_along(pca_res$var_explained),
                  pca_res$var_explained), collapse = ", "), "\n")

export_table(pca_res$scores, RESULT_DIR, "02_pca_scores", use_rownames = FALSE)
export_table(pca_res$loadings, RESULT_DIR, "02_pca_loadings", use_rownames = FALSE)

step("plot_pca_scores (color=phase, shape=variety)")
p_pca <- plot_pca_scores(pca_res, sample_info,
                         color_col = GROUP_PHASE, shape_col = GROUP_VARIETY,
                         pc_x = 1, pc_y = 2, show_ellipse = TRUE)
export_plot(p_pca, FIGURE_DIR, "02_pca_scores_phase", width = 9, height = 7)

p_pca2 <- plot_pca_scores(pca_res, sample_info,
                          color_col = GROUP_VARIETY, shape_col = GROUP_LOCATION,
                          pc_x = 1, pc_y = 2, show_ellipse = TRUE)
export_plot(p_pca2, FIGURE_DIR, "02_pca_scores_variety", width = 9, height = 7)

step("plot_pca_loadings")
p_load <- plot_pca_loadings(pca_res, pc_x = 1, pc_y = 2, top_n = 15)
export_plot(p_load, FIGURE_DIR, "02_pca_loadings", width = 8, height = 7)

# ==============================================================================
# SECTION 4: PLS-DA 判别分析
# ==============================================================================
section("SECTION 4  PLS-DA 判别分析")

plsda_runs <- list()
for (gc in c(GROUP_VARIETY, GROUP_PHASE)) {
  section(sprintf("4.x PLS-DA  group_col = %s", gc), 2)
  step(sprintf("run_plsda (group_col=%s, ncomp=2)", gc))
  pl <- run_plsda(pareto_mat, sample_info, group_col = gc, ncomp = 2)
  cat("    分组水平:", paste(pl$groups, collapse = ", "), "\n")
  cat("    scores 列名:", paste(colnames(pl$scores), collapse = ", "), "\n")
  cat(sprintf("    VIP 特征数: %d, VIP>1 的特征数: %d\n",
              nrow(pl$vip), sum(pl$vip$vip > 1)))

  export_table(pl$scores, RESULT_DIR,
               sprintf("03_plsda_scores_%s", gc), use_rownames = FALSE)
  export_table(pl$vip, RESULT_DIR,
               sprintf("03_plsda_vip_%s", gc),
               use_rownames = TRUE, id_col_name = "metabolite")

  p_sc <- plot_plsda_scores(pl, sample_info, color_col = gc,
                            comp_x = 1, comp_y = 2, show_ellipse = TRUE)
  export_plot(p_sc, FIGURE_DIR, sprintf("03_plsda_scores_%s", gc),
              width = 9, height = 7)

  p_vip <- plot_vip(pl, top_n = 25, threshold = 1.0)
  export_plot(p_vip, FIGURE_DIR, sprintf("03_plsda_vip_%s", gc),
              width = 8, height = 8)

  plsda_runs[[gc]] <- pl
}

# ==============================================================================
# SECTION 5: 缓存中间态
# ==============================================================================
section("SECTION 5  缓存中间态供进阶脚本复用")

saveRDS(log2_mat,       file.path(CACHE_DIR, "log2_mat.rds"))
saveRDS(pareto_mat,     file.path(CACHE_DIR, "pareto_mat.rds"))
saveRDS(sample_info,    file.path(CACHE_DIR, "sample_info.rds"))
saveRDS(feature_info,   file.path(CACHE_DIR, "feature_info.rds"))
step("已缓存 log2_mat / pareto_mat / sample_info / feature_info")

cat("\n[done] SECTION 1-5 完成。\n")
