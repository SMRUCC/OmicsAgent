#!/usr/bin/env Rscript
options(error = function() { traceback(3); q(status = 1) })
source("G:/OmicsWorks/agent/rscript/source_all_scripts.R")

data_dir   <- "G:/OmicsWorks/extdata/Tobacco-fermentation"
layer_spec <- list(
  transcriptome = list(expr = "expression_transcriptome.csv", finfo = "featureinfo_transcriptome.csv", id_col = "gene_id", match_col = "name"),
  metabolome    = list(expr = "expression_metabolome.csv", finfo = "featureinfo_metabolome.csv", id_col = "ID", match_col = "name"),
  volatilome    = list(expr = "expression_volatilome.csv", finfo = "featureinfo_volatilome.csv", id_col = "ID", match_col = "name"),
  microbiome    = list(expr = "expression_16s.csv", finfo = "featureinfo_16s.csv", id_col = "ID", match_col = "ID")
)
sample_info <- load_sample_info(file.path(data_dir, "sampleinfo.csv"))
expr_list <- list(); finfo_list <- list(); match_cols <- character(0)
for (nm in names(layer_spec)) {
  sp <- layer_spec[[nm]]
  expr_list[[nm]] <- load_expression_matrix(file.path(data_dir, sp$expr))
  finfo_list[[nm]] <- load_feature_info(file.path(data_dir, sp$finfo), id_col = sp$id_col)
  match_cols[nm] <- sp$match_col
}
mo <- create_multiomics_data(expr_list, sample_info, finfo_list, match_cols = match_cols)
mo <- preprocess_multiomics(mo, group_col = "condition")

cat("\n=== Step 16: WGCNA module-trait ===\n")
wgcna_res <- build_wgcna_modules_layer(mo, "transcriptome", min_module_size = 20)
cat("modules:", length(setdiff(unique(wgcna_res$module_colors), "grey")), "\n")
traits_met <- wgcna_traits_from_layer(mo, "metabolome", reference_samples = rownames(wgcna_res$MEs))
cat("traits dims:", dim(traits_met), "\n")
assoc <- run_wgcna_trait_association(wgcna_res, traits_met, trait_layer = "metabolome")
cat("module-trait pairs:", nrow(assoc$module_trait), "sig:", sum(assoc$module_trait$significant), "\n")
annot <- annotate_wgcna_trait_result(assoc, trait_feature_info = get_feature_info(mo, "metabolome"),
                                     module_layer = "transcriptome", trait_layer = "metabolome")
cat("annotated rows:", nrow(annot), "trait_name head:", head(annot$trait_name, 3), "\n")
p <- plot_wgcna_trait_heatmap(assoc, top_n_traits = 20)
cat("heatmap ok:", inherits(p, "ggplot"), "\n")

cat("\n=== Step 17: regression ===\n")
reg1 <- run_cross_omics_regression(get_omics_matrix(mo, "microbiome"), get_omics_matrix(mo, "volatilome"),
                                   x_name = "microbiome", y_name = "volatilome")
cat("micro->vol pairs:", nrow(reg1$pairs), "sig:", sum(reg1$pairs$significant), "\n")
reg2 <- run_cross_omics_regression(get_omics_matrix(mo, "transcriptome"), get_omics_matrix(mo, "metabolome"),
                                   x_name = "transcriptome", y_name = "metabolome")
cat("trans->meta pairs:", nrow(reg2$pairs), "sig:", sum(reg2$pairs$significant), "\n")
top <- top_regression_pairs(reg2, top_n = 3)
cat("top pairs rows:", nrow(top), "\n")
cat("ALL NEW STEPS OK\n")
