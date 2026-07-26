# Inspect WGCNA RData structure
wgcna_rdata <- "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step2_data.RData"
load(wgcna_rdata)
cat("=== Objects in WGCNA RData ===\n")
cat(paste(ls(), collapse = "\n"), "\n\n")

# Check merged_MEs
if (exists("merged_MEs")) {
 cat("=== merged_MEs ===\n")
 print(dim(merged_MEs))
 print(head(rownames(merged_MEs)))
 print(head(colnames(merged_MEs)))
 cat("\n")
}

# Check MEs_aligned
if (exists("MEs_aligned")) {
 cat("=== MEs_aligned ===\n")
 print(dim(MEs_aligned))
 print(head(rownames(MEs_aligned)))
 print(head(colnames(MEs_aligned)))
 cat("\n")
}

# Check merged_colors
if (exists("merged_colors")) {
 cat("=== merged_colors (first20) ===\n")
 print(table(merged_colors))
 cat("\n")
}

# Check module_sizes
if (exists("module_sizes")) {
 cat("=== module_sizes ===\n")
 print(module_sizes)
 cat("\n")
}
