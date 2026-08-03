#!/usr/bin/env Rscript
# ==============================================================================
# Advanced Multi-Omics Association Analysis of Tobacco Leaf Fermentation
# ==============================================================================
#
# STUDY BACKGROUND
# ----------------
# Tobacco leaf fermentation (aging) is a temporally structured microbial and
# biochemical process that converts freshly cured leaf into a matured product
# with the desired aroma profile. The accompanying dataset follows the process
# across 13 timepoints (day -1 to day 60), two growing regions (Yunnan
# highland, Henan lowland) and two varieties (Virginia, Burley), profiling five
# molecular layers on the very same samples:
#
#   microbiome    (16S)  - the fermenting community that drives the process
#   transcriptome        - host and microbial gene expression
#   proteome             - the enzymes actually present
#   metabolome           - the non-volatile biochemical pool
#   volatilome           - the volatile compounds that define aroma quality
#
# The companion script demo_multiomics.R performs the broad descriptive and
# integrative survey of this dataset. The present script is deliberately
# complementary and lightweight: it focuses exclusively on three advanced
# association analyses that reconstruct *directed* and *hierarchical* structure
# rather than symmetric correlation.
#
# SCIENTIFIC QUESTIONS
# --------------------
#   Q1  Temporal causal structure. Which molecular features at one timepoint
#       predict the state of other features at the next timepoint? Dynamic
#       Bayesian networks are learned per omics layer, and then one merged
#       pan-omics network is learned so that arcs crossing layers become
#       explicit.
#
#   Q2  Regulatory importance. If a node were removed, forced high, or forced
#       low, how far and how strongly would the effect propagate through the
#       network? Virtual (in-silico) perturbation ranks nodes by the breadth
#       and magnitude of their downstream impact.
#
#   Q3  Hierarchical pathway architecture. When features are grouped into
#       biologically meaningful latent variables using EC numbers, KEGG
#       annotation, compound classes and microbial taxonomy, how does signal
#       flow along the microbiome -> transcriptome -> proteome -> metabolome
#       -> volatilome hierarchy? A PLS path model quantifies each link.
#
# RUNTIME NOTE
# ------------
# All analyses here are size-controlled through the CONFIG block below. The
# defaults are chosen so the whole script completes quickly; increasing any of
# the values raises the cost, with the number of network nodes and the
# bootstrap replicate count being by far the most expensive knobs.
#
# OUTPUT
# ------
#   tables/  adv_stepNN_*.csv  result tables
#   figures/ adv_stepNN_*.pdf  and  .png  figures
# ==============================================================================

set.seed(42)
source("G:/OmicsWorks/agent/rscript/source_all_scripts.R")

suppressPackageStartupMessages({
  library(ggplot2)
  library(ggrepel)
})

# ------------------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------------------
data_dir   <- "G:/OmicsWorks/extdata/Tobacco-fermentation"
result_dir <- "G:/OmicsWorks/test/multiple_omics"
fig_dir    <- file.path(result_dir, "figures")
tab_dir    <- file.path(result_dir, "tables")
for (d in c(fig_dir, tab_dir)) if (!dir.exists(d)) dir.create(d, recursive = TRUE)

# ------------------------------------------------------------------------------
# CONFIG - all size / runtime knobs live here
# ------------------------------------------------------------------------------
CFG <- list(
  # --- shared temporal design -------------------------------------------------
  time_col    = "day",                        # numeric time axis
  group_cols  = c("location", "variety"),     # independent time series
  layer_order = c("microbiome", "transcriptome", "proteome",
                  "metabolome", "volatilome"),

  # --- Q1 dynamic Bayesian networks ------------------------------------------
  dbn_nodes_per_layer   = 18,   # features per single-omics DBN  (cost: high)
  dbn_nodes_merged      = 6,    # features per layer in merged DBN (cost: high)
  dbn_boot_R            = 60,   # bootstrap replicates            (cost: high)
  dbn_strength_min      = 0.40, # minimum bootstrap arc strength
  dbn_bins              = 3,    # discretisation levels

  # --- Q2 virtual perturbation ------------------------------------------------
  perturb_top_n = 10,    # candidates sent to the inference layer
  perturb_n_sim = 3000,  # Monte-Carlo samples per intervention  (cost: medium)

  # --- Q3 hierarchical PLS path model ----------------------------------------
  plspm_sources = list(microbiome    = "taxonomy_phylum",
                       transcriptome = "ec_number",
                       proteome      = "ec_number",
                       metabolome    = "super_class",
                       volatilome    = "super_class"),
  plspm_ec_level        = 2,   # "EC 1.13.11.71" -> "1.13"
  plspm_min_size        = 3,   # minimum features per latent variable
  plspm_max_latent      = 4,   # latent variables kept per omics layer
  plspm_max_features    = 10,  # manifest variables per latent variable
  plspm_adjacent_only   = TRUE # connect consecutive layers only
)

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

t_start <- Sys.time()
n_tables <- 0L
n_figures <- 0L

# small helpers so every step reports consistently -----------------------------
save_table <- function(df, filename, rownames = FALSE) {
  if (is.null(df) || nrow(df) == 0) {
    cat(sprintf("  (skip table %s: empty)\n", filename))
    return(invisible(FALSE))
  }
  export_table(df, tab_dir, filename, use_rownames = rownames)
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


# ==== Step 1: load the five omics layers (Q1-Q3) ==============================
cat("\n=== Step 1: Loading Tobacco-fermentation multi-omics data ===\n")

sample_info <- load_sample_info(file.path(data_dir, "sampleinfo.csv"))
expr_list <- list(); finfo_list <- list(); match_cols <- c()

for (nm in names(layer_spec)) {
  sp <- layer_spec[[nm]]
  expr_list[[nm]]  <- load_expression_matrix(file.path(data_dir, sp$expr))
  finfo_list[[nm]] <- load_feature_info(file.path(data_dir, sp$finfo),
                                        id_col = sp$id_col)
  match_cols[nm]   <- sp$match_col
  cat(sprintf("  %-14s %5d features x %3d samples\n", nm,
              nrow(expr_list[[nm]]), ncol(expr_list[[nm]])))
}

cat(sprintf("  sample_info    %5d samples, %d timepoints, %d series\n",
            nrow(sample_info),
            length(unique(sample_info[[CFG$time_col]])),
            nrow(unique(sample_info[, CFG$group_cols, drop = FALSE]))))


# ==== Step 2: build and preprocess the multi-omics container (Q1-Q3) ==========
cat("\n=== Step 2: Building and preprocessing the MultiOmicsData container ===\n")

mo <- create_multiomics_data(expr_list, sample_info, finfo_list,
                             match_cols = match_cols)
mo <- preprocess_multiomics(mo, group_col = "condition")

cat(sprintf("  common samples: %d\n", length(mo$common_samples)))
for (nm in mo$metadata$omics_names) {
  cat(sprintf("  %-14s %5d features retained\n", nm,
              nrow(get_omics_matrix(mo, nm))))
}


# ==== Step 3: per-layer dynamic Bayesian networks (Q1) ========================
cat("\n=== Step 3: Dynamic Bayesian network per omics layer (Q1) ===\n")
cat("  Consecutive timepoints are unrolled into t -> t+1 transition pairs\n")
cat("  within each location x variety series; a blacklist forces every arc\n")
cat("  to run from the past slice to the future slice.\n\n")

dbn_layers <- list()
dbn_summaries <- list()

for (nm in CFG$layer_order) {
  if (!nm %in% mo$metadata$omics_names) next
  cat(sprintf("  [%s]\n", nm))

  res <- tryCatch({
    run_dbn_layer(get_omics_matrix(mo, nm), mo$sample_info,
                  get_feature_info(mo, nm),
                  time_col = CFG$time_col, group_cols = CFG$group_cols,
                  max_nodes = CFG$dbn_nodes_per_layer,
                  boot_R = CFG$dbn_boot_R,
                  strength_threshold = CFG$dbn_strength_min,
                  n_bins = CFG$dbn_bins,
                  name_col = layer_spec[[nm]]$match_col)
  }, error = function(e) {
    cat(sprintf("    DBN failed: %s\n", conditionMessage(e)))
    NULL
  })

  if (is.null(res)) next
  dbn_layers[[nm]] <- res

  st <- res$stats
  cat(sprintf("    %d transition pairs from %d timepoints x %d series\n",
              st$n_transitions, st$n_timepoints, st$n_series))
  cat(sprintf("    %d nodes, %d time-lagged arcs (strength >= %.2f)\n",
              st$n_nodes, st$n_arcs, CFG$dbn_strength_min))

  save_table(res$edges_df, sprintf("adv_step03_dbn_%s_edges.csv", nm))
  save_table(res$nodes_df, sprintf("adv_step03_dbn_%s_nodes.csv", nm))
  save_figure(plot_dbn_layer(res, title = sprintf("Dynamic Bayesian network - %s", nm)),
              sprintf("adv_step03_dbn_%s", nm), width = 9, height = 7)

  dbn_summaries[[nm]] <- summarise_dbn_network(res, label = nm)
}

if (length(dbn_summaries) > 0) {
  save_table(do.call(rbind, dbn_summaries), "adv_step03_dbn_layer_summary.csv")
}


# ==== Step 4: merged pan-omics dynamic Bayesian network (Q1) ==================
cat("\n=== Step 4: Merged pan-omics dynamic Bayesian network (Q1) ===\n")
cat("  All five layers enter one network; arcs are classified as intra-omics\n")
cat("  or inter-omics, and the biological layer order constrains direction.\n\n")

dbn_all <- tryCatch({
  run_dbn_multiomics(mo, layers = CFG$layer_order,
                     per_layer_nodes = CFG$dbn_nodes_merged,
                     time_col = CFG$time_col, group_cols = CFG$group_cols,
                     enforce_layer_order = TRUE,
                     layer_order = CFG$layer_order,
                     boot_R = CFG$dbn_boot_R,
                     strength_threshold = CFG$dbn_strength_min,
                     n_bins = CFG$dbn_bins)
}, error = function(e) {
  cat(sprintf("  merged DBN failed: %s\n", conditionMessage(e)))
  NULL
})

if (!is.null(dbn_all)) {
  st <- dbn_all$stats
  cat(sprintf("  %d layers, %d nodes, %d arcs\n", st$n_layers, st$n_nodes,
              st$n_arcs))
  cat(sprintf("  inter-omics arcs: %d | intra-omics arcs: %d\n",
              st$n_inter_omics_arcs, st$n_intra_omics_arcs))

  save_table(dbn_all$edges_df, "adv_step04_dbn_panomics_edges.csv")
  save_table(dbn_all$nodes_df, "adv_step04_dbn_panomics_nodes.csv")
  save_table(summarise_dbn_network(dbn_all, label = "pan_omics"),
             "adv_step04_dbn_panomics_summary.csv")

  save_figure(plot_dbn_multiomics(
    dbn_all, title = "Pan-omics dynamic Bayesian network (t -> t+1)",
    layer_order = CFG$layer_order),
    "adv_step04_dbn_panomics", width = 11, height = 7.5)

  inter <- dbn_all$edges_df[!is.na(dbn_all$edges_df$edge_type) &
                              dbn_all$edges_df$edge_type == "inter_omics", ,
                            drop = FALSE]
  if (nrow(inter) > 0) {
    cat("\n  Top inter-omics temporal arcs:\n")
    show <- head(inter, 8)
    for (i in seq_len(nrow(show))) {
      cat(sprintf("    %-30s -> %-30s  strength=%.2f  (%s -> %s)\n",
                  substr(show$from_label[i], 1, 30),
                  substr(show$to_label[i], 1, 30),
                  show$strength[i], show$from_omics[i], show$to_omics[i]))
    }
    save_table(inter, "adv_step04_dbn_panomics_interomics_edges.csv")
  }
}


# ==== Step 5: virtual perturbation of the pan-omics network (Q2) ==============
cat("\n=== Step 5: Virtual perturbation and regulatory importance (Q2) ===\n")
cat("  knockout    - remove the node, measure structural damage\n")
cat("  overexpress - clamp the node to its high state (do-operator)\n")
cat("  inhibit     - clamp the node to its low state\n\n")

perturb_target <- if (!is.null(dbn_all)) dbn_all else
  if (length(dbn_layers) > 0) dbn_layers[[1]] else NULL

if (is.null(perturb_target)) {
  cat("  No network available; perturbation analysis skipped.\n")
} else {
  ko <- tryCatch(run_node_knockout(perturb_target, top_n = CFG$perturb_top_n),
                 error = function(e) {
                   cat(sprintf("  knockout screen failed: %s\n",
                               conditionMessage(e)))
                   NULL
                 })
  if (!is.null(ko) && nrow(ko) > 0) {
    cat(sprintf("  structural knockout screen: %d node(s) evaluated\n",
                nrow(ko)))
    save_table(ko, "adv_step05_knockout_structural.csv")
  }

  panel <- tryCatch({
    run_perturbation_panel(perturb_target, n_sim = CFG$perturb_n_sim,
                           top_n = CFG$perturb_top_n)
  }, error = function(e) {
    cat(sprintf("  perturbation panel failed: %s\n", conditionMessage(e)))
    NULL
  })

  if (!is.null(panel) && nrow(panel$importance) > 0) {
    imp <- panel$importance
    save_table(imp, "adv_step05_perturbation_importance.csv")
    save_table(panel$pair_details, "adv_step05_perturbation_pairs.csv")

    cat("\n  Top regulators by impact score:\n")
    top <- imp[imp$mode == "overexpress", , drop = FALSE]
    if (nrow(top) == 0) top <- imp
    top <- head(top[order(-top$impact_score), , drop = FALSE], 8)
    for (i in seq_len(nrow(top))) {
      cat(sprintf("    %2d. %-32s desc=%2d  meanTVD=%s  score=%.3f\n",
                  i, substr(top$label[i], 1, 32), top$n_descendants[i],
                  ifelse(is.na(top$mean_tvd[i]), "  n/a",
                         sprintf("%.3f", top$mean_tvd[i])),
                  top$impact_score[i]))
    }

    save_figure(plot_perturbation_ranking(
      imp, top_n = CFG$perturb_top_n,
      title = "Regulatory importance under virtual perturbation"),
      "adv_step05_perturbation_ranking", width = 12, height = 7)

    save_figure(plot_perturbation_heatmap(
      panel$pair_details, mode = "overexpress", top_n = CFG$perturb_top_n,
      title = "Downstream impact of node overexpression"),
      "adv_step05_perturbation_heatmap", width = 10, height = 7.5)

    hub <- imp$node[which.max(imp$impact_score)]
    hub_label <- imp$label[which.max(imp$impact_score)]
    save_figure(plot_perturbation_subnetwork(
      perturb_target, hub,
      title = sprintf("Downstream impact sub-network of %s", hub_label)),
      "adv_step05_perturbation_subnetwork", width = 9, height = 8)
  }
}


# ==== Step 6: hierarchical multi-omics PLS path model (Q3) ====================
cat("\n=== Step 6: Hierarchical multi-omics PLS-PM (Q3) ===\n")
cat("  Latent variables are built from EC classes (transcriptome, proteome),\n")
cat("  compound classes (metabolome, volatilome) and phylum-level taxonomy\n")
cat("  (microbiome), then connected along the biological hierarchy.\n\n")

latent <- tryCatch({
  build_multiomics_latent_def(mo, layer_sources = CFG$plspm_sources,
                              min_size = CFG$plspm_min_size,
                              max_latent_per_layer = CFG$plspm_max_latent,
                              max_features_per_latent = CFG$plspm_max_features,
                              ec_level = CFG$plspm_ec_level)
}, error = function(e) {
  cat(sprintf("  latent variable construction failed: %s\n",
              conditionMessage(e)))
  NULL
})

plspm_res <- NULL
if (!is.null(latent)) {
  cat(sprintf("\n  %d latent variable(s) across %d layer(s)\n",
              nrow(latent$definitions), length(unique(latent$definitions$layer))))
  save_table(latent$definitions, "adv_step06_plspm_latent_definitions.csv")

  inner <- tryCatch({
    build_hierarchical_inner_model(latent$definitions,
                                   layer_order = CFG$layer_order,
                                   adjacent_only = CFG$plspm_adjacent_only)
  }, error = function(e) {
    cat(sprintf("  inner model construction failed: %s\n",
                conditionMessage(e)))
    NULL
  })

  if (!is.null(inner)) {
    cat(sprintf("  inner model: %d x %d, %d directed link(s)\n",
                nrow(inner$path_matrix), ncol(inner$path_matrix),
                sum(inner$path_matrix)))

    plspm_res <- tryCatch({
      run_multiomics_plspm(mo, latent$latent_def, inner$definitions,
                           inner$path_matrix)
    }, error = function(e) {
      cat(sprintf("  PLS-PM fitting failed: %s\n", conditionMessage(e)))
      NULL
    })
  }
}

if (!is.null(plspm_res)) {
  save_table(plspm_res$inner_paths, "adv_step06_plspm_inner_paths.csv")
  save_table(plspm_res$outer_loadings, "adv_step06_plspm_outer_loadings.csv")
  save_table(plspm_res$fit_summary, "adv_step06_plspm_fit_summary.csv")
  save_table(plspm_res$scores, "adv_step06_plspm_latent_scores.csv",
             rownames = TRUE)

  path_sum <- summarise_plspm_paths(plspm_res)
  if (!is.null(path_sum)) {
    save_table(path_sum, "adv_step06_plspm_path_summary.csv")
    cat("\n  Path strength by layer transition:\n")
    for (i in seq_len(nrow(path_sum))) {
      cat(sprintf("    %-34s n=%2d  sig=%2d  mean|beta|=%.3f\n",
                  path_sum$transition[i], path_sum$n_paths[i],
                  path_sum$n_significant[i], path_sum$mean_abs_path_coeff[i]))
    }
  }

  ip <- plspm_res$inner_paths
  cat(sprintf("\n  %d path(s), %d significant (p<0.05), GoF = %.4f\n",
              nrow(ip), sum(ip$significant, na.rm = TRUE), plspm_res$gof))

  cat("\n  Strongest latent-to-latent paths:\n")
  show <- head(ip, 8)
  for (i in seq_len(nrow(show))) {
    cat(sprintf("    %-26s -> %-26s beta=%+.3f  p=%.3g %s\n",
                substr(show$from[i], 1, 26), substr(show$to[i], 1, 26),
                show$path_coeff[i], show$p_value[i],
                ifelse(show$significant[i], "*", "")))
  }

  save_figure(plot_plspm_hierarchy(
    plspm_res, layer_order = CFG$layer_order,
    title = "Hierarchical multi-omics PLS path model"),
    "adv_step06_plspm_hierarchy", width = 12, height = 8)

  save_figure(plot_plspm_hierarchy(
    plspm_res, layer_order = CFG$layer_order, significant_only = TRUE,
    title = "Hierarchical PLS path model (significant paths only)"),
    "adv_step06_plspm_hierarchy_significant", width = 12, height = 8)

  save_figure(plot_plspm_r2(
    plspm_res, title = "Explained variance of endogenous latent variables"),
    "adv_step06_plspm_r2", width = 9, height = 6.5)
}


# ==== Step 7: summary =========================================================
cat("\n=== Step 7: Summary ===\n")
cat("--------------------------------------------------------------\n")

elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))

cat(sprintf("  Samples analysed          : %d\n", length(mo$common_samples)))
cat(sprintf("  Omics layers              : %d\n",
            length(mo$metadata$omics_names)))
cat(sprintf("  Per-layer DBNs built      : %d\n", length(dbn_layers)))

if (length(dbn_layers) > 0) {
  total_arcs <- sum(vapply(dbn_layers, function(d) d$stats$n_arcs, integer(1)))
  cat(sprintf("  Time-lagged arcs (layers) : %d\n", total_arcs))
}
if (!is.null(dbn_all)) {
  cat(sprintf("  Pan-omics DBN             : %d nodes, %d arcs (%d inter-omics)\n",
              dbn_all$stats$n_nodes, dbn_all$stats$n_arcs,
              dbn_all$stats$n_inter_omics_arcs))
}
if (exists("panel") && !is.null(panel) && nrow(panel$importance) > 0) {
  cat(sprintf("  Perturbations evaluated   : %d across %d mode(s)\n",
              nrow(panel$importance), length(unique(panel$importance$mode))))
}
if (!is.null(plspm_res)) {
  cat(sprintf("  PLS-PM latent variables   : %d\n",
              nrow(plspm_res$definitions)))
  cat(sprintf("  PLS-PM paths (significant): %d (%d)\n",
              nrow(plspm_res$inner_paths),
              sum(plspm_res$inner_paths$significant, na.rm = TRUE)))
  cat(sprintf("  PLS-PM goodness of fit    : %.4f\n", plspm_res$gof))
}

cat("--------------------------------------------------------------\n")
cat(sprintf("  Tables written            : %d  -> %s\n", n_tables, tab_dir))
cat(sprintf("  Figures written           : %d  -> %s\n", n_figures, fig_dir))
cat(sprintf("  Total runtime             : %.1f s\n", elapsed))
cat("--------------------------------------------------------------\n")
cat("\nAdvanced multi-omics analysis completed.\n")
