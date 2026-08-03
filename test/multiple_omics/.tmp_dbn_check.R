set.seed(42)
source("G:/OmicsWorks/agent/rscript/source_all_scripts.R")

dd <- "G:/OmicsWorks/extdata/Tobacco-fermentation"
spec <- list(
  transcriptome = list(e = "expression_transcriptome.csv", f = "featureinfo_transcriptome.csv", id = "gene_id", m = "name"),
  proteome      = list(e = "expression_proteome.csv",      f = "featureinfo_proteome.csv",      id = "gene_id", m = "name"),
  metabolome    = list(e = "expression_metabolome.csv",    f = "featureinfo_metabolome.csv",    id = "ID",      m = "name"),
  volatilome    = list(e = "expression_volatilome.csv",    f = "featureinfo_volatilome.csv",    id = "ID",      m = "name"),
  microbiome    = list(e = "expression_16s.csv",           f = "featureinfo_16s.csv",           id = "ID",      m = "ID")
)
si <- load_sample_info(file.path(dd, "sampleinfo.csv"))
el <- list(); fl <- list(); mc <- c()
for (nm in names(spec)) {
  s <- spec[[nm]]
  el[[nm]] <- load_expression_matrix(file.path(dd, s$e))
  fl[[nm]] <- load_feature_info(file.path(dd, s$f), id_col = s$id)
  mc[nm] <- s$m
}
mo <- create_multiomics_data(el, si, fl, match_cols = mc)
mo <- preprocess_multiomics(mo, group_col = "condition")

d <- run_dbn_multiomics(mo, per_layer_nodes = 6, boot_R = 30,
                        strength_threshold = 0.4, enforce_layer_order = TRUE,
                        layer_order = c("microbiome","transcriptome","proteome","metabolome","volatilome"))

cat("\n=== knockout structural ===\n")
ko <- run_node_knockout(d, top_n = 8)
print(head(ko, 6))

cat("\n=== perturbation panel ===\n")
t0 <- Sys.time()
pp <- run_perturbation_panel(d, n_sim = 2000, top_n = 8)
cat("elapsed:", round(as.numeric(difftime(Sys.time(), t0, units="secs")),1), "s\n")
cat("importance rows:", nrow(pp$importance), " pairs:", nrow(pp$pair_details), "\n")
print(head(pp$importance[, c("label","mode","n_descendants","mean_tvd","mean_prob_shift","impact_score","rank")], 12))
cat("\npair sample:\n")
print(head(pp$pair_details[, c("perturbed_label","downstream_label","distance","tvd","prob_shift","mode")], 8))
cat("DONE\n")
