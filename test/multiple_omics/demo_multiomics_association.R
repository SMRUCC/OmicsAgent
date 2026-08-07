#!/usr/bin/env Rscript
# =============================================================================
# Multi-Omics Spearman + MIC Association Network (Tobacco Leaf Fermentation)
# =============================================================================
# STUDY BACKGROUND
#   烟叶发酵是一个多组学协同演化的过程：微生物组（16S）驱动底物转化，
#   代谢组 / 挥发性组决定最终风味与香气，转录组 / 蛋白组反映宿主与微生物
#   的功能响应。理解这些层之间"谁影响谁、以什么形式（线性/非线性）关联"
#   是风味形成机制研究的核心。
#
# SCIENTIFIC QUESTIONS
#   1. 哪些跨组学特征对（如微生物物种 vs 挥发性组分）存在显著关联？
#   2. 这些关联是单调线性（Spearman 主导）还是复杂非线性（MIC 主导）？
#   3. 同一组学层内部存在哪些协同/拮抗的特征模块？
#   4. 哪些特征是连接多层的"枢纽 (hub)"？
#
# WHAT THIS SCRIPT DOES
#   对预筛选后的 Top-N 特征，构建 Spearman（单调线性）+ MIC（最大信息系数，
#   任意非线性）双指标关联网络：
#     - run_cross_omics_association : 跨组学两层特征配对
#     - run_intra_omics_association : 组学内上三角特征配对
#   导出严格 9 列边表 CSV，并对显著关联进行网络可视化。
#
# RUNTIME NOTE
#   本脚本为轻量版本，刻意不运行 demo_multiomics.R 中耗时的大段分析。
#   性能由 CFG 中的 top_n_features / max_pairs_for_mic / n_perm 控制：
#     - 先向量化计算全部 Spearman（毫秒级），再按 |rho| 取 Top-K 候选对
#       计算 MIC（唯一瓶颈），最后用共享零分布置换求 MIC p 值。
#   在 5 层各取 Top 60 特征时，整体运行通常在数分钟内完成。
#
# OUTPUT
#   tables/assoc_step*.csv  —— 9 列边表（source/target/spearman-rho/
#                              spearman-pval/MIC/MIC-pvalue/score/pvalue/association）
#   figures/assoc_step*.pdf / .png —— 显著关联网络图与汇总柱状图
# =============================================================================

set.seed(42)
source("G:/OmicsWorks/agent/rscript/source_all_scripts.R")

suppressPackageStartupMessages({
  library(ggplot2)
  library(ggrepel)
  library(reshape2)
})

data_dir   <- "G:/OmicsWorks/extdata/Tobacco-fermentation"
result_dir <- "G:/OmicsWorks/test/multiple_omics"
fig_dir    <- file.path(result_dir, "figures")
tab_dir    <- file.path(result_dir, "tables")
for (d in c(fig_dir, tab_dir)) if (!dir.exists(d)) dir.create(d, recursive = TRUE)

# -----------------------------------------------------------------------------
# CONFIG（所有耗时旋钮集中于此；cost 注释帮助调参）
# -----------------------------------------------------------------------------
CFG <- list(
  layer_order = c("microbiome", "transcriptome", "proteome",
                  "metabolome", "volatilome"),
  top_n_features      = 50,    # 每层按方差取 Top N 特征 (cost: 影响总配对数)
  max_pairs_for_mic   = 1000,  # 进入 MIC 计算的候选对数上限 (cost: 高，核心瓶颈)
  mic_pvalue_method   = "permutation",  # "permutation" | "none"
  n_perm              = 100,   # 共享零分布置换次数 (cost: 中)
  score_method        = "combined",    # "combined" | "nonlinear"
  score_weight        = 0.5,   # combined 模式下 |rho| 权重
  p_threshold         = 0.05,  # 合并 p 显著性阈值
  rho_linear_min      = 0.3,   # |rho| 高于此视为线性，否则非线性
  max_edges_plot      = 400,   # 网络图边数上限 (按 score 截断，提升可读性)
  label_top_n         = 12     # 网络图标注的枢纽节点数
)

# 五层数据规格（各层 id_col / match_col 不同，照 demo_multiomics.R）
layer_spec <- list(
  transcriptome = list(expr  = "expression/expression_transcriptome.csv",
                        finfo = "featureinfo_transcriptome.csv",
                        id_col = "gene_id", match_col = "name"),
  proteome      = list(expr  = "expression/expression_proteome.csv",
                        finfo = "featureinfo_proteome.csv",
                        id_col = "gene_id", match_col = "name"),
  metabolome    = list(expr  = "expression/expression_metabolome.csv",
                        finfo = "featureinfo_metabolome.csv",
                        id_col = "ID", match_col = "name"),
  volatilome    = list(expr  = "expression/expression_volatilome.csv",
                        finfo = "featureinfo_volatilome.csv",
                        id_col = "ID", match_col = "name"),
  microbiome    = list(expr  = "expression/expression_16s.csv",
                        finfo = "featureinfo_16s.csv",
                        id_col = "ID", match_col = "ID")
)

# -----------------------------------------------------------------------------
# 计数器与保存助手（与 demo_multiomics_advanced.R 一致）
# -----------------------------------------------------------------------------
t_start <- Sys.time()
n_tables  <- 0L
n_figures <- 0L

save_table <- function(df, filename, rownames = FALSE, check_names = FALSE) {
  if (is.null(df) || nrow(df) == 0) {
    cat(sprintf("  (skip table %s: empty)\n", filename))
    return(invisible(FALSE))
  }
  # 关联边表含连字符列名（spearman-rho / MIC-pvalue 等）。data.frame 用
  # check.names = FALSE 构造后列名即为连字符；write.table 会原样写出列名
  # （不像 write.csv 那样把 "-" 改写为 "."），故此处用 write.table 而非 write.csv。
  if (!dir.exists(tab_dir)) dir.create(tab_dir, recursive = TRUE)
  if (!grepl("\\.csv$", filename)) filename <- paste0(filename, ".csv")
  fp <- file.path(tab_dir, filename)
  if (rownames && !is.null(rownames(df)) &&
      !all(rownames(df) == as.character(seq_len(nrow(df))))) {
    out <- cbind(row.names(df), df)
    colnames(out)[1] <- "feature_id"
    utils::write.table(out, fp, sep = ",", row.names = FALSE,
                       col.names = TRUE, quote = FALSE)
  } else {
    utils::write.table(df, fp, sep = ",", row.names = FALSE,
                       col.names = TRUE, quote = FALSE)
  }
  n_tables <<- n_tables + 1L
  invisible(TRUE)
}

save_figure <- function(p, filename, width = 9, height = 6.5) {
  if (is.null(p)) {
    cat(sprintf("  (skip figure %s: NULL)\n", filename))
    return(invisible(FALSE))
  }
  ok <- tryCatch({
    export_plot(p, fig_dir, filename, width = width, height = height)
    TRUE
  }, error = function(e) {
    cat(sprintf("  figure %s failed: %s\n", filename, conditionMessage(e)))
    FALSE
  })
  if (ok) n_figures <<- n_figures + 1L
  invisible(ok)
}

# =============================================================================
# Step 1: 加载五层数据
# =============================================================================
cat("\n=== Step 1: Load multi-omics data ===\n")
sample_info <- load_sample_info(file.path(data_dir, "sampleinfo.csv"))
expr_list  <- list()
finfo_list <- list()
match_cols <- c()
for (nm in names(layer_spec)) {
  sp <- layer_spec[[nm]]
  expr_list[[nm]]  <- load_expression_matrix(file.path(data_dir, sp$expr))
  finfo_list[[nm]] <- load_feature_info(file.path(data_dir, sp$finfo),
                                        id_col = sp$id_col)
  match_cols[nm]   <- sp$match_col
}
cat(sprintf("  Loaded %d omics layers, %d samples.\n",
            length(expr_list), ncol(expr_list[[1]])))

# =============================================================================
# Step 2: 构建容器并预处理
# =============================================================================
cat("\n=== Step 2: Build & preprocess MultiOmicsData ===\n")
mo <- create_multiomics_data(expr_list, sample_info, finfo_list,
                             match_cols = match_cols)
mo <- preprocess_multiomics(mo, group_col = "condition")
cat("  Preprocessing done.\n")

# =============================================================================
# Step 3: 特征预筛选（仅在每个矩阵内取 Top-N，不改变原始数据加载）
# =============================================================================
cat("\n=== Step 3: Feature pre-selection (top variance) ===\n")
mats <- lapply(CFG$layer_order, function(nm) get_omics_matrix(mo, nm))
names(mats) <- CFG$layer_order
for (nm in names(mats)) {
  mats[[nm]] <- select_top_features(mats[[nm]], CFG$top_n_features,
                                    label = nm, verbose = TRUE)
}

# =============================================================================
# Step 4: 跨组学两两关联
# =============================================================================
cat("\n=== Step 4: Cross-omics associations ===\n")
cross_res <- list()
for (i in seq_along(CFG$layer_order)) {
  for (j in seq_along(CFG$layer_order)) {
    if (i < j) {
      a <- CFG$layer_order[i]; b <- CFG$layer_order[j]
      key <- sprintf("%s__%s", a, b)
      res <- tryCatch({
        run_cross_omics_association(
          mats[[a]], mats[[b]], name_x = a, name_y = b,
          top_n = NULL,                       # 已在 Step 3 预筛选
          max_pairs_for_mic = CFG$max_pairs_for_mic,
          mic_pvalue_method = CFG$mic_pvalue_method,
          n_perm = CFG$n_perm,
          score_method = CFG$score_method,
          score_weight = CFG$score_weight,
          p_adjust = "BH",
          p_threshold = CFG$p_threshold,
          rho_linear_min = CFG$rho_linear_min,
          verbose = TRUE)
      }, error = function(e) {
        cat(sprintf("  [cross %s] failed: %s\n", key, conditionMessage(e)))
        NULL
      })
      if (!is.null(res)) {
        cross_res[[key]] <- res
        save_table(res$edges, sprintf("assoc_step4_cross_%s.csv", key))
        # 网络可视化
        g <- build_association_network(res$edges,
                                        p_threshold = CFG$p_threshold,
                                        max_edges = CFG$max_edges_plot,
                                        default_omics = "feature")
        if (!is.null(g)) {
          p_net <- plot_association_network(
            g, label_top_n = CFG$label_top_n,
            title = sprintf("Cross-omics: %s x %s", a, b))
          save_figure(p_net, sprintf("assoc_step4_network_%s", key))
          hubs <- get_association_hubs(g, top_n = 20)
          if (!is.null(hubs)) save_table(hubs, sprintf("assoc_step4_hubs_%s.csv", key))
        }
      }
    }
  }
}
cat(sprintf("  Completed %d cross-omics combinations.\n", length(cross_res)))

# =============================================================================
# Step 5: 组学内关联
# =============================================================================
cat("\n=== Step 5: Intra-omics associations ===\n")
intra_res <- list()
for (nm in CFG$layer_order) {
  res <- tryCatch({
    run_intra_omics_association(
      mats[[nm]], name = nm,
      top_n = NULL,
      max_pairs_for_mic = CFG$max_pairs_for_mic,
      mic_pvalue_method = CFG$mic_pvalue_method,
      n_perm = CFG$n_perm,
      score_method = CFG$score_method,
      score_weight = CFG$score_weight,
      p_adjust = "BH",
      p_threshold = CFG$p_threshold,
      rho_linear_min = CFG$rho_linear_min,
      verbose = TRUE)
  }, error = function(e) {
    cat(sprintf("  [intra %s] failed: %s\n", nm, conditionMessage(e)))
    NULL
  })
  if (!is.null(res)) {
    intra_res[[nm]] <- res
    save_table(res$edges, sprintf("assoc_step5_intra_%s.csv", nm))
    g <- build_association_network(res$edges,
                                    p_threshold = CFG$p_threshold,
                                    max_edges = CFG$max_edges_plot,
                                    default_omics = nm)
    if (!is.null(g)) {
      p_net <- plot_association_network(
        g, label_top_n = CFG$label_top_n,
        title = sprintf("Intra-omics: %s", nm))
      save_figure(p_net, sprintf("assoc_step5_network_%s", nm))
      hubs <- get_association_hubs(g, top_n = 20)
      if (!is.null(hubs)) save_table(hubs, sprintf("assoc_step5_hubs_%s.csv", nm))
    }
  }
}
cat(sprintf("  Completed %d intra-omics layers.\n", length(intra_res)))

# =============================================================================
# Step 6: 关联汇总图（所有组合显著边数量与类型构成）
# =============================================================================
cat("\n=== Step 6: Association summary plot ===\n")
all_res <- c(cross_res, intra_res)
p_sum <- tryCatch(plot_association_summary(all_res, title = "Association Summary"),
                  error = function(e) {
                    cat(sprintf("  summary plot failed: %s\n", conditionMessage(e)))
                    NULL
                  })
save_figure(p_sum, "assoc_step6_summary")

# =============================================================================
# Step 7: 汇总与耗时
# =============================================================================
cat("\n=== Step 7: Summary ===\n")
# 校验 CSV 列名严格性（取任意一个跨组学边表检查）
ref_cols <- c("source", "target", "spearman-rho", "spearman-pval",
              "MIC", "MIC-pvalue", "score", "pvalue", "association")
for (key in names(cross_res)) {
  cols <- colnames(cross_res[[key]]$edges)
  if (!identical(cols, ref_cols)) {
    warning(sprintf("Edge table [%s] column names mismatch: %s",
                    key, paste(cols, collapse = ",")))
  }
}
# 打印各组合统计
cat(sprintf("%-40s %10s %12s %10s\n", "combo", "pairs", "signif", "nonlinear"))
for (key in names(all_res)) {
  pr <- all_res[[key]]$params
  cat(sprintf("%-40s %10d %12d %10d\n",
              key, pr$n_pairs, pr$n_significant, pr$n_nonlinear))
}
t_end <- Sys.time()
cat(sprintf("\nTables written : %d\n", n_tables))
cat(sprintf("Figures written: %d\n", n_figures))
cat(sprintf("Total runtime  : %.1f sec\n", as.numeric(difftime(t_end, t_start, units = "secs"))))
cat("=== Done ===\n")
