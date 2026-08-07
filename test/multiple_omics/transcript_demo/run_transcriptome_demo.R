# =============================================================================
# run_transcriptome_demo.R  --  烟草发酵转录组学分析 主流程
# 链路：加载对齐 -> QC -> 预处理 -> PCA -> limma 差异 -> Fisher 富集 -> 热图
#        -> 写入 cache/ 供进阶脚本复用
# 所有分析逻辑均来自 agent/rscript 模块化函数（仅通过 source_modules + 调用）。
# =============================================================================
source("config.R")

source_modules(c(
  "utils/load_data.R",
  "utils/export.R",
  "utils/plot_helpers.R",
  "theme_palette.R",
  "preprocessing/filter_missing.R",
  "preprocessing/normalize.R",
  "preprocessing/transform.R",
  "preprocessing/scale.R",
  "qcqa/qcqa.R",
  "multivariate/pca.R",
  "differential/limma_de.R",
  "enrichment/fisher_enrich.R",
  "visualization/volcano_plot.R",
  "visualization/heatmap_plot.R"
))

set.seed(SEED)

# =============================================================================
# SECTION 1  数据加载与对齐（以 name 为主键，保留全部 2000 基因）
# =============================================================================
section("SECTION 1  数据加载与对齐")

step("读取原始表达矩阵")
expr_raw <- read.csv(EXPR_FILE, check.names = FALSE, stringsAsFactors = FALSE)
feat_raw <- read.csv(FEATURE_FILE, check.names = FALSE, stringsAsFactors = FALSE)
samp_raw <- read.csv(SAMPLE_FILE, check.names = FALSE, stringsAsFactors = FALSE)

# 表达矩阵：首列为 name，构造 矩阵（基因 x 样本）
expr_ids <- as.character(expr_raw[, 1])
expr_mat <- as.matrix(expr_raw[, -1, drop = FALSE])
mode(expr_mat) <- "numeric"
rownames(expr_mat) <- make.unique(expr_ids)
colnames(expr_mat) <- colnames(expr_raw)[-1]
mat_dim(expr_mat, "expression matrix (genes x samples)")

# 样本信息：以 ID 为行名
rownames(samp_raw) <- as.character(samp_raw$ID)
sample_info <- samp_raw[colnames(expr_mat), , drop = FALSE]
mat_dim(sample_info, "sample_info (aligned)")

# 特征注释：以 name 为主键对齐表达矩阵，未匹配的 2 个基因注释置 NA 但保留
feat_by_name <- as.character(feat_raw$name)
feat_raw$name <- make.unique(feat_by_name)   # 复测 load_feature_info 的 make.unique 兜底
feature_info <- data.frame(
  feature_id = rownames(expr_mat),
  stringsAsFactors = FALSE
)
for (cc in colnames(feat_raw)) {
  m <- match(rownames(expr_mat), feat_raw$name)
  feature_info[[cc]] <- feat_raw[[cc]][m]
}
# 对未匹配的注释列置 NA（保留全部 2000 基因）
mat_dim(feature_info, "feature_info (aligned, full 2000)")
cat(sprintf("  未匹配注释的基因数(置NA): %d\n",
            sum(is.na(feature_info$name) | feature_info$name == "")))

# 构造供后续模块使用的 OmicsData（用于需要 feature_info 的可视化）
omics_data <- list(
  expr_matrix = expr_mat,
  sample_info = sample_info,
  feature_info = feature_info,
  feature_id_col = "feature_id"
)

# =============================================================================
# SECTION 2  质量控制（无 QC 样本组，手动计算 CV / 缺失 / 表达分布）
# =============================================================================
section("SECTION 2  质量控制")
step("计算基因 CV 与表达分布（跨样本）")
gene_mean <- rowMeans(expr_mat, na.rm = TRUE)
gene_sd   <- matrixStats::rowSds(expr_mat, na.rm = TRUE)
gene_cv   <- ifelse(gene_mean > 0, gene_sd / gene_mean * 100, NA)
qc_df <- data.frame(
  feature_id = rownames(expr_mat),
  mean_abundance = round(gene_mean, 4),
  sd = round(gene_sd, 4),
  cv_percent = round(gene_cv, 2),
  stringsAsFactors = FALSE
)
qc_high_cv <- sum(gene_cv > CV_THRESHOLD, na.rm = TRUE)
cat(sprintf("  CV > %.0f%% 的基因数: %d / %d\n", CV_THRESHOLD, qc_high_cv, nrow(expr_mat)))
cat(sprintf("  表达中位数: %.3f ; 范围 [%.3f, %.3f]\n",
            median(expr_mat), min(expr_mat), max(expr_mat)))
cat(sprintf("  缺失率(NA): %.4f%% ; 零值率: %.4f%%\n",
            100 * mean(is.na(expr_mat)), 100 * mean(expr_mat == 0, na.rm = TRUE)))
export_table(qc_df, output_dir = RESULTS_DIR, filename = "01_qc_gene_cv.csv")

# 表达分布箱线图（按 phase 分组）
step("表达分布箱线图")
dist_long <- reshape2::melt(expr_mat)
colnames(dist_long) <- c("feature_id", "sample_id", "abundance")
dist_long$phase <- sample_info[as.character(dist_long$sample_id), GROUP_PHASE]
p_dist <- ggplot2::ggplot(dist_long, ggplot2::aes(x = phase, y = log2(abundance + 1))) +
  ggplot2::geom_boxplot(fill = "#4a90d9", alpha = 0.7) +
  ggplot2::labs(title = "Expression Distribution by Fermentation Phase",
                x = "Phase", y = "log2(abundance + 1)") +
  ggplot2::theme_bw()
export_plot(p_dist, output_dir = FIGURES_DIR, filename = "01_expression_distribution")

# =============================================================================
# SECTION 3  预处理链路：过滤 -> 中位数归一化 -> log2 -> Pareto
# =============================================================================
section("SECTION 3  预处理")
step("缺失过滤")
# 数据无缺失/零值，使用 overall 法、阈值=1 表示仅移除真正完全缺失的 Feature
filt <- filter_missing_values(expr_mat, sample_info = sample_info,
                              threshold = 1, method = "overall",
                              group_col = GROUP_PHASE)
expr_filtered <- filt$filtered_matrix
mat_dim(expr_filtered, "after filter_missing_values")
cat(sprintf("  被移除的 Feature 数: %d\n", length(filt$removed_features)))

step("中位数归一化")
expr_norm <- normalize_median(expr_filtered)
mat_dim(expr_norm, "after normalize_median")

step("log2 变换 (pseudo_count = 1)")
expr_log2 <- log2_transform(expr_norm, pseudo_count = 1, base = 2)
mat_dim(expr_log2, "after log2_transform")

step("Pareto 标度（供 PCA）")
expr_pareto <- scale_pareto(expr_log2)
mat_dim(expr_pareto, "after scale_pareto")

# =============================================================================
# SECTION 4  PCA（按 phase / variety / location 着色）
# =============================================================================
section("SECTION 4  PCA")
pca_res <- run_pca(expr_pareto, scale = TRUE, center = TRUE)
cat(sprintf("  PC1=%.2f%%  PC2=%.2f%%  PC3=%.2f%%  PC4=%.2f%%\n",
            pca_res$var_explained[1], pca_res$var_explained[2],
            pca_res$var_explained[3], pca_res$var_explained[4]))

for (g in c(GROUP_PHASE, GROUP_VARIETY, GROUP_LOCATION)) {
  p <- plot_pca_scores(pca_res, sample_info = sample_info, color_col = g)
  export_plot(p, output_dir = FIGURES_DIR,
              filename = sprintf("02_pca_scores_%s", g))
}
p_load <- plot_pca_loadings(pca_res, pc_x = 1, pc_y = 2, top_n = 15)
export_plot(p_load, output_dir = FIGURES_DIR, filename = "02_pca_loadings_PC1_PC2")
cat("  PCA 得分图与载荷图已导出。\n")

# =============================================================================
# SECTION 5  limma 差异表达（phase 主对比 + variety 次级对比）
# =============================================================================
section("SECTION 5  limma 差异表达")
step(sprintf("主对比: %s vs %s", CONTRAST_PHASE_CONTROL, CONTRAST_PHASE_CASE))
limma_phase <- run_limma(expr_log2, sample_info = sample_info,
                         group_col = GROUP_PHASE,
                         control_group = CONTRAST_PHASE_CONTROL,
                         case_groups = CONTRAST_PHASE_CASE,
                         strategy = "pvalue_logFC",
                         p_threshold = P_THRESHOLD,
                         logfc_threshold = LOGFC_THRESHOLD)
de_phase <- limma_phase$results
mat_dim(de_phase, "limma phase results")
n_sig_phase <- sum(de_phase$p_adj < P_THRESHOLD & abs(de_phase$logFC) >= LOGFC_THRESHOLD,
                   na.rm = TRUE)
cat(sprintf("  显著差异基因 (p_adj<%.2f & |logFC|>=%d): %d\n",
            P_THRESHOLD, LOGFC_THRESHOLD, n_sig_phase))
export_table(de_phase, output_dir = RESULTS_DIR, filename = "02_limma_phase.csv")

p_vol_phase <- plot_volcano(de_phase, p_col = "p_adj", logfc_col = "logFC",
                            feature_col = "feature_id")
export_plot(p_vol_phase, output_dir = FIGURES_DIR, filename = "02_volcano_phase")

step(sprintf("次级对比: %s vs %s", CONTRAST_VAR_CONTROL, CONTRAST_VAR_CASE))
limma_var <- run_limma(expr_log2, sample_info = sample_info,
                       group_col = GROUP_VARIETY,
                       control_group = CONTRAST_VAR_CONTROL,
                       case_groups = CONTRAST_VAR_CASE,
                       strategy = "pvalue_logFC",
                       p_threshold = P_THRESHOLD,
                       logfc_threshold = LOGFC_THRESHOLD)
de_var <- limma_var$results
n_sig_var <- sum(de_var$p_adj < P_THRESHOLD & abs(de_var$logFC) >= LOGFC_THRESHOLD,
                 na.rm = TRUE)
cat(sprintf("  显著差异基因 (p_adj<%.2f & |logFC|>=%d): %d\n",
            P_THRESHOLD, LOGFC_THRESHOLD, n_sig_var))
export_table(de_var, output_dir = RESULTS_DIR, filename = "02_limma_variety.csv")

# =============================================================================
# SECTION 6  Fisher 过表达富集（super_class / category / family）
# =============================================================================
section("SECTION 6  Fisher 富集")
# run_limma 的显著/背景 ID 存放在结果表的 feature_id 列（非行名）
sig_mask <- de_phase$p_adj < P_THRESHOLD & abs(de_phase$logFC) >= LOGFC_THRESHOLD
sig_phase_ids <- as.character(de_phase$feature_id[sig_mask])
all_ids      <- as.character(de_phase$feature_id)
cat(sprintf("  用于富集的显著ID数: %d ; 背景ID数: %d\n",
            length(sig_phase_ids), length(all_ids)))

for (cat_col in c("super_class", "category", "family")) {
  step(sprintf("富集维度: %s", cat_col))
  enr <- run_fisher_enrich(
    significant_features = sig_phase_ids,
    all_features = all_ids,
    feature_info = feature_info,
    feature_id_col = "feature_id",
    category_col = cat_col,
    p_adj_method = "BH", min_size = 2
  )
  out_name <- sprintf("03_fisher_%s.csv", cat_col)
  export_table(as.data.frame(enr), output_dir = RESULTS_DIR, filename = out_name)
  cat(sprintf("  %s 富集类别数(达到 min_size): %d\n", cat_col, nrow(enr)))
  p_enr <- plot_enrichment(enr, top_n = 20, p_threshold = P_THRESHOLD)
  export_plot(p_enr, output_dir = FIGURES_DIR,
              filename = sprintf("03_fisher_%s", cat_col))
}

# =============================================================================
# SECTION 7  Top 差异基因分层聚类热图
# =============================================================================
section("SECTION 7  差异基因热图")
step("筛选 Top 差异基因")
# 以 feature_id 列对齐表达矩阵行名（feature_id 即表达矩阵基因名）
ord <- order(de_phase$p_adj, -abs(de_phase$logFC))
top_ids <- as.character(de_phase$feature_id[ord])[1:min(N_TOP_CLUSTER, nrow(de_phase))]
top_ids <- intersect(top_ids, rownames(expr_log2))
heat_mat <- expr_log2[top_ids, , drop = FALSE]
heat_feat <- feature_info[match(top_ids, feature_info$feature_id), , drop = FALSE]

p_heat <- plot_heatmap(
  heat_mat, sample_info = sample_info, feature_info = heat_feat,
  group_col = GROUP_PHASE, name_col = "name", family_col = "family",
  scale = "row", show_rownames = FALSE, show_colnames = FALSE,
  n_features = length(top_ids)
)
export_heatmap(p_heat, output_dir = FIGURES_DIR,
               filename = sprintf("04_heatmap_top%d", length(top_ids)))
cat(sprintf("  热图已导出 (Top %d 差异基因)。\n", length(top_ids)))

# =============================================================================
# SECTION 8  缓存中间态
# =============================================================================
section("SECTION 8  缓存")
cache_obj <- list(
  expr_mat = expr_mat,
  expr_log2 = expr_log2,
  expr_pareto = expr_pareto,
  sample_info = sample_info,
  feature_info = feature_info,
  omics_data = omics_data,
  de_phase = de_phase,
  de_var = de_var,
  pca_res = pca_res
)
saveRDS(cache_obj, file.path(CACHE_DIR, "transcript_pipeline_cache.rds"))
cat("  已缓存: cache/transcript_pipeline_cache.rds\n")
step("主流程完成")
