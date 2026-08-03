#!/usr/bin/env Rscript
# ==============================================================================
# OmicsFlow Demo: Multi-Omics Association Analysis of Tobacco Flavour Fermentation
# ==============================================================================
#
# Research background
# -------------------
# Tobacco leaves of two varieties (Virginia and Burley) were fermented in two
# geographically contrasting regions: Yunnan, a highland site (altitude around
# 1900 m, cooler and drier), and Henan, a plain site (altitude around 90 m,
# warmer and more humid). Leaves were sampled from the fresh state through the
# early, active and late maturation phases of fermentation, over 13 time points
# spanning day -1 (fresh) to day 60.
#
# Five molecular layers were profiled on the same 312 samples:
#   transcriptome  2000 genes    (host Nicotiana tabacum plus microbial genes)
#   proteome       1000 proteins (host plus microbial)
#   metabolome     1000 metabolites
#   volatilome      300 volatile aroma compounds
#   microbiome      131 bacterial taxa (16S)
#
# Scientific questions addressed by this pipeline
# -----------------------------------------------
#   Q1 Geographic divergence: how do the two regions differ across all layers,
#      and how much of that difference tracks temperature, humidity and altitude?
#   Q2 Temporal dynamics: what trajectory does fermentation follow, and do the
#      two regions progress at the same rhythm?
#   Q3 Microbial drivers: which taxa are associated with the metabolites and
#      aroma compounds that define flavour?
#   Q4 Pathway bridging: can a signal be traced from gene to protein to
#      metabolite to aroma compound within the same functional category?
#
# Outputs are written to figures/ (PNG and PDF) and tables/ (CSV).
# ==============================================================================

set.seed(42)

source("G:/OmicsWorks/agent/rscript/source_all_scripts.R")

suppressPackageStartupMessages({
  library(ggplot2)
  library(ggrepel)
  library(RColorBrewer)
  library(pheatmap)
})

# ---- Paths -------------------------------------------------------------------
data_dir   <- "G:/OmicsWorks/extdata/Tobacco-fermentation"
result_dir <- "G:/OmicsWorks/test/multiple_omics"
fig_dir    <- file.path(result_dir, "figures")
tab_dir    <- file.path(result_dir, "tables")

for (d in c(fig_dir, tab_dir)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

# Layer specification: expression file, annotation file, annotation id column,
# and the column used to match features to the expression matrix rownames.
# The 16S layer is keyed on its ID (MIC_xxxxx) while the other four layers are
# keyed on the compound or gene name.
layer_spec <- list(
  transcriptome = list(expr = "expression_transcriptome.csv",
                       finfo = "featureinfo_transcriptome.csv",
                       id_col = "gene_id", match_col = "name"),
  proteome      = list(expr = "expression_proteome.csv",
                       finfo = "featureinfo_proteome.csv",
                       id_col = "gene_id", match_col = "name"),
  metabolome    = list(expr = "expression_metabolome.csv",
                       finfo = "featureinfo_metabolome.csv",
                       id_col = "ID", match_col = "name"),
  volatilome    = list(expr = "expression_volatilome.csv",
                       finfo = "featureinfo_volatilome.csv",
                       id_col = "ID", match_col = "name"),
  microbiome    = list(expr = "expression_16s.csv",
                       finfo = "featureinfo_16s.csv",
                       id_col = "ID", match_col = "ID")
)

env_vars <- c("temperature_C", "humidity_pct", "altitude_m")

cat("\n")
cat("==============================================================\n")
cat(" OmicsFlow Multi-Omics Demo: Tobacco Flavour Fermentation\n")
cat("==============================================================\n")


# ==== Step 1: Load the five omics layers ======================================
cat("\n=== Step 1: Loading five omics layers ===\n")

sample_info <- load_sample_info(file.path(data_dir, "sampleinfo.csv"))
cat(sprintf("Sample metadata: %d samples, %d annotation columns\n",
            nrow(sample_info), ncol(sample_info)))

expr_list <- list()
finfo_list <- list()
match_cols <- character(0)

for (nm in names(layer_spec)) {
  sp <- layer_spec[[nm]]
  expr_list[[nm]] <- load_expression_matrix(file.path(data_dir, sp$expr))
  finfo_list[[nm]] <- load_feature_info(file.path(data_dir, sp$finfo),
                                        id_col = sp$id_col)
  match_cols[nm] <- sp$match_col
  cat(sprintf("  %-14s %5d features x %3d samples\n",
              nm, nrow(expr_list[[nm]]), ncol(expr_list[[nm]])))
}


# ==== Step 2: Build and align the MultiOmicsData container ====================
cat("\n=== Step 2: Aligning layers into a MultiOmicsData container ===\n")

mo <- create_multiomics_data(expr_list, sample_info, finfo_list,
                             match_cols = match_cols)
print(mo)

export_table(
  data.frame(
    omics = names(mo$metadata$n_features_per_omics),
    n_features = as.integer(mo$metadata$n_features_per_omics),
    n_samples = mo$metadata$n_samples,
    stringsAsFactors = FALSE
  ),
  tab_dir, "step02_layer_overview.csv", use_rownames = FALSE
)


# ==== Step 3: Per-layer preprocessing =========================================
cat("\n=== Step 3: Preprocessing every layer ===\n")
# Compositional 16S counts and the four abundance layers all pass through the
# same chain: missing-value filtering, half-minimum imputation, total-sum
# normalisation and Pareto scaling. The unprocessed container is kept so that
# Step 6 can test absolute intensity differences, which sample-total
# normalisation would otherwise remove.

mo_raw <- mo
mo <- preprocess_multiomics(mo, group_col = "condition")

cat("Feature counts after preprocessing:\n")
for (nm in mo$metadata$omics_names) {
  cat(sprintf("  %-14s %5d features\n", nm, nrow(get_omics_matrix(mo, nm))))
}


# ==== Step 4: Per-layer PCA overview ==========================================
cat("\n=== Step 4: PCA overview of each layer ===\n")

pca_results <- list()
for (nm in mo$metadata$omics_names) {
  res <- tryCatch({
    pca <- run_pca(get_omics_matrix(mo, nm))
    pca_results[[nm]] <- pca

    p_loc <- plot_pca_scores(pca, mo$sample_info, color_col = "location")
    export_plot(p_loc + ggtitle(sprintf("PCA of %s coloured by region", nm)),
                fig_dir, sprintf("step04_pca_%s_location", nm))

    p_phase <- plot_pca_scores(pca, mo$sample_info, color_col = "phase")
    export_plot(p_phase + ggtitle(sprintf("PCA of %s coloured by phase", nm)),
                fig_dir, sprintf("step04_pca_%s_phase", nm))

    cat(sprintf("  %-14s PC1 %.1f%%, PC2 %.1f%%\n",
                nm, pca$var_explained[1], pca$var_explained[2]))
    TRUE
  }, error = function(e) {
    cat(sprintf("  PCA failed for %s: %s\n", nm, conditionMessage(e)))
    FALSE
  })
}


# ==== Step 5: Per-layer PLS-DA on region ======================================
cat("\n=== Step 5: PLS-DA discriminating the two regions ===\n")

plsda_results <- list()
vip_tables <- list()
for (nm in mo$metadata$omics_names) {
  tryCatch({
    pls <- run_plsda(get_omics_matrix(mo, nm), mo$sample_info,
                     group_col = "location")
    plsda_results[[nm]] <- pls

    p <- plot_plsda_scores(pls, mo$sample_info, color_col = "location")
    export_plot(p + ggtitle(sprintf("PLS-DA of %s by region", nm)),
                fig_dir, sprintf("step05_plsda_%s", nm))

    # run_plsda returns vip as a data.frame with a single 'vip' column and the
    # feature identifiers held in the rownames.
    if (!is.null(pls$vip) && nrow(pls$vip) > 0) {
      vip_df <- data.frame(feature = rownames(pls$vip),
                           VIP = as.numeric(pls$vip$vip),
                           omics = nm,
                           stringsAsFactors = FALSE)
      vip_df <- vip_df[order(-vip_df$VIP), , drop = FALSE]
      vip_tables[[nm]] <- vip_df
      cat(sprintf("  %-14s %d features with VIP > 1\n",
                  nm, sum(vip_df$VIP > 1, na.rm = TRUE)))
    }
  }, error = function(e) {
    cat(sprintf("  PLS-DA failed for %s: %s\n", nm, conditionMessage(e)))
  })
}
if (length(vip_tables) > 0) {
  export_table(do.call(rbind, vip_tables), tab_dir,
               "step05_vip_all_layers.csv", use_rownames = FALSE)
}


# ==== Step 6: Regional differential analysis (Q1) =============================
cat("\n=== Step 6: Differential features between Yunnan and Henan ===\n")
# Two design facts shape this step.
#
# First, the layout is fully crossed: both regions were sampled at all 13 time
# points with both varieties. Fermentation phase dominates the variance (a
# per-feature ANOVA gives a median R2 near 0.64 for phase against roughly 0.01
# for region), so pooling every phase buries the regional contrast in the
# temporal spread. The test is therefore stratified by phase.
#
# Second, the regional effect in this dataset is largely a uniform shift in
# overall signal intensity. normalize_sample_total() rescales each sample to
# relative abundance and removes exactly that shift, which is appropriate for
# the correlation and ordination work of the later steps but erases the very
# contrast tested here. Differential testing therefore runs on a container that
# has been filtered and imputed but not normalised or scaled.

mo_de <- preprocess_multiomics(mo_raw, group_col = "condition",
                               normalize = FALSE, scale = FALSE)

phases <- c("Fresh", "Early_fermentation", "Active_fermentation", "Late_maturation")
phases <- intersect(phases, unique(as.character(mo_de$sample_info$phase)))

de_tables <- list()
de_counts <- list()

for (nm in mo_de$metadata$omics_names) {
  mat <- get_omics_matrix(mo_de, nm)
  layer_hits <- integer(0)

  for (ph in phases) {
    keep <- rownames(mo_de$sample_info)[
      as.character(mo_de$sample_info$phase) == ph]
    if (length(keep) < 6) next

    tbl <- tryCatch({
      de <- run_limma(mat[, keep, drop = FALSE],
                      mo_de$sample_info[keep, , drop = FALSE],
                      group_col = "location",
                      control_group = "Henan", case_groups = "Yunnan")
      de$results
    }, error = function(e) {
      cat(sprintf("  limma failed for %s / %s: %s\n",
                  nm, ph, conditionMessage(e)))
      NULL
    })

    if (!is.null(tbl) && nrow(tbl) > 0) {
      tbl$feature <- rownames(tbl)
      tbl$omics <- nm
      tbl$phase <- ph
      rownames(tbl) <- NULL
      de_tables[[paste(nm, ph, sep = "_")]] <- tbl
      layer_hits[ph] <- sum(tbl$p_adj < 0.05, na.rm = TRUE)

      p <- plot_volcano(tbl, p_threshold = 0.05, logfc_threshold = 1)
      export_plot(p + ggtitle(sprintf("%s, %s: Yunnan vs Henan", nm, ph)),
                  fig_dir, sprintf("step06_volcano_%s_%s", nm, ph))
    }
  }

  if (length(layer_hits) > 0) {
    cat(sprintf("  %-14s significant by phase (padj<0.05): %s\n", nm,
                paste(sprintf("%s=%d", names(layer_hits), layer_hits),
                      collapse = ", ")))
    de_counts[[nm]] <- data.frame(
      omics = nm, phase = names(layer_hits),
      n_significant = as.integer(layer_hits), stringsAsFactors = FALSE)
  }
}

if (length(de_tables) > 0) {
  export_table(do.call(rbind, de_tables), tab_dir,
               "step06_regional_de_by_phase.csv", use_rownames = FALSE)
}
if (length(de_counts) > 0) {
  cnt <- do.call(rbind, de_counts)
  rownames(cnt) <- NULL
  export_table(cnt, tab_dir, "step06_regional_de_counts.csv",
               use_rownames = FALSE)
}


# ==== Step 7: Mantel tests (Q1) ===============================================
cat("\n=== Step 7: Mantel tests between layers and against environment ===\n")
# Distances are computed in sample space, so the test is independent of how
# many features a layer contributes.

mantel_res <- tryCatch({
  run_mantel_test(get_omics_list(mo),
                  env_data = mo$sample_info[, env_vars, drop = FALSE],
                  permutations = 999)
}, error = function(e) {
  cat(sprintf("  Mantel test failed: %s\n", conditionMessage(e)))
  NULL
})

if (!is.null(mantel_res)) {
  if (nrow(mantel_res$omics_omics) > 0) {
    export_table(mantel_res$omics_omics, tab_dir,
                 "step07_mantel_layer_vs_layer.csv", use_rownames = FALSE)
  }
  if (nrow(mantel_res$omics_env) > 0) {
    export_table(mantel_res$omics_env, tab_dir,
                 "step07_mantel_layer_vs_environment.csv", use_rownames = FALSE)
    top_env <- mantel_res$omics_env[order(-mantel_res$omics_env$mantel_r), ][1, ]
    cat(sprintf("  Strongest environmental association: %s vs %s, r = %.3f, p = %.3f\n",
                top_env$layer, top_env$variable, top_env$mantel_r, top_env$p_value))
  }
  p <- plot_mantel_network(mantel_res)
  if (!is.null(p)) export_plot(p, fig_dir, "step07_mantel_summary",
                               width = 9, height = 8)
}


# ==== Step 8: Procrustes congruence (Q1) ======================================
cat("\n=== Step 8: Procrustes congruence of key layer pairs ===\n")

proc_pairs <- list(
  c("microbiome", "metabolome"),
  c("microbiome", "volatilome"),
  c("metabolome", "volatilome"),
  c("transcriptome", "proteome")
)
proc_rows <- list()
for (pr in proc_pairs) {
  tryCatch({
    res <- run_procrustes(get_omics_matrix(mo, pr[1]),
                          get_omics_matrix(mo, pr[2]),
                          permutations = 999,
                          name_x = pr[1], name_y = pr[2])
    proc_rows[[paste(pr, collapse = "_")]] <- data.frame(
      layer_x = pr[1], layer_y = pr[2],
      procrustes_r = res$correlation,
      ss = res$ss,
      p_value = res$p_value,
      stringsAsFactors = FALSE
    )
    cat(sprintf("  %-14s vs %-14s r = %.3f, p = %.3f\n",
                pr[1], pr[2], res$correlation, res$p_value))

    p <- plot_procrustes(res, mo$sample_info, color_col = "location",
                         title = sprintf("Procrustes: %s vs %s", pr[1], pr[2]))
    if (!is.null(p)) {
      export_plot(p, fig_dir,
                  sprintf("step08_procrustes_%s_vs_%s", pr[1], pr[2]))
    }
  }, error = function(e) {
    cat(sprintf("  Procrustes failed for %s vs %s: %s\n",
                pr[1], pr[2], conditionMessage(e)))
  })
}
if (length(proc_rows) > 0) {
  export_table(do.call(rbind, proc_rows), tab_dir,
               "step08_procrustes_summary.csv", use_rownames = FALSE)
}


# ==== Step 9: DIABLO multi-block discrimination (Q1) ==========================
cat("\n=== Step 9: DIABLO multi-block integration on region ===\n")

diablo_res <- run_diablo(mo, group_col = "location", ncomp = 2)

if (!is.null(diablo_res)) {
  export_table(diablo_res$selected_features, tab_dir,
               "step09_diablo_selected_features.csv", use_rownames = FALSE)
  p <- plot_diablo_scores(diablo_res)
  if (!is.null(p)) export_plot(p, fig_dir, "step09_diablo_scores",
                               width = 11, height = 7)

  # selected_features carries the block name in the 'layer' column.
  n_by_layer <- table(diablo_res$selected_features$layer)
  cat("  Features selected per block:\n")
  for (nm in names(n_by_layer)) {
    cat(sprintf("    %-14s %d\n", nm, n_by_layer[[nm]]))
  }
} else {
  cat("  DIABLO unavailable; the per-layer PLS-DA of Step 5 serves as fallback.\n")
}


# ==== Step 10: Fermentation trajectories (Q2) =================================
cat("\n=== Step 10: Fermentation trajectory per layer and region ===\n")

traj_all <- tryCatch({
  run_all_temporal_trajectories(mo, time_col = "day",
                                group_col = "location", phase_col = "phase")
}, error = function(e) {
  cat(sprintf("  Trajectory analysis failed: %s\n", conditionMessage(e)))
  NULL
})

if (!is.null(traj_all)) {
  for (nm in names(traj_all$per_layer)) {
    p <- plot_temporal_trajectory(
      traj_all$per_layer[[nm]],
      title = sprintf("Fermentation trajectory: %s", nm))
    if (!is.null(p)) {
      export_plot(p, fig_dir, sprintf("step10_trajectory_%s", nm))
    }
    export_table(traj_all$per_layer[[nm]]$trajectory, tab_dir,
                 sprintf("step10_trajectory_%s.csv", nm), use_rownames = FALSE)
  }
  if (nrow(traj_all$path_summary) > 0) {
    export_table(traj_all$path_summary, tab_dir,
                 "step10_trajectory_path_length.csv", use_rownames = FALSE)
    cat("  Cumulative trajectory length (larger = more compositional change):\n")
    ps <- traj_all$path_summary
    for (i in seq_len(nrow(ps))) {
      cat(sprintf("    %-14s %-8s %.2f\n",
                  ps$omics[i], ps$group[i], ps$path_length[i]))
    }
  }
}


# ==== Step 11: Temporal expression clustering (Q2) ============================
cat("\n=== Step 11: Temporal pattern clustering ===\n")

for (nm in c("volatilome", "metabolome", "microbiome")) {
  tryCatch({
    tc <- run_temporal_clustering(get_omics_matrix(mo, nm), mo$sample_info,
                                  time_col = "day", n_clusters = 6)
    export_table(tc$membership, tab_dir,
                 sprintf("step11_temporal_clusters_%s.csv", nm),
                 use_rownames = FALSE)
    p <- plot_temporal_clusters(
      tc, title = sprintf("Temporal clusters: %s", nm))
    if (!is.null(p)) {
      export_plot(p, fig_dir, sprintf("step11_temporal_clusters_%s", nm),
                  width = 9, height = 6)
    }
  }, error = function(e) {
    cat(sprintf("  Temporal clustering failed for %s: %s\n",
                nm, conditionMessage(e)))
  })
}


# ==== Step 12: Microbe to metabolite association (Q3) =========================
cat("\n=== Step 12: Microbiome to metabolome association ===\n")

cc_metab <- tryCatch({
  run_cross_correlation(get_omics_matrix(mo, "microbiome"),
                        get_omics_matrix(mo, "metabolome"),
                        r_threshold = 0.7, p_threshold = 0.05,
                        name_x = "microbiome", name_y = "metabolome")
}, error = function(e) {
  cat(sprintf("  Correlation failed: %s\n", conditionMessage(e)))
  NULL
})

if (!is.null(cc_metab)) {
  export_table(cc_metab$pairs, tab_dir,
               "step12_microbiome_metabolome_pairs.csv", use_rownames = FALSE)
  hm <- plot_cross_correlation_heatmap(
    cc_metab, top_n = 30,
    title = "Microbiome vs metabolome correlation")
  if (!is.null(hm)) {
    export_heatmap(hm, fig_dir, "step12_microbiome_metabolome_heatmap")
  }
  partners <- summarise_correlation_partners(cc_metab$pairs)
  export_table(partners, tab_dir,
               "step12_microbiome_metabolome_partners.csv", use_rownames = FALSE)
  p <- plot_correlation_partners(
    partners, top_n = 20,
    title = "Taxa with most metabolite associations")
  if (!is.null(p)) export_plot(p, fig_dir, "step12_top_taxa_metabolome")
}


# ==== Step 13: Microbe to aroma association (Q3) ==============================
cat("\n=== Step 13: Microbiome to volatilome (aroma) association ===\n")

cc_volat <- tryCatch({
  run_cross_correlation(get_omics_matrix(mo, "microbiome"),
                        get_omics_matrix(mo, "volatilome"),
                        r_threshold = 0.7, p_threshold = 0.05,
                        name_x = "microbiome", name_y = "volatilome")
}, error = function(e) {
  cat(sprintf("  Correlation failed: %s\n", conditionMessage(e)))
  NULL
})

if (!is.null(cc_volat)) {
  export_table(cc_volat$pairs, tab_dir,
               "step13_microbiome_volatilome_pairs.csv", use_rownames = FALSE)
  hm <- plot_cross_correlation_heatmap(
    cc_volat, top_n = 30,
    title = "Microbiome vs volatilome correlation")
  if (!is.null(hm)) {
    export_heatmap(hm, fig_dir, "step13_microbiome_volatilome_heatmap")
  }

  # Attach taxonomy so the candidate drivers are biologically readable.
  partners <- summarise_correlation_partners(cc_volat$pairs)
  mic_info <- get_feature_info(mo, "microbiome")
  hit <- match(partners$feature, rownames(mic_info))
  partners$taxon <- mic_info$name[hit]
  partners$family <- mic_info$family[hit]
  partners$phylum <- mic_info$taxonomy_phylum[hit]
  export_table(partners, tab_dir,
               "step13_aroma_driving_taxa.csv", use_rownames = FALSE)

  cat("  Top candidate aroma-driving taxa:\n")
  for (i in seq_len(min(5, nrow(partners)))) {
    cat(sprintf("    %-24s (%s) %d aroma partners, mean |r| = %.2f\n",
                partners$taxon[i], partners$phylum[i],
                partners$n_partners[i], partners$mean_abs_r[i]))
  }
  p <- plot_correlation_partners(
    partners, top_n = 20, title = "Taxa with most aroma associations")
  if (!is.null(p)) export_plot(p, fig_dir, "step13_top_taxa_volatilome")
}


# ==== Step 14: Pathway bridging (Q4) ==========================================
cat("\n=== Step 14: Gene to protein to metabolite to aroma bridging ===\n")

modules <- tryCatch({
  build_cross_omics_modules(mo, category_col = "super_class", min_size = 3)
}, error = function(e) {
  cat(sprintf("  Module construction failed: %s\n", conditionMessage(e)))
  NULL
})

if (!is.null(modules) && length(modules$eigengenes) >= 2) {
  export_table(modules$definitions, tab_dir,
               "step14_module_definitions.csv", use_rownames = FALSE)

  bridge <- tryCatch({
    run_pathway_bridge(modules)
  }, error = function(e) {
    cat(sprintf("  Pathway bridging failed: %s\n", conditionMessage(e)))
    NULL
  })

  if (!is.null(bridge) && nrow(bridge$links) > 0) {
    export_table(bridge$links, tab_dir,
                 "step14_pathway_links.csv", use_rownames = FALSE)
    export_table(bridge$chains, tab_dir,
                 "step14_pathway_chains.csv", use_rownames = FALSE)
    p <- plot_pathway_bridge_heatmap(bridge, top_n = 30)
    if (!is.null(p)) export_plot(p, fig_dir, "step14_pathway_bridge_heatmap",
                                 width = 9, height = 8)

    full <- bridge$chains[bridge$chains$n_links >= 3, , drop = FALSE]
    cat(sprintf("  %d module(s) span three or more layer transitions\n",
                nrow(full)))
    for (i in seq_len(min(3, nrow(full)))) {
      cat(sprintf("    %s: %s\n", full$module[i], full$path[i]))
    }
  }

  # Host and microbial pathways are separated using the organism annotation.
  for (side in c("host", "microbe")) {
    tryCatch({
      mods_side <- build_cross_omics_modules(
        mo, category_col = "super_class", min_size = 3,
        layers = c("transcriptome", "proteome"),
        organism_col = "organism", organism_keep = side, verbose = FALSE)
      if (length(mods_side$eigengenes) >= 2) {
        br_side <- run_pathway_bridge(
          mods_side, layer_order = c("transcriptome", "proteome"),
          verbose = FALSE)
        if (nrow(br_side$links) > 0) {
          export_table(br_side$links, tab_dir,
                       sprintf("step14_pathway_links_%s.csv", side),
                       use_rownames = FALSE)
          cat(sprintf("  %-8s transcriptome-proteome links: %d (%d significant)\n",
                      side, nrow(br_side$links),
                      sum(br_side$links$padj < 0.05, na.rm = TRUE)))
        }
      }
    }, error = function(e) {
      cat(sprintf("  %s pathway split failed: %s\n", side, conditionMessage(e)))
    })
  }
} else {
  cat("  Fewer than two layers carry a super_class annotation; bridging skipped.\n")
}


# ==== Step 15: Cross-omics network and hubs (Q3) ==============================
cat("\n=== Step 15: Cross-omics association network ===\n")

pairs_list <- list()
if (!is.null(cc_metab)) pairs_list[["microbiome_vs_metabolome"]] <- cc_metab$pairs
if (!is.null(cc_volat)) pairs_list[["microbiome_vs_volatilome"]] <- cc_volat$pairs

if (length(pairs_list) > 0) {
  net <- tryCatch({
    build_cross_omics_network(pairs_list, r_threshold = 0.8,
                              padj_threshold = 0.01, max_edges = 2000)
  }, error = function(e) {
    cat(sprintf("  Network construction failed: %s\n", conditionMessage(e)))
    NULL
  })

  if (!is.null(net)) {
    export_table(net$edges, tab_dir, "step15_network_edges.csv",
                 use_rownames = FALSE)
    export_table(net$nodes, tab_dir, "step15_network_nodes.csv",
                 use_rownames = FALSE)

    hubs <- get_network_hubs(net, top_n = 20, by = "degree")
    export_table(hubs, tab_dir, "step15_network_hubs.csv", use_rownames = FALSE)

    p <- plot_cross_omics_network(net, label_top = 15)
    if (!is.null(p)) export_plot(p, fig_dir, "step15_cross_omics_network",
                                 width = 10, height = 8)
  }
} else {
  cat("  No correlation result available for the network.\n")
}


# ==== Step 16: Summary ========================================================
cat("\n=== Step 16: Summary ===\n")

n_fig <- length(list.files(fig_dir, pattern = "\\.(png|pdf)$"))
n_tab <- length(list.files(tab_dir, pattern = "\\.csv$"))

cat("\n--------------------------------------------------------------\n")
cat(" Analysis complete\n")
cat("--------------------------------------------------------------\n")
cat(sprintf(" Samples analysed      : %d\n", mo$metadata$n_samples))
cat(sprintf(" Omics layers          : %d (%s)\n",
            mo$metadata$n_omics,
            paste(mo$metadata$omics_names, collapse = ", ")))
cat(sprintf(" Total features        : %d\n",
            sum(mo$metadata$n_features_per_omics)))
cat(sprintf(" Figures written       : %d  -> %s\n", n_fig, fig_dir))
cat(sprintf(" Tables written        : %d  -> %s\n", n_tab, tab_dir))
cat("--------------------------------------------------------------\n")

if (length(de_counts) > 0) {
  cnt_all <- do.call(rbind, de_counts)
  cat(sprintf(" Q1 region     : %d region-associated features across phases\n",
              sum(cnt_all$n_significant)))
  cat("                 (detected only after stratifying by fermentation phase\n")
  cat("                  and before sample-total normalisation)\n")
}
if (!is.null(mantel_res) && nrow(mantel_res$omics_env) > 0) {
  sig_env <- mantel_res$omics_env[mantel_res$omics_env$p_value < 0.05, ]
  cat(sprintf(" Q1 environment: %d of %d layer-variable pairs significant\n",
              nrow(sig_env), nrow(mantel_res$omics_env)))
}
if (!is.null(traj_all) && nrow(traj_all$path_summary) > 0) {
  cat(sprintf(" Q2 dynamics   : trajectories reconstructed for %d layers\n",
              length(traj_all$per_layer)))
}
if (!is.null(cc_volat)) {
  cat(sprintf(" Q3 drivers    : %d significant microbe-aroma associations\n",
              nrow(cc_volat$pairs)))
}
cat("--------------------------------------------------------------\n\n")
