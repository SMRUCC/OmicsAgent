#!/usr/bin/env Rscript
options(error = function() { traceback(3); q(status = 1) })
source("G:/OmicsWorks/agent/rscript/source_all_scripts.R")

data_dir   <- "G:/OmicsWorks/extdata/Tobacco-fermentation"
layer_spec <- list(
  transcriptome = list(expr = "expression_transcriptome.csv",
                       finfo = "featureinfo_transcriptome.csv",
                       id_col = "gene_id", match_col = "name")
)
sample_info <- load_sample_info(file.path(data_dir, "sampleinfo.csv"))
expr_list <- list()
finfo_list <- list()
match_cols <- character(0)
for (nm in names(layer_spec)) {
  sp <- layer_spec[[nm]]
  expr_list[[nm]] <- load_expression_matrix(file.path(data_dir, sp$expr))
  finfo_list[[nm]] <- load_feature_info(file.path(data_dir, sp$finfo), id_col = sp$id_col)
  match_cols[nm] <- sp$match_col
}
mo <- create_multiomics_data(expr_list, sample_info, finfo_list, match_cols = match_cols)
mo <- preprocess_multiomics(mo, group_col = "condition")

cat("=== direct build_wgcna_modules ===\n")
res <- build_wgcna_modules(get_omics_matrix(mo, "transcriptome"),
                           min_module_size = 20, network_type = "signed", cor_fn = "cor")
cat("OK: n modules =", length(setdiff(unique(res$module_colors), "grey")), "\n")
cat("soft_power =", res$soft_power, "\n")
