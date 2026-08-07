# =============================================================================
# run_proteome_demo.R  --  烟草发酵蛋白质组学分析主流程
# -----------------------------------------------------------------------------
# 通过 source() 加载 agent/rscript 模块化函数，顺序完成：
#   SECTION 1  数据加载与对齐
#   SECTION 2  蛋白质组质控 (QC)
#   SECTION 3  预处理链路 (缺失过滤 -> 中位数归一化 -> log2 -> Pareto 标度)
#   SECTION 4  PCA 主成分分析
#   SECTION 5  limma 差异表达分析 (phase 主对比 + variety 次级对比)
#   SECTION 6  Fisher 过表达富集 (super_class / category / family)
#   SECTION 7  差异蛋白分层聚类热图
#   SECTION 8  中间态缓存 (cache/*.rds)
# 导出：results/*.csv 与 figures/*.{pdf,png}
# =============================================================================
source("g:/OmicsWorks/test/multiple_omics/proteome_demo/config.R")
set.seed(SEED)

# 模块加载（仅加载本流程实际调用的脚本，路径相对 agent/rscript）
source_modules(c(
  "utils/load_data.R",
  "utils/export.R",
  "utils/plot_helpers.R",
  "theme_palette.R",
  "preprocessing/filter_missing.R",
  "preprocessing/normalize.R",
  "preprocessing/scale.R",
  "preprocessing/transform.R",
  "proteome/protein_qc.R",
  "multivariate/pca.R",
  "differential/limma_de.R",
  "enrichment/fisher_enrich.R",
  "visualization/volcano_plot.R",
  "visualization/heatmap_plot.R"
))

# =============================================================================
# SECTION 1  数据加载与对齐
# =============================================================================
section("SECTION 1  数据加载与对齐")

step("加载表达矩阵 (load_expression_matrix)")
expr_mat <- load_expression_matrix(EXPR_FILE, feature_id_col = NULL)
mat_dim(expr_mat, "expr_mat")

step("加载样本信息 (load_sample_info)")
sample_info <- load_sample_info(SAMPLE_FILE)
mat_dim(sample_info, "sample_info")
cat("  sample_info 行名样例:", paste(head(rownames(sample_info)), collapse = ", "), "\n")

step("加载蛋白注释 (load_feature_info, id_col='name')")
# 注释表无大写 ID 列，用 name 作主键（与表达矩阵首列语义一致）。
# 重复 name 已在 load_feature_info 内通过 make.unique 兜底。
feature_info <- load_feature_info(FEATURE_FILE, id_col = "name")
mat_dim(feature_info, "feature_info")

step("构建统一组学对象 (create_omics_data, match_col='ID' 行名对齐)")
# expr_mat 与 feature_info 行名均由 name 经 make.unique 生成，规则一致，
# 用行名精确对齐可避免 name 重复导致的 fan-out。
omics <- create_omics_data(expr_mat, sample_info, feature_info, match_col = "ID")
mat_dim(omics$expression, "omics$expression")
cat("  匹配特征:", omics$metadata$matched_features,
    " / 未匹配:", omics$metadata$unmatched_features, "\n")
cat("  分组 (sample_info) 水平数:", omics$metadata$n_groups, "\n")

# 后续分析统一使用对齐后的矩阵与样本信息
expr_aligned <- omics$expression
samp_aligned <- omics$sample_info
feat_aligned <- omics$feature_info

# 分组列诊断
cat("  phase 水平:", paste(sort(unique(samp_aligned[[GROUP_PHASE]])), collapse = ", "), "\n")
cat("  variety 水平:", paste(sort(unique(samp_aligned[[GROUP_VARIETY]])), collapse = ", "), "\n")

# =============================================================================
# SECTION 2  蛋白质组质控 (QC)
# =============================================================================
section("SECTION 2  蛋白质组质控")

step("运行 QC (run_protein_qc, group_col=phase)")
qc_result <- run_protein_qc(expr_aligned, samp_aligned,
                            group_col = GROUP_PHASE,
                            cv_threshold = CV_THRESHOLD,
                            missing_rate_threshold = MISSING_THRESH,
                            log_transform = FALSE)
cat("  QC 参数:", paste(names(qc_result$params), qc_result$params, sep = "=", collapse = ", "), "\n")
cat("  标记异常样本数:", nrow(qc_result$flagged_samples),
    " 标记异常特征数:", nrow(qc_result$flagged_features), "\n")

step("导出 QC 表格")
export_table(qc_result$sample_summary, RESULTS_DIR, "01_qc_sample_summary.csv")
export_table(qc_result$feature_summary, RESULTS_DIR, "01_qc_feature_summary.csv")
export_table(qc_result$cv_distribution, RESULTS_DIR, "01_qc_cv_distribution.csv")
export_table(qc_result$missing_rates, RESULTS_DIR, "01_qc_missing_rates.csv")
cat("  -> results/01_qc_*.csv\n")

step("绘制并导出 QC 插图")
qc_plots <- plot_protein_qc(qc_result)
for (nm in names(qc_plots)) {
  if (!is.null(qc_plots[[nm]])) {
    export_plot(qc_plots[[nm]], FIGURES_DIR, sprintf("01_qc_%s", nm), width = 8, height = 6)
  }
}
cat("  -> figures/01_qc_*.{pdf,png}\n")

# =============================================================================
# SECTION 3  预处理链路
# =============================================================================
section("SECTION 3  预处理链路 (线性 -> log2 -> Pareto)")

step("缺失值过滤 (filter_missing_values, 本数据集无缺失应为全保留)")
# 注意：该函数返回 list（含 $filtered_matrix / $removed_features / $missing_report），
# 与同目录其它预处理函数（直接返回矩阵）接口不一致 —— 调用方需取 $filtered_matrix。
filt_obj <- filter_missing_values(expr_aligned, samp_aligned, sample_info = samp_aligned,
                                  method = "overall", threshold = 0.8)
pre_filt <- filt_obj$filtered_matrix
mat_dim(pre_filt, "pre_filt")
cat(sprintf("  被移除特征数: %d (本数据集应无缺失)\n", length(filt_obj$removed_features)))
export_table(filt_obj$missing_report, RESULTS_DIR, "02_missing_report.csv")

step("中位数归一化 (normalize_median)")
pre_norm <- normalize_median(pre_filt)
mat_dim(pre_norm, "pre_norm")

step("log2 变换 (log2_transform, pseudo_count=1)")
pre_log <- log2_transform(pre_norm, pseudo_count = 1, base = 2)
mat_dim(pre_log, "pre_log")

step("Pareto 标度 (scale_pareto, 用于 PCA)")
pre_pareto <- scale_pareto(pre_log)
mat_dim(pre_pareto, "pre_pareto")
cat("  Pareto 矩阵用于 PCA；log2 矩阵用于差异分析。\n")

# =============================================================================
# SECTION 4  PCA 主成分分析
# =============================================================================
section("SECTION 4  PCA 主成分分析")

step("运行 PCA (run_pca, scale=FALSE 因已 Pareto 标度)")
pca_obj <- run_pca(pre_pareto, scale = FALSE, center = TRUE, ncomp = 10)
ve <- pca_obj$var_explained
cat("  前 5 主成分方差解释率:", paste(sprintf("PC%d=%.2f%%", 1:5, ve[1:5]), collapse = ", "), "\n")

step("绘制 PCA 得分图 (按 phase 着色)")
p_pca_phase <- plot_pca_scores(pca_obj, samp_aligned,
                               color_col = GROUP_PHASE, shape_col = NULL,
                               pc_x = 1, pc_y = 2, show_ellipse = TRUE)
export_plot(p_pca_phase, FIGURES_DIR, "02_pca_scores_phase", width = 8, height = 6)

step("绘制 PCA 得分图 (按 variety 着色)")
p_pca_var <- plot_pca_scores(pca_obj, samp_aligned,
                             color_col = GROUP_VARIETY, shape_col = NULL,
                             pc_x = 1, pc_y = 2, show_ellipse = TRUE)
export_plot(p_pca_var, FIGURES_DIR, "02_pca_scores_variety", width = 8, height = 6)

step("绘制 PCA 载荷图 (Top 贡献特征)")
p_pca_load <- plot_pca_loadings(pca_obj, pc_x = 1, pc_y = 2, top_n = 10)
export_plot(p_pca_load, FIGURES_DIR, "02_pca_loadings", width = 8, height = 6)
cat("  -> figures/02_pca_*.{pdf,png}\n")

# =============================================================================
# SECTION 5  limma 差异表达分析
# =============================================================================
section("SECTION 5  limma 差异表达分析")

# ---- 5a. 主对比：Fresh vs Late_maturation ----
step(sprintf("limma 主对比: %s vs %s", CONTRAST_PHASE_CONTROL, CONTRAST_PHASE_CASE))
# run_limma 返回 list（$results = 完整结果，$significant = 显著子集），此处取 $results
de_phase <- run_limma(pre_log, samp_aligned,
                      group_col = GROUP_PHASE,
                      control_group = CONTRAST_PHASE_CONTROL,
                      case_groups = CONTRAST_PHASE_CASE,
                      exclude_groups = NULL,
                      strategy = "pvalue_logFC",
                      p_threshold = P_THRESHOLD,
                      logfc_threshold = LOGFC_THRESHOLD,
                      p_adj_method = "BH")$results
mat_dim(de_phase, "de_phase")
n_sig_phase <- sum(de_phase$p_adj < P_THRESHOLD & abs(de_phase$logFC) >= LOGFC_THRESHOLD, na.rm = TRUE)
cat("  显著蛋白数 (p_adj<", P_THRESHOLD, "& |logFC|>=", LOGFC_THRESHOLD, "): ", n_sig_phase, "\n", sep = "")
export_table(de_phase, RESULTS_DIR, "03_de_phase_Fresh_vs_LateMaturation.csv")

step("绘制 phase 火山图")
p_vol_phase <- plot_volcano(de_phase, p_col = "p_adj", logfc_col = "logFC",
                            feature_col = "feature_id", p_threshold = P_THRESHOLD,
                            logfc_threshold = LOGFC_THRESHOLD, top_n = 8)
export_plot(p_vol_phase, FIGURES_DIR, "03_volcano_phase", width = 9, height = 6)

# ---- 5b. 次级对比：品种 Burley vs Virginia ----
step(sprintf("limma 次级对比: %s vs %s", CONTRAST_VAR_CONTROL, CONTRAST_VAR_CASE))
de_var <- run_limma(pre_log, samp_aligned,
                    group_col = GROUP_VARIETY,
                    control_group = CONTRAST_VAR_CONTROL,
                    case_groups = CONTRAST_VAR_CASE,
                    exclude_groups = NULL,
                    strategy = "pvalue_logFC",
                    p_threshold = P_THRESHOLD,
                    logfc_threshold = LOGFC_THRESHOLD,
                    p_adj_method = "BH")$results
mat_dim(de_var, "de_var")
n_sig_var <- sum(de_var$p_adj < P_THRESHOLD & abs(de_var$logFC) >= LOGFC_THRESHOLD, na.rm = TRUE)
cat("  显著蛋白数 (p_adj<", P_THRESHOLD, "& |logFC|>=", LOGFC_THRESHOLD, "): ", n_sig_var, "\n", sep = "")
export_table(de_var, RESULTS_DIR, "03_de_variety_Burley_vs_Virginia.csv")

step("绘制 variety 火山图")
p_vol_var <- plot_volcano(de_var, p_col = "p_adj", logfc_col = "logFC",
                          feature_col = "feature_id", p_threshold = P_THRESHOLD,
                          logfc_threshold = LOGFC_THRESHOLD, top_n = 8)
export_plot(p_vol_var, FIGURES_DIR, "03_volcano_variety", width = 9, height = 6)
cat("  -> results/03_de_*.csv  figures/03_volcano_*.{pdf,png}\n")

# =============================================================================
# SECTION 6  Fisher 过表达富集
# =============================================================================
section("SECTION 6  Fisher 过表达富集 (功能类别)")

# 以 phase 主对比的显著蛋白作为 foreground
sig_phase_ids <- de_phase$feature_id[de_phase$p_adj < P_THRESHOLD &
                                     abs(de_phase$logFC) >= LOGFC_THRESHOLD]
all_ids <- de_phase$feature_id
cat("  foreground 显著蛋白:", length(sig_phase_ids), " / background:", length(all_ids), "\n")

for (cat_col in c("super_class", "category", "family")) {
  step(sprintf("Fisher 富集: category_col='%s'", cat_col))
  enrich_res <- run_fisher_enrich(significant_features = sig_phase_ids,
                                  all_features = all_ids,
                                  feature_info = feat_aligned,
                                  feature_id_col = "name",
                                  category_col = cat_col,
                                  p_adj_method = "BH",
                                  min_size = 3)
  out_name <- sprintf("04_enrich_%s.csv", cat_col)
  export_table(enrich_res, RESULTS_DIR, out_name)
  n_sig_enrich <- if (!is.null(enrich_res) && nrow(enrich_res) > 0)
    sum(enrich_res$p_adj < P_THRESHOLD, na.rm = TRUE) else 0
  cat(sprintf("    %s: %d 个类别进入检验, %d 个显著 (p_adj<%.2f)\n",
              cat_col, nrow(enrich_res), n_sig_enrich, P_THRESHOLD))

  step(sprintf("富集条形图: %s", cat_col))
  p_enrich <- plot_enrichment(enrich_res, top_n = 15, p_threshold = P_THRESHOLD)
  export_plot(p_enrich, FIGURES_DIR, sprintf("04_enrich_%s", cat_col), width = 9, height = 6)
}
cat("  -> results/04_enrich_*.csv  figures/04_enrich_*.{pdf,png}\n")

# =============================================================================
# SECTION 7  差异蛋白分层聚类热图
# =============================================================================
section("SECTION 7  差异蛋白分层聚类热图")

step("选取 Top 差异蛋白 (按 |logFC| 排序)")
de_phase_ranked <- de_phase[order(abs(de_phase$logFC), decreasing = TRUE), ]
top_ids <- head(de_phase_ranked$feature_id, N_TOP_CLUSTER)
top_mat <- pre_log[rownames(pre_log) %in% top_ids, , drop = FALSE]
# 保持按 |logFC| 排序的行顺序
top_mat <- top_mat[match(top_ids, rownames(top_mat)), ]
mat_dim(top_mat, "top_mat")

step("绘制聚类热图 (group_col=phase, family_col=super_class)")
p_heat <- plot_heatmap(top_mat, samp_aligned, feat_aligned,
                       group_col = GROUP_PHASE, name_col = "name",
                       family_col = "super_class", scale = "row",
                       show_rownames = TRUE, show_colnames = FALSE,
                       n_features = N_TOP_CLUSTER)
export_plot(p_heat, FIGURES_DIR, "05_heatmap_topDE_phase", width = 10, height = 8)
cat("  -> figures/05_heatmap_topDE_phase.{pdf,png}\n")

# =============================================================================
# SECTION 8  中间态缓存
# =============================================================================
section("SECTION 8  中间态缓存 (cache/*.rds)")

cache_objs <- list(
  expr_aligned = expr_aligned,
  samp_aligned = samp_aligned,
  feat_aligned = feat_aligned,
  pre_log = pre_log,
  pre_pareto = pre_pareto,
  pca_obj = pca_obj,
  de_phase = de_phase,
  de_var = de_var,
  qc_result = qc_result
)
for (nm in names(cache_objs)) {
  saveRDS(cache_objs[[nm]], file.path(CACHE_DIR, sprintf("%s.rds", nm)))
}
cat("  -> cache/ :", paste(names(cache_objs), collapse = ", "), "\n")

section("主流程完成")
cat("  results/ 与 figures/ 已生成；进阶脚本可读取 cache/ 继续分析。\n")
