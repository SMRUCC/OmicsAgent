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

cat("\n=== EC clean check ===\n")
tf <- get_feature_info(mo, "transcriptome")
cat("raw ec sample:", head(na.omit(tf$ec_number), 3), "\n")
cat("cleaned:", head(na.omit(clean_ec_number(tf$ec_number, 2)), 5), "\n")
cat("coverage:", round(mean(!is.na(clean_ec_number(tf$ec_number,2))),3), "\n")

cat("\n=== latent def ===\n")
lat <- build_multiomics_latent_def(
  mo,
  layer_sources = list(microbiome = "taxonomy_phylum",
                       transcriptome = "ec_number",
                       proteome = "ec_number",
                       metabolome = "super_class",
                       volatilome = "super_class"),
  min_size = 3, max_latent_per_layer = 4, max_features_per_latent = 10)
print(lat$definitions)

cat("\n=== inner model ===\n")
im <- build_hierarchical_inner_model(
  lat$definitions,
  layer_order = c("microbiome","transcriptome","proteome","metabolome","volatilome"),
  adjacent_only = TRUE)
cat("path matrix dim:", dim(im$path_matrix), " edges:", sum(im$path_matrix), "\n")

cat("\n=== fit ===\n")
t0 <- Sys.time()
res <- run_multiomics_plspm(mo, lat$latent_def, im$definitions, im$path_matrix)
cat("elapsed:", round(as.numeric(difftime(Sys.time(), t0, units="secs")),1), "s\n")
print(head(res$inner_paths, 10))
cat("\nfit summary:\n"); print(res$fit_summary)
cat("\npath summary:\n"); print(summarise_plspm_paths(res))
cat("\nouter head:\n"); print(head(res$outer_loadings, 4))
cat("DONE\n")
