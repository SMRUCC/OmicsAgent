# =============================================================================
# run_wgcna_analysis.R  --  WGCNA 共表达模块与模块-性状关联
# 链路：读取 cache -> 软阈值筛选 -> 模块识别 -> 聚类树 ->
#       与数值性状及 phase 做模块-性状关联 -> 相关热图
# 所有分析逻辑均来自 agent/rscript 模块化函数（仅通过 source_modules + 调用）。
# =============================================================================
source("config.R")

source_modules(c(
  "utils/export.R",
  "utils/plot_helpers.R",
  "theme_palette.R",
  "network/wgcna_module.R",
  "network/wgcna_trait.R"
))

set.seed(SEED)

# =============================================================================
# SECTION 1  读取缓存
# =============================================================================
section("SECTION 1  读取主流程 cache")
cache <- readRDS(file.path(CACHE_DIR, "transcript_pipeline_cache.rds"))
expr_log2   <- cache$expr_log2        # 2000 genes x 312 samples
sample_info <- cache$sample_info
feature_info <- cache$feature_info
mat_dim(expr_log2, "expr_log2 (genes x samples)")

# 构造 trait 矩阵：数值性状 + phase 哑变量
num_traits <- c("temperature_C", "humidity_pct", "altitude_m", "day")
traits <- sample_info[, num_traits, drop = FALSE]
for (lv in levels(factor(sample_info[[GROUP_PHASE]]))) {
  traits[[paste0("phase_", lv)]] <- as.numeric(sample_info[[GROUP_PHASE]] == lv)
}
traits <- as.data.frame(traits)
rownames(traits) <- rownames(sample_info)
mat_dim(traits, "trait matrix (samples x traits)")
cat(sprintf("  性状列: %s\n", paste(colnames(traits), collapse = ", ")))

# =============================================================================
# SECTION 2  软阈值筛选
# =============================================================================
section("SECTION 2  WGCNA 软阈值筛选")
step("plot_soft_threshold(expr_matrix)")
p_soft <- plot_soft_threshold(expr_log2, powers = 1:20, network_type = WGCNA_NETWORK_TYPE)
export_plot(p_soft, output_dir = FIGURES_DIR, filename = "06_wgcna_soft_threshold")
cat("  软阈值筛选图已导出。\n")

# =============================================================================
# SECTION 3  共表达模块识别
# =============================================================================
section("SECTION 3  共表达模块识别")
step(sprintf("build_wgcna_modules (min_module_size=%d, network_type=%s)",
             WGCNA_MIN_MODULE_SIZE, WGCNA_NETWORK_TYPE))
wgcna_res <- build_wgcna_modules(
  expr_matrix       = expr_log2,
  soft_power        = NULL,            # 自动 pickSoftThreshold
  min_module_size   = WGCNA_MIN_MODULE_SIZE,
  merge_cut_height  = 0.25,
  network_type      = WGCNA_NETWORK_TYPE,
  cor_fn            = "cor"
)
mat_dim(wgcna_res$module_colors, "module_colors (gene -> color)")
cat(sprintf("  软阈值 power: %d\n", wgcna_res$soft_power))
cat(sprintf("  模块数(不含 grey): %d\n",
            length(setdiff(unique(wgcna_res$module_colors), "grey"))))
tab <- table(wgcna_res$module_colors)
print(tab)

# 单独缓存 WGCNA 结果，避免重算
saveRDS(wgcna_res, file.path(CACHE_DIR, "wgcna_result.rds"))
cat("  已缓存: cache/wgcna_result.rds\n")

# =============================================================================
# SECTION 4  模块聚类树（返回闭包，用 export_heatmap 落盘）
# =============================================================================
section("SECTION 4  WGCNA 聚类树")
step("plot_wgcna_dendrogram -> export_heatmap (base graphics closure)")
p_dend <- plot_wgcna_dendrogram(wgcna_res)
export_heatmap(p_dend, output_dir = FIGURES_DIR, filename = "06_wgcna_dendrogram")
cat("  WGCNA 聚类树已导出。\n")

# =============================================================================
# SECTION 5  模块成员表
# =============================================================================
section("SECTION 5  模块成员表")
feat_map <- feature_info
gene_colors <- wgcna_res$module_colors
member_df <- data.frame(
  feature_id = names(gene_colors),
  name       = as.character(feat_map$name[match(names(gene_colors), feat_map$feature_id)]),
  module_color = as.character(gene_colors),
  stringsAsFactors = FALSE
)
for (cc in c("super_class", "category", "family", "kegg")) {
  member_df[[cc]] <- as.character(feat_map[[cc]][match(names(gene_colors), feat_map$feature_id)])
}
export_table(member_df, output_dir = RESULTS_DIR, filename = "06_wgcna_members.csv")
cat(sprintf("  成员表已导出 (n=%d)。\n", nrow(member_df)))

# 模块特征基因矩阵（MEs）
me_df <- as.data.frame(wgcna_res$MEs)
me_df$sample_id <- rownames(me_df)
export_table(me_df, output_dir = RESULTS_DIR, filename = "06_wgcna_module_eigengenes.csv")
cat(sprintf("  模块特征基因矩阵已导出 (modules=%d)。\n", ncol(wgcna_res$MEs)))

# =============================================================================
# SECTION 6  模块-性状关联
# =============================================================================
section("SECTION 6  模块-性状关联")
step("wgcna_module_trait(wgcna_result, traits)")
assoc <- wgcna_module_trait(wgcna_res, traits = traits, sample_info = sample_info,
                            cor_method = "pearson")
mat_dim(assoc$module_trait_cor, "module_trait_cor")
mat_dim(assoc$module_trait_p, "module_trait_p")

# 相关表（长格式，含 -log10(p) 显著性）
cor_mat <- assoc$module_trait_cor
p_mat   <- assoc$module_trait_p
assoc_long <- data.frame(
  module = rep(rownames(cor_mat), ncol(cor_mat)),
  trait  = rep(colnames(cor_mat), each = nrow(cor_mat)),
  correlation = as.numeric(as.vector(cor_mat)),
  p_value = as.numeric(as.vector(p_mat)),
  stringsAsFactors = FALSE
)
assoc_long$neg_log10_p <- -log10(pmax(assoc_long$p_value, 1e-300))
assoc_long$significant <- assoc_long$p_value < P_THRESHOLD
export_table(assoc_long, output_dir = RESULTS_DIR, filename = "06_wgcna_module_trait.csv")
cat(sprintf("  模块-性状关联表已导出 (n=%d)。\n", nrow(assoc_long)))

# 关联热图（相关矩阵）
step("plot_module_trait -> 相关热图")
p_trait <- plot_module_trait(assoc, p_threshold = P_THRESHOLD)
export_plot(p_trait, output_dir = FIGURES_DIR, filename = "06_wgcna_module_trait")
cat("  模块-性状关联热图已导出。\n")
step("WGCNA 分析完成")
