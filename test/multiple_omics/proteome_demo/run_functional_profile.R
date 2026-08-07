# =============================================================================
# run_functional_profile.R  --  功能谱进阶分析
# -----------------------------------------------------------------------------
# 读取 run_proteome_demo.R 生成的 cache，对蛋白质按功能类别聚合丰度，
# 生成功能活性矩阵、功能谱热图、分组比较图与功能类别差异分析。
# 导出：results/06_func_*.csv 与 figures/06_func_*.{pdf,png}
# =============================================================================
source("g:/OmicsWorks/test/multiple_omics/proteome_demo/config.R")
set.seed(SEED)

source_modules(c(
  "utils/export.R",
  "utils/plot_helpers.R",
  "theme_palette.R",
  "differential/limma_de.R",
  "proteome/functional_profile.R",
  "visualization/heatmap_plot.R"
))

section("功能谱进阶分析：读取 cache")
pre_log  <- readRDS(file.path(CACHE_DIR, "pre_log.rds"))
samp     <- readRDS(file.path(CACHE_DIR, "samp_aligned.rds"))
feat     <- readRDS(file.path(CACHE_DIR, "feat_aligned.rds"))
mat_dim(pre_log, "pre_log"); mat_dim(feat, "feat_aligned")

# 确保 expr 矩阵行名与 feature_info 行名一致（均为 make.unique 后的 name）
common_rn <- intersect(rownames(pre_log), rownames(feat))
pre_log <- pre_log[common_rn, ]
feat    <- feat[common_rn, ]
cat(sprintf("  对齐后特征数: %d\n", length(common_rn)))

# =============================================================================
# SECTION A  按 super_class / category 计算功能谱
# =============================================================================
section("功能谱计算 (calc_protein_functional_profile)")

func_results <- list()
for (cat_col in c("super_class", "category")) {
  step(sprintf("计算功能谱: category_col='%s'", cat_col))
  fr <- calc_protein_functional_profile(pre_log, feat,
                                        category_col = cat_col,
                                        agg_method = "mean",
                                        min_size = 3,
                                        max_size = 200)
  func_results[[cat_col]] <- fr
  mat_dim(fr$profile_matrix, sprintf("profile[%s]", cat_col))
  export_table(fr$profile_matrix, RESULTS_DIR,
               sprintf("06_func_profile_%s.csv", cat_col))
  export_table(fr$category_info, RESULTS_DIR,
               sprintf("06_func_category_info_%s.csv", cat_col))
  cat(sprintf("    %d 个功能类别 (size>=3)\n", fr$params$n_categories))
}

# =============================================================================
# SECTION B  功能谱热图（按 phase 排列样本）
# =============================================================================
section("功能谱热图 (plot_functional_heatmap)")

for (cat_col in c("super_class", "category")) {
  step(sprintf("功能谱热图: %s", cat_col))
  p_hm <- plot_functional_heatmap(func_results[[cat_col]], samp,
                                  group_col = GROUP_PHASE, top_n = 30, scale = TRUE)
  export_plot(p_hm, FIGURES_DIR, sprintf("06_func_heatmap_%s", cat_col),
              width = 10, height = 8)
}
cat("  -> figures/06_func_heatmap_*.{pdf,png}\n")

# =============================================================================
# SECTION C  分组功能类别比较图（phase 与 variety）
# =============================================================================
section("功能类别分组比较图 (plot_functional_comparison)")

for (cat_col in c("super_class", "category")) {
  for (g in c(GROUP_PHASE, GROUP_VARIETY)) {
    step(sprintf("功能比较图: %s / %s", cat_col, g))
    p_cmp <- plot_functional_comparison(func_results[[cat_col]], samp,
                                        group_col = g, top_n = 15)
    export_plot(p_cmp, FIGURES_DIR,
                sprintf("06_func_comparison_%s_%s", cat_col, g),
                width = 10, height = 6)
  }
}
cat("  -> figures/06_func_comparison_*.{pdf,png}\n")

# =============================================================================
# SECTION D  功能类别差异分析（limma，修复后调用 run_limma）
# =============================================================================
section("功能类别差异分析 (diff_functional_category)")

for (cat_col in c("super_class", "category")) {
  step(sprintf("功能类别差异: %s (对照=%s)", cat_col, CONTRAST_PHASE_CONTROL))
  de_func <- diff_functional_category(func_results[[cat_col]], samp,
                                      group_col = GROUP_PHASE,
                                      control_group = CONTRAST_PHASE_CONTROL,
                                      p_adjust = "BH",
                                      p_threshold = P_THRESHOLD,
                                      fc_threshold = 0.5)
  export_table(de_func, RESULTS_DIR,
               sprintf("06_func_diff_%s.csv", cat_col))
  n_sig <- sum(de_func$significant)
  cat(sprintf("    %s: %d 个功能类别显著差异 (|logFC|>=0.5, p_adj<%.2f)\n",
              cat_col, n_sig, P_THRESHOLD))
}

section("功能谱进阶分析完成")
