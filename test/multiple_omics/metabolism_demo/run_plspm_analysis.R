# ==============================================================================
# 三套潜变量 PLSPM 路径分析脚本
# ==============================================================================
# 职责：读取 cache 的 log2 矩阵、feature_info 与 wgcna_result，分别以三套
#       潜变量体系构建 PLSPM 路径模型：
#   (a) WGCNA 共表达模块       —— 由 module_colors 按模块分组构造 latent_def
#   (b) KEGG 通路              —— map_kegg_compound_to_pathway + build_latent_def_from_annotation
#   (c) 代谢物 class 化学分类  —— build_latent_def_from_annotation(category_col="class")
#
# 每套体系导出潜变量得分表、外模型载荷表、内模型路径系数表与路径网络图。
# ==============================================================================

source("g:/OmicsWorks/test/multiple_omics/metabolism_demo/config.R", encoding = "UTF-8")

set.seed(RANDOM_SEED)

section("三套潜变量 PLSPM 路径分析")

step("加载 agent/rscript 模块")
source_modules(c(
  "utils/export.R",
  "utils/plot_helpers.R",
  "utils/kegg_pathway.R",
  "network/plspm_net.R"
))

log2_mat     <- readRDS(file.path(CACHE_DIR, "log2_mat.rds"))
feature_info <- readRDS(file.path(CACHE_DIR, "feature_info.rds"))
sample_info  <- readRDS(file.path(CACHE_DIR, "sample_info.rds"))
wgcna_res    <- readRDS(file.path(CACHE_DIR, "wgcna.rds"))
mat_dim("缓存 log2 矩阵", log2_mat)

# feature_info 的行名即 Feature ID（由 load_feature_info(id_col="name") 设定），
# 与 log2_mat 的行名一致
FEATURE_ID_COL <- "name"

# ------------------------------------------------------------------------------
# 通用执行与导出流程
# ------------------------------------------------------------------------------
run_and_export <- function(latent_def, tag, title) {
  section(sprintf("PLSPM 体系: %s", title))

  if (length(latent_def) == 0) {
    cat("    [warn] 潜变量为空，跳过该体系\n")
    return(NULL)
  }

  # 控制潜变量个数：内模型为 k*(k-1) 次回归，k 过大不可解且图不可读
  sizes <- vapply(latent_def, length, integer(1))
  if (length(latent_def) > PLSPM_MAX_LV) {
    keep <- order(sizes, decreasing = TRUE)[seq_len(PLSPM_MAX_LV)]
    latent_def <- latent_def[sort(keep)]
    sizes <- vapply(latent_def, length, integer(1))
    cat(sprintf("    [info] 潜变量数超过上限，按成员数保留 Top %d\n", PLSPM_MAX_LV))
  }

  cat(sprintf("    潜变量个数: %d\n", length(latent_def)))
  cat("    各潜变量成员数:\n")
  for (nm in names(latent_def)) {
    cat(sprintf("      %-46s : %d\n", substr(nm, 1, 46), length(latent_def[[nm]])))
  }

  step("run_plspm")
  res <- timed(sprintf("run_plspm(%s)", tag),
               run_plspm(log2_mat, feature_info, latent_def,
                         feature_id_col = FEATURE_ID_COL, ncomp = 2))

  n_lv <- ncol(res$scores)
  cat(sprintf("    实际建成潜变量数: %d\n", n_lv))
  if (n_lv == 0) {
    cat("    [warn] 无有效潜变量，跳过导出\n")
    return(res)
  }

  cat(sprintf("    外模型载荷行数  : %d\n", nrow(res$outer_model)))
  cat(sprintf("    内模型路径数    : %d\n", nrow(res$inner_model)))
  if (nrow(res$inner_model) > 0) {
    n_sig <- sum(res$inner_model$p_value < 0.05, na.rm = TRUE)
    cat(sprintf("    p < 0.05 的路径 : %d / %d\n", n_sig, nrow(res$inner_model)))
    cat("    |path_coeff| 分布:\n")
    print(round(stats::quantile(abs(res$inner_model$path_coeff),
                                c(0, .25, .5, .75, 1), na.rm = TRUE), 4))

    top_paths <- res$inner_model[order(abs(res$inner_model$path_coeff),
                                       decreasing = TRUE), ]
    cat("\n    Top5 强路径:\n")
    for (i in seq_len(min(5, nrow(top_paths)))) {
      cat(sprintf("      %-28s -> %-28s  beta=%+.4f  p=%.3g\n",
                  substr(top_paths$from[i], 1, 28),
                  substr(top_paths$to[i], 1, 28),
                  top_paths$path_coeff[i], top_paths$p_value[i]))
    }
  }

  # --- 导出 ---
  export_table(res$scores, RESULT_DIR, sprintf("40_plspm_%s_scores", tag),
               use_rownames = TRUE, id_col_name = "sample_id")
  export_table(res$outer_model, RESULT_DIR,
               sprintf("40_plspm_%s_outer_model", tag), use_rownames = FALSE)
  export_table(res$inner_model, RESULT_DIR,
               sprintf("40_plspm_%s_inner_model", tag), use_rownames = FALSE)
  export_table(as.data.frame(res$path_coefficients), RESULT_DIR,
               sprintf("40_plspm_%s_path_matrix", tag),
               use_rownames = TRUE, id_col_name = "from")

  # 潜变量成员归属表
  memb <- do.call(rbind, lapply(names(latent_def), function(nm) {
    data.frame(latent_variable = nm, feature_id = latent_def[[nm]],
               stringsAsFactors = FALSE)
  }))
  export_table(memb, RESULT_DIR, sprintf("40_plspm_%s_membership", tag),
               use_rownames = FALSE)

  step("plot_plspm_network")
  p <- plot_plspm_network(res, p_threshold = 0.05)
  export_plot(p, FIGURE_DIR, sprintf("41_plspm_%s_network", tag),
              width = 11, height = 9)

  invisible(res)
}

# ==============================================================================
# 体系 (a): WGCNA 共表达模块作为潜变量
# ==============================================================================
section("SECTION A  构造 WGCNA 模块潜变量")

mc <- wgcna_res$module_colors
cat(sprintf("    WGCNA 模块归属特征数: %d\n", length(mc)))
# 按模块颜色分组；剔除 grey（WGCNA 中 grey 表示"未分配到任何模块"）
lat_wgcna <- split(names(mc), as.character(mc))
lat_wgcna <- lat_wgcna[names(lat_wgcna) != "grey"]
names(lat_wgcna) <- paste0("ME:", names(lat_wgcna))
lat_wgcna <- lat_wgcna[vapply(lat_wgcna, length, integer(1)) >= PLSPM_MIN_SIZE]
cat(sprintf("    剔除 grey 后的模块潜变量数: %d\n", length(lat_wgcna)))

res_wgcna <- run_and_export(lat_wgcna, "wgcna_module",
                            "WGCNA 共表达模块作为潜变量")

# ==============================================================================
# 体系 (b): KEGG 通路作为潜变量
# ==============================================================================
section("SECTION B  构造 KEGG 通路潜变量")

kegg_vals <- trimws(as.character(feature_info[["kegg"]]))
kegg_ids <- unique(kegg_vals[nzchar(kegg_vals) & !is.na(kegg_vals)])
cat(sprintf("    注释表中唯一 KEGG 化合物数: %d\n", length(kegg_ids)))

step("map_kegg_compound_to_pathway (带 cache_dir 落盘缓存)")
kegg_mapping <- timed("map_kegg_compound_to_pathway",
                      map_kegg_compound_to_pathway(
                        kegg_ids, cache_dir = KEGG_CACHE,
                        batch_size = 10, delay = 0.3
                      ))
cat(sprintf("    映射记录数: %d\n", nrow(kegg_mapping)))
if (nrow(kegg_mapping) > 0) {
  cat(sprintf("    覆盖化合物数: %d, 涉及通路数: %d\n",
              length(unique(kegg_mapping$compound_id)),
              length(unique(kegg_mapping$pathway_name))))
  export_table(kegg_mapping, RESULT_DIR, "40_kegg_pathway_mapping",
               use_rownames = FALSE)
}

step("build_latent_def_from_annotation (use_kegg=TRUE)")
lat_kegg <- build_latent_def_from_annotation(
  log2_mat, feature_info, kegg_mapping = kegg_mapping,
  feature_id_col = FEATURE_ID_COL, kegg_col = "kegg",
  min_size = PLSPM_MIN_SIZE,
  use_kegg = TRUE, use_super_class = FALSE,
  prefix_kegg = "KEGG:"
)
cat(sprintf("    KEGG 潜变量数: %d\n", length(lat_kegg)))

res_kegg <- run_and_export(lat_kegg, "kegg_pathway",
                           "KEGG 通路作为潜变量")

# ==============================================================================
# 体系 (c): 代谢物 class 分类作为潜变量
# ==============================================================================
section("SECTION C  构造代谢物 class 分类潜变量")

step("build_latent_def_from_annotation (category_col='class', use_kegg=FALSE)")
lat_class <- build_latent_def_from_annotation(
  log2_mat, feature_info, kegg_mapping = NULL,
  feature_id_col = FEATURE_ID_COL, category_col = "class",
  min_size = PLSPM_MIN_SIZE,
  use_kegg = FALSE, use_super_class = TRUE,
  prefix_super = "CLASS:"
)
cat(sprintf("    class 潜变量数: %d\n", length(lat_class)))

res_class <- run_and_export(lat_class, "metabolite_class",
                            "代谢物 class 分类作为潜变量")

# ==============================================================================
# 汇总
# ==============================================================================
section("三套体系汇总")

mk_row <- function(res, label) {
  if (is.null(res) || ncol(res$scores) == 0) {
    return(data.frame(system = label, n_latent = 0L, n_paths = 0L,
                      n_sig_paths = 0L, stringsAsFactors = FALSE))
  }
  data.frame(
    system = label,
    n_latent = ncol(res$scores),
    n_paths = nrow(res$inner_model),
    n_sig_paths = sum(res$inner_model$p_value < 0.05, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}

summ <- rbind(
  mk_row(res_wgcna, "WGCNA module"),
  mk_row(res_kegg,  "KEGG pathway"),
  mk_row(res_class, "Metabolite class")
)
print(summ)
export_table(summ, RESULT_DIR, "40_plspm_summary", use_rownames = FALSE)

saveRDS(list(wgcna = res_wgcna, kegg = res_kegg, class = res_class),
        file.path(CACHE_DIR, "plspm.rds"))
step("已缓存 plspm.rds")

cat("\n[done] PLSPM 路径分析完成。\n")
