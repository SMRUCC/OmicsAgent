# Detailed check of WGCNA data
rdata <- "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step2_data.RData"
env <- new.env(); load(rdata, envir=env)

cat("merged_colors length:", length(env$merged_colors), "\n")
cat("merged_colors is.null:", is.null(names(env$merged_colors)), "\n")
cat("merged_colors names empty:", all(names(env$merged_colors)==""), "\n")

# Check module_df
cat("\nmodule_df columns:", paste(colnames(env$module_df), collapse=", "), "\n")
cat("module_df nrow:", nrow(env$module_df), "\n")
cat("module_df Feature col type:", class(env$module_df$Feature), "\n")
cat("module_df first5 features:\n")
print(head(env$module_df$Feature,20))

# Read anno_matched from step1 data
f1 <- "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step1_data.RData"
env1 <- new.env(); load(f1, envir=env1)
cat("\n=== step1 data ===\n")
cat("anno_matched columns:", paste(colnames(env1$anno_matched), collapse=", "), "\n")
cat("anno_matched first5 IDs:\n")
print(head(env1$anno_matched[,1:4]))

cat("\nexpr_matrix columns (first5):", paste(colnames(env1$expr_matrix)[1:5], collapse=", "), "\n")
cat("expr_matrix rownames (first5):\n")
print(head(rownames(env1$expr_matrix),5))
