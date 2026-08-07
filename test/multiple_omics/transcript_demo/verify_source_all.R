# =============================================================================
# verify_source_all.R  --  模块加载健康检查
# source agent/rscript/source_all_scripts.R，验证全部脚本加载成功，
# 并检查本流程所需关键函数在全局环境可见（回归 BUG-1 嵌套 source 递归修复）。
# =============================================================================
source("config.R")

section("加载 source_all_scripts.R")
src_all <- file.path(RSCRIPT_ROOT, "source_all_scripts.R")
if (!file.exists(src_all)) stop(sprintf("source_all_scripts.R 不存在: %s", src_all))
source(src_all, local = FALSE, encoding = "UTF-8")
step("source_all_scripts.R 加载完成（无递归死循环）")

section("关键函数存在性检查")
required_fns <- c(
  # 加载/导出
  "load_expression_matrix", "load_sample_info", "load_feature_info", "create_omics_data",
  "export_table", "export_plot", "export_heatmap",
  # 预处理
  "filter_missing_values", "normalize_median", "log2_transform", "scale_pareto",
  # 多变量
  "run_pca", "plot_pca_scores", "plot_pca_loadings",
  # 差异
  "run_limma",
  # 富集
  "run_fisher_enrich", "plot_enrichment",
  # 可视化
  "plot_volcano", "plot_heatmap",
  # 时序聚类
  "cluster_protein_profiles", "plot_profile_clusters", "plot_cluster_centers",
  # WGCNA
  "build_wgcna_modules", "plot_soft_threshold", "plot_wgcna_dendrogram",
  "wgcna_module_trait", "plot_module_trait",
  # KEGG
  "run_kegg_pathway_enrich", "run_kegg_pathway_gsva", "run_kegg_pathway_wgcna",
  "map_kegg_compound_to_pathway"
)
missing_fns <- setdiff(required_fns, ls(envir = .GlobalEnv))
if (length(missing_fns) > 0) {
  cat("  缺失函数:", paste(missing_fns, collapse = ", "), "\n")
  stop("存在未加载的关键函数")
}
cat(sprintf("  全部 %d 个关键函数均已在全局环境可见。\n", length(required_fns)))
step("完成")
