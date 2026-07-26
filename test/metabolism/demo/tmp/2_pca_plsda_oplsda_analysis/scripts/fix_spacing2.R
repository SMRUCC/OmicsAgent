lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Fix missing spaces: "in1" -> "in1"
lines <- gsub("in1:nrow", "in1:nrow", lines)
lines <- gsub("in1:n_perm", "in1:n_perm", lines)
writeLines(lines, "G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Fixed spacing issues.\n")
