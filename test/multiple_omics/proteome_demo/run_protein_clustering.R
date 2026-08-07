# =============================================================================
# run_protein_clustering.R  --  蛋白表达模式聚类进阶分析
# -----------------------------------------------------------------------------
# 读取 run_proteome_demo.R 生成的 cache，按发酵阶段/品种聚合蛋白表达轮廓，
# 做 kmeans 聚类，导出聚类成员表、表达轮廓图与聚类中心比较图。
# 导出：results/07_cluster_*.csv 与 figures/07_cluster_*.{pdf,png}
# =============================================================================
source("g:/OmicsWorks/test/multiple_omics/proteome_demo/config.R")
set.seed(SEED)

source_modules(c(
  "utils/export.R",
  "utils/plot_helpers.R",
  "theme_palette.R",
  "proteome/protein_clustering.R"
))

section("蛋白表达模式聚类：读取 cache")
pre_log <- readRDS(file.path(CACHE_DIR, "pre_log.rds"))
samp    <- readRDS(file.path(CACHE_DIR, "samp_aligned.rds"))
mat_dim(pre_log, "pre_log"); mat_dim(samp, "samp_aligned")

# =============================================================================
# SECTION A  按发酵阶段聚类（kmeans）
# =============================================================================
section("蛋白表达轮廓聚类 (cluster_protein_profiles, kmeans)")

step(sprintf("聚类: group_col=%s, n_clusters=%d", GROUP_PHASE, N_CLUSTERS))
clust <- cluster_protein_profiles(pre_log, samp,
                                  group_col = GROUP_PHASE,
                                  method = "kmeans",
                                  n_clusters = N_CLUSTERS,
                                  scale = TRUE,
                                  nstart = 25)

# 导出聚类成员表
member_df <- data.frame(
  feature_id = names(clust$clusters),
  cluster = as.integer(clust$clusters),
  stringsAsFactors = FALSE
)
export_table(member_df, RESULTS_DIR, "07_cluster_membership.csv")
cat(sprintf("  样本聚合分组水平: %d ; 聚类中心维度: %s\n",
            nrow(clust$centers), paste(dim(clust$centers), collapse = " x ")))

# 导出聚类中心矩阵
export_table(clust$centers, RESULTS_DIR, "07_cluster_centers.csv")

# 导出每个特征在各组（阶段）的平均表达（用于溯源）
if (!is.null(clust$profiles)) {
  export_table(clust$profiles, RESULTS_DIR, "07_cluster_profiles_groupmean.csv")
}

# =============================================================================
# SECTION B  聚类轮廓图与中心比较图
# =============================================================================
section("绘制聚类轮廓图与中心图")

step("绘制聚类表达轮廓图 (plot_profile_clusters)")
p_clust <- plot_profile_clusters(clust, group_labels = NULL)
export_plot(p_clust, FIGURES_DIR, "07_cluster_profiles", width = 10, height = 7)

step("绘制聚类中心比较图 (plot_cluster_centers)")
p_cent <- plot_cluster_centers(clust, group_labels = NULL)
export_plot(p_cent, FIGURES_DIR, "07_cluster_centers", width = 10, height = 7)

cat("  -> figures/07_cluster_*.{pdf,png}\n")

# =============================================================================
# SECTION C  按品种聚类（次级维度，验证聚类稳健性）
# =============================================================================
section("次级聚类：按品种 (variety)")

step(sprintf("聚类: group_col=%s", GROUP_VARIETY))
clust_var <- cluster_protein_profiles(pre_log, samp,
                                      group_col = GROUP_VARIETY,
                                      method = "kmeans",
                                      n_clusters = N_CLUSTERS,
                                      scale = TRUE,
                                      nstart = 25)
member_var <- data.frame(
  feature_id = names(clust_var$clusters),
  cluster = as.integer(clust_var$clusters),
  stringsAsFactors = FALSE
)
export_table(member_var, RESULTS_DIR, "07_cluster_membership_variety.csv")

p_clust_var <- plot_profile_clusters(clust_var)
export_plot(p_clust_var, FIGURES_DIR, "07_cluster_profiles_variety", width = 10, height = 7)

section("蛋白表达模式聚类完成")
