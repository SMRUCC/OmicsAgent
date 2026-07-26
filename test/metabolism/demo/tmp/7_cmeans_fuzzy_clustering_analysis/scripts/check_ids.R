# Check ID mapping between CMeans and WGCNA
rdata <- "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step2_data.RData"
env <- new.env(); load(rdata, envir=env)

# WGCNA names (from merged_colors)
wgcna_names <- names(env$merged_colors)
cat("WGCNA merged_colors names (first20):\n", paste(head(wgcna_names,20), collapse=", "), "\n")
cat("WGCNA names example:", wgcna_names[1], "\n")

# CMeans names
cres <- readRDS("G:/OmicsWorks/test/metabolism/demo/tmp/7_cmeans_fuzzy_clustering_analysis/cmeans_result.rds")
cm_names <- names(cres$cluster)
cat("\nCMeans cluster names (first20):\n", paste(head(cm_names,20), collapse=", "), "\n")
cat("CMeans name example:", cm_names[1], "\n")

# Check module_df for feature IDs
cat("\nmodule_df columns:", paste(colnames(env$module_df), collapse=", "), "\n")
cat("module_df first few feature IDs:\n")
print(head(env$module_df[,1:3]))

# Read expression/preprocessed to find mapping
expr <- read.csv("G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv",
 check.names=FALSE, nrows=5)
cat("\nPreprocessed expr first col header:", colnames(expr)[1], "\n")
cat("First5 values:", paste(expr[1:5,1], collapse=", "), "\n")
