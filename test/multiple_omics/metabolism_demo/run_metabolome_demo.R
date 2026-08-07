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
# SECTION 5: limma 两组差异分析 (variety)
# ==============================================================================
section("SECTION 5  limma 两组差异分析 (variety: Virginia vs Burley)")

step("run_limma (control_group=Burley, strategy=pvalue_logFC)")
# 差异分析在 log2 空间进行，保证 logFC 语义正确
de_variety <- run_limma(
  log2_mat, sample_info,
  group_col = GROUP_VARIETY,
  control_group = "Burley",
  exclude_groups = NULL,          # 本数据集无 QC 样本，显式关闭默认排除
  strategy = "pvalue_logFC",
  p_threshold = 0.05,
  logfc_threshold = 0.25          # log2 归一化后动态范围较小，阈值相应下调
)
cat(sprintf("    结果行数: %d\n", nrow(de_variety$results)))
cat(sprintf("    显著特征数: %d\n", nrow(de_variety$significant)))
cat("    调节方向分布:",
    paste(sprintf("%s=%d", names(table(de_variety$results$regulation)),
                  table(de_variety$results$regulation)), collapse = ", "), "\n")

export_table(de_variety$results, RESULT_DIR, "04_limma_variety_all",
             use_rownames = FALSE)
export_table(de_variety$significant, RESULT_DIR, "04_limma_variety_significant",
             use_rownames = FALSE)

step("plot_volcano")
p_volc <- plot_volcano(de_variety$results, p_col = "p_adj",
                       p_threshold = 0.05, logfc_threshold = 0.25, top_n = 10)
export_plot(p_volc, FIGURE_DIR, "04_volcano_variety", width = 9, height = 7)

# --- 另测 pvalue_topN 策略（覆盖该分支的索引逻辑）---------------------------
step("run_limma (strategy=pvalue_topN, top_n=30) 覆盖 topN 分支")
de_topn <- run_limma(
  log2_mat, sample_info,
  group_col = GROUP_VARIETY, control_group = "Burley",
  exclude_groups = NULL, strategy = "pvalue_topN",
  p_threshold = 0.05, top_n = 30
)
cat(sprintf("    topN 策略显著特征数: %d (期望 <= 30)\n",
            nrow(de_topn$significant)))
export_table(de_topn$significant, RESULT_DIR, "04_limma_variety_top30",
             use_rownames = FALSE)

# --- 另测 pvalue_vip 策略（覆盖 merge 分支）----------------------------------
step("run_limma (strategy=pvalue_vip) 覆盖 VIP 合并分支")
de_vip <- run_limma(
  log2_mat, sample_info,
  group_col = GROUP_VARIETY, control_group = "Burley",
  exclude_groups = NULL, strategy = "pvalue_vip",
  p_threshold = 0.05, vip_threshold = 1.0,
  vip_result = plsda_runs[[GROUP_VARIETY]]$vip
)
cat(sprintf("    VIP 策略显著特征数: %d\n", nrow(de_vip$significant)))
export_table(de_vip$significant, RESULT_DIR, "04_limma_variety_vip",
             use_rownames = FALSE)

# ==============================================================================
# SECTION 6: 多组差异检验 (phase)
# ==============================================================================
section("SECTION 6  多组差异检验 (phase, 4 组)")

step("run_f_test (group_col=phase)")
ft <- run_f_test(log2_mat, sample_info, group_col = GROUP_PHASE,
                 exclude_groups = NULL)
ft_res <- if (is.list(ft) && !is.data.frame(ft)) ft$results else ft
cat(sprintf("    F 检验结果行数: %d\n", nrow(ft_res)))
cat(sprintf("    p_adj < 0.05 的特征数: %d\n",
            sum(ft_res$p_adj < 0.05, na.rm = TRUE)))
export_table(ft_res, RESULT_DIR, "05_ftest_phase", use_rownames = FALSE)

step("run_anova (factors = variety * phase)")
av <- run_anova(log2_mat, sample_info,
                factors = c(GROUP_VARIETY, GROUP_PHASE),
                exclude_groups = NULL)
av_res <- if (is.list(av) && !is.data.frame(av)) av$results else av
cat(sprintf("    ANOVA 结果行数: %d\n", nrow(av_res)))
cat("    ANOVA 结果列名:", paste(colnames(av_res), collapse = ", "), "\n")
export_table(av_res, RESULT_DIR, "05_anova_variety_phase", use_rownames = FALSE)

# ==============================================================================
# SECTION 7: 聚类热图
# ==============================================================================
section("SECTION 7  聚类热图")

# 取 F 检验最显著的 top 60 代谢物
ord_ft <- order(ft_res$p_adj, decreasing = FALSE)
top_feats <- ft_res$feature_id[ord_ft][seq_len(min(60, nrow(ft_res)))]
top_feats <- intersect(top_feats, rownames(log2_mat))
cat(sprintf("    热图特征数: %d\n", length(top_feats)))

step("plot_heatmap (group_col=phase, family_col=super_class)")
hm <- plot_heatmap(
  log2_mat[top_feats, , drop = FALSE], sample_info, feature_info,
  group_col = GROUP_PHASE, name_col = "name", family_col = "super_class",
  scale = "row", show_rownames = TRUE, show_colnames = FALSE,
  n_features = 60
)
export_heatmap(hm, FIGURE_DIR, "06_heatmap_phase_top60",
               width = 12, height = 11)

# ==============================================================================
# SECTION 8: 化学分类富集分析
# ==============================================================================
section("SECTION 8  化学分类富集分析")

sig_feats <- unique(de_variety$significant$feature_id)
all_feats <- rownames(log2_mat)
cat(sprintf("    显著集: %d, 背景集: %d\n", length(sig_feats), length(all_feats)))

enrich_results <- list()
for (cc in c("super_class", "class", "family")) {
  section(sprintf("8.x 富集 category_col = %s", cc), 2)
  er <- run_fisher_enrich(
    significant_features = sig_feats,
    all_features = all_feats,
    feature_info = feature_info,
    feature_id_col = FEATURE_ID_COL,
    category_col = cc,
    min_size = 2
  )
  cat(sprintf("    富集类别数: %d\n", nrow(er)))
  if (nrow(er) > 0) {
    cat(sprintf("    p_adj < 0.05 的类别数: %d\n", sum(er$p_adj < 0.05)))
    cat("    Top3:", paste(head(rownames(er), 3), collapse = ", "), "\n")
  }
  export_table(er, RESULT_DIR, sprintf("07_enrichment_%s", cc),
               use_rownames = TRUE, id_col_name = "category")

  p_en <- plot_enrichment(er, top_n = 20, p_threshold = 0.05)
  export_plot(p_en, FIGURE_DIR, sprintf("07_enrichment_%s", cc),
              width = 9, height = 7)
  enrich_results[[cc]] <- er
}

# 额外用 kegg 列跑一次，覆盖"类别几乎全空"的边界情况
section("8.x 富集 category_col = kegg (边界测试)", 2)
er_kegg <- run_fisher_enrich(
  significant_features = sig_feats, all_features = all_feats,
  feature_info = feature_info, feature_id_col = FEATURE_ID_COL,
  category_col = "kegg", min_size = 2
)
cat(sprintf("    KEGG 富集类别数: %d\n", nrow(er_kegg)))
export_table(er_kegg, RESULT_DIR, "07_enrichment_kegg",
             use_rownames = TRUE, id_col_name = "category")
p_kegg <- plot_enrichment(er_kegg, top_n = 20)
export_plot(p_kegg, FIGURE_DIR, "07_enrichment_kegg", width = 9, height = 7)

# ==============================================================================
# SECTION 9: 缓存中间态
# ==============================================================================
section("SECTION 9  缓存中间态供进阶脚本复用")

saveRDS(log2_mat,       file.path(CACHE_DIR, "log2_mat.rds"))
saveRDS(pareto_mat,     file.path(CACHE_DIR, "pareto_mat.rds"))
saveRDS(sample_info,    file.path(CACHE_DIR, "sample_info.rds"))
saveRDS(feature_info,   file.path(CACHE_DIR, "feature_info.rds"))
saveRDS(list(variety = de_variety, ftest = ft_res, anova = av_res),
        file.path(CACHE_DIR, "de_results.rds"))
step("已缓存 log2_mat / pareto_mat / sample_info / feature_info / de_results")

cat("\n[done] 基础流程 SECTION 1-9 全部完成。\n")
