# =============================================================================
# run_temporal_clustering.R  --  转录组时序表达模式聚类
# 链路：读取 cache -> 按发酵天数(day)聚类基因表达轨迹 -> 轮廓图/中心图
# 所有分析逻辑均来自 agent/rscript 模块化函数（仅通过 source_modules + 调用）。
# =============================================================================
source("config.R")

source_modules(c(
  "utils/export.R",
  "utils/plot_helpers.R",
  "theme_palette.R",
  "proteome/protein_clustering.R"
))

set.seed(SEED)

# =============================================================================
# SECTION 1  读取缓存
# =============================================================================
section("SECTION 1  读取主流程 cache")
cache <- readRDS(file.path(CACHE_DIR, "transcript_pipeline_cache.rds"))
expr_log2   <- cache$expr_log2
sample_info <- cache$sample_info
feature_info <- cache$feature_info
mat_dim(expr_log2, "expr_log2 (genes x samples)")
mat_dim(sample_info, "sample_info")

# 时序坐标：以 day 列作为时间轴（Fresh 已记为 -1）
si <- sample_info
si[[TIME_COL]] <- as.numeric(as.character(si[[TIME_COL]]))
# 按 day 升序排列样本，使聚类轨迹按发酵进程展开
ord_sample <- order(si[[TIME_COL]])
expr_time <- expr_log2[, ord_sample, drop = FALSE]
si_time   <- si[ord_sample, , drop = FALSE]
cat(sprintf("  时序样本数: %d ; day 范围: [%.0f, %.0f]\n",
            nrow(si_time), min(si_time[[TIME_COL]]), max(si_time[[TIME_COL]])))

# =============================================================================
# SECTION 2  时序表达模式聚类（kmeans，按 day 聚合）
# =============================================================================
section("SECTION 2  时序表达模式聚类")
step(sprintf("cluster_protein_profiles (method=kmeans, n_clusters=%d)", N_CLUSTERS))
clust <- cluster_protein_profiles(
  expr_matrix = expr_time,
  sample_info = si_time,
  group_col   = TIME_COL,      # 以 day 作为时间轴聚合
  method      = "kmeans",
  n_clusters  = N_CLUSTERS,
  scale       = TRUE,
  nstart      = 25
)
mat_dim(clust$clusters, "clusters vector")
cat(sprintf("  聚类数: %d ; 平均轮廓系数: %.4f\n",
            clust$n_clusters,
            if (is.na(clust$silhouette)) NaN else clust$silhouette))
cat(sprintf("  各簇大小:\n"))
print(table(clust$clusters))

# =============================================================================
# SECTION 3  聚类成员表（cluster 列用 as.character，避免数值化丢失 'C' 前缀）
# =============================================================================
section("SECTION 3  聚类成员表")
member_df <- data.frame(
  feature_id = rownames(expr_log2),
  name       = as.character(feature_info$name[match(rownames(expr_log2), feature_info$feature_id)]),
  cluster    = as.character(clust$clusters[rownames(expr_log2)]),
  stringsAsFactors = FALSE
)
# 补充注释维度，便于下游解读
for (cc in c("super_class", "category", "family", "kegg")) {
  member_df[[cc]] <- as.character(feature_info[[cc]][match(rownames(expr_log2), feature_info$feature_id)])
}
export_table(member_df, output_dir = RESULTS_DIR, filename = "05_cluster_members.csv")
cat(sprintf("  成员表已导出 (n=%d)。\n", nrow(member_df)))

# =============================================================================
# SECTION 4  轮廓图与聚类中心图
# =============================================================================
section("SECTION 4  聚类可视化")
step("表达模式轮廓图")
p_profile <- plot_profile_clusters(clust, show_centers = TRUE, line_alpha = 0.15)
export_plot(p_profile, output_dir = FIGURES_DIR, filename = "05_cluster_profiles")

step("聚类中心图")
p_centers <- plot_cluster_centers(clust)
export_plot(p_centers, output_dir = FIGURES_DIR, filename = "05_cluster_centers")
cat("  时序聚类轮廓图与中心图已导出。\n")
step("时序聚类分析完成")
