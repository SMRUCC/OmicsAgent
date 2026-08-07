# =============================================================================
# run_kegg_pathway.R  --  KEGG 通路分析（基于注释表 KO 号）
# 链路：读取 cache -> 联网构建 KO->pathway mapping（源码已扩展 KO 支持）
#       -> 差异基因通路富集(Fisher/超几何) -> 全样本通路活性 GSVA 评分
# 所有分析逻辑均来自 agent/rscript 模块化函数（仅通过 source_modules + 调用）。
# =============================================================================
source("config.R")

source_modules(c(
  "utils/export.R",
  "utils/plot_helpers.R",
  "theme_palette.R",
  "utils/kegg_pathway.R"
))

set.seed(SEED)

# =============================================================================
# SECTION 1  读取缓存
# =============================================================================
section("SECTION 1  读取主流程 cache")
cache <- readRDS(file.path(CACHE_DIR, "transcript_pipeline_cache.rds"))
expr_log2   <- cache$expr_log2         # 2000 genes x 312 samples (log2)
expr_mat    <- cache$expr_mat          # 2000 genes x 312 samples (raw)
feature_info <- cache$feature_info     # 2000 features
mat_dim(expr_log2, "expr_log2")
cat(sprintf("  feature_info 行数: %d ; 含 kegg 非空: %d\n",
            nrow(feature_info), sum(!is.na(feature_info$kegg))))

# 差异基因（来自 limma phase 主对比，复用主流程结果）
de_phase <- cache$de_phase
sig_mask <- de_phase$p_adj < P_THRESHOLD & abs(de_phase$logFC) >= LOGFC_THRESHOLD
sig_ids  <- as.character(de_phase$feature_id[sig_mask])
all_ids  <- as.character(de_phase$feature_id)
cat(sprintf("  显著差异基因: %d / %d\n", length(sig_ids), length(all_ids)))

# KEGG 缓存目录（API 响应落盘，避免重复联网）
kegg_cache_dir <- file.path(CACHE_DIR, "kegg")
if (!dir.exists(kegg_cache_dir)) dir.create(kegg_cache_dir, recursive = TRUE)

# =============================================================================
# SECTION 2  构建 KO -> pathway mapping（源码已支持 KO 号）
# =============================================================================
section("SECTION 2  构建 KO -> pathway mapping")
ko_ids <- unique(feature_info$kegg[!is.na(feature_info$kegg)])
cat(sprintf("  非空 KO 号: %d 个。\n", length(ko_ids)))
step("map_kegg_compound_to_pathway (KO 号，联网 + 缓存)")
kegg_mapping <- map_kegg_compound_to_pathway(
  ko_ids, cache_dir = kegg_cache_dir, delay = 0.05, batch_size = 50
)
mat_dim(kegg_mapping, "kegg_mapping (compound_id x pathway_id)")
cat(sprintf("  唯一 KO 号映射到通路: %d / %d\n",
            length(unique(kegg_mapping$compound_id)), length(ko_ids)))
# 缓存 mapping 供下游复用
saveRDS(kegg_mapping, file.path(CACHE_DIR, "kegg_mapping.rds"))
export_table(kegg_mapping, output_dir = RESULTS_DIR, filename = "07_kegg_mapping.csv")

# =============================================================================
# SECTION 3  差异基因 KEGG 通路富集
# =============================================================================
section("SECTION 3  差异基因 KEGG 通路富集")
step("run_kegg_pathway_enrich (query=差异基因, 背景=全部有KO注释基因)")
kegg_enrich <- run_kegg_pathway_enrich(
  feature_info        = feature_info,
  expr_mat            = expr_mat,
  query_compounds     = sig_ids,        # 差异基因（feature_info 行名）
  kegg_col            = "kegg",
  kegg_mapping        = kegg_mapping,
  cache_dir           = kegg_cache_dir,
  p_threshold         = P_THRESHOLD,
  min_pathway_size    = 2
)
if (!is.null(kegg_enrich$enrichment_table)) {
  mat_dim(kegg_enrich$enrichment_table, "enrichment_table")
  cat(sprintf("  显著通路(p<%g): %d\n", P_THRESHOLD,
              sum(kegg_enrich$enrichment_table$p_value < P_THRESHOLD, na.rm = TRUE)))
  export_table(kegg_enrich$enrichment_table, output_dir = RESULTS_DIR,
               filename = "07_kegg_enrich.csv")
  if (nrow(kegg_enrich$enrichment_table) > 0) {
    step("富集条形图")
    p_enr <- plot_kegg_enrichment(kegg_enrich, top_n = min(15, nrow(kegg_enrich$enrichment_table)))
    export_plot(p_enr, output_dir = FIGURES_DIR, filename = "07_kegg_enrich")
  }
} else {
  cat("  [WARN] enrichment_table 为空，跳过富集表导出。\n")
}

# =============================================================================
# SECTION 4  全样本 KEGG 通路活性 GSVA 评分
# =============================================================================
section("SECTION 4  全样本 KEGG 通路活性 GSVA 评分")
step("run_kegg_pathway_gsva (kegg_mapping 传入，绕开联网)")
gsva_res <- run_kegg_pathway_gsva(
  feature_info  = feature_info,
  expr_mat      = expr_mat,
  kegg_col      = "kegg",
  kegg_mapping  = kegg_mapping,
  cache_dir     = kegg_cache_dir
)
if (!is.null(gsva_res$activity_matrix)) {
  mat_dim(gsva_res$activity_matrix, "gsva activity_matrix (pathway x sample)")
  # 转置为 sample x pathway 便于下游
  act_df <- as.data.frame(t(gsva_res$activity_matrix))
  act_df$sample_id <- rownames(act_df)
  export_table(act_df, output_dir = RESULTS_DIR, filename = "07_kegg_gsva_activity.csv")
  # 通路活性热图
  step("通路活性热图")
  p_act <- plot_kegg_pathway_activity(gsva_res)
  export_plot(p_act, output_dir = FIGURES_DIR, filename = "07_kegg_gsva_activity")
} else {
  cat("  [WARN] GSVA activity_matrix 为空，跳过活性评分导出。\n")
}

step("KEGG 通路分析完成")
