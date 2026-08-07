# ==============================================================================
# Spearman + MIC 相关性网络脚本
# ==============================================================================
# 职责：读取 cache 的 log2 矩阵 -> run_intra_omics_association
#       （Spearman 全量 + 候选对 MIC + 置换检验经验 p）
#       -> 导出显著关联边表与节点度表
#       -> build_association_network 构图 -> plot_association_network
#       -> get_association_hubs 枢纽节点表
# ==============================================================================

source("g:/OmicsWorks/test/multiple_omics/metabolism_demo/config.R", encoding = "UTF-8")

set.seed(RANDOM_SEED)

section("Spearman + MIC 相关性网络")

step("加载 agent/rscript 模块")
source_modules(c(
  "utils/export.R",
  "utils/plot_helpers.R",
  "multiomics/multiomics_data.R",      # drop_zero_variance
  "multiomics/association_network.R",
  "multiomics/plot_association_network.R"
))

log2_mat     <- readRDS(file.path(CACHE_DIR, "log2_mat.rds"))
feature_info <- readRDS(file.path(CACHE_DIR, "feature_info.rds"))
mat_dim("缓存 log2 矩阵", log2_mat)

# ==============================================================================
# SECTION 1: 层内关联分析
# ==============================================================================
section("SECTION 1  run_intra_omics_association")

cat(sprintf("    性能参数: top_n=%d, max_pairs_for_mic=%d, n_perm=%d\n",
            ASSOC_TOP_N, MIC_MAX_PAIRS, MIC_N_PERM))
cat(sprintf("    预期 Spearman 配对数: %d\n",
            ASSOC_TOP_N * (ASSOC_TOP_N - 1) / 2))

assoc <- timed("run_intra_omics_association",
               run_intra_omics_association(
                 log2_mat,
                 name = "metabolome",
                 top_n = ASSOC_TOP_N,
                 max_pairs_for_mic = MIC_MAX_PAIRS,
                 mic_pvalue_method = "permutation",
                 n_perm = MIC_N_PERM,
                 score_method = "combined",
                 score_weight = 0.5,
                 p_adjust = "BH",
                 p_threshold = 0.05,
                 rho_linear_min = 0.3,
                 verbose = TRUE
               ))

edges <- assoc$edges
nodes <- assoc$nodes

section("关联类型分布", 2)
assoc_tab <- table(edges$association)
for (nm in names(assoc_tab)) {
  cat(sprintf("    %-18s : %6d (%.2f%%)\n", nm, assoc_tab[nm],
              100 * assoc_tab[nm] / nrow(edges)))
}
cat(sprintf("    总边数            : %6d\n", nrow(edges)))
cat(sprintf("    已算 MIC 的边数   : %6d\n", sum(!is.na(edges$MIC))))
cat(sprintf("    padj < 0.05 边数  : %6d\n", sum(edges$padj < 0.05, na.rm = TRUE)))

cat("\n    Spearman rho 分布:\n")
print(round(stats::quantile(edges$`spearman-rho`,
                            c(0, .05, .25, .5, .75, .95, 1)), 4))
cat("\n    MIC 分布（候选对）:\n")
print(round(stats::quantile(edges$MIC, c(0, .25, .5, .75, 1), na.rm = TRUE), 4))

# ==============================================================================
# SECTION 2: 导出边表与节点表
# ==============================================================================
section("SECTION 2  导出边表与节点表")

# 全量边表体积大（44850 行），仅导出显著边 + Top 评分边
sig_edges <- edges[!is.na(edges$padj) & edges$padj < 0.05 &
                     edges$association != "not_significant", , drop = FALSE]
sig_edges <- sig_edges[order(sig_edges$score, decreasing = TRUE), ]
cat(sprintf("    显著边数: %d\n", nrow(sig_edges)))
export_table(sig_edges, RESULT_DIR, "20_assoc_edges_significant",
             use_rownames = FALSE)

top_edges <- edges[order(edges$score, decreasing = TRUE), ][seq_len(min(2000, nrow(edges))), ]
export_table(top_edges, RESULT_DIR, "20_assoc_edges_top2000",
             use_rownames = FALSE)

# 节点表附化学分类注释
ann_idx <- match(nodes$name, rownames(feature_info))
nodes$super_class <- as.character(feature_info$super_class[ann_idx])
nodes$class <- as.character(feature_info$class[ann_idx])
nodes <- nodes[order(nodes$degree, decreasing = TRUE), ]
cat(sprintf("    节点数: %d, degree 范围: [%d, %d]\n",
            nrow(nodes), min(nodes$degree), max(nodes$degree)))
export_table(nodes, RESULT_DIR, "20_assoc_nodes", use_rownames = FALSE)

# ==============================================================================
# SECTION 3: 构建网络并绘图
# ==============================================================================
section("SECTION 3  构建网络并绘图")

step("build_association_network (p_threshold=0.05, max_edges=1500)")
g <- build_association_network(
  edges, p_threshold = 0.05, max_edges = 1500,
  default_omics = "metabolome", verbose = TRUE
)

if (is.null(g)) {
  cat("    [warn] 无显著边，跳过网络绘图\n")
} else {
  cat(sprintf("    网络: %d 节点, %d 边\n",
              igraph::vcount(g), igraph::ecount(g)))

  step("plot_association_network")
  p_net <- timed("plot_association_network",
                 plot_association_network(
                   g, label_top_n = 15,
                   title = "Metabolome Spearman + MIC Association Network"
                 ))
  export_plot(p_net, FIGURE_DIR, "21_association_network",
              width = 11, height = 9)

  step("get_association_hubs (top_n=30)")
  hubs <- get_association_hubs(g, top_n = 30)
  cat("    Top10 枢纽节点:\n")
  print(utils::head(hubs, 10))
  export_table(hubs, RESULT_DIR, "21_association_hubs", use_rownames = FALSE)
}

step("plot_association_summary")
p_sum <- plot_association_summary(list(metabolome = assoc),
                                  title = "Association Type Composition")
export_plot(p_sum, FIGURE_DIR, "21_association_summary", width = 7, height = 6)

# ==============================================================================
# SECTION 4: 参数与缓存
# ==============================================================================
section("SECTION 4  参数记录与缓存")

param_df <- data.frame(
  param = names(assoc$params),
  value = vapply(assoc$params, function(x) paste(as.character(x), collapse = ";"),
                 character(1)),
  stringsAsFactors = FALSE
)
print(param_df)
export_table(param_df, RESULT_DIR, "20_assoc_params", use_rownames = FALSE)

saveRDS(assoc, file.path(CACHE_DIR, "assoc_network.rds"))
step("已缓存 assoc_network.rds")

cat("\n[done] 关联网络分析完成。\n")
