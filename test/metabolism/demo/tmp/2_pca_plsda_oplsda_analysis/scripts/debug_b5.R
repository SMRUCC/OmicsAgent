lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Find the B5 weighted distances section
for (i in seq_along(lines)) {
 if (grepl("B5", lines[i]) && grepl("Weighted", lines[i])) {
 cat("B5 section starts at line", i, "\n")
 for (j in i:min(i+60, length(lines))) {
 cat(j, ":", lines[j], "\n")
 }
 break
 }
}
