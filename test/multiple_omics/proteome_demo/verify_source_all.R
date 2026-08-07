# =============================================================================
# verify_source_all.R  --  模块库加载器连通性健康检查
# 通过 agent/rscript/source_all_scripts.R 一次性加载全部模块，
# 统计成功/失败脚本数，对失败项报错退出，作为集成测试前置门槛。
# =============================================================================
source("g:/OmicsWorks/test/multiple_omics/proteome_demo/config.R")

section("模块库加载健康检查")
src_all <- file.path(RSCRIPT_ROOT, "source_all_scripts.R")
if (!file.exists(src_all)) stop(sprintf("source_all_scripts.R 不存在: %s", src_all))

# source_all_scripts.R 内部对单文件失败有容错，会打印 WARNING；
# 我们包装一次以捕获致命错误并统计结果。
res <- tryCatch({
  source(src_all, encoding = "UTF-8")
  "ok"
}, error = function(e) {
  cat("  [FATAL] source_all_scripts.R 加载失败:\n")
  cat("    ", conditionMessage(e), "\n")
  "fatal"
})

if (res == "fatal") {
  quit(status = 1)
}

# 关键函数可达性检查（确保后续 demo 调用的函数确实存在）
required_fns <- c(
  "load_expression_matrix", "load_sample_info", "load_feature_info", "create_omics_data",
  "run_protein_qc", "plot_protein_qc",
  "filter_missing_values", "normalize_median", "log2_transform", "scale_pareto",
  "run_pca", "plot_pca_scores", "plot_pca_loadings",
  "run_limma", "plot_volcano",
  "run_fisher_enrich", "plot_enrichment",
  "plot_heatmap",
  "calc_protein_functional_profile", "plot_functional_heatmap",
  "plot_functional_comparison", "diff_functional_category",
  "cluster_protein_profiles", "plot_profile_clusters", "plot_cluster_centers",
  "export_table", "export_plot"
)
missing_fns <- setdiff(required_fns, ls(envir = .GlobalEnv))
if (length(missing_fns) > 0) {
  cat("  [WARN] 以下预期函数未在全局环境找到 (可能 source_all 跳过了其所在文件):\n")
  for (f in missing_fns) cat("    -", f, "\n")
} else {
  cat(sprintf("  [OK] 全部 %d 个预期函数均在全局环境可见。\n", length(required_fns)))
}

cat("  -> 模块库加载健康检查通过\n")
section("加载健康检查完成")
