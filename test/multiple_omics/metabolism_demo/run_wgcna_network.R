# ==============================================================================
# WGCNA 共表达模块分析脚本
# ==============================================================================
# 职责：读取 cache 的 log2 矩阵 -> 按方差取 top N 特征 -> build_wgcna_modules
#       -> 导出模块成员归属表 / 模块特征基因矩阵 MEs / 模块规模统计
#       -> plot_soft_threshold 软阈值曲线 -> plot_wgcna_dendrogram 模块树状图
#       -> 表型数值编码后 wgcna_module_trait 模块-性状关联 -> plot_module_trait
# 末尾缓存 wgcna_result 供 PLSPM 脚本复用。
# ==============================================================================

source("g:/OmicsWorks/test/multiple_omics/metabolism_demo/config.R", encoding = "UTF-8")

set.seed(RANDOM_SEED)

section("WGCNA 共表达模块分析")

step("加载 agent/rscript 模块")
source_modules(c(
  "utils/export.R",
  "utils/plot_helpers.R",
  "network/wgcna_module.R",
  "network/wgcna_trait.R"
))

# ------------------------------------------------------------------------------
# 读取缓存
# ------------------------------------------------------------------------------
log2_mat     <- readRDS(file.path(CACHE_DIR, "log2_mat.rds"))
sample_info  <- readRDS(file.path(CACHE_DIR, "sample_info.rds"))
feature_info <- readRDS(file.path(CACHE_DIR, "feature_info.rds"))
mat_dim("缓存 log2 矩阵", log2_mat)

# ==============================================================================
# SECTION 1: 特征筛选（性能控制）
# ==============================================================================
section("SECTION 1  按方差筛选 top 特征")

# WGCNA 使用 log2 矩阵（保留特征间方差结构），不用 Pareto 标度矩阵
feat_var <- apply(log2_mat, 1, stats::var, na.rm = TRUE)
top_idx <- order(feat_var, decreasing = TRUE)[seq_len(min(WGCNA_TOP_N, nrow(log2_mat)))]
wgcna_mat <- log2_mat[sort(top_idx), , drop = FALSE]
mat_dim(sprintf("WGCNA 输入 (top %d)", WGCNA_TOP_N), wgcna_mat)
cat(sprintf("    方差范围: [%.4g, %.4g]\n",
            min(feat_var[top_idx]), max(feat_var[top_idx])))

# ==============================================================================
# SECTION 2: 软阈值选择曲线
# ==============================================================================
section("SECTION 2  软阈值幂选择")

step("plot_soft_threshold (powers=1:20, signed)")
p_sft <- timed("plot_soft_threshold",
               plot_soft_threshold(wgcna_mat, powers = 1:20,
                                   network_type = "signed"))
export_plot(p_sft, FIGURE_DIR, "10_wgcna_soft_threshold", width = 8, height = 6)
cat("    软阈值曲线数据 (前 10 个幂):\n")
print(utils::head(p_sft$data, 10))
export_table(p_sft$data, RESULT_DIR, "10_wgcna_soft_threshold",
             use_rownames = FALSE)

# ==============================================================================
# SECTION 3: 构建共表达模块
# ==============================================================================
section("SECTION 3  构建 WGCNA 共表达模块")

step("build_wgcna_modules (network_type=signed, min_module_size=20)")
wgcna_res <- timed("build_wgcna_modules",
                   build_wgcna_modules(
                     wgcna_mat,
                     soft_power = NULL,
                     min_module_size = 20,
                     merge_cut_height = 0.25,
                     network_type = "signed",
                     cor_fn = "cor"
                   ))

cat(sprintf("    选定软阈值 soft_power = %s\n", wgcna_res$soft_power))
mod_tab <- sort(table(wgcna_res$module_colors), decreasing = TRUE)
cat(sprintf("    模块数（含 grey）: %d\n", length(mod_tab)))
cat("    模块规模:\n")
for (i in seq_along(mod_tab)) {
  cat(sprintf("      %-14s : %d\n", names(mod_tab)[i], mod_tab[i]))
}
mat_dim("MEs (转置视角)", t(wgcna_res$MEs))

# --- 导出模块成员归属 ---------------------------------------------------------
module_df <- data.frame(
  feature_id   = names(wgcna_res$module_colors),
  module_color = as.character(wgcna_res$module_colors),
  module_label = as.integer(wgcna_res$module_labels),
  stringsAsFactors = FALSE
)
# 附上化学分类注释便于解读
ann_idx <- match(module_df$feature_id, rownames(feature_info))
module_df$super_class <- as.character(feature_info$super_class[ann_idx])
module_df$class <- as.character(feature_info$class[ann_idx])
module_df <- module_df[order(module_df$module_color, module_df$feature_id), ]
export_table(module_df, RESULT_DIR, "11_wgcna_module_membership",
             use_rownames = FALSE)
step("已导出 11_wgcna_module_membership.csv")

size_df <- data.frame(
  module_color = names(mod_tab),
  n_features = as.integer(mod_tab),
  stringsAsFactors = FALSE
)
export_table(size_df, RESULT_DIR, "11_wgcna_module_size", use_rownames = FALSE)

export_table(as.data.frame(wgcna_res$MEs), RESULT_DIR,
             "11_wgcna_module_eigengenes",
             use_rownames = TRUE, id_col_name = "sample_id")
step("已导出 11_wgcna_module_eigengenes.csv")

# ==============================================================================
# SECTION 4: 模块树状图
# ==============================================================================
section("SECTION 4  模块树状图")

step("plot_wgcna_dendrogram (base R 绘图，返回绘图闭包)")
draw_dendro <- plot_wgcna_dendrogram(wgcna_res)
cat("    返回对象类型:", class(draw_dendro), "\n")
# 修复后返回无参绘图函数，可由 export_heatmap 承接 base R 副作用绘图
export_heatmap(draw_dendro, FIGURE_DIR, "12_wgcna_dendrogram",
               width = 12, height = 7)
step("已导出 12_wgcna_dendrogram.pdf/png")

# ==============================================================================
# SECTION 5: 模块-性状关联
# ==============================================================================
section("SECTION 5  模块-性状关联分析")

# --- 分类表型数值编码 ---------------------------------------------------------
# wgcna_module_trait 要求 traits 为数值矩阵，而 variety/phase 为分类变量。
# 二分类直接 0/1 编码；多分类用 one-hot 展开，保留每个水平的独立关联信号。
step("构造数值型 traits 矩阵")

encode_binary <- function(v, positive) as.integer(as.character(v) == positive)
onehot <- function(v, prefix) {
  v <- as.character(v)
  lv <- sort(unique(v))
  m <- vapply(lv, function(l) as.integer(v == l), integer(length(v)))
  colnames(m) <- paste0(prefix, "_", lv)
  m
}

traits <- cbind(
  variety_Virginia = encode_binary(sample_info[[GROUP_VARIETY]], "Virginia"),
  onehot(sample_info[[GROUP_PHASE]], "phase"),
  onehot(sample_info[[GROUP_LOCATION]], "loc")
)
# 若存在数值型时间列则一并纳入
for (nc in c("day", "timepoint")) {
  if (nc %in% colnames(sample_info)) {
    num_v <- suppressWarnings(as.numeric(as.character(sample_info[[nc]])))
    if (!all(is.na(num_v))) {
      traits <- cbind(traits, setNames(data.frame(num_v), nc))
      cat(sprintf("    纳入数值表型列: %s\n", nc))
    }
  }
}
traits <- as.data.frame(traits)
rownames(traits) <- rownames(sample_info)
cat(sprintf("    traits 维度: %d 样本 x %d 表型\n", nrow(traits), ncol(traits)))
cat("    表型列:", paste(colnames(traits), collapse = ", "), "\n")

step("wgcna_module_trait (cor_method=pearson)")
assoc <- wgcna_module_trait(wgcna_res, traits, sample_info = sample_info,
                            cor_method = "pearson")

cat(sprintf("    相关矩阵维度: %d 模块 x %d 表型\n",
            nrow(assoc$module_trait_cor), ncol(assoc$module_trait_cor)))
n_sig <- sum(assoc$module_trait_p < 0.05, na.rm = TRUE)
cat(sprintf("    p < 0.05 的模块-表型对: %d / %d\n",
            n_sig, length(assoc$module_trait_p)))

export_table(as.data.frame(assoc$module_trait_cor), RESULT_DIR,
             "13_module_trait_cor", use_rownames = TRUE, id_col_name = "module")
export_table(as.data.frame(assoc$module_trait_p), RESULT_DIR,
             "13_module_trait_pvalue", use_rownames = TRUE, id_col_name = "module")
export_table(assoc$module_trait_lm, RESULT_DIR, "13_module_trait_lm",
             use_rownames = FALSE)
step("已导出模块-性状关联表")

step("plot_module_trait")
p_mt <- plot_module_trait(assoc, p_threshold = 0.05)
export_plot(p_mt, FIGURE_DIR, "13_module_trait_heatmap",
            width = max(8, 0.6 * ncol(traits) + 5),
            height = max(6, 0.4 * nrow(assoc$module_trait_cor) + 3))

# ==============================================================================
# SECTION 6: 缓存
# ==============================================================================
section("SECTION 6  缓存 WGCNA 结果")

# diss_TOM 体积大（top_n^2），PLSPM 不需要，剔除后再缓存
wgcna_slim <- wgcna_res
wgcna_slim$diss_TOM <- NULL
saveRDS(wgcna_slim, file.path(CACHE_DIR, "wgcna.rds"))
saveRDS(traits, file.path(CACHE_DIR, "traits.rds"))
step("已缓存 wgcna.rds / traits.rds")

cat("\n[done] WGCNA 分析完成。\n")
