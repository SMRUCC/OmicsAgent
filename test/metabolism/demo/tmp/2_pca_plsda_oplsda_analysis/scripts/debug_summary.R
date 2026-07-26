lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Find the summary section around the for loop
for (i in seq_along(lines)) {
 if (grepl("for \\(pw_nm in pairwise_names\\) \\{", lines[i])) {
 cat("Found for loop at line", i, "\n")
 for (j in i:min(i+15, length(lines))) {
 cat(j, ":", lines[j], "\n")
 }
 break
 }
}
